// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/utils/file_selector.dart';
import 'package:vibe/utils/localized_exception_extension.dart';
import 'package:vibe/vibe/screens/chat/events/message.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_pending_files.dart';

/// Reply threads: when a message already has two or more replies, replying
/// opens the whole thread in a pane over the blurred chat. It looks like the
/// chat itself (same bubbles, names, avatars and text box). Sent replies
/// slide in from the text box and show the same status dots as the chat
/// (encrypting, sent, delivered, read); new replies from others appear live.
abstract class VibeReplyThread {
  /// Apple's sheet motion (a spring with no bounce, ~0.5 s response), as a
  /// curve: quick to start, long soft landing.
  static const _sheetCurve = Cubic(0.32, 0.72, 0, 1);

  static String? _parentId(Event e) =>
      e.inReplyToEventId(includingFallback: false);

  /// The ids of the reply conversation [event] belongs to, from what's
  /// loaded: everything it replies to, and everything replying to those.
  static Set<String> _ids(Event event, Timeline timeline) {
    final byId = {for (final e in timeline.events) e.eventId: e};
    final ids = <String>{event.eventId};
    var cur = event;
    for (var i = 0; i < 50; i++) {
      final p = _parentId(cur);
      if (p == null || !ids.add(p)) break;
      final parent = byId[p];
      if (parent == null) break;
      cur = parent;
    }
    var added = true;
    while (added) {
      added = false;
      for (final e in timeline.events) {
        final p = _parentId(e);
        if (p != null && ids.contains(p) && ids.add(e.eventId)) added = true;
      }
    }
    return ids;
  }

  /// A thread: the message and at least two replies around it.
  static bool isThread(Event event, Timeline timeline) =>
      _ids(event, timeline).length >= 3;

  /// The thread from what's loaded, oldest first (instant).
  static List<Event> _loaded(Event event, Timeline timeline) {
    final ids = _ids(event, timeline);
    final chain = timeline.events
        .where((e) => ids.contains(e.eventId) && !e.redacted)
        .toList();
    if (!chain.any((e) => e.eventId == event.eventId)) chain.add(event);
    chain.sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
    return chain;
  }

  /// Older messages of the thread that aren't loaded in the chat yet.
  static Future<List<Event>> _olderParents(
    List<Event> chain,
    Timeline timeline,
  ) async {
    final found = <Event>[];
    if (chain.isEmpty) return found;
    var top = chain.first;
    for (var i = 0; i < 10; i++) {
      final parent = await top.getReplyEvent(timeline);
      if (parent == null ||
          parent.redacted ||
          chain.any((e) => e.eventId == parent.eventId) ||
          found.any((e) => e.eventId == parent.eventId)) {
        break;
      }
      found.insert(0, parent);
      top = parent;
    }
    return found;
  }

  static Future<void> show(
    BuildContext context, {
    required Room room,
    required Timeline timeline,
    required Event replyTo,
    required Set<String> bigEmojis,
    required void Function(String eventId) scrollToEventId,
    required void Function(Event event) showInfo,
    String? threadRootEventId,
    String? threadLastEventId,
  }) async {
    VibeHaptics.light();
    final chain = _loaded(replyTo, timeline);
    // A live blur is nearly free on iPhone but redrawn every frame on
    // Android, where it made the slide stutter: Android gets a dim instead.
    final blur = Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.macOS;
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierLabel: 'Close',
        barrierColor: Colors.black.withValues(alpha: blur ? 0.25 : 0.55),
        transitionDuration: const Duration(milliseconds: 460),
        reverseTransitionDuration: const Duration(milliseconds: 340),
        pageBuilder: (ctx, _, _) => _ThreadPane(
          room: room,
          timeline: timeline,
          chain: chain,
          replyTo: replyTo,
          bigEmojis: bigEmojis,
          scrollToEventId: scrollToEventId,
          showInfo: showInfo,
          threadRootEventId: threadRootEventId,
          threadLastEventId: threadLastEventId,
        ),
        transitionsBuilder: (ctx, anim, _, child) {
          // Like an iPhone sheet: the pane slides up as one solid piece
          // (only moved, never faded or resized, so nothing is redrawn while
          // it travels) and slides back down on close.
          final slide = Tween(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
                CurvedAnimation(
                  parent: anim,
                  curve: _sheetCurve,
                  reverseCurve: _sheetCurve.flipped,
                ),
              );
          final pane = SlideTransition(
            position: slide,
            child: RepaintBoundary(child: child),
          );
          if (!blur) return pane;
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: FadeTransition(
                    opacity: anim,
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              pane,
            ],
          );
        },
      ),
    );
  }
}

class _ThreadPane extends StatefulWidget {
  final Room room;
  final Timeline timeline;
  final List<Event> chain;
  final Event replyTo;
  final Set<String> bigEmojis;
  final void Function(String eventId) scrollToEventId;
  final void Function(Event event) showInfo;
  final String? threadRootEventId;
  final String? threadLastEventId;
  const _ThreadPane({
    required this.room,
    required this.timeline,
    required this.chain,
    required this.replyTo,
    required this.bigEmojis,
    required this.scrollToEventId,
    required this.showInfo,
    this.threadRootEventId,
    this.threadLastEventId,
  });

  @override
  State<_ThreadPane> createState() => _ThreadPaneState();
}

class _ThreadPaneState extends State<_ThreadPane>
    with SingleTickerProviderStateMixin {
  // the messages slide up once the pane is in place (not while it moves)
  late final _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<XFile> _files = [];
  final _focus = FocusNode();
  late Event _target = widget.replyTo;
  late List<Event> _chain = widget.chain;
  bool _sending = false;
  bool _canSend = false;

  /// Messages already on screen; anything new slides in from the text box.
  final Set<String> _seen = {};
  StreamSubscription<Event>? _eventSub;
  StreamSubscription<SyncUpdate>? _syncSub;

  /// Stays the same while a message goes from "sending" to "sent".
  static String _key(Event e) => e.transactionId ?? e.eventId;

  /// Picks up new and updated messages from the chat (own replies being
  /// sent, replies from others, status changes, read markers).
  void _refresh() {
    if (!mounted) return;
    final fresh = VibeReplyThread._loaded(widget.replyTo, widget.timeline);
    final byKey = {for (final e in _chain) _key(e): e};
    for (final e in fresh) {
      byKey[_key(e)] = e;
    }
    final merged = byKey.values.where((e) => !e.redacted).toList()
      ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
    setState(() => _chain = merged);
  }

  @override
  void initState() {
    super.initState();
    _seen.addAll(_chain.map(_key));
    final client = widget.room.client;
    _eventSub = client.onTimelineEvent.stream
        .where((e) => e.roomId == widget.room.id)
        .listen((_) => _refresh());
    _syncSub = client.onSync.stream.listen((_) => _refresh());
    _text.addListener(() {
      final can = _text.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
    // No keyboard on open: it resized the pane while it was still moving.
    // Tap the text box to type.
    VibeReplyThread._olderParents(_chain, widget.timeline).then((older) {
      if (mounted && older.isNotEmpty) {
        // older messages above: no slide-in for those
        _seen.addAll(older.map(_key));
        setState(() => _chain = [...older, ..._chain]);
      }
    });
  }

  Animation<double>? _route;

  /// The messages slide in only once the pane has landed, so the two
  /// motions never run at the same time.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_route != null) return;
    final route = _route = ModalRoute.of(context)?.animation;
    if (route == null || route.isCompleted) {
      _intro.forward();
      return;
    }
    void landed(AnimationStatus s) {
      if (s != AnimationStatus.completed) return;
      route.removeStatusListener(landed);
      if (mounted) _intro.forward();
    }
    route.addStatusListener(landed);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _syncSub?.cancel();
    _text.dispose();
    _scroll.dispose();
    _focus.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    final picked = await selectFiles(context, allowMultiple: true);
    if (picked.isEmpty || !mounted) return;
    setState(() => _files.addAll(picked));
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if ((text.isEmpty && _files.isEmpty) || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    if (_files.isNotEmpty) {
      // the chat keeps uploading after this pane closes
      VibePendingFiles.send(
        Navigator.of(context, rootNavigator: true).context,
        widget.room,
        List.of(_files),
        inReplyTo: _target,
        threadRootEventId: widget.threadRootEventId,
        threadLastEventId: widget.threadLastEventId,
      );
      _files.clear();
    }
    // The pane stays open: the reply slides in from the text box and its
    // dots follow it (encrypting, sent, delivered, read).
    _text.clear();
    setState(() => _sending = false);
    VibeHaptics.light();
    if (text.isEmpty) return;
    try {
      await widget.room.sendTextEvent(
        text,
        inReplyTo: _target,
        threadRootEventId: widget.threadRootEventId,
        threadLastEventId: widget.threadLastEventId,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final colors = [theme.secondaryBubbleColor, theme.bubbleColor];
    final chain = _chain;
    // the chat list runs newest first; so does this one
    final events = chain.reversed.toList();
    final canSend = _canSend || _files.isNotEmpty;
    final targetName = _target.senderFromMemoryOrFallback.calcDisplayname();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          8,
          24,
          8,
          8 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Material(
          color: cs.surface,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(24),
          elevation: 12,
          child: Column(
            children: [
              // header, like the chat's app bar; drag it down to close
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 250) {
                    Navigator.of(context).pop();
                  }
                },
                child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
                child: Row(
                  children: [
                    Icon(Icons.forum_outlined, color: cs.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Thread',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${chain.length} messages · '
                            '${widget.room.getLocalizedDisplayname()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              ),
              Divider(height: 1, color: theme.dividerColor),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: events.length,
                  // a new message at the bottom keeps the others' state
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<String>) return null;
                    final i = events.indexWhere((e) => _key(e) == key.value);
                    return i < 0 ? null : i;
                  },
                  itemBuilder: (context, i) {
                    final e = events[i];
                    // Tree: the first message at the top (0), answers to the
                    // message just above (1), answers to an older one
                    // indented under it (2).
                    final older = i + 1 < events.length ? events[i + 1] : null;
                    final parent = VibeReplyThread._parentId(e);
                    final depth = older == null
                        ? 0
                        : parent == null || parent == older.eventId ||
                                !events.any((x) => x.eventId == parent)
                            ? 1
                            : 2;
                    // the newest few slide up one after another; the rest
                    // (off screen) just appear
                    final start = i < 6 ? i * 0.09 : 0.0;
                    // sent or received while the pane is open
                    final isNew = _seen.add(_key(e));
                    return RepaintBoundary(
                      key: ValueKey(_key(e)),
                      child: AnimatedBuilder(
                        animation: _intro,
                        builder: (context, child) {
                          if (i >= 6 || _intro.isCompleted) return child!;
                          final p = ((_intro.value - start) / (1 - 0.45))
                              .clamp(0.0, 1.0);
                          final v = Curves.easeOutCubic.transform(p);
                          return Opacity(
                            opacity: v,
                            child: Transform.translate(
                              offset: Offset(0, 14 * (1 - v)),
                              child: child,
                            ),
                          );
                        },
                        child: _SlideIn(
                          play: isNew,
                          child: _TreeRow(
                            depth: depth,
                            color: theme.dividerColor,
                            accent: cs.primary,
                            child: Message(
                      e,
                      nextEvent: i + 1 < events.length ? events[i + 1] : null,
                      previousEvent: i > 0 ? events[i - 1] : null,
                      bigEmojis: widget.bigEmojis,
                      timeline: widget.timeline,
                      colors: colors,
                      scrollController: _scroll,
                      highlightMarker: e.eventId == _target.eventId,
                      // swipe a message here to answer that one instead
                      onSwipe: () => setState(() => _target = e),
                      onSelect: (e) => setState(() => _target = e),
                      onInfoTab: widget.showInfo,
                      onMention: () {},
                      onEdit: () {},
                      scrollToEventId: (id) {
                        Navigator.of(context).pop();
                        widget.scrollToEventId(id);
                      },
                      singleSelected: false,
                      enterThread: null,
                      threadView: true,
                    ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // "Replying to …", like the chat's reply bar
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 12, 0),
                child: Row(
                  children: [
                    Icon(Icons.reply, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'Replying to ',
                          style: TextStyle(color: cs.onSurfaceVariant),
                          children: [
                            TextSpan(
                              text: targetName,
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              // the chat's text box: + · pill · send
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(6, 6, 0, 3),
                        padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(32),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            VibePendingFilesStrip(
                              files: _files,
                              onRemove: (f) =>
                                  setState(() => _files.remove(f)),
                            ),
                            Row(
                              children: [
                                Material(
                                  color: cs.surfaceContainerHighest,
                                  shape: const CircleBorder(),
                                  clipBehavior: Clip.antiAlias,
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      tooltip: 'Add photo, video or file',
                                      icon: const Icon(Icons.add, size: 26),
                                      onPressed: _sending ? null : _attach,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _text,
                                    focusNode: _focus,
                                    minLines: 1,
                                    maxLines: 6,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: const InputDecoration(
                                      hintText: 'Reply in thread',
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 56,
                      width: 56,
                      margin: const EdgeInsets.only(top: 6, bottom: 3),
                      alignment: Alignment.center,
                      child: IconButton(
                        onPressed: canSend && !_sending ? _send : null,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFDCE4FF),
                          foregroundColor: const Color(0xFF226DFD),
                          fixedSize: const Size(56, 56),
                        ),
                        icon: _sending
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 24),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A message sent or received while the pane is open rises from the text
/// box into place (moved and faded only, so nothing is laid out again).
class _SlideIn extends StatefulWidget {
  final bool play;
  final Widget child;
  const _SlideIn({required this.play, required this.child});

  @override
  State<_SlideIn> createState() => _SlideInState();
}

class _SlideInState extends State<_SlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    value: widget.play ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.play) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      if (_c.isCompleted) return child!;
      final v = Curves.easeOutCubic.transform(_c.value);
      return Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 48 * (1 - v)),
          child: child,
        ),
      );
    },
  );
}

/// Slack/Reddit-style thread line: a line down the side for every answer,
/// and a curve into answers to an older message (indented one more step).
class _TreeRow extends StatelessWidget {
  final int depth;
  final Color color;
  final Color accent;
  final Widget child;
  const _TreeRow({
    required this.depth,
    required this.color,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (depth == 0) return child;
    return Stack(
      children: [
        Positioned(
          left: 12,
          top: 0,
          bottom: 0,
          child: Container(width: 2, color: color),
        ),
        if (depth == 2)
          Positioned(
            left: 34,
            top: 0,
            child: CustomPaint(
              size: const Size(12, 26),
              painter: _CurvePainter(accent),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(left: depth == 2 ? 44 : 22),
          child: child,
        ),
      ],
    );
  }
}

/// The small curve from the line into an indented answer.
class _CurvePainter extends CustomPainter {
  final Color color;
  const _CurvePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(1, 0)
      ..lineTo(1, size.height - 10)
      ..quadraticBezierTo(1, size.height - 1, 10, size.height - 1)
      ..lineTo(size.width, size.height - 1);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => old.color != color;
}

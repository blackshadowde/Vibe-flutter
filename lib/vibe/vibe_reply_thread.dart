// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/gestures.dart';
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
/// chat itself (same bubbles, names, avatars and text box); send, and the
/// pane goes away and the reply lands in the chat.
abstract class VibeReplyThread {
  static Offset? _lastDown;
  static bool _listening = false;

  /// Where the finger last touched the screen (the message being answered).
  static void _listen() {
    if (_listening) return;
    _listening = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
      if (e is PointerDownEvent) _lastDown = e.position;
    });
  }

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
    _listen();
    final chain = _loaded(replyTo, timeline);
    final size = MediaQuery.sizeOf(context);
    final from = _lastDown;
    // the pane grows out of the tapped message and shrinks back into it
    final origin = from == null || size.isEmpty
        ? Alignment.center
        : Alignment(
            (from.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
            (from.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
          );
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierLabel: 'Close',
        barrierColor: Colors.black.withValues(alpha: 0.3),
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 220),
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
          final t = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutQuart,
            reverseCurve: Curves.easeInCubic,
          );
          return Stack(
            children: [
              // a fixed blur that fades in: cheaper than animating the blur
              Positioned.fill(
                child: IgnorePointer(
                  child: FadeTransition(
                    opacity: t,
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              ScaleTransition(
                alignment: origin,
                scale: Tween(begin: 0.6, end: 1.0).animate(t),
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: anim,
                    curve: const Interval(0, 0.6, curve: Curves.easeOut),
                    reverseCurve: const Interval(0.3, 1, curve: Curves.easeIn),
                  ),
                  child: child,
                ),
              ),
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
  late final _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..forward();
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<XFile> _files = [];
  final _focus = FocusNode();
  late Event _target = widget.replyTo;
  late List<Event> _chain = widget.chain;
  bool _sending = false;
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      final can = _text.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
    // the keyboard comes up after the pane has slid in, not during it
    Future<void>.delayed(const Duration(milliseconds: 340), () {
      if (mounted) _focus.requestFocus();
    });
    VibeReplyThread._olderParents(_chain, widget.timeline).then((older) {
      if (mounted && older.isNotEmpty) {
        setState(() => _chain = [...older, ..._chain]);
      }
    });
  }

  @override
  void dispose() {
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
    try {
      if (text.isNotEmpty) {
        await widget.room.sendTextEvent(
          text,
          inReplyTo: _target,
          threadRootEventId: widget.threadRootEventId,
          threadLastEventId: widget.threadLastEventId,
        );
      }
      VibeHaptics.light();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
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
                  itemBuilder: (context, i) {
                    final e = events[i];
                    // each message slides up a moment after the one below
                    final start = (i * 0.08).clamp(0.0, 0.5);
                    final t = CurvedAnimation(
                      parent: _intro,
                      curve: Interval(
                        start,
                        (start + 0.5).clamp(0.0, 1.0),
                        curve: Curves.easeOutBack,
                      ),
                    );
                    return RepaintBoundary(
                      key: ValueKey(e.eventId),
                      child: AnimatedBuilder(
                        animation: t,
                        builder: (context, child) => Opacity(
                          opacity: t.value.clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, 28 * (1 - t.value)),
                            child: child,
                          ),
                        ),
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

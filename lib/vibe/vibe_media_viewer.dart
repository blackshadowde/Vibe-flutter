// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_dialog.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/pages/chat/events/video_player.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/vibe/vibe_media_saver.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/vibe/vibe_stable_id.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// Google Messages style media slideshow: swipe through every photo and
/// video of the chat, neighbours peek in at the sides, thumbnail strip at
/// the bottom. Tap a photo to zoom.
class VibeMediaViewer extends StatefulWidget {
  final List<Event> events;
  final int initial;
  const VibeMediaViewer({
    required this.events,
    required this.initial,
    super.key,
  });

  static Future<void> open(
    BuildContext context,
    List<Event> events,
    int index,
  ) => Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) =>
          VibeMediaViewer(events: events, initial: index),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(
            CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    ),
  );

  /// Tapping a photo or video in a chat: a slideshow of every photo and
  /// video loaded in that chat (oldest left, newest right), starting at it.
  static Future<void> openFromTimeline(
    BuildContext context,
    Event event,
    Timeline? timeline,
  ) {
    final media =
        (timeline?.events ?? const <Event>[])
            .where(
              (e) =>
                  !e.redacted &&
                  e.type == EventTypes.Message &&
                  {
                    MessageTypes.Image,
                    MessageTypes.Video,
                  }.contains(e.messageType),
            )
            .toList()
            .reversed
            .toList();
    var index = media.indexWhere((e) => e.eventId == event.eventId);
    if (index < 0) {
      media.add(event);
      index = media.length - 1;
    }
    return open(context, media, index);
  }

  @override
  State<VibeMediaViewer> createState() => _VibeMediaViewerState();
}

class _VibeMediaViewerState extends State<VibeMediaViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initial,
    viewportFraction: 0.88,
  );
  late final ScrollController _strip = ScrollController();
  late int _index = widget.initial;
  double _dragDown = 0;

  static const _thumb = 56.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerStrip());
  }

  @override
  void dispose() {
    MxcImage.clearCache('vibe-viewer');
    _pages.dispose();
    _strip.dispose();
    super.dispose();
  }

  void _centerStrip() {
    if (!_strip.hasClients) return;
    final w = MediaQuery.sizeOf(context).width;
    final target = (_index * (_thumb + 8)) - w / 2 + _thumb / 2 + 12;
    _strip.animateTo(
      target.clamp(0.0, _strip.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.events[_index];
    final sender = event.senderFromMemoryOrFallback.calcDisplayname();
    final fade = (1 - _dragDown / 300).clamp(0.3, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: fade),
      body: SafeArea(
        child: Column(
          children: [
            // ---- top bar ----
            Opacity(
              opacity: fade,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          event.originServerTs.localizedTime(context),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.download_outlined,
                      color: Colors.white,
                    ),
                    tooltip: 'Save to gallery',
                    onPressed: () => VibeMediaSaver.save(context, event),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined, color: Colors.white),
                    tooltip: 'Share',
                    onPressed: () => event.shareFile(context),
                  ),
                ],
              ),
            ),
            // ---- slideshow ----
            Expanded(
              child: GestureDetector(
                // swipe down to close
                onVerticalDragUpdate: (d) => setState(
                  () => _dragDown = (_dragDown + d.delta.dy).clamp(0, 400),
                ),
                onVerticalDragEnd: (d) {
                  if (_dragDown > 120 || (d.primaryVelocity ?? 0) > 900) {
                    Navigator.of(context).pop();
                  } else {
                    setState(() => _dragDown = 0);
                  }
                },
                child: Transform.translate(
                  offset: Offset(0, _dragDown),
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: widget.events.length,
                    onPageChanged: (i) {
                      VibeHaptics.selection();
                      setState(() => _index = i);
                      _centerStrip();
                    },
                    itemBuilder: (context, i) => AnimatedBuilder(
                      animation: _pages,
                      builder: (context, child) {
                        var d = 0.0;
                        if (_pages.hasClients &&
                            _pages.position.haveDimensions) {
                          d = ((_pages.page ?? i.toDouble()) - i).abs();
                        } else {
                          d = (i - _index).abs().toDouble();
                        }
                        // Neighbours shrink a little (paint-only; no
                        // see-through layer, which was costly per frame).
                        final s = (1 - 0.1 * d).clamp(0.85, 1.0);
                        return Transform.scale(scale: s, child: child);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 12,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: _Slide(
                            event: widget.events[i],
                            hero: i == widget.initial,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // ---- thumbnail strip ----
            Opacity(
              opacity: fade,
              child: SizedBox(
                height: _thumb + 20,
                child: ListView.separated(
                  controller: _strip,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  itemCount: widget.events.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final sel = i == _index;
                    final e = widget.events[i];
                    return GestureDetector(
                      onTap: () => _pages.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: _thumb,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sel ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Opacity(
                            opacity: sel ? 1 : 0.6,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                MxcImage(
                                  key: ValueKey('thumb_${e.eventId}'),
                                  cacheKey: 'thumb_${e.eventId}',
                                  event: e,
                                  width: _thumb,
                                  height: _thumb,
                                  fit: BoxFit.cover,
                                  isThumbnail: true,
                                ),
                                if (e.messageType == MessageTypes.Video)
                                  const Center(
                                    child: Icon(
                                      Icons.play_circle_fill,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  final Event event;
  final bool hero;
  const _Slide({required this.event, this.hero = false});

  /// Long-press: close the slideshow (and any pane under it) and show this
  /// photo or video in the chat.
  void _jump(BuildContext context) {
    final router = GoRouter.of(context);
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((r) => r.settings is Page || r.isFirst);
    router.go('/rooms/${event.room.id}?event=${event.eventId}');
  }

  /// The chat's own thumbnail (already in memory), shown instantly.
  Widget _thumb() => MxcImage(
    key: ValueKey('chat_thumb_${VibeStableId.of(event)}'),
    cacheName: event.room.id,
    cacheKey: VibeStableId.of(event),
    event: event,
    fit: BoxFit.contain,
    isThumbnail: true,
    placeholder: (_) => const SizedBox.shrink(),
  );

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (event.messageType == MessageTypes.Video) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          _thumb(),
          // The player starts once the slideshow has opened.
          VibeSettled(child: Center(child: EventVideoPlayer(event))),
        ],
      );
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          _thumb(),
          // Full picture loads after the opening animation, on top of the
          // thumbnail, so opening is instant and smooth.
          VibeSettled(
            child: MxcImage(
              // Full pictures stay in memory while the slideshow is open, so
              // swiping back doesn't load them again (freed on close).
              key: ValueKey('full_${event.eventId}'),
              cacheName: 'vibe-viewer',
              cacheKey: 'full_${event.eventId}',
              event: event,
              fit: BoxFit.contain,
              isThumbnail: false,
              animated: true,
              placeholder: (_) => const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }
    content = ColoredBox(color: const Color(0xFF111214), child: content);
    if (hero) content = Hero(tag: event.eventId, child: content);
    return GestureDetector(
      onLongPress: () => _jump(context),
      // tap a photo to zoom in the full image viewer
      onTap: event.messageType == MessageTypes.Video
          ? null
          : () => showVibeDialog(
              context: context,
              builder: (_) => ImageViewer(event, outerContext: context),
            ),
      child: content,
    );
  }
}

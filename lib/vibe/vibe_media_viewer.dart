// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat/events/video_player.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
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
                    tooltip: 'Save',
                    onPressed: () => event.saveFile(context),
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
                        final s = (1 - 0.1 * d).clamp(0.85, 1.0);
                        return Transform.scale(
                          scale: s,
                          child: Opacity(
                            opacity: (1 - 0.4 * d).clamp(0.5, 1.0),
                            child: child,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 12,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: _Slide(event: widget.events[i]),
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
  const _Slide({required this.event});

  @override
  Widget build(BuildContext context) {
    if (event.messageType == MessageTypes.Video) {
      return ColoredBox(
        color: const Color(0xFF111214),
        child: Center(child: EventVideoPlayer(event)),
      );
    }
    return GestureDetector(
      // tap to zoom in the full image viewer
      onTap: () => showDialog(
        context: context,
        builder: (_) => ImageViewer(event, outerContext: context),
      ),
      child: ColoredBox(
        color: const Color(0xFF111214),
        child: MxcImage(
          event: event,
          fit: BoxFit.contain,
          isThumbnail: false,
          animated: true,
        ),
      ),
    );
  }
}

// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/config/themes.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/utils/show_scaffold_dialog.dart';
import 'package:vibe/widgets/share_scaffold_dialog.dart';
import 'package:vibe/vibe/vibe_media_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/screens/image_viewer/video_player.dart';
import 'package:vibe/widgets/hover_builder.dart';
import 'package:vibe/widgets/mxc_image.dart';

class ImageViewer extends StatefulWidget {
  final Event event;
  final Timeline? timeline;
  final BuildContext outerContext;

  const ImageViewer(
    this.event, {
    required this.outerContext,
    this.timeline,
    super.key,
  });

  @override
  _ImageViewerState createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  final FocusNode focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    allEvents =
        widget.timeline?.events
            .where(
              (event) => {
                MessageTypes.Image,
                MessageTypes.Sticker,
                if (PlatformInfos.supportsVideoPlayer) MessageTypes.Video,
              }.contains(event.messageType),
            )
            .toList()
            .reversed
            .toList() ??
        [widget.event];
    var index = allEvents.indexWhere(
      (event) => event.eventId == widget.event.eventId,
    );
    if (index < 0) index = 0;
    pageController = PageController(initialPage: index);
  }

  late final PageController pageController;

  late final List<Event> allEvents;

  void onKeyEvent(KeyEvent event) {
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        if (canGoBack) prevImage();
        break;
      case LogicalKeyboardKey.arrowDown:
        if (canGoNext) nextImage();
        break;
    }
  }

  Future<void> prevImage() async {
    await pageController.previousPage(
      duration: VibeThemes.animationDuration,
      curve: VibeThemes.animationCurve,
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> nextImage() async {
    await pageController.nextPage(
      duration: VibeThemes.animationDuration,
      curve: VibeThemes.animationCurve,
    );
    if (!mounted) return;
    setState(() {});
  }

  int get _index => pageController.page?.toInt() ?? 0;

  Event get currentEvent => allEvents[_index];

  bool get canGoNext => _index < allEvents.length - 1;

  bool get canGoBack => _index > 0;

  /// Forward this image to another room.
  void forwardAction() => showScaffoldDialog(
    context: context,
    builder: (context) =>
        ShareScaffoldDialog(items: [ContentShareItem(currentEvent.content)]),
  );

  /// Save this file with a system call.
  void saveFileAction(BuildContext context) =>
      VibeMediaSaver.save(context, currentEvent);

  /// Save this file with a system call.
  void shareFileAction(BuildContext context) => currentEvent.shareFile(context);

  static const maxScaleFactor = 1.5;

  /// Go back if user swiped it away
  void onInteractionEnds(ScaleEndDetails endDetails) {
    if (PlatformInfos.usesTouchscreen == false) {
      if (endDetails.velocity.pixelsPerSecond.dy >
          MediaQuery.sizeOf(context).height * maxScaleFactor) {
        Navigator.of(context, rootNavigator: false).pop();
      }
    }
  }

  @override
  void dispose() {
    focusNode.dispose();
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconButtonStyle = IconButton.styleFrom(
      backgroundColor: Colors.black.withAlpha(200),
      foregroundColor: Colors.white,
    );
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black.withAlpha(128),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          elevation: 0,
          leading: IconButton(
            style: iconButtonStyle,
            icon: const Icon(Icons.close),
            onPressed: Navigator.of(context).pop,
            color: Colors.white,
            tooltip: L10n.of(context).close,
          ),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              style: iconButtonStyle,
              icon: const Icon(Icons.reply_outlined),
              onPressed: forwardAction,
              color: Colors.white,
              tooltip: L10n.of(context).share,
            ),
            const SizedBox(width: 8),
            IconButton(
              style: iconButtonStyle,
              icon: const Icon(Icons.download_outlined),
              onPressed: () => saveFileAction(context),
              color: Colors.white,
              tooltip: L10n.of(context).downloadFile,
            ),
            const SizedBox(width: 8),
            if (PlatformInfos.isMobile)
              // Use builder context to correctly position the share dialog on iPad
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Builder(
                  builder: (context) => IconButton(
                    style: iconButtonStyle,
                    onPressed: () => shareFileAction(context),
                    tooltip: L10n.of(context).share,
                    color: Colors.white,
                    icon: Icon(Icons.adaptive.share_outlined),
                  ),
                ),
              ),
          ],
        ),
        body: HoverBuilder(
          builder: (context, hovered) => Stack(
            children: [
              KeyboardListener(
                focusNode: focusNode,
                onKeyEvent: onKeyEvent,
                child: PageView.builder(
                  scrollDirection: Axis.vertical,
                  controller: pageController,
                  itemCount: allEvents.length,
                  itemBuilder: (context, i) {
                    final event = allEvents[i];
                    switch (event.messageType) {
                      case MessageTypes.Video:
                        return Padding(
                          padding: const EdgeInsets.only(top: 52.0),
                          child: Center(
                            child: GestureDetector(
                              // Ignore taps to not go back here:
                              onTap: () {},
                              child: EventVideoPlayer(event),
                            ),
                          ),
                        );
                      case MessageTypes.Image:
                      case MessageTypes.Sticker:
                      default:
                        return InteractiveViewer(
                          minScale: 1.0,
                          maxScale: 10.0,
                          onInteractionEnd: onInteractionEnds,
                          child: Center(
                            child: Hero(
                              tag: event.eventId,
                              child: GestureDetector(
                                // Ignore taps to not go back here:
                                onTap: () {},
                                child: MxcImage(
                                  key: ValueKey(event.eventId),
                                  event: event,
                                  fit: BoxFit.contain,
                                  isThumbnail: false,
                                  animated: true,
                                ),
                              ),
                            ),
                          ),
                        );
                    }
                  },
                ),
              ),
              if (hovered)
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    mainAxisSize: .min,
                    children: [
                      if (canGoBack)
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: IconButton(
                            style: iconButtonStyle,
                            tooltip: L10n.of(context).previous,
                            icon: const Icon(Icons.arrow_upward_outlined),
                            onPressed: prevImage,
                          ),
                        ),
                      if (canGoNext)
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: IconButton(
                            style: iconButtonStyle,
                            tooltip: L10n.of(context).next,
                            icon: const Icon(Icons.arrow_downward_outlined),
                            onPressed: nextImage,
                          ),
                        ),
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


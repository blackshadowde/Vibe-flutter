// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_date_pill.dart';
import 'package:collection/collection.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/screens/chat/chat.dart';
import 'package:vibe/vibe/screens/chat/encrpytion_info.dart';
import 'package:vibe/vibe/screens/chat/events/message.dart';
import 'package:vibe/vibe/screens/chat/seen_by_row.dart';
import 'package:vibe/vibe/screens/chat/typing_indicators.dart';
import 'package:vibe/utils/account_config.dart';
import 'package:vibe/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/vibe/vibe_entrance.dart';
import 'package:vibe/vibe/vibe_message.dart';
import 'package:vibe/vibe/vibe_message_menu.dart';
import 'package:vibe/vibe/vibe_starred.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix_api_lite/model/event_types.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:vibe/utils/date_time_extension.dart';

class ChatEventList extends StatelessWidget {
  final ChatController controller;

  const ChatEventList({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final timeline = controller.timeline;

    if (timeline == null) {
      return const Center(child: CupertinoActivityIndicator());
    }
    final theme = Theme.of(context);

    final colors = [theme.secondaryBubbleColor, theme.bubbleColor];

    final horizontalPadding = VibeThemes.isColumnMode(context) ? 8.0 : 0.0;

    final hiddenIds = VibeHidden.ids(controller.room.id);
    final events = timeline.events
        .filterByVisibleInGui(threadId: controller.activeThreadId)
        .where((e) => !hiddenIds.contains(e.eventId))
        .toList();

    // create a map of eventId --> index to greatly improve performance of
    // ListView's findChildIndexCallback
    // Keyed by the same stable id as the list items, so a message keeps its
    // widget (and doesn't animate again) when its id changes after sending.
    final thisEventsKeyMap = <String, int>{};
    for (var i = 0; i < events.length; i++) {
      thisEventsKeyMap[controller.stableId(events[i])] = i;
    }

    final hasWallpaper =
        controller.room.client.applicationAccountConfig.wallpaperUrl != null;

    return Stack(
      children: [
        MediaQuery(
        data: MediaQuery.of(context).copyWith(
          // Like Telegram: message text uses the Text size setting, names
          // and times keep their size (no scaling of the whole chat).
          textScaler: TextScaler.noScaling,
        ),
        child: ValueListenableBuilder<double?>(
          valueListenable: controller.inputBarHeightNotifier,
          // Only the space under the list changes; the messages themselves
          // are not rebuilt while the input bar resizes.
          builder: (context, barHeight, list) => Padding(
            padding: EdgeInsets.only(
              bottom:
                  barHeight ??
                  (72 + (VibeThemes.isColumnMode(context) ? 16 : 0)),
            ),
            child: list,
          ),
          child: ListView.custom(
          padding: EdgeInsets.only(
            top: 8 + MediaQuery.paddingOf(context).top,
            bottom: 8,
            left: horizontalPadding,
            right: horizontalPadding,
          ),
          reverse: true,
          // Build (and start loading pictures for) about a screen and a half
          // beyond the edge, so messages are ready before they scroll in.
          // (not while the chat is still sliding in: only what's on screen)
          cacheExtent: controller.routeSettled ? 1200 : 0,
          controller: controller.scrollController,
          keyboardDismissBehavior: PlatformInfos.isIOS
              ? ScrollViewKeyboardDismissBehavior.onDrag
              : ScrollViewKeyboardDismissBehavior.manual,
          childrenDelegate: SliverChildBuilderDelegate(
            (BuildContext context, int i) {
              // Footer to display typing indicator and read receipts:
              if (i == 0) {
                if (timeline.canRequestFuture) {
                  return Center(
                    child: TextButton.icon(
                      onPressed: timeline.isRequestingFuture
                          ? null
                          : controller.requestFuture,
                      icon: timeline.isRequestingFuture
                          ? CircularProgressIndicator.adaptive(strokeWidth: 2)
                          : const Icon(Icons.arrow_downward_outlined),
                      label: Text(L10n.of(context).loadMore),
                    ),
                  );
                }
                return Column(
                  mainAxisSize: .min,
                  children: [
                    if (events.isNotEmpty) SeenByRow(event: events.first),
                    TypingIndicators(controller),
                    EncryptionInfo(room: controller.room),
                  ],
                );
              }

              // Request history button or progress indicator:
              if (i == events.length + 1) {
                if (controller.activeThreadId != null) {
                  return const SizedBox.shrink();
                }
                if (!timeline.canRequestHistory) {
                  return VibeChatIntro(controller.room);
                }
                return Builder(
                  builder: (context) {
                    final visibleIndex = timeline.events.lastIndexWhere(
                      (event) =>
                          !event.isCollapsedState && event.isVisibleInGui,
                    );
                    if (visibleIndex > timeline.events.length - 50) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        controller.requestHistory,
                      );
                    }
                    return Center(
                      child: TextButton.icon(
                        onPressed: timeline.isRequestingHistory
                            ? null
                            : controller.requestHistory,
                        icon: timeline.isRequestingHistory
                            ? CircularProgressIndicator.adaptive(strokeWidth: 2)
                            : const Icon(Icons.arrow_upward_outlined),
                        label: Text(L10n.of(context).loadMore),
                      ),
                    );
                  },
                );
              }
              i--;

              // The message at this index:
              final event = events[i];
              final stableId = controller.stableId(event);
              final animateIn = stableId == controller.animateInEventId;

              final nextEvent = i + 1 < events.length ? events[i + 1] : null;
              final previousEvent = i > 0 ? events[i - 1] : null;

              // Collapsed state event
              final canExpand =
                  event.isCollapsedState &&
                  nextEvent?.isCollapsedState == true &&
                  previousEvent?.isCollapsedState != true;
              final isCollapsed =
                  event.isCollapsedState &&
                  previousEvent?.isCollapsedState == true &&
                  !controller.expandedEventIds.contains(event.eventId);

              final displayDate =
                  event.type == EventTypes.RoomCreate ||
                  nextEvent == null ||
                  !event.originServerTs.sameDay(nextEvent.originServerTs);

              return AutoScrollTag(
                key: ValueKey(stableId),
                index: i,
                controller: controller.scrollController,
                child: RepaintBoundary(
                  child: VibeEntrance(
                  animate: animateIn,
                  fromRight:
                      event.senderId == controller.room.client.userID,
                  child: Column(
                  mainAxisSize: .min,
                  children: [
                    if (!isCollapsed && displayDate)
                      VibeDateDivider(event.originServerTs),
                    Message(
                      event,
                      bigEmojis: controller.bigEmojis,
                      animateIn: false,
                      onSwipe: () => controller.replyAction(replyTo: event),
                      onInfoTab: controller.showEventInfo,
                      onMention: () => controller.sendController.text +=
                          '${event.senderFromMemoryOrFallback.mention} ',
                      highlightMarker:
                          controller.scrollToEventIdMarker == event.eventId ||
                          controller.replyEvent?.eventId == event.eventId ||
                          controller.editEvent?.eventId == event.eventId,
                      onSelect: controller.onSelectMessage,
                      onLongPress: (e) =>
                          VibeMessageMenu.show(context, controller, e),
                      scrollToEventId: controller.scrollToEventId,
                      longPressSelect: controller.selectedEvents.isNotEmpty,
                      selected: controller.selectedEvents.any(
                        (e) => e.eventId == event.eventId,
                      ),
                      singleSelected:
                          controller.selectedEvents.singleOrNull?.eventId ==
                          event.eventId,
                      onEdit: controller.editSelectedEventAction,
                      timeline: timeline,
                      displayReadMarker:
                          i > 0 &&
                          controller.readMarkerEventId == event.eventId,
                      nextEvent: nextEvent,
                      previousEvent: previousEvent,
                      wallpaperMode: hasWallpaper,
                      scrollController: controller.scrollController,
                      colors: colors,
                      isCollapsed: isCollapsed,
                      enterThread: controller.activeThreadId == null
                          ? controller.enterThread
                          : null,
                      onExpand: canExpand
                          ? () => controller.expandEventsFrom(
                              event,
                              !controller.expandedEventIds.contains(
                                event.eventId,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
                ),
                ),
              );
            },
            childCount: events.length + 2,
            findChildIndexCallback: (key) =>
                controller.findChildIndexCallback(key, thisEventsKeyMap),
          ),
        ),
        ),
      ),
        // the day of the messages at the top, while scrolling (like Vibe X)
        Positioned(
          top: 8 + MediaQuery.paddingOf(context).top,
          left: 0,
          right: 0,
          child: Center(
            child: VibeDatePill(
              scroll: controller.scrollController,
              events: () => events,
            ),
          ),
        ),
      ],
    );
  }
}

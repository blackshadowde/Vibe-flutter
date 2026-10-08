// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:collection/collection.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/message_content.dart';
import 'package:fluffychat/pages/chat/events/message_reactions.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/vibe/vibe_disappearing.dart';
import 'package:fluffychat/vibe/vibe_heart_burst.dart';
import 'package:fluffychat/vibe/vibe_user_sheet.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:fluffychat/vibe/vibe_swipe_reply.dart';
import 'package:fluffychat/vibe/vibe_chunks.dart';

const Color _ownNameColor = Color(0xFFB5BAC1);
const Color _otherNameColor = Color(0xFFF2F3F5);
const Color _readTickColor = Color(0xFF5865F2);

String vibeTime(DateTime ts) {
  final local = ts.toLocal();
  final now = DateTime.now();
  final t = DateFormat('hh:mm a').format(local);
  final d = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  if (d == today) return 'Today at $t';
  if (today.difference(d).inDays == 1) return 'Yesterday at $t';
  return '${DateFormat.yMd().format(local)} $t';
}

String vibeDayLabel(DateTime ts) {
  final local = ts.toLocal();
  final now = DateTime.now();
  final d = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  if (d == today) return 'Today';
  if (today.difference(d).inDays == 1) return 'Yesterday';
  return DateFormat.yMMMMd().format(local);
}

/// "──── Today ────" divider between days.
class VibeDateDivider extends StatelessWidget {
  final DateTime date;
  const VibeDateDivider(this.date, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, color: theme.dividerColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              vibeDayLabel(date),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Divider(height: 1, color: theme.dividerColor)),
        ],
      ),
    );
  }
}

/// "Welcome to your chat with X!" block shown at the very top of a chat.
class VibeChatIntro extends StatelessWidget {
  final Room room;
  const VibeChatIntro(this.room, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final dm = room.isDirectChat;
    final enc = room.encrypted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.surfaceContainerHighest,
            ),
            child: Text(
              dm ? '@' : '#',
              style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            dm ? 'Welcome to your chat with $name!' : 'Welcome to $name!',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            dm
                ? 'This is the start of your direct ${enc ? 'encrypted ' : ''}conversation with $name.${enc ? ' End-to-end encrypted with Megolm v1 AES-SHA2.' : ''}'
                : 'This is the start of the $name conversation.${enc ? ' End-to-end encrypted with Megolm v1 AES-SHA2.' : ''}',
            style: TextStyle(
              fontSize: 16,
              height: 1.35,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(child: Divider(height: 1, color: theme.dividerColor)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  enc ? 'LIVE ENCRYPTED STREAM' : 'LIVE STREAM',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(child: Divider(height: 1, color: theme.dividerColor)),
            ],
          ),
        ],
      ),
    );
  }
}

bool _readByOther(Event event, Timeline timeline) {
  final me = event.room.client.userID;
  for (final e in timeline.events) {
    if (e.receipts.any((r) => r.user.id != me)) return true;
    if (e.eventId == event.eventId) break;
  }
  return false;
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Sending / sent (single tick) / read (two blue ticks) indicator.
class _StatusBits extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  const _StatusBits(this.event, this.timeline);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = event.status;
    final dim = theme.colorScheme.onSurfaceVariant;
    if (status == EventStatus.error) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 16,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 4),
              Text(
                L10n.of(context).couldNotBeSent,
                style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
              ),
            ],
          ),
          _MiniAction(
            icon: Icons.refresh,
            label: 'Retry',
            color: theme.colorScheme.primary,
            onTap: () => event.sendAgain(),
          ),
          _MiniAction(
            icon: Icons.close,
            label: 'Cancel',
            color: theme.colorScheme.error,
            onTap: () => event.cancelSend(),
          ),
        ],
      );
    }
    if (status == EventStatus.sending) {
      final label = switch (event.fileSendingStatus) {
        null => event.room.encrypted ? 'Encrypting…' : 'Sending…',
        FileSendingStatus.generatingThumbnail =>
          L10n.of(context).generatingThumbnail,
        FileSendingStatus.encrypting => L10n.of(context).encrypting,
        FileSendingStatus.uploading => L10n.of(context).uploading,
      };
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: dim)),
          const SizedBox(width: 6),
          SizedBox.square(
            dimension: 11,
            child: CircularProgressIndicator(strokeWidth: 1.4, color: dim),
          ),
          if (event.fileSendingStatus != null) ...[
            const SizedBox(width: 10),
            _MiniAction(
              icon: Icons.close,
              label: 'Cancel',
              color: theme.colorScheme.error,
              onTap: () => event.cancelSend(),
            ),
          ],
        ],
      );
    }
    return StreamBuilder(
      stream: event.room.client.onSync.stream.where(
        (u) =>
            u.rooms?.join?[event.room.id]?.ephemeral?.any(
              (e) => e.type == 'm.receipt',
            ) ??
            false,
      ),
      builder: (context, _) {
        final read = _readByOther(event, timeline);
        return Icon(
          read ? Icons.done_all : Icons.done,
          size: 18,
          color: read ? _readTickColor : dim,
        );
      },
    );
  }
}

class VibeMessage extends StatelessWidget {
  final Event event;
  final Event? nextEvent;
  final Event? previousEvent;
  final bool displayReadMarker;
  final void Function(Event) onSelect;
  final void Function(Event) onInfoTab;
  final void Function(String) scrollToEventId;
  final void Function() onSwipe;
  final void Function() onMention;
  final void Function(String eventId)? enterThread;
  final bool longPressSelect;
  final bool selected;
  final bool singleSelected;
  final Timeline timeline;
  final bool highlightMarker;
  final Set<String> bigEmojis;
  final void Function(Event)? onLongPress;

  const VibeMessage(
    this.event, {
    required this.nextEvent,
    required this.previousEvent,
    required this.displayReadMarker,
    required this.onSelect,
    required this.onInfoTab,
    required this.scrollToEventId,
    required this.onSwipe,
    required this.onMention,
    required this.enterThread,
    required this.longPressSelect,
    required this.selected,
    required this.singleSelected,
    required this.timeline,
    required this.highlightMarker,
    required this.bigEmojis,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (VibeDisappearing.isExpired(event)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final client = Matrix.of(context).client;
    final ownMessage = event.senderId == client.userID;

    bool sameGroup(Event? e) =>
        e != null &&
        {EventTypes.Message, EventTypes.Sticker}.contains(e.type) &&
        e.senderId == event.senderId &&
        e.originServerTs.sameEnvironment(event.originServerTs);

    // The list is newest-first, so "nextEvent" is the OLDER neighbour.
    bool hasReply(Event? e) =>
        e != null && e.inReplyToEventId(includingFallback: false) != null;
    // A reply always starts a new visual group (avatar + header + reply line).
    final replying = hasReply(event);
    final first = replying || !sameGroup(nextEvent);
    final last = hasReply(previousEvent) || !sameGroup(previousEvent);

    final displayEvent = event.getDisplayEvent(timeline);
    final sender = event.senderFromMemoryOrFallback;
    final hasReactions = event.hasAggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );
    final threadChildren = event.aggregatedEvents(
      timeline,
      RelationshipTypes.thread,
    );
    final isEdited = event.hasAggregatedEvents(timeline, RelationshipTypes.edit);
    final showReactionPicker =
        singleSelected && event.room.canSendDefaultMessages;
    final enterThread = this.enterThread;
    const avatarSize = 46.0;

    final sentReactions = <String>{};
    if (singleSelected) {
      sentReactions.addAll(
        event
            .aggregatedEvents(timeline, RelationshipTypes.reaction)
            .where(
              (e) =>
                  e.senderId == e.room.client.userID && e.type == 'm.reaction',
            )
            .map(
              (e) => e.content
                  .tryGetMap<String, Object?>('m.relates_to')
                  ?.tryGet<String>('key'),
            )
            .whereType<String>(),
      );
    }

    Widget avatar() {
      if (longPressSelect && !event.redacted) {
        return SizedBox(
          width: avatarSize,
          height: avatarSize,
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: L10n.of(context).select,
            icon: Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
            ),
            onPressed: () => onSelect(event),
          ),
        );
      }
      if (!first) return const SizedBox(width: avatarSize);
      return FutureBuilder<User?>(
        future: event.fetchSenderUser(),
        builder: (context, snapshot) {
          final user = snapshot.data ?? sender;
          return Avatar(
            mxContent: user.avatarUrl,
            name: user.calcDisplayname(),
            size: avatarSize,
            client: client,
            onTap: () => VibeUserSheet.show(
              context,
              client: client,
              userId: user.id,
              displayName: user.calcDisplayname(),
              avatarUrl: user.avatarUrl,
              currentRoomId: event.room.id,
            ),
          );
        },
      );
    }

    Widget header() {
      return FutureBuilder<User?>(
        future: event.fetchSenderUser(),
        builder: (context, snapshot) {
          final displayname =
              snapshot.data?.calcDisplayname() ?? sender.calcDisplayname();
          final color = ownMessage
              ? _ownNameColor
              : event.room.isDirectChat
              ? _otherNameColor
              : (theme.brightness == Brightness.light
                    ? displayname.colorScheme.primary
                    : displayname.colorScheme.primaryContainer);
          return Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  displayname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16.5,
                    color: color,
                  ),
                ),
              ),
              Icon(
                event.room.encrypted ? Icons.lock_outline : Icons.lock_open,
                size: 16,
                color: event.room.encrypted
                    ? cs.onSurfaceVariant
                    : Colors.redAccent,
              ),
              if (event.status.isSent)
                Text(
                  vibeTime(event.originServerTs),
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              if (isEdited)
                Text(
                  L10n.of(context).edited,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
            ],
          );
        },
      );
    }

    Widget replyStrip() {
      return FutureBuilder<Event?>(
        future: event.getReplyEvent(timeline),
        builder: (context, snapshot) {
          final replyEvent = snapshot.data;
          final lineColor = cs.onSurfaceVariant.withValues(alpha: 0.45);
          Widget content;
          if (replyEvent == null) {
            content = Text(
              snapshot.connectionState == ConnectionState.done
                  ? 'Original message not available'
                  : '…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
              ),
            );
          } else {
            final rs = replyEvent.senderFromMemoryOrFallback;
            final rname = rs.calcDisplayname();
            final rown = replyEvent.senderId == client.userID;
            final rcolor = rown
                ? _ownNameColor
                : event.room.isDirectChat
                ? _otherNameColor
                : (theme.brightness == Brightness.light
                      ? rname.colorScheme.primary
                      : rname.colorScheme.primaryContainer);
            final preview = replyEvent
                .getDisplayEvent(timeline)
                .calcLocalizedBodyFallback(
                  MatrixLocals(L10n.of(context)),
                  hideReply: true,
                  hideEdit: true,
                  plaintextBody: true,
                  removeMarkdown: true,
                );
            content = Row(
              children: [
                Avatar(
                  mxContent: rs.avatarUrl,
                  name: rname,
                  size: 16,
                  client: client,
                ),
                const SizedBox(width: 6),
                Flexible(
                  flex: 0,
                  child: Text(
                    '@$rname',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: rcolor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          }
          return InkWell(
            onTap: replyEvent == null
                ? null
                : () => scrollToEventId(replyEvent.eventId),
            child: SizedBox(
              height: 22,
              child: Row(
                children: [
                  SizedBox(
                    width: avatarSize,
                    height: 22,
                    child: CustomPaint(painter: _ReplyCurve(lineColor)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: content),
                ],
              ),
            ),
          );
        },
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (first) header(),
        Align(
          alignment: Alignment.centerLeft,
          child: Builder(
            builder: (context) {
              final content = VibeChunks.info(displayEvent) != null
                  ? VibeChunkCard(displayEvent)
                  : MessageContent(
                      displayEvent,
                      textColor: cs.onSurface,
                      linkColor: cs.primary,
                      onInfoTab: onInfoTab,
                      borderRadius: BorderRadius.circular(14),
                      timeline: timeline,
                      selected: selected,
                      bigEmojis: bigEmojis,
                    );
              // Sent/read ticks sit right after the text, like WhatsApp.
              if (!ownMessage || !event.status.isSent) return content;
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(child: content),
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 3),
                    child: _StatusBits(event, timeline),
                  ),
                ],
              );
            },
          ),
        ),
        if (hasReactions)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: MessageReactions(event, timeline),
          ),
        // Sending / failed (with Retry and Cancel) stays under the message.
        if (ownMessage && !event.status.isSent)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _StatusBits(event, timeline),
          ),
                                    Align(
                              alignment: Alignment.bottomLeft,
                              child: AnimatedSize(
                                duration: FluffyThemes.animationDuration,
                                curve: FluffyThemes.animationCurve,
                                child: showReactionPicker
                                    ? Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Material(
                                          elevation: 4,
                                          borderRadius: BorderRadius.circular(
                                            AppConfig.borderRadius,
                                          ),
                                          shadowColor: theme.colorScheme.surface
                                              .withAlpha(128),
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              mainAxisSize: .min,
                                              children: [
                                                ...AppConfig.defaultReactions.map(
                                                  (emoji) => IconButton(
                                                    padding: EdgeInsets.zero,
                                                    icon: Center(
                                                      child: Opacity(
                                                        opacity:
                                                            sentReactions
                                                                .contains(emoji)
                                                            ? 0.33
                                                            : 1,
                                                        child: Text(
                                                          emoji,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 20,
                                                              ),
                                                          textAlign:
                                                              TextAlign.center,
                                                        ),
                                                      ),
                                                    ),
                                                    onPressed:
                                                        sentReactions.contains(
                                                          emoji,
                                                        )
                                                        ? null
                                                        : () {
                                                            onSelect(event);
                                                            event.room
                                                                .sendReaction(
                                                                  event.eventId,
                                                                  emoji,
                                                                );
                                                          },
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.add_reaction_outlined,
                                                  ),
                                                  tooltip: L10n.of(
                                                    context,
                                                  ).customReaction,
                                                  onPressed: () async {
                                                    final emoji = await showAdaptiveBottomSheet<String>(
                                                      context: context,
                                                      builder: (context) => Scaffold(
                                                        appBar: AppBar(
                                                          title: Text(
                                                            L10n.of(
                                                              context,
                                                            ).customReaction,
                                                          ),
                                                          leading: CloseButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  context,
                                                                ).pop(null),
                                                          ),
                                                        ),
                                                        body: SizedBox(
                                                          height:
                                                              double.infinity,
                                                          child: EmojiPicker(
                                                            onEmojiSelected:
                                                                (_, emoji) =>
                                                                    Navigator.of(
                                                                      context,
                                                                    ).pop(
                                                                      emoji
                                                                          .emoji,
                                                                    ),
                                                            config: Config(
                                                              locale:
                                                                  Localizations.localeOf(
                                                                    context,
                                                                  ),
                                                              emojiViewConfig:
                                                                  const EmojiViewConfig(
                                                                    backgroundColor:
                                                                        Colors
                                                                            .transparent,
                                                                  ),
                                                              bottomActionBarConfig:
                                                                  const BottomActionBarConfig(
                                                                    enabled:
                                                                        false,
                                                                  ),
                                                              categoryViewConfig: CategoryViewConfig(
                                                                initCategory:
                                                                    Category
                                                                        .SMILEYS,
                                                                backspaceColor: theme
                                                                    .colorScheme
                                                                    .primary,
                                                                iconColor: theme
                                                                    .colorScheme
                                                                    .primary
                                                                    .withAlpha(
                                                                      128,
                                                                    ),
                                                                iconColorSelected:
                                                                    theme
                                                                        .colorScheme
                                                                        .primary,
                                                                indicatorColor: theme
                                                                    .colorScheme
                                                                    .primary,
                                                                backgroundColor:
                                                                    theme
                                                                        .colorScheme
                                                                        .surface,
                                                              ),
                                                              skinToneConfig: SkinToneConfig(
                                                                dialogBackgroundColor: Color.lerp(
                                                                  theme
                                                                      .colorScheme
                                                                      .surface,
                                                                  theme
                                                                      .colorScheme
                                                                      .primaryContainer,
                                                                  0.75,
                                                                )!,
                                                                indicatorColor: theme
                                                                    .colorScheme
                                                                    .onSurface,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                    if (emoji == null) {
                                                      return;
                                                    }
                                                    if (sentReactions.contains(
                                                      emoji,
                                                    )) {
                                                      return;
                                                    }
                                                    onSelect(event);

                                                    await event.room
                                                        .sendReaction(
                                                          event.eventId,
                                                          emoji,
                                                        );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
      ],
    );

    return VibeHeartHost(
      event: event,
      timeline: timeline,
      builder: (context, heart) => Center(
      child: VibeSwipeReply(
        key: ValueKey(event.transactionId ?? event.eventId),
        onReply: onSwipe,
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: FluffyThemes.maxTimelineWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: highlightMarker
                    ? const Color(0xFF5865F2).withAlpha(64)
                    : selected
                    ? cs.secondaryContainer.withAlpha(110)
                    : Colors.transparent,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: longPressSelect ? () => onSelect(event) : null,
                  onLongPress: longPressSelect
                      ? null
                      : () {
                          VibeHaptics.heavy();
                          final cb = onLongPress;
                          if (cb != null) {
                            cb(event);
                          } else {
                            onSelect(event);
                          }
                        },
                  onDoubleTap:
                      AppSettings.doubleTapToReact.value &&
                          event.room.canSendDefaultMessages
                      ? () {
                          VibeHaptics.light();
                          final emoji = AppSettings.doubleTapReaction.value;
                          final existing = event
                              .aggregatedEvents(
                                timeline,
                                RelationshipTypes.reaction,
                              )
                              .firstWhereOrNull(
                                (e) =>
                                    e.senderId == event.room.client.userID &&
                                    e.content
                                            .tryGetMap<String, Object?>(
                                              'm.relates_to',
                                            )
                                            ?.tryGet<String>('key') ==
                                        emoji,
                              );
                          if (existing != null) {
                            existing.redactEvent();
                          } else {
                            if (emoji.contains('❤')) heart.burst();
                            event.room.sendReaction(event.eventId, emoji);
                          }
                        }
                      : null,
                  onDoubleTapDown: (d) => heart.noteTap(d.globalPosition),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      first ? 12 : 1,
                      14,
                      last ? 6 : 1,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (replying) replyStrip(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            avatar(),
                            const SizedBox(width: 12),
                            Expanded(child: body),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
                            if (enterThread != null)
                AnimatedSize(
                  duration: FluffyThemes.animationDuration,
                  curve: FluffyThemes.animationCurve,
                  alignment: Alignment.bottomCenter,
                  child: threadChildren.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(
                            top: 2.0,
                            bottom: 8.0,
                            left: avatarSize + 8,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: FluffyThemes.columnWidth * 1.5,
                            ),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                foregroundColor:
                                    theme.colorScheme.onSecondaryContainer,
                                backgroundColor:
                                    theme.colorScheme.secondaryContainer,
                              ),
                              onPressed: () => enterThread(event.eventId),
                              icon: const Icon(Icons.message),
                              label: Text(
                                '${L10n.of(context).countReplies(threadChildren.length)} | ${threadChildren.first.calcLocalizedBodyFallback(MatrixLocals(L10n.of(context)), withSenderNamePrefix: true)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                ),
                            if (displayReadMarker)
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 16.0,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppConfig.borderRadius / 3,
                        ),
                        color: theme.colorScheme.surface.withAlpha(128),
                      ),
                      child: Text(
                        L10n.of(context).readUpToHere,
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}


/// Discord-style reply connector: up from the avatar's top-centre, then a
/// rounded corner to the right, ending beside the replied-to author.
class _ReplyCurve extends CustomPainter {
  final Color color;
  const _ReplyCurve(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final mid = size.height / 2;
    const r = 8.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(cx, size.height + 2)
      ..lineTo(cx, mid + r)
      ..quadraticBezierTo(cx, mid, cx + r, mid)
      ..lineTo(size.width, mid);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ReplyCurve old) => old.color != color;
}

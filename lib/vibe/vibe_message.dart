// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_member_tags.dart';
import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_effects.dart';
import 'package:vibe/vibe/vibe_emoji_sheet.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:collection/collection.dart';
import 'package:vibe/config/app_config.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/screens/chat/events/message_content.dart';
import 'package:vibe/vibe/screens/chat/events/message_reactions.dart';
import 'package:vibe/utils/date_time_extension.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/utils/string_color.dart';
import 'package:vibe/vibe/vibe_disappearing.dart';
import 'package:vibe/vibe/vibe_heart_burst.dart';
import 'package:vibe/vibe/vibe_user_sheet.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/vibe/vibe_stable_id.dart';
import 'package:vibe/vibe/vibe_slash.dart';
import 'package:vibe/vibe/vibe_name_style.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/vibe/vibe_swipe_reply.dart';
import 'package:vibe/vibe/vibe_chunks.dart';
import 'package:vibe/vibe/vibe_link_preview.dart';
import 'package:vibe/vibe/vibe_hot_words.dart';

const Color _ownNameColor = Color(0xFFB5BAC1);
const Color _otherNameColor = Color(0xFFF2F3F5);
// Light mode: dark names (the dark-mode greys/whites vanish on white).
const Color _ownNameColorLight = Color(0xFF4E5058);
const Color _otherNameColorLight = Color(0xFF060607);

/// Soft shadow under names in light mode, so they stand out on white.
List<Shadow>? _nameShadows(ThemeData theme) =>
    theme.brightness == Brightness.light
    ? const [
        Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
      ]
    : null;
Color get _readTickColor => VibePalette.accent;

String vibeTime(DateTime ts) {
  final local = ts.toLocal();
  final now = DateTime.now();
  final t = DateFormat('h:mm a').format(local);
  final d = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  // Discord style: just the time for today.
  if (d == today) return t;
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
  // Retry / Cancel: at least 40 dp tall so they're easy to hit.
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 8),
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

/// Failed messages and file uploads show their status (with buttons) under
/// the message; everything else shows it inline after the text.
bool _statusBelow(Event e) =>
    e.status == EventStatus.error ||
    (e.status == EventStatus.sending && e.fileSendingStatus != null);

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
      final offline =
          event.room.client.onSyncStatus.value?.status == SyncStatus.error;
      final label = switch (event.fileSendingStatus) {
        null when offline => 'Waiting for connection…',
        null => event.room.encrypted ? 'Encrypting…' : 'Sending…',
        FileSendingStatus.generatingThumbnail =>
          L10n.of(context).generatingThumbnail,
        FileSendingStatus.encrypting => L10n.of(context).encrypting,
        FileSendingStatus.uploading => L10n.of(context).uploading,
      };
      if (event.fileSendingStatus == null) {
        if (offline) return Text(label, style: TextStyle(fontSize: 12, color: dim));
        // Encrypting: a line runs between two dots; then it folds into one
        // dot that pulses while the message goes out.
        final ink = theme.brightness == Brightness.dark ? dim : const Color(0xFF111214);
        return VibeSendingDots(encrypting: event.room.encrypted, color: ink);
      }
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
        // dots instead of ticks: 1 grey sent, 2 grey delivered (back from
        // the server), 3 blue read. Grey turns black in light mode.
        final ink = theme.brightness == Brightness.dark ? dim : const Color(0xFF111214);
        final count = read ? 3 : (status.isSynced ? 2 : 1);
        return VibeStatusDots(count: count, color: read ? _readTickColor : ink);
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
    const avatarSize = 40.0;

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
              ? (theme.brightness == Brightness.light ? _ownNameColorLight : _ownNameColor)
              : event.room.isDirectChat
              ? (theme.brightness == Brightness.light ? _otherNameColorLight : _otherNameColor)
              : (theme.brightness == Brightness.light
                    ? displayname.colorScheme.primary
                    : displayname.colorScheme.primaryContainer);
          return Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 0,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: VibeNameText(
                  displayname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.15,
                    color: color,
                    shadows: _nameShadows(theme),
                  ),
                ),
              ),
              ...VibeMemberTags.chips(event.room, snapshot.data ?? sender),
              // Encrypted is the normal case (shown once in the chat
              // header); only warn when a chat is NOT encrypted.
              if (!event.room.encrypted)
                const Icon(
                  Icons.lock_open,
                  size: 14,
                  color: Colors.redAccent,
                ),
              if (event.status.isSent)
                Text(
                  vibeTime(event.originServerTs),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.15,
                    color: cs.onSurfaceVariant,
                  ),
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
                ? (theme.brightness == Brightness.light ? _ownNameColorLight : _ownNameColor)
                : event.room.isDirectChat
                ? (theme.brightness == Brightness.light ? _otherNameColorLight : _otherNameColor)
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
                      shadows: _nameShadows(theme),
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
              // Vibe X's soft shadow under the text in light mode
              final Widget content = DefaultTextStyle.merge(
                style: TextStyle(shadows: _nameShadows(theme)),
                // a long message is only as wide as its longest line, so the dots sit right after it
                textWidthBasis: TextWidthBasis.longestLine,
                child: VibeChunks.info(displayEvent) != null
                  ? VibeChunkCard(displayEvent)
                  // just a link: the preview card below stands in for it
                  : VibeLinkPreview.onlyLink(displayEvent)
                  ? const SizedBox.shrink()
                  : MessageContent(
                      displayEvent,
                      textColor: cs.onSurface,
                      linkColor: cs.primary,
                      onInfoTab: onInfoTab,
                      borderRadius: BorderRadius.circular(14),
                      timeline: timeline,
                      selected: selected,
                      bigEmojis: bigEmojis,
                    ),
              );
              // Sent with an effect: play it once as it arrives, and keep a
              // small badge to play it again.
              final effect = VibeEffects.of(event);
              if (effect != null) {
                VibeEffects.maybePlay(context, event);
              } else {
                // hot words (hahaha, congrats, kiss, hug, party...) fill the screen
                VibeHotWords.maybePlay(context, event);
              }
              // Status sits right after the text the whole time:
              // "Encrypting…" → ✓ → blue ✓✓, changing in place. Only
              // failures and file uploads (with Retry / Cancel) go below.
              final ticks = ownMessage && !_statusBelow(event);
              if (!ticks && effect == null) return content;
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(child: content),
                  if (effect != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: VibeEffectBadge(effect),
                    ),
                  // Sent/read ticks sit right after the text, like WhatsApp.
                  if (ticks)
                    Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 3),
                      child: _StatusBits(event, timeline),
                    ),
                ],
              );
            },
          ),
        ),
        VibeLinkPreview(event: displayEvent),
        if (hasReactions)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: MessageReactions(event, timeline),
          ),
        // Sending / failed (with Retry and Cancel) stays under the message.
        if (ownMessage && _statusBelow(event))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _StatusBits(event, timeline),
          ),
                                    Align(
                              alignment: Alignment.bottomLeft,
                              child: AnimatedSize(
                                duration: VibeThemes.animationDuration,
                                curve: VibeThemes.animationCurve,
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
                                                    final emoji = await VibeEmojiSheet.pick(
                                                      context,
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
        key: ValueKey(VibeStableId.of(event)),
        onReply: onSwipe,
        child: VibeSlashRow(
        eventId: event.eventId,
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: VibeThemes.maxTimelineWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: highlightMarker
                    ? VibePalette.accent.withAlpha(64)
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
                      12,
                      first ? 10 : 0,
                      12,
                      last ? 4 : 0,
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
                  duration: VibeThemes.animationDuration,
                  curve: VibeThemes.animationCurve,
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
                              maxWidth: VibeThemes.columnWidth * 1.5,
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
                      child: Container(
                        height: 1.2,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF23F43),
                          boxShadow: theme.brightness == Brightness.light
                              ? const [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1))]
                              : null,
                        ),
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
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFF23F43),
                          shadows: _nameShadows(theme),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1.2,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF23F43),
                          boxShadow: theme.brightness == Brightness.light
                              ? const [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1))]
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
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

  /// How far past its box the line goes: up to the small avatar.
  static const reach = 7.0;

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
      ..moveTo(cx, size.height + 4)
      ..lineTo(cx, mid + r)
      ..quadraticBezierTo(cx, mid, cx + r, mid)
      // runs on into the small picture of the person being replied to
      ..lineTo(size.width + _ReplyCurve.reach, mid);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ReplyCurve old) => old.color != color;
}


/// Message status as small dots; a new dot pops in with a spring.
class VibeStatusDots extends StatelessWidget {
  final int count;
  final Color color;
  const VibeStatusDots({required this.count, required this.color, super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 16,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          AnimatedScale(
            scale: i < count ? 1 : 0,
            duration: const Duration(milliseconds: 380),
            curve: Curves.elasticOut,
            child: i < count
                ? Container(
                    margin: EdgeInsets.only(left: i == 0 ? 0 : 2.5),
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    ),
  );
}


/// While a message goes out: (encrypted rooms) two dots with a line running
/// between them, which folds into one dot; that dot pulses until it's sent.
class VibeSendingDots extends StatefulWidget {
  final bool encrypting;
  final Color color;
  const VibeSendingDots({required this.encrypting, required this.color, super.key});

  @override
  State<VibeSendingDots> createState() => _VibeSendingDotsState();
}

class _VibeSendingDotsState extends State<VibeSendingDots> with TickerProviderStateMixin {
  late final AnimationController _run = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
  // 0 = encrypting (two dots + line), 1 = folded into one pulsing dot
  late final AnimationController _fold = AnimationController(vsync: this, duration: const Duration(milliseconds: 280), value: widget.encrypting ? 0 : 1);

  @override
  void initState() {
    super.initState();
    if (widget.encrypting) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) _fold.forward();
      });
    }
  }

  @override
  void dispose() {
    _run.dispose();
    _fold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 16,
    child: AnimatedBuilder(
      animation: Listenable.merge([_run, _fold]),
      builder: (context, _) => CustomPaint(painter: _SendingPainter(_run.value, _fold.value, widget.color)),
    ),
  );
}

class _SendingPainter extends CustomPainter {
  final double t, fold;
  final Color color;
  _SendingPainter(this.t, this.fold, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const r = 2.5;
    final left = Offset(r, y);
    final right = Offset(size.width - r, y);
    if (fold < 1) {
      final a = 1 - fold;
      final p = Paint()..color = color.withValues(alpha: color.a * a);
      // the second dot slides into the first as it folds
      canvas.drawCircle(left, r, p);
      canvas.drawCircle(Offset.lerp(right, left, fold)!, r, p);
      // a short line running back and forth between them
      final from = left.dx + r + 1, to = right.dx - r - 1;
      final head = from + (to - from) * Curves.easeInOut.transform(t);
      final len = (to - from) * 0.35;
      canvas.drawLine(
        Offset((head - len).clamp(from, to), y),
        Offset(head, y),
        Paint()
          ..color = color.withValues(alpha: color.a * a * 0.8)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
    if (fold > 0) {
      final pulse = 0.3 + 0.55 * t;
      canvas.drawCircle(left, r, Paint()..color = color.withValues(alpha: color.a * pulse * fold));
    }
  }

  @override
  bool shouldRepaint(covariant _SendingPainter old) => old.t != t || old.fold != fold || old.color != color;
}

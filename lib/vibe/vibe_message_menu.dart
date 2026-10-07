// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/vibe/vibe_message.dart';
import 'package:fluffychat/vibe/vibe_starred.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

const Color _red = Color(0xFFF87171);
const Color _blue = Color(0xFF5865F2);

/// Long-press menu for a message (reactions, preview, actions).
abstract class VibeMessageMenu {
  static Future<void> show(
    BuildContext context,
    ChatController controller,
    Event event,
  ) {
    final cs = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cs.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) =>
          _Menu(controller: controller, event: event, sheetContext: sheetContext),
    );
  }
}

class _Menu extends StatelessWidget {
  final ChatController controller;
  final Event event;
  final BuildContext sheetContext;

  const _Menu({
    required this.controller,
    required this.event,
    required this.sheetContext,
  });

  void _close() => Navigator.of(sheetContext).pop();

  /// Runs a controller action that works on the current selection.
  Future<void> _withSelection(Future<void> Function() action) async {
    _close();
    controller.selectedEvents
      ..clear()
      ..add(event);
    try {
      await action();
    } finally {
      controller.selectedEvents.clear();
    }
  }

  Future<void> _react(BuildContext context, String emoji) async {
    _close();
    await event.room.sendReaction(event.eventId, emoji);
  }

  Future<void> _moreEmojis(BuildContext context) async {
    final parent = controller.context;
    _close();
    if (!parent.mounted) return;
    final emoji = await showModalBottomSheet<String>(
      context: parent,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (c) => SizedBox(
        height: 400,
        child: EmojiPicker(
          onEmojiSelected: (_, e) => Navigator.of(c).pop(e.emoji),
          config: const Config(
            emojiViewConfig: EmojiViewConfig(
              backgroundColor: Colors.transparent,
            ),
            bottomActionBarConfig: BottomActionBarConfig(enabled: false),
          ),
        ),
      ),
    );
    if (emoji != null) await event.room.sendReaction(event.eventId, emoji);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final i18n = MatrixLocals(L10n.of(context));
    final sender = event.senderFromMemoryOrFallback;
    final name = sender.calcDisplayname(i18n: i18n);
    final body = event.getDisplayEvent(controller.timeline!).body;

    // Evaluate permissions against a temporary selection.
    controller.selectedEvents
      ..clear()
      ..add(event);
    final canEdit = controller.canEditSelectedEvents;
    final canRedact = controller.canRedactSelectedEvents;
    controller.selectedEvents.clear();

    final starred = VibeStarred.isStarred(event.room.id, event.eventId);
    final canSend = event.room.canSendDefaultMessages;
    final inner = BoxDecoration(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: theme.dividerColor),
    );

    Widget item(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? color,
      String? subtitle,
    }) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color ?? cs.onSurfaceVariant),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: color ?? cs.onSurface,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canSend)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                decoration: inner,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final e in const ['❤️', '👍', '🔥', '😂', '🎉'])
                      Material(
                        color: cs.surfaceContainerHigh,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _react(context, e),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: Text(
                                e,
                                style: const TextStyle(fontSize: 23),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Material(
                      color: cs.surfaceContainerHigh,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _moreEmojis(context),
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            Icons.sentiment_satisfied_alt_outlined,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: inner,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Icon(
                      Icons.arrow_back,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Avatar(
                    mxContent: sender.avatarUrl,
                    name: name,
                    size: 38,
                    client: event.room.client,
                    presenceUserId: sender.id,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    vibeTime(event.originServerTs),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (canSend)
              item(Icons.reply, 'Reply', () {
                _close();
                controller.replyAction(replyTo: event);
              }),
            item(
              Icons.shortcut,
              'Forward',
              () => _withSelection(controller.forwardEventsAction),
            ),
            item(Icons.copy_outlined, 'Copy Text', () {
              _close();
              controller.selectedEvents
                ..clear()
                ..add(event);
              controller.copyEventsAction();
              controller.selectedEvents.clear();
            }),
            item(
              starred ? Icons.bookmark : Icons.bookmark_border,
              starred ? 'Remove Bookmark' : 'Bookmark Message',
              () {
                _close();
                VibeStarred.toggle(event.room.id, event.eventId);
              },
            ),
            if (canEdit)
              item(Icons.edit_outlined, 'Edit', () {
                _close();
                controller.selectedEvents
                  ..clear()
                  ..add(event);
                controller.editSelectedEventAction();
              }, color: _blue),
            item(Icons.info_outline, 'Info', () {
              _close();
              controller.showEventInfo(event);
            }),
            Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: theme.dividerColor,
            ),
            if (canRedact)
              item(
                Icons.block,
                'Delete for Everyone',
                () => _withSelection(controller.redactEventsAction),
                color: _red,
              ),
            item(
              Icons.delete_outline,
              'Hide on this device',
              () {
                _close();
                VibeHidden.hide(event.room.id, event.eventId);
                controller.clearSelectedEvents();
              },
              color: _red,
              subtitle: 'Other people still see it.',
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

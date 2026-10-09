// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:flutter/material.dart';

/// "Replying to **name**  (x)" header shown inside the input pill.
class ReplyDisplay extends StatelessWidget {
  final ChatController controller;
  const ReplyDisplay(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reply = controller.replyEvent;
    final editing = controller.editEvent != null;

    Widget label = const SizedBox.shrink();
    if (reply != null) {
      final name = reply.senderFromMemoryOrFallback.calcDisplayname(
        i18n: MatrixLocals(L10n.of(context)),
      );
      label = Text.rich(
        TextSpan(
          text: 'Replying to ',
          style: TextStyle(color: cs.onSurfaceVariant),
          children: [
            TextSpan(
              text: name,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 17),
      );
    } else if (editing) {
      label = Text(
        'Editing message',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: cs.onSurface,
        ),
      );
    }

    return AnimatedSize(
      // Opens smoothly, closes instantly: closing while the sent message
      // lands in the timeline made the chat stutter.
      duration: reply != null || editing
          ? FluffyThemes.animationDuration
          : Duration.zero,
      curve: FluffyThemes.animationCurve,
      clipBehavior: Clip.hardEdge,
      child: reply != null || editing
          ? Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                children: [
                  Expanded(child: label),
                  Material(
                    color: cs.surfaceContainerHighest,
                    shape: const CircleBorder(),
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: L10n.of(context).close,
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: controller.cancelReplyEventAction,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

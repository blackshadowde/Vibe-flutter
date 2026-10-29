// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/config/themes.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/screens/chat/chat.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
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
    final quote = controller.replyQuote;
    if (reply != null && quote != null) {
      final name = reply.senderFromMemoryOrFallback.calcDisplayname(
        i18n: MatrixLocals(L10n.of(context)),
      );
      // "Reply to quote from name" + the words; tap to pick other words
      label = InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => controller.quotePartAction(reply),
        child: Row(
          children: [
            Icon(Icons.format_quote_rounded, color: cs.primary, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reply to quote from $name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  Text(
                    quote.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else if (reply != null) {
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
          ? VibeThemes.animationDuration
          : Duration.zero,
      curve: VibeThemes.animationCurve,
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

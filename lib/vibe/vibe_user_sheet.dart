// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// Big "about this user" sheet: photo banner, name, Matrix ID, Message button.
abstract class VibeUserSheet {
  static Future<void> show(
    BuildContext context, {
    required Client client,
    required String userId,
    required String displayName,
    Uri? avatarUrl,
    String? currentRoomId,
  }) {
    final router = GoRouter.of(context);
    return showModalBottomSheet<void>(
      sheetAnimationStyle: vibeSheetStyle,
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) => _Sheet(
        client: client,
        userId: userId,
        displayName: displayName,
        avatarUrl: avatarUrl,
        currentRoomId: currentRoomId,
        router: router,
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  final Client client;
  final String userId;
  final String displayName;
  final Uri? avatarUrl;
  final String? currentRoomId;
  final GoRouter router;

  const _Sheet({
    required this.client,
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required this.currentRoomId,
    required this.router,
  });

  Future<void> _message(BuildContext context) async {
    final existing = client.getDirectChatFromUserId(userId);
    if (existing != null) {
      Navigator.of(context).pop();
      if (existing != currentRoomId) router.go('/rooms/$existing');
      return;
    }
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.startDirectChat(userId),
    );
    final roomId = result.result;
    if (roomId == null) return;
    if (context.mounted) Navigator.of(context).pop();
    router.go('/rooms/$roomId');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isMe = userId == client.userID;
    final box = BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: theme.dividerColor),
    );
    final labelStyle = TextStyle(
      fontWeight: FontWeight.bold,
      letterSpacing: 0.8,
      color: cs.onSurfaceVariant,
    );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 340,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (avatarUrl != null)
                  MxcImage(
                    client: client,
                    uri: avatarUrl,
                    cacheKey: 'vibe_banner_$avatarUrl',
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 340,
                    isThumbnail: false,
                  )
                else
                  Container(
                    color: cs.primaryContainer,
                    alignment: Alignment.center,
                    child: Text(
                      displayName.isEmpty
                          ? '@'
                          : displayName.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        fontSize: 120,
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        cs.surface.withAlpha(235),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 18,
                  child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        userId,
                        style: TextStyle(
                          fontFamily: 'RobotoMono',
                          fontSize: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DISPLAY NAME', style: labelStyle),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  decoration: box,
                  child: Text(displayName, style: const TextStyle(fontSize: 17)),
                ),
                const SizedBox(height: 20),
                Text('MATRIX USER ID', style: labelStyle),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(
                    left: 18,
                    right: 6,
                    top: 4,
                    bottom: 4,
                  ),
                  decoration: box,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          userId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_outlined),
                        tooltip: 'Copy',
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(ClipboardData(text: userId));
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Copied')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (!isMe) ...[
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton.icon(
                      onPressed: () => _message(context),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Message'),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
                SafeArea(top: false, child: const SizedBox(height: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_activity_card.dart';
import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_dm_finder.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_status.dart';
import 'package:vibe/vibe/vibe_sheet_drag.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:vibe/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// "About this user" sheet (Discord style): photo banner, name, username,
/// Message / call buttons, status and member since.
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
    return showVibeSheet<void>(
      sheetAnimationStyle: vibeSheetStyle,
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => VibeSheetDragClose(
        child: _Sheet(
          client: client,
          userId: userId,
          displayName: displayName,
          avatarUrl: avatarUrl,
          currentRoomId: currentRoomId,
          router: router,
        ),
      ),
    );
  }
}

class _Sheet extends StatefulWidget {
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

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  DateTime? _since;

  Client get client => widget.client;
  String get userId => widget.userId;

  /// The chat this profile was opened from, or your DM with them.
  Room? get _room {
    final id = widget.currentRoomId;
    if (id != null) return client.getRoomById(id);
    return VibeDmFinder.find(client, userId);
  }

  @override
  void initState() {
    super.initState();
    _loadSince();
  }

  /// "Member since": when they joined this chat (Matrix has no public
  /// account creation date). Read from their membership event.
  Future<void> _loadSince() async {
    final room = _room;
    if (room == null) return;
    final known = room.getState(EventTypes.RoomMember, userId);
    if (known is Event) {
      if (mounted) setState(() => _since = known.originServerTs);
      return;
    }
    try {
      final json = await client.request(
        RequestType.GET,
        '/client/v3/rooms/${Uri.encodeComponent(room.id)}/state/'
        'm.room.member/${Uri.encodeComponent(userId)}',
        query: {'format': 'event'},
      );
      final ts = json['origin_server_ts'];
      if (ts is int && mounted) {
        setState(() => _since = DateTime.fromMillisecondsSinceEpoch(ts));
      }
    } catch (_) {}
  }

  /// Groups you're both in.
  int get _mutual => client.rooms
      .where(
        (r) =>
            !r.isDirectChat &&
            !r.isSpace &&
            r.membership == Membership.join &&
            r.getState(EventTypes.RoomMember, userId)?.content['membership'] ==
                'join',
      )
      .length;

  Future<String?> _dm(BuildContext context) async {
    final existing = VibeDmFinder.find(
      client,
      userId,
      currentRoomId: widget.currentRoomId,
    );
    if (existing != null) return existing.id;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => VibeDmFinder.open(client, userId),
    );
    return result.result;
  }

  Future<void> _message(BuildContext context) async {
    final roomId = await _dm(context);
    if (roomId == null || !context.mounted) return;
    Navigator.of(context).pop();
    if (roomId != widget.currentRoomId) widget.router.go('/rooms/$roomId');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isMe = userId == client.userID;
    final displayName = widget.displayName;
    final avatarUrl = widget.avatarUrl;
    final muted = cs.onSurfaceVariant;
    final soft = !VibePalette.isVibe
        ? Theme.of(context).colorScheme.surfaceContainerHigh
        : dark ? const Color(0xFF2B2D31) : const Color(0xFFEBEDEF);
    final room = _room;
    final mutual = isMe ? 0 : _mutual;
    final label = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: muted,
    );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo banner that fades into the sheet.
          SizedBox(
            height: 280,
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
                    height: 280,
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
                        fontSize: 96,
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
                        cs.surface,
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 14,
                  child: Material(
                    color: Colors.black38,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                // Username, tap to copy.
                GestureDetector(
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: userId));
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Copied')),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          userId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14.5, color: muted),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.copy_rounded, size: 14, color: muted),
                    ],
                  ),
                ),
                if (mutual > 0) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.groups_rounded, size: 17, color: muted),
                      const SizedBox(width: 6),
                      Text(
                        mutual == 1 ? '1 mutual group' : '$mutual mutual groups',
                        style: TextStyle(fontSize: 13.5, color: muted),
                      ),
                    ],
                  ),
                ],
                if (!isMe) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: FilledButton.icon(
                            onPressed: () => _message(context),
                            icon: const Icon(Icons.chat_bubble, size: 18),
                            label: const Text('Message'),
                            style: FilledButton.styleFrom(
                              backgroundColor: VibePalette.accent,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(fontFamily: 'Figtree', 
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (room != null && !isMe) ...[
                  const SizedBox(height: 22),
                  Text('Status', style: label),
                  const SizedBox(height: 4),
                  VibeStatusLine(
                    room: room,
                    userId: userId,
                    alwaysTime: true,
                    maxLines: 3,
                    fallback: 'No status',
                    style: TextStyle(fontSize: 15, color: cs.onSurface),
                  ),
                ],
                if (room != null)
                  VibeActivityCard(
                    status: VibeStatus.of(room, userId),
                    client: room.client,
                  ),
                if (_since != null) ...[
                  const SizedBox(height: 18),
                  Text('Member since', style: label),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.forum_rounded, size: 17, color: muted),
                      const SizedBox(width: 8),
                      Text(
                        _date(_since!),
                        style: TextStyle(fontSize: 15, color: cs.onSurface),
                      ),
                      if (room != null && !room.isDirectChat) ...[
                        Text('  ·  ', style: TextStyle(color: muted)),
                        Flexible(
                          child: Text(
                            room.getLocalizedDisplayname(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: muted),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                const SafeArea(top: false, child: SizedBox(height: 24)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

class _SquareButton extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color color;
  final VoidCallback onTap;
  const _SquareButton({
    required this.icon,
    required this.background,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        width: 42,
        height: 42,
        child: Icon(icon, size: 20, color: color),
      ),
    ),
  );
}

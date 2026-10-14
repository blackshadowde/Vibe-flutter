// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/vibe/vibe_profile_cache.dart';
import 'package:fluffychat/vibe/vibe_set_status.dart';
import 'package:fluffychat/vibe/vibe_status.dart';
import 'package:fluffychat/vibe/vibe_sheet_drag.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

/// Your own profile: bleed header with the photo, camera / pencil / gear
/// buttons, editable display name, Matrix ID and quick actions.
abstract class VibeOwnProfile {
  static Future<void> show(BuildContext context, Client client) {
    final router = GoRouter.of(context);
    return showVibeSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 460),
        reverseDuration: Duration(milliseconds: 260),
        curve: Curves.easeOutQuint,
        reverseCurve: Curves.easeInCubic,
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) => VibeSheetDragClose(
        child: _OwnSheet(client: client, router: router),
      ),
    );
  }
}

class _OwnSheet extends StatefulWidget {
  final Client client;
  final GoRouter router;
  const _OwnSheet({required this.client, required this.router});

  @override
  State<_OwnSheet> createState() => _OwnSheetState();
}

class _OwnSheetState extends State<_OwnSheet> {
  late Future<Profile> _profile;
  final TextEditingController _name = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  bool _editing = false;

  Client get client => widget.client;

  @override
  void initState() {
    super.initState();
    _profile = VibeProfileCache.get(client);
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _reload() {
    VibeProfileCache.refresh();
    if (!mounted) return;
    setState(() => _profile = VibeProfileCache.get(client));
  }

  Future<void> _photo(Profile? profile) async {
    final action = await showVibeSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (profile?.avatarUrl != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                title: Text(
                  'Remove photo',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'remove') {
      final r = await showFutureLoadingDialog(
        context: context,
        future: () => client.setAvatar(null),
      );
      if (r.error == null) _reload();
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 60,
    );
    if (picked == null || !mounted) return;
    final file = MatrixFile(
      bytes: await picked.readAsBytes(),
      name: picked.path,
    );
    if (!mounted) return;
    final r = await showFutureLoadingDialog(
      context: context,
      future: () => client.setAvatar(file),
    );
    if (r.error == null) _reload();
  }

  void _startEdit(String current) {
    setState(() {
      _editing = true;
      _name.text = current;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  Future<void> _saveName() async {
    final value = _name.text.trim();
    if (value.isEmpty) return;
    final r = await showFutureLoadingDialog(
      context: context,
      future: () => client.setProfileField(client.userID!, 'displayname', {
        'displayname': value,
      }),
    );
    if (!mounted) return;
    setState(() => _editing = false);
    if (r.error == null) _reload();
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) => Material(
    color: Colors.black.withValues(alpha: 0.45),
    shape: CircleBorder(
      side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
    ),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Icon(icon, size: 21, color: Colors.white),
      ),
    ),
  );

  Widget _squareButton(BuildContext context, IconData icon, VoidCallback onTap) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF2B2D31) : const Color(0xFFEBEDEF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final userId = client.userID ?? '';
    return FutureBuilder<Profile>(
      future: _profile,
      builder: (context, snap) {
        final profile = snap.data;
        final name = (profile?.displayName?.isNotEmpty ?? false)
            ? profile!.displayName!
            : userId.localpart ?? userId;
        final avatar = profile?.avatarUrl;
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Discord-style header: banner, round picture with the
              // online dot, and the status thought bubble.
              SizedBox(
                height: 236,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(height: 128, color: const Color(0xFF1F2624)),
                    Positioned(
                      left: 14,
                      top: 16,
                      child: _circleButton(
                        Icons.close,
                        () => Navigator.of(context).pop(),
                      ),
                    ),
                    Positioned(
                      right: 14,
                      top: 16,
                      child: Row(
                        children: [
                          _circleButton(
                            Icons.photo_camera_outlined,
                            () => _photo(profile),
                          ),
                          const SizedBox(width: 10),
                          _circleButton(
                            Icons.edit_outlined,
                            () => _startEdit(name),
                          ),
                          const SizedBox(width: 10),
                          _circleButton(Icons.settings_outlined, () {
                            Navigator.of(context).pop();
                            widget.router.go('/rooms/settings');
                          }),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 16,
                      top: 80,
                      child: VibeRingAvatar(
                        mxc: avatar,
                        name: name,
                        client: client,
                        ring: cs.surface,
                        size: 120,
                      ),
                    ),
                    Positioned(
                      left: 158,
                      right: 16,
                      top: 104,
                      child: Builder(
                        builder: (context) {
                          final s = VibeStatus.mine(client);
                          final active = s != null && s.active;
                          return VibeThoughtBubble(
                            text: active
                                ? (s.emoji.isEmpty
                                      ? s.text
                                      : '${s.emoji} ${s.text}')
                                : null,
                            showPlus: true,
                            onTap: () async {
                              await VibeSetStatusPage.open(context, client);
                              if (!mounted) return;
                              setState(() {});
                              // The new status arrives with the next sync.
                              Future.delayed(
                                const Duration(milliseconds: 1500),
                                () {
                                  if (mounted) setState(() {});
                                },
                              );
                            },
                          );
                        },
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
                    // Name: tap the pencil to edit it right here.
                    if (_editing)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _name,
                              focusNode: _nameFocus,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                              ),
                              onSubmitted: (_) => _saveName(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check, size: 22),
                            onPressed: _saveName,
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 22),
                            onPressed: () => setState(() => _editing = false),
                          ),
                        ],
                      )
                    else
                      Text(
                        name,
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
                              style: TextStyle(
                                fontSize: 14.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.copy_rounded,
                            size: 14,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              VibeStagger(
                index: 3,
                dy: 20,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: FilledButton.icon(
                            onPressed: () => _startEdit(name),
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Edit profile'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF5865F2),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _squareButton(
                        context,
                        Icons.qr_code_2,
                        () => FluffyShare.share(userId, context),
                      ),
                      const SizedBox(width: 8),
                      _squareButton(context, Icons.settings, () {
                        Navigator.of(context).pop();
                        widget.router.go('/rooms/settings');
                      }),
                    ],
                  ),
                ),
              ),
              const SafeArea(top: false, child: SizedBox(height: 16)),
            ],
          ),
        );
      },
    );
  }
}

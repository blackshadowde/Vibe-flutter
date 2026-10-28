// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_activity_card.dart';
import 'package:vibe/vibe/vibe_tap_icon.dart';
import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/utils/vibe_share.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_name_style.dart';
import 'package:vibe/vibe/vibe_profile_cache.dart';
import 'package:vibe/vibe/vibe_set_status.dart';
import 'package:vibe/vibe/vibe_status.dart';
import 'package:vibe/vibe/vibe_sheet_drag.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:vibe/widgets/mxc_image.dart';
import 'dart:ui' as ui;
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

  Widget _wideButton({
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    final blurple = VibePalette.accent;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: filled
          ? BorderSide.none
          : BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
    );
    return Material(
      color: filled ? blurple : Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 40,
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: filled ? Colors.white : blurple),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: filled ? Colors.white : blurple,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barItem(IconData icon, String label, VoidCallback onTap) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return VibeTapArea(
      child: InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: SizedBox(
        width: 72,
        height: 50,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            VibeTapIcon(
              kind: icon == Icons.settings ? VibeTap.spin : VibeTap.pop,
              child: Icon(icon, size: 20, color: ink),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _squareButton(BuildContext context, IconData icon, VoidCallback onTap) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: !VibePalette.isVibe
          ? Theme.of(context).colorScheme.surfaceContainerHigh
          : dark ? const Color(0xFF2B2D31) : const Color(0xFFEBEDEF),
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
        // The keyboard pushes the pane up, so you see what you type.
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Discord-style header: banner, round picture with the
              // online dot, and the status thought bubble.
              SizedBox(
                height: 184,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Vibe X's banner: your picture, blurred and dimmed
                    SizedBox(
                      height: 104,
                      width: double.infinity,
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const ColoredBox(color: Color(0xFF1F2624)),
                            if (avatar != null)
                              ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(
                                  sigmaX: 28,
                                  sigmaY: 28,
                                  tileMode: TileMode.clamp,
                                ),
                                child: MxcImage(
                                  uri: avatar,
                                  client: client,
                                  fit: BoxFit.cover,
                                  width: 360,
                                  height: 104,
                                  isThumbnail: true,
                                  placeholder: (_) => const SizedBox.shrink(),
                                ),
                              ),
                            ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      top: 16,
                      child: _circleButton(
                        Icons.close,
                        () => Navigator.of(context).pop(),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      top: 60,
                      child: VibeRingAvatar(
                        mxc: avatar,
                        name: name,
                        client: client,
                        ring: cs.surface,
                        size: 92,
                      ),
                    ),
                    Positioned(
                      left: 122,
                      right: 14,
                      top: 76,
                      child: Align(
                        alignment: Alignment.centerLeft,
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
                      VibeNameText(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
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
                                fontSize: 13,
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
              // what you're listening to, Discord style
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: VibeActivityCard(
                  status: VibeStatus.mine(client),
                  client: client,
                ),
              ),
              VibeStagger(
                index: 3,
                dy: 20,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                    children: [
                      _wideButton(
                        icon: Icons.qr_code_2,
                        label: 'Share my Vibe ID',
                        filled: true,
                        onTap: () => VibeShare.share(userId, context),
                      ),
                    ],
                  ),
                ),
              ),
              // Vibe X's floating bar
              VibeStagger(
                index: 4,
                dy: 20,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 18),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF2B2D31)
                          : const Color(0xFFEBEDEF),
                      borderRadius: BorderRadius.circular(36),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _barItem(Icons.photo_camera, 'Photo', () => _photo(profile)),
                        _barItem(Icons.edit, 'Edit', () async {
                          await VibeSetStatusPage.open(context, client);
                          if (!mounted) return;
                          VibeProfileCache.refresh();
                          setState(() => _profile = VibeProfileCache.get(client));
                        }),
                        _barItem(Icons.settings, 'Settings', () {
                          Navigator.of(context).pop();
                          widget.router.go('/rooms/settings');
                        }),
                      ],
                    ),
                  ),
                ),
              ),
              const SafeArea(top: false, child: SizedBox(height: 16)),
            ],
          ),
          ),
        );
      },
    );
  }
}

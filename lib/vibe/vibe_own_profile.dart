// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/vibe/vibe_profile_cache.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
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
    return showModalBottomSheet<void>(
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
      builder: (_) => _OwnSheet(client: client, router: router),
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
    final action = await showModalBottomSheet<String>(
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final userId = client.userID ?? '';
    final box = BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: cs.outlineVariant),
    );
    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.8,
      color: cs.onSurfaceVariant,
    );
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
              SizedBox(
                height: 340,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (avatar != null)
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 1.18, end: 1.0),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, child) =>
                            Transform.scale(scale: v, child: child),
                        child: MxcImage(
                          client: client,
                          uri: avatar,
                          cacheKey: 'vibe_own_banner_$avatar',
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 340,
                          isThumbnail: false,
                        ),
                      )
                    else
                      Container(
                        color: cs.primaryContainer,
                        alignment: Alignment.center,
                        child: Text(
                          name.isEmpty ? '@' : name.substring(0, 1).toUpperCase(),
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
                      child: _circleButton(
                        Icons.arrow_back,
                        () => Navigator.of(context).pop(),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 14,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface,
                                  ),
                                ),
                                Text(
                                  userId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'RobotoMono',
                                    fontSize: 14,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
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
                  ],
                ),
              ),
              VibeStagger(
                index: 3,
                dy: 28,
                child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DISPLAY NAME', style: labelStyle),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.only(
                        left: 18,
                        right: _editing ? 6 : 18,
                        top: _editing ? 2 : 16,
                        bottom: _editing ? 2 : 16,
                      ),
                      decoration: box,
                      child: _editing
                          ? Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _name,
                                    focusNode: _nameFocus,
                                    style: const TextStyle(fontSize: 16),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isDense: true,
                                      filled: false,
                                    ),
                                    onSubmitted: (_) => _saveName(),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.check),
                                  onPressed: _saveName,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () =>
                                      setState(() => _editing = false),
                                ),
                              ],
                            )
                          : Text(name, style: const TextStyle(fontSize: 16)),
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
                                fontSize: 16,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_outlined),
                            tooltip: 'Copy',
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              await Clipboard.setData(
                                ClipboardData(text: userId),
                              );
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Copied')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Divider(height: 1, color: cs.outlineVariant),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.router.go('/rooms/settings');
                        },
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Open settings'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: OutlinedButton.icon(
                        onPressed: () => FluffyShare.share(userId, context),
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('Share my ID'),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: cs.outlineVariant),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    SafeArea(top: false, child: const SizedBox(height: 14)),
                  ],
                ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

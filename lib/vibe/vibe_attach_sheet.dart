// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/send_file_dialog.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:photo_manager/photo_manager.dart';

/// "+" attachment sheet: gallery grid + Photos / Contacts / Files / Location.
abstract class VibeAttachSheet {
  static Future<void> show(BuildContext context, ChatController controller) {
    controller.inputFocus.unfocus();
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.62,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _AttachSheet(controller: controller),
    );
  }
}

class _AttachSheet extends StatefulWidget {
  final ChatController controller;
  const _AttachSheet({required this.controller});

  @override
  State<_AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends State<_AttachSheet> {
  final List<AssetEntity> _assets = [];
  final Set<String> _selected = {};
  final ScrollController _scroll = ScrollController();
  AssetPathEntity? _path;
  int _page = 0;
  bool _loading = false;
  bool _end = false;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    _init();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.hasAccess) {
        if (mounted) setState(() => _denied = true);
        return;
      }
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      );
      if (paths.isEmpty) {
        if (mounted) setState(() => _end = true);
        return;
      }
      _path = paths.first;
      await _loadMore();
    } catch (_) {
      if (mounted) setState(() => _end = true);
    }
  }

  Future<void> _loadMore() async {
    final path = _path;
    if (path == null || _loading || _end) return;
    _loading = true;
    try {
      final list = await path.getAssetListPaged(page: _page, size: 80);
      if (!mounted) return;
      setState(() {
        _assets.addAll(list);
        _page++;
        if (list.length < 80) _end = true;
      });
    } finally {
      _loading = false;
    }
  }

  Future<void> _sendSelected() async {
    final c = widget.controller;
    final files = <XFile>[];
    for (final a in _assets.where((a) => _selected.contains(a.id))) {
      final f = await a.originFile;
      if (f != null) files.add(XFile(f.path));
    }
    if (files.isEmpty) return;
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!c.context.mounted) return;
    await showAdaptiveDialog(
      context: c.context,
      builder: (_) => SendFileDialog(
        files: files,
        room: c.room,
        outerContext: c.context,
        threadRootEventId: c.activeThreadId,
        threadLastEventId: c.threadLastEventId,
      ),
    );
  }

  void _contacts() {
    final c = widget.controller;
    Navigator.of(context).pop();
    final rooms = c.room.client.rooms
        .where((r) => r.isDirectChat && r.directChatMatrixID != null)
        .toList();
    showModalBottomSheet<void>(
      context: c.context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Share a contact',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: rooms.length,
                  itemBuilder: (context, i) {
                    final r = rooms[i];
                    final name = r.getLocalizedDisplayname(
                      MatrixLocals(L10n.of(context)),
                    );
                    final id = r.directChatMatrixID!;
                    return ListTile(
                      leading: Avatar(
                        mxContent: r.avatar,
                        name: name,
                        size: 42,
                        client: r.client,
                      ),
                      title: Text(name),
                      subtitle: Text(id),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        c.room.sendTextEvent('https://matrix.to/#/$id');
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = widget.controller;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        if (_denied)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Allow access to photos to attach media'),
                TextButton(
                  onPressed: PhotoManager.openSetting,
                  child: const Text('Open settings'),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(8, 4, 8, 110 + bottom),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: _assets.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    c.onAddPopupMenuButtonSelected(
                      AddPopupMenuActions.photoCamera,
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.photo_camera,
                      size: 40,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final asset = _assets[i - 1];
              final picked = _selected.contains(asset.id);
              return GestureDetector(
                onTap: () => setState(() {
                  if (!_selected.add(asset.id)) _selected.remove(asset.id);
                }),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FutureBuilder<Uint8List?>(
                        future: asset.thumbnailDataWithSize(
                          const ThumbnailSize(260, 260),
                        ),
                        builder: (context, snap) => snap.data == null
                            ? ColoredBox(color: cs.surfaceContainerHighest)
                            : Image.memory(snap.data!, fit: BoxFit.cover),
                      ),
                      if (asset.type == AssetType.video)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.videocam,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _fmt(asset.videoDuration),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: picked ? cs.primary : Colors.black38,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: picked
                              ? Icon(
                                  Icons.check,
                                  size: 15,
                                  color: cs.onPrimary,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 12 + bottom,
          child: _selected.isNotEmpty
              ? SizedBox(
                  height: 60,
                  child: FilledButton.icon(
                    onPressed: _sendSelected,
                    icon: const Icon(Icons.send_rounded),
                    label: Text('Send ${_selected.length}'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              : Material(
                  color: cs.surfaceContainerHigh,
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Action(
                          icon: Icons.photo_library,
                          label: 'Photos',
                          active: true,
                          onTap: () => _scroll.animateTo(
                            0,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          ),
                        ),
                        _Action(
                          icon: Icons.contacts,
                          label: 'Contacts',
                          onTap: _contacts,
                        ),
                        _Action(
                          icon: Icons.attach_file,
                          label: 'Files',
                          onTap: () {
                            Navigator.of(context).pop();
                            c.onAddPopupMenuButtonSelected(
                              AddPopupMenuActions.file,
                            );
                          },
                        ),
                        _Action(
                          icon: Icons.location_on,
                          label: 'Location',
                          onTap: () {
                            Navigator.of(context).pop();
                            c.onAddPopupMenuButtonSelected(
                              AddPopupMenuActions.location,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? cs.onSurface : cs.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:vibe/vibe/vibe_stickers.dart';
import 'package:cross_file/cross_file.dart';
import 'package:vibe/config/app_config.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

abstract class ShareItem {}

class TextShareItem extends ShareItem {
  final String value;
  TextShareItem(this.value);
}

class ContentShareItem extends ShareItem {
  final Map<String, Object?> value;
  ContentShareItem(this.value);
}

class FileShareItem extends ShareItem {
  final XFile value;
  FileShareItem(this.value);
}

class ShareScaffoldDialog extends StatefulWidget {
  final List<ShareItem> items;

  const ShareScaffoldDialog({required this.items, super.key});

  @override
  State<ShareScaffoldDialog> createState() => _ShareScaffoldDialogState();
}

class _ShareScaffoldDialogState extends State<ShareScaffoldDialog> {
  final TextEditingController _filterController = TextEditingController();

  String? selectedRoomId;

  void _toggleRoom(String roomId) {
    setState(() {
      selectedRoomId = roomId;
    });
  }

  Future<void> _forwardAction() async {
    final roomId = selectedRoomId;
    if (roomId == null) {
      throw Exception(
        'Started forward action before room was selected. This should never happen.',
      );
    }
    if (widget.items.any((item) => item is! FileShareItem)) {
      final consent = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).forwardCountMessages(widget.items.length),
        okLabel: L10n.of(context).forward,
        cancelLabel: L10n.of(context).cancel,
      );
      if (consent != OkCancelResult.ok) return;
    }
    if (!mounted) return;
    while (context.canPop()) {
      context.pop();
    }
    context.go('/rooms/$roomId', extra: widget.items);
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  /// A shared sticker.ly pack link.
  String? get _stickerLink {
    for (final i in widget.items) {
      if (i is TextShareItem) {
        final l = VibeStickers.stickerLink(i.value);
        if (l != null) return l;
      }
    }
    return null;
  }

  Future<void> _importLink() async {
    final client = Matrix.of(context).client;
    final link = _stickerLink!;
    final messenger = ScaffoldMessenger.of(context);
    final r = await showFutureLoadingDialog(
      context: context,
      future: () => VibeStickers.importLink(client, link),
    );
    if (!mounted || r.result == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Added ${r.result!.$2} stickers to "${r.result!.$1}"'),
      ),
    );
    context.pop();
  }

  /// Shared files that can become stickers (pictures or a pack file).
  List<XFile> get _stickerFiles {
    final files = [
      for (final i in widget.items)
        if (i is FileShareItem) i.value,
    ];
    if (files.isEmpty || files.length != widget.items.length) return const [];
    final ok = files.every(
      (f) => VibeStickers.isImage(f.name) || VibeStickers.isPackFile(f.name),
    );
    return ok ? files : const [];
  }

  Future<void> _addToStickers() async {
    final client = Matrix.of(context).client;
    final files = _stickerFiles;
    final messenger = ScaffoldMessenger.of(context);
    final r = await showFutureLoadingDialog<String>(
      context: context,
      future: () async {
        var total = 0;
        String? packName;
        final singles = <(String, Uint8List)>[];
        for (final f in files) {
          final bytes = await f.readAsBytes();
          if (VibeStickers.isPackFile(f.name)) {
            final (title, n) = await VibeStickers.importPack(client, bytes, f.name);
            total += n;
            packName = title;
          } else {
            singles.add((f.name, bytes));
          }
        }
        if (singles.isNotEmpty) {
          total += await VibeStickers.add(client, singles, 'My stickers');
          packName ??= 'My stickers';
        }
        return total == 0
            ? 'No stickers found in that file'
            : 'Added $total sticker${total == 1 ? '' : 's'} to "$packName"';
      },
    );
    if (!mounted) return;
    if (r.result != null) {
      messenger.showSnackBar(SnackBar(content: Text(r.result!)));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rooms = Matrix.of(context).client.rooms
        .where(
          (room) =>
              room.canSendDefaultMessages &&
              !room.isSpace &&
              room.membership == Membership.join,
        )
        .toList();
    final filter = _filterController.text.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(
        leading: Center(child: CloseButton(onPressed: context.pop)),
        title: Text(L10n.of(context).share),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            toolbarHeight: 72,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            title: TextField(
              controller: _filterController,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.colorScheme.secondaryContainer,
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(99),
                ),
                contentPadding: EdgeInsets.zero,
                hintText: L10n.of(context).search,
                hintStyle: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.normal,
                ),
                floatingLabelBehavior: FloatingLabelBehavior.never,
                prefixIcon: IconButton(
                  onPressed: () {},
                  icon: Icon(
                    Icons.search_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
          // Vibe: a shared sticker (or a WhatsApp sticker pack file) can go
          // straight into your stickers
          if (_stickerLink != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  tileColor: theme.colorScheme.secondaryContainer,
                  leading: const Icon(Icons.emoji_emotions_outlined),
                  title: const Text('Import this sticker pack'),
                  subtitle: Text(_stickerLink!),
                  onTap: _importLink,
                ),
              ),
            ),
          if (_stickerFiles.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  tileColor: theme.colorScheme.secondaryContainer,
                  leading: const Icon(Icons.emoji_emotions_outlined),
                  title: Text(
                    _stickerFiles.any((f) => VibeStickers.isPackFile(f.name))
                        ? 'Import sticker pack'
                        : 'Add to my stickers',
                  ),
                  subtitle: const Text('Use them from the sticker tray'),
                  onTap: _addToStickers,
                ),
              ),
            ),
          SliverList.builder(
            itemCount: rooms.length,
            itemBuilder: (context, i) {
              final room = rooms[i];
              final displayname = room.getLocalizedDisplayname(
                MatrixLocals(L10n.of(context)),
              );
              final value = selectedRoomId == room.id;
              final filterOut = !displayname.toLowerCase().contains(filter);
              if (!value && filterOut) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Opacity(
                  opacity: filterOut ? 0.5 : 1,
                  child: FutureBuilder(
                    future: room.loadHeroUsers(),
                    builder: (context, _) => CheckboxListTile.adaptive(
                      checkboxShape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(90),
                      ),
                      controlAffinity: ListTileControlAffinity.trailing,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConfig.borderRadius,
                        ),
                      ),
                      secondary: Avatar(
                        mxContent: room.avatar,
                        name: displayname,
                        size: Avatar.defaultSize * 0.75,
                      ),
                      title: Text(
                        displayname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        room.directChatMatrixID ??
                            L10n.of(context).countParticipants(
                              (room.summary.mJoinedMemberCount ?? 0) +
                                  (room.summary.mInvitedMemberCount ?? 0),
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      value: selectedRoomId == room.id,
                      onChanged: (_) => _toggleRoom(room.id),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: AnimatedSize(
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        child: selectedRoomId == null
            ? const SizedBox.shrink()
            : Material(
                elevation: 8,
                shadowColor: theme.appBarTheme.shadowColor,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton(
                      onPressed: _forwardAction,
                      child: Text(L10n.of(context).forward),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

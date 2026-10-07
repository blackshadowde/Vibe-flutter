// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/pages/new_private_chat/qr_scanner_modal.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// "Add Contact by Matrix ID" bottom sheet.
abstract class VibeAddContact {
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      sheetAnimationStyle: vibeSheetStyle,
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _AddContactSheet(parentContext: context),
    );
  }
}

class _AddContactSheet extends StatefulWidget {
  final BuildContext parentContext;
  const _AddContactSheet({required this.parentContext});

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final TextEditingController _id = TextEditingController();

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  String get _value => _id.text.trim();
  bool get _valid => _value.isValidMatrixIdStrict() && _value.startsWith('@');

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    setState(() => _id.text = _extractId(text));
  }

  static String _extractId(String raw) {
    var text = raw;
    try {
      text = Uri.decodeFull(raw);
    } catch (_) {}
    final m = RegExp(r'@[^\s/?#:]+:[^\s/?#]+').firstMatch(text);
    return m?.group(0) ?? raw;
  }

  Future<void> _scan() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => QrScannerModal(
          onScan: (data) {
            if (!mounted) return;
            setState(() => _id.text = _extractId(data));
          },
        ),
      ),
    );
  }

  Future<void> _start() async {
    if (!_valid) return;
    final client = Matrix.of(context).client;
    final router = GoRouter.of(widget.parentContext);
    final id = _value;
    final existing = client.getDirectChatFromUserId(id);
    if (existing != null) {
      Navigator.of(context).pop();
      router.go('/rooms/$existing');
      return;
    }
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.startDirectChat(id),
    );
    final roomId = result.result;
    if (roomId == null) return;
    if (mounted) Navigator.of(context).pop();
    router.go('/rooms/$roomId');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.person_add_alt,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Add Contact by Matrix ID',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Scan QR, paste or type ID',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                    child: IconButton(
                      icon: const Icon(Icons.content_paste),
                      tooltip: 'Paste',
                      onPressed: _paste,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(14),
                    child: IconButton(
                      icon: Icon(Icons.qr_code_scanner, color: cs.onPrimary),
                      tooltip: 'Scan QR',
                      onPressed: _scan,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    text: 'MATRIX USER ID ',
                    children: [
                      TextSpan(
                        text: '*',
                        style: TextStyle(color: cs.error),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _id,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.go,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _start(),
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: '@username:matrix.org',
                  filled: true,
                  fillColor: cs.surfaceContainerLowest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: cs.primary.withAlpha(120)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: cs.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Divider(
              height: 1,
              indent: 20,
              endIndent: 20,
              color: theme.dividerColor,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: _valid ? _start : null,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Start Chat'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(170, 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

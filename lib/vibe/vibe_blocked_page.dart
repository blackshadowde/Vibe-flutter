// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Blocked people: block someone by their Matrix ID, unblock with one tap.
/// Blocked people's messages and invites never reach you.
class VibeBlockedPage extends StatefulWidget {
  final String? initialUserId;
  const VibeBlockedPage({this.initialUserId, super.key});

  @override
  State<VibeBlockedPage> createState() => _VibeBlockedPageState();
}

class _VibeBlockedPageState extends State<VibeBlockedPage> {
  late final _id = TextEditingController(text: widget.initialUserId);
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  Future<void> _block() async {
    final userId = _id.text.trim();
    if (userId.isEmpty) return;
    if (!userId.isValidMatrixIdStrict() || userId.sigil != '@') {
      setState(() => _error = L10n.of(context).invalidInput);
      return;
    }
    setState(() => _error = null);
    final client = Matrix.of(context).client;
    await showFutureLoadingDialog(
      context: context,
      future: () => client.ignoreUser(userId),
    );
    _id.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final t2 = VibeSettingsStyle.text2(context);
    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        title: Text(l10n.blockedUsers),
      ),
      body: MaxWidthBody(
        child: StreamBuilder(
          // the list changes when the account data does
          stream: client.onSync.stream.where(
            (s) =>
                s.accountData?.any((a) => a.type == 'm.ignored_user_list') ??
                false,
          ),
          builder: (context, _) {
            if (client.prevBatch == null) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator.adaptive()),
              );
            }
            final blocked = client.ignoredUsers;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _id,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _block(),
                    decoration: InputDecoration(
                      errorText: _error,
                      hintText: '@name:server.org',
                      labelText: 'Block someone',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        tooltip: l10n.block,
                        icon: const Icon(Icons.block),
                        onPressed: _block,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text(
                    l10n.blockListDescription,
                    style: TextStyle(fontSize: 13, color: t2),
                  ),
                ),
                if (blocked.isNotEmpty) ...[
                  VibeSectionLabel('Blocked — ${blocked.length}'),
                  VibeCard(
                    children: [
                      for (final id in blocked)
                        _BlockedRow(
                          client: client,
                          userId: id,
                          onUnblock: () => showFutureLoadingDialog(
                            context: context,
                            future: () => client.unignoreUser(id),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BlockedRow extends StatelessWidget {
  final Client client;
  final String userId;
  final VoidCallback onUnblock;
  const _BlockedRow({
    required this.client,
    required this.userId,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile>(
      future: client.getProfileFromUserId(userId),
      builder: (context, snap) {
        final p = snap.data;
        final name = p?.displayName ?? userId.localpart ?? userId;
        return ListTile(
          leading: Avatar(mxContent: p?.avatarUrl, name: name, size: 40),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(userId, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: TextButton(
            onPressed: onUnblock,
            child: const Text('Unblock'),
          ),
        );
      },
    );
  }
}

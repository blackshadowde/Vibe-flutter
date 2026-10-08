// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:matrix/matrix.dart' hide Contact;

/// "Share a contact" with two tabs: Matrix friends and phone contacts.
class VibeContactShareSheet extends StatefulWidget {
  final Room room;
  const VibeContactShareSheet({required this.room, super.key});

  @override
  State<VibeContactShareSheet> createState() => _VibeContactShareSheetState();
}

class _VibeContactShareSheetState extends State<VibeContactShareSheet> {
  final TextEditingController _q = TextEditingController();
  Future<List<Contact>?>? _phone;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<List<Contact>?> _loadPhone() async {
    final ok = await FlutterContacts.requestPermission(readonly: true);
    if (!ok) return null;
    final list = await FlutterContacts.getContacts(withProperties: true);
    return list.where((c) => c.phones.isNotEmpty).toList();
  }

  Future<bool> _confirm(String name, String detail) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send $name?'),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _sendPhone(Contact c) async {
    final numbers = c.phones.map((p) => p.number).join('\n');
    if (!await _confirm(c.displayName, numbers)) return;
    if (!mounted) return;
    Navigator.of(context).pop();
    final vcard = c.toVCard();
    final safeName = c.displayName.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    await widget.room.sendFileEvent(
      MatrixFile(
        bytes: Uint8List.fromList(utf8.encode(vcard)),
        name: '${safeName.isEmpty ? 'contact' : safeName}.vcf',
        mimeType: 'text/vcard',
      ),
      extraContent: {
        'body': '📇 ${c.displayName}\n$numbers',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _q.text.trim().toLowerCase();
    return DefaultTabController(
      length: 2,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            const Text(
              'Share a contact',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            TabBar(
              onTap: (i) {
                if (i == 1 && _phone == null) {
                  setState(() => _phone = _loadPhone());
                }
              },
              tabs: const [
                Tab(icon: Icon(Icons.forum_outlined), text: 'Matrix'),
                Tab(icon: Icon(Icons.contact_phone_outlined), text: 'Phone'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [_matrixTab(q), _phoneTab(q)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _matrixTab(String q) {
    final rooms = widget.room.client.rooms
        .where((r) => r.isDirectChat && r.directChatMatrixID != null)
        .where((r) {
          if (q.isEmpty) return true;
          final name = r
              .getLocalizedDisplayname(MatrixLocals(L10n.of(context)))
              .toLowerCase();
          return name.contains(q) ||
              r.directChatMatrixID!.toLowerCase().contains(q);
        })
        .toList();
    if (rooms.isEmpty) {
      return const Center(child: Text('No Matrix contacts'));
    }
    return ListView.builder(
      itemCount: rooms.length,
      itemBuilder: (context, i) {
        final r = rooms[i];
        final name = r.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
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
          onTap: () async {
            if (!await _confirm(name, id)) return;
            if (!context.mounted) return;
            Navigator.of(context).pop();
            await widget.room.sendTextEvent('https://matrix.to/#/$id');
          },
        );
      },
    );
  }

  Widget _phoneTab(String q) {
    final future = _phone;
    if (future == null) {
      // Tab opened by swiping instead of tapping.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _phone == null) {
          setState(() => _phone = _loadPhone());
        }
      });
      return const Center(child: CircularProgressIndicator());
    }
    return FutureBuilder<List<Contact>?>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snap.data;
        if (snap.hasError) {
          return Center(child: Text('Could not read contacts: ${snap.error}'));
        }
        if (all == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Allow access to your contacts to share them'),
                TextButton(
                  onPressed: () => setState(() => _phone = _loadPhone()),
                  child: const Text('Allow'),
                ),
              ],
            ),
          );
        }
        final List<Contact> contacts = all;
        final list = contacts.where((c) {
          if (q.isEmpty) return true;
          return c.displayName.toLowerCase().contains(q) ||
              c.phones.any((p) => p.number.contains(q));
        }).toList();
        if (list.isEmpty) {
          return const Center(child: Text('No phone contacts'));
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final c = list[i];
            return ListTile(
              leading: CircleAvatar(
                child: Text(
                  c.displayName.isEmpty
                      ? '?'
                      : c.displayName.characters.first.toUpperCase(),
                ),
              ),
              title: Text(c.displayName),
              subtitle: Text(
                c.phones.first.number,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _sendPhone(c),
            );
          },
        );
      },
    );
  }
}

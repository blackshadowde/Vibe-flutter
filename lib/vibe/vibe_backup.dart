// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_dialog.dart';
import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:share_plus/share_plus.dart';

/// Chat backups: every chat's messages (who, when, text) in one
/// password-protected file. Encryption is done by Android (AES-256-GCM, key
/// from the password with PBKDF2, see VibeBackupNative.kt). Photos and files
/// are not included. Matrix can't put old messages back on the server, so a
/// backup is opened inside Vibe to read them.
abstract class VibeBackup {
  static const _ch = MethodChannel('vibe/backup');
  static const _pwKey = 'chat.vibe.backup_password';
  static const _autoPrefix = 'vibe-auto-';
  static const _keepAuto = 3;
  static const _maxPerChat = 5000;
  static bool _running = false;

  static String _stamp(DateTime d, {bool time = true}) {
    String two(int v) => v.toString().padLeft(2, '0');
    final day = '${d.year}-${two(d.month)}-${two(d.day)}';
    return time ? '$day-${two(d.hour)}${two(d.minute)}' : day;
  }

  /// Reads every chat you're in, oldest message first.
  static Future<Map<String, Object?>> collect(
    Client client, {
    void Function(String step)? progress,
  }) async {
    final rooms = client.rooms
        .where((r) => r.membership == Membership.join)
        .toList();
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < rooms.length; i++) {
      final room = rooms[i];
      progress?.call('Reading chat ${i + 1} of ${rooms.length}');
      final timeline = await room.getTimeline();
      try {
        var rounds = 0;
        while (timeline.canRequestHistory &&
            timeline.events.length < _maxPerChat &&
            rounds < 100) {
          rounds++;
          final before = timeline.events.length;
          await timeline.requestHistory(historyCount: 250);
          if (timeline.events.length == before) break;
        }
        final messages = <Map<String, Object?>>[];
        for (final e in timeline.events.reversed) {
          if (e.redacted) continue;
          if (e.type != EventTypes.Message &&
              e.type != EventTypes.Sticker &&
              e.type != EventTypes.Encrypted) {
            continue;
          }
          messages.add({
            's': e.senderId,
            'n': e.senderFromMemoryOrFallback.calcDisplayname(),
            't': e.originServerTs.millisecondsSinceEpoch,
            'b': e.type == EventTypes.Encrypted
                ? '[could not be decrypted]'
                : e.calcLocalizedBodyFallback(
                    const MatrixDefaultLocalizations(),
                    hideReply: true,
                    plaintextBody: true,
                  ),
          });
        }
        out.add({
          'id': room.id,
          'name': room.getLocalizedDisplayname(),
          'dm': room.isDirectChat,
          'm': messages,
        });
      } finally {
        timeline.cancelSubscriptions();
      }
    }
    return {
      'v': 1,
      'app': 'Vibe',
      'user': client.userID,
      'created': DateTime.now().millisecondsSinceEpoch,
      'rooms': out,
    };
  }

  static Future<Uint8List> _seal(Map<String, Object?> data, String pw) async {
    final packed = GZipCodec().encode(utf8.encode(jsonEncode(data)));
    final out = await _ch.invokeMethod<Uint8List>('encrypt', {
      'password': pw,
      'data': Uint8List.fromList(packed),
    });
    return out!;
  }

  /// Opens a backup file. Throws [PlatformException] with code
  /// 'wrong_password' or 'not_backup'.
  static Future<Map<String, Object?>> open(Uint8List file, String pw) async {
    final plain = await _ch.invokeMethod<Uint8List>('decrypt', {
      'password': pw,
      'data': file,
    });
    final json = jsonDecode(utf8.decode(GZipCodec().decode(plain!)));
    return Map<String, Object?>.from(json as Map);
  }

  static Future<String> _saveToPhone(
    String name,
    Uint8List bytes, {
    bool auto = false,
  }) async {
    final where = await _ch.invokeMethod<String>('save', {
      'name': name,
      'data': bytes,
      if (auto) 'keepPrefix': _autoPrefix,
      if (auto) 'keep': _keepAuto,
    });
    return where ?? 'Downloads';
  }

  /// Picks the Google Drive (or other) file automatic backups go to; null if cancelled.
  static Future<String?> pickCloud() =>
      _ch.invokeMethod<String>('pickCloud', {'name': 'vibe-backup.vibebackup'});

  static Future<String?> cloudName(String uri) async {
    try {
      return await _ch.invokeMethod<String>('cloudName', {'uri': uri});
    } catch (_) {
      return null;
    }
  }

  static Future<String> _saveToCloud(String uri, Uint8List bytes) async =>
      await _ch.invokeMethod<String>('saveCloud', {'uri': uri, 'data': bytes}) ??
      'Google Drive';

  static Future<String?> savedPassword() =>
      const FlutterSecureStorage().read(key: _pwKey);

  static Future<void> savePassword(String pw) =>
      const FlutterSecureStorage().write(key: _pwKey, value: pw);

  /// Automatic backup when it's due (called when Vibe opens). Quiet: the
  /// result is shown on the Backups page.
  static Future<void> maybeAuto(Client client) async {
    if (!PlatformInfos.isAndroid || _running || !client.isLogged()) return;
    final mode = AppSettings.vibeAutoBackup.value;
    if (mode == 'off') return;
    final every = mode == 'daily'
        ? const Duration(days: 1)
        : const Duration(days: 7);
    final last = DateTime.fromMillisecondsSinceEpoch(
      AppSettings.vibeLastAutoBackup.value,
    );
    if (DateTime.now().difference(last) < every) return;
    final pw = await savedPassword();
    if (pw == null || pw.isEmpty) {
      await AppSettings.vibeAutoBackupResult.setItem(
        'Needs a backup password: open Backups to set one',
      );
      return;
    }
    _running = true;
    try {
      // Give the first sync a moment so the newest messages are included.
      await Future.delayed(const Duration(seconds: 30));
      final data = await collect(client);
      final bytes = await _seal(data, pw);
      final now = DateTime.now();
      final cloud = AppSettings.vibeBackupCloudUri.value;
      // Google Drive: the one backup file there is replaced, like WhatsApp
      final where = cloud.isNotEmpty
          ? await _saveToCloud(cloud, bytes)
          : await _saveToPhone(
              '$_autoPrefix${_stamp(now, time: false)}.vibebackup',
              bytes,
              auto: true,
            );
      await AppSettings.vibeLastAutoBackup.setItem(now.millisecondsSinceEpoch);
      await AppSettings.vibeAutoBackupResult.setItem(
        'Last backup ${_stamp(now)} · $where',
      );
    } catch (e) {
      Logs().w('Vibe auto backup failed', e);
      await AppSettings.vibeAutoBackupResult.setItem(
        'Last automatic backup failed. It will try again next time Vibe opens.',
      );
    } finally {
      _running = false;
    }
  }
}

/// Settings > Backups.
class VibeBackupPage extends StatefulWidget {
  const VibeBackupPage({super.key});

  @override
  State<VibeBackupPage> createState() => _VibeBackupPageState();
}

class _VibeBackupPageState extends State<VibeBackupPage> {
  Future<String?> _askPassword({
    required String title,
    required bool confirm,
  }) => showVibeDialog<String>(
    context: context,
    builder: (ctx) => _PasswordDialog(title: title, confirm: confirm),
  );

  Future<T?> _withProgress<T>(
    Future<T> Function(ValueNotifier<String> step) work,
  ) async {
    final step = ValueNotifier<String>('Starting…');
    showVibeDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: step,
                  builder: (_, s, _) => Text(s),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      return await work(step);
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String? _cloud;

  @override
  void initState() {
    super.initState();
    final u = AppSettings.vibeBackupCloudUri.value;
    if (u.isNotEmpty) {
      VibeBackup.cloudName(u).then((n) {
        if (mounted) setState(() => _cloud = n ?? 'Google Drive');
      });
    }
  }

  /// Once: pick the file in Google Drive; automatic backups replace it from then on.
  Future<void> _pickCloud() async {
    String? uri;
    try {
      uri = await VibeBackup.pickCloud();
    } catch (e) {
      _say('$e');
      return;
    }
    if (uri == null || !mounted) return;
    await AppSettings.vibeBackupCloudUri.setItem(uri);
    final n = await VibeBackup.cloudName(uri);
    if (!mounted) return;
    setState(() => _cloud = n ?? 'Google Drive');
    if (AppSettings.vibeAutoBackup.value == 'off') {
      _say('Now turn on "Back up automatically" to keep it up to date');
    } else {
      // back up right away so Drive has a copy now
      await AppSettings.vibeLastAutoBackup.setItem(0);
      if (!mounted) return;
      VibeBackup.maybeAuto(Matrix.of(context).client);
      _say('Backing up to Google Drive…');
    }
  }

  Future<void> _backupNow() async {
    final client = Matrix.of(context).client;
    final pw = await _askPassword(title: 'Backup password', confirm: true);
    if (pw == null || !mounted) return;
    Uint8List? bytes;
    try {
      bytes = await _withProgress((step) async {
        final data = await VibeBackup.collect(
          client,
          progress: (s) => step.value = s,
        );
        step.value = 'Locking the backup…';
        return VibeBackup._seal(data, pw);
      });
    } catch (e) {
      _say('Backup failed: $e');
      return;
    }
    if (bytes == null || !mounted) return;
    final name = 'vibe-backup-${VibeBackup._stamp(DateTime.now())}.vibebackup';
    final where = await showVibeSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Backup ready',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('Where should it go?'),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: const Text('Save on this phone'),
              subtitle: const Text('Downloads/Vibe backups'),
              onTap: () => Navigator.of(ctx).pop('phone'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload),
              title: const Text('Google Drive or another app'),
              onTap: () => Navigator.of(ctx).pop('share'),
            ),
          ],
        ),
      ),
    );
    if (where == null || !mounted) return;
    try {
      if (where == 'phone') {
        final path = await VibeBackup._saveToPhone(name, bytes);
        _say('Saved to $path');
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                name: name,
                mimeType: 'application/octet-stream',
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _say('Could not save: $e');
    }
  }

  Future<void> _openBackup() async {
    final files = await selectFiles(context, title: 'Pick a Vibe backup');
    if (files.isEmpty || !mounted) return;
    final bytes = await files.first.readAsBytes();
    if (!mounted) return;
    final pw = await _askPassword(title: 'Backup password', confirm: false);
    if (pw == null || !mounted) return;
    try {
      final data = await _withProgress(
        (step) => VibeBackup.open(bytes, pw),
      );
      if (data == null || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VibeBackupViewer(data: data)),
      );
    } on PlatformException catch (e) {
      _say(
        e.code == 'wrong_password'
            ? 'Wrong password'
            : e.code == 'not_backup'
            ? 'That file is not a Vibe backup'
            : 'Could not open: ${e.message}',
      );
    } catch (e) {
      _say('Could not open: $e');
    }
  }

  Future<void> _pickAuto() async {
    final choice = await showVibeDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Back up automatically'),
        children: [
          for (final o in const [
            ('off', 'Off'),
            ('daily', 'Every day'),
            ('weekly', 'Every week'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(o.$1),
              child: Text(o.$2),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice != 'off' && (await VibeBackup.savedPassword()) == null) {
      if (!mounted) return;
      final pw = await _askPassword(
        title: 'Password for automatic backups',
        confirm: true,
      );
      if (pw == null) return;
      await VibeBackup.savePassword(pw);
    }
    await AppSettings.vibeAutoBackup.setItem(choice);
    if (choice != 'off') {
      // Run the first one soon.
      await AppSettings.vibeLastAutoBackup.setItem(0);
      if (mounted) VibeBackup.maybeAuto(Matrix.of(context).client);
    }
    if (mounted) setState(() {});
  }

  Future<void> _changePassword() async {
    final pw = await _askPassword(
      title: 'New password for automatic backups',
      confirm: true,
    );
    if (pw == null) return;
    await VibeBackup.savePassword(pw);
    _say('Password changed. Older backups still open with their old password.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = TextStyle(
      color: theme.colorScheme.secondary,
      fontWeight: FontWeight.bold,
    );
    final auto = AppSettings.vibeAutoBackup.value;
    final result = AppSettings.vibeAutoBackupResult.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Backups')),
      body: ListView(
        children: [
          // VibeGroups is applied by hand here (same look as the other pages).
          _Group(
            children: [
              ListTile(title: Text('Chat backup', style: header)),
              ListTile(
                leading: const Icon(Icons.backup),
                title: const Text('Back up now'),
                subtitle: const Text(
                  'Every chat\'s messages in one file, locked with a password',
                ),
                onTap: _backupNow,
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Open a backup'),
                subtitle: const Text(
                  'Read old chats from a backup file, even if the server deleted them',
                ),
                onTap: _openBackup,
              ),
            ],
          ),
          if (PlatformInfos.isAndroid)
            _Group(
              children: [
                ListTile(title: Text('Automatic backup', style: header)),
                ListTile(
                  leading: const Icon(Icons.update),
                  title: const Text('Back up automatically'),
                  subtitle: Text(switch (auto) {
                    'daily' => 'Every day · keeps the last 3',
                    'weekly' => 'Every week · keeps the last 3',
                    _ => 'Off',
                  }),
                  trailing: const Icon(Icons.chevron_right_outlined),
                  onTap: _pickAuto,
                ),
                ListTile(
                  leading: const Icon(Icons.add_to_drive),
                  title: const Text('Back up to Google Drive'),
                  subtitle: Text(
                    _cloud ?? 'Off · automatic backups stay on this phone',
                  ),
                  trailing: _cloud == null
                      ? const Icon(Icons.chevron_right_outlined)
                      : IconButton(
                          tooltip: 'Stop',
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            await AppSettings.vibeBackupCloudUri.setItem('');
                            if (mounted) setState(() => _cloud = null);
                          },
                        ),
                  onTap: _pickCloud,
                ),
                if (auto != 'off')
                  ListTile(
                    leading: const Icon(Icons.password),
                    title: const Text('Change backup password'),
                    onTap: _changePassword,
                  ),
                if (auto != 'off' && result.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.info),
                    title: Text(result),
                  ),
              ],
            ),
          _Group(
            children: [
              ListTile(title: Text('Good to know', style: header)),
              const ListTile(
                title: Text(
                  '• Backups hold the text of your messages: who, when and what. '
                  'Photos, videos and files are not included.\n'
                  '• Without the password nobody can open a backup, not even '
                  'Vibe. If you forget it, that backup can\'t be opened.\n'
                  '• Automatic backups go to Downloads/Vibe backups and stay '
                  'there even if you uninstall Vibe. They run when you open Vibe.\n'
                  '• Your encryption keys are backed up separately in '
                  'Encryption & Keys.',
                  style: TextStyle(fontSize: 13.5, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A rounded settings card (same look as VibeGroups).
class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2E2D32) : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: children),
        ),
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  final String title;
  final bool confirm;
  const _PasswordDialog({required this.title, required this.confirm});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _ok() {
    final pw = _a.text;
    if (widget.confirm && pw.length < 8) {
      setState(() => _error = 'At least 8 characters');
      return;
    }
    if (widget.confirm && pw != _b.text) {
      setState(() => _error = 'The passwords don\'t match');
      return;
    }
    if (pw.isEmpty) return;
    Navigator.of(context).pop(pw);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.confirm)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'You\'ll need this password to open the backup. Vibe can\'t '
                'recover it for you.',
              ),
            ),
          TextField(
            controller: _a,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => widget.confirm ? null : _ok(),
          ),
          if (widget.confirm)
            TextField(
              controller: _b,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repeat password'),
              onSubmitted: (_) => _ok(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _ok, child: const Text('OK')),
      ],
    );
  }
}

/// Read-only view of a backup: chats, then their messages.
class VibeBackupViewer extends StatelessWidget {
  final Map<String, Object?> data;
  const VibeBackupViewer({required this.data, super.key});

  @override
  Widget build(BuildContext context) {
    final rooms = (data['rooms'] as List? ?? const [])
        .whereType<Map>()
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    final created = DateTime.fromMillisecondsSinceEpoch(
      (data['created'] as num?)?.toInt() ?? 0,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('Backup · ${VibeBackup._stamp(created, time: false)}'),
      ),
      body: ListView.builder(
        itemCount: rooms.length,
        itemBuilder: (context, i) {
          final r = rooms[i];
          final msgs = (r['m'] as List? ?? const []).whereType<Map>().toList();
          return ListTile(
            leading: Icon(r['dm'] == true ? Icons.person : Icons.group),
            title: Text('${r['name'] ?? 'Chat'}'),
            subtitle: Text('${msgs.length} messages'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _BackupChat(
                  name: '${r['name'] ?? 'Chat'}',
                  messages: msgs,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BackupChat extends StatelessWidget {
  final String name;
  final List<Map> messages;
  const _BackupChat({required this.name, required this.messages});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: messages.length,
        itemBuilder: (context, i) {
          final m = messages[messages.length - 1 - i];
          final t = DateTime.fromMillisecondsSinceEpoch(
            (m['t'] as num?)?.toInt() ?? 0,
          );
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${m['n'] ?? m['s'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(
                        text: '  ${VibeBackup._stamp(t)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText('${m['b'] ?? ''}'),
              ],
            ),
          );
        },
      ),
    );
  }
}

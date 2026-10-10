// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// A newer Vibe release on GitHub.
class VibeRelease {
  final String version; // e.g. 2.0.21
  final String apkUrl;
  final String apkName;
  final int size; // bytes, 0 if unknown
  final List<String> notes;
  final String pageUrl;
  const VibeRelease({
    required this.version,
    required this.apkUrl,
    required this.apkName,
    required this.size,
    required this.notes,
    required this.pageUrl,
  });

  Map<String, Object?> toJson() => {
    'version': version,
    'apkUrl': apkUrl,
    'apkName': apkName,
    'size': size,
    'notes': notes,
    'pageUrl': pageUrl,
  };

  static VibeRelease? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return VibeRelease(
        version: j['version'] as String,
        apkUrl: j['apkUrl'] as String,
        apkName: j['apkName'] as String,
        size: (j['size'] as num?)?.toInt() ?? 0,
        notes: (j['notes'] as List? ?? const []).whereType<String>().toList(),
        pageUrl: j['pageUrl'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// In-app updater: checks the GitHub "latest release", shows what's new,
/// downloads the APK with Android's download manager and opens the system
/// installer. Native side: android/.../VibeUpdater.kt.
abstract class VibeUpdater {
  static const _repo = 'blackshadowde/Vibe-flutter';
  static const _api = 'https://api.github.com/repos/$_repo/releases/latest';
  static const _channel = MethodChannel('vibe/updater');

  static const _lastCheckKey = 'chat.vibe.update_last_check';
  static const _laterVersionKey = 'chat.vibe.update_later_version';
  static const _laterUntilKey = 'chat.vibe.update_later_until';

  static const _pendingKey = 'chat.vibe.update_pending';
  static const _checkedAtKey = 'chat.vibe.update_checked_at';

  static bool _busy = false;
  static bool _loaded = false;

  /// The newer release waiting to be installed (drives the red dots).
  static final ValueNotifier<VibeRelease?> pending = ValueNotifier(null);

  /// When GitHub was last asked successfully.
  static final ValueNotifier<DateTime?> lastChecked = ValueNotifier(null);

  /// True while a check is running (Updates page spinner).
  static final ValueNotifier<bool> checking = ValueNotifier(false);

  static String? _current;
  static Future<String> currentVersion() async =>
      _current ??= (await PackageInfo.fromPlatform()).version;

  /// Restores the last known pending update, so the red dot survives a
  /// restart without asking GitHub again. Drops it once installed.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final store = AppSettings.store;
      final at = store.getInt(_checkedAtKey);
      if (at != null) {
        lastChecked.value = DateTime.fromMillisecondsSinceEpoch(at);
      }
      final raw = store.getString(_pendingKey);
      if (raw == null) return;
      final r = VibeRelease.fromJson(jsonDecode(raw));
      if (r != null && compare(r.version, await currentVersion()) > 0) {
        pending.value = r;
      } else {
        await store.remove(_pendingKey);
      }
    } catch (_) {}
  }

  /// Asks GitHub now. Updates [pending] / [lastChecked]. Throws when offline.
  static Future<VibeRelease?> refresh() async {
    await load();
    checking.value = true;
    try {
      final r = await fetchNewer();
      final store = AppSettings.store;
      final now = DateTime.now();
      lastChecked.value = now;
      await store.setInt(_checkedAtKey, now.millisecondsSinceEpoch);
      pending.value = r;
      if (r == null) {
        await store.remove(_pendingKey);
      } else {
        await store.setString(_pendingKey, jsonEncode(r.toJson()));
      }
      return r;
    } finally {
      checking.value = false;
    }
  }

  /// Compares "2.0.19" style versions. > 0 when [a] is newer.
  static int compare(String a, String b) {
    List<int> parts(String v) => v
        .replaceFirst(RegExp(r'^v'), '')
        .split(RegExp(r'[.+]'))
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  /// Lines from the "What's new in this update" part of the release page.
  static List<String> _notesFrom(String body) {
    const start = "### What's new in this update";
    final i = body.indexOf(start);
    if (i < 0) return const [];
    var part = body.substring(i + start.length);
    final end = part.indexOf('\n---');
    if (end >= 0) part = part.substring(0, end);
    return part
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map(
          (l) => l
              .replaceFirst(RegExp(r'^[-*]\s+'), '')
              .replaceAll('**', '')
              .replaceAll('`', ''),
        )
        .toList();
  }

  /// Latest release if it is newer than this app, else null.
  static Future<VibeRelease?> fetchNewer() async {
    final current = await currentVersion();
    final res = await http
        .get(
          Uri.parse(_api),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('GitHub answered ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (j['tag_name'] as String? ?? '').replaceFirst('v', '');
    if (tag.isEmpty || compare(tag, current) <= 0) return null;
    final assets = (j['assets'] as List? ?? const [])
        .whereType<Map>()
        .where((a) => (a['name'] as String? ?? '').endsWith('.apk'))
        .toList();
    if (assets.isEmpty) return null;
    final apk = assets.first;
    return VibeRelease(
      version: tag,
      apkUrl: apk['browser_download_url'] as String,
      apkName: apk['name'] as String,
      size: (apk['size'] as num?)?.toInt() ?? 0,
      notes: _notesFrom(j['body'] as String? ?? ''),
      pageUrl: j['html_url'] as String? ??
          'https://github.com/$_repo/releases/latest',
    );
  }

  /// Quiet check on app start: at most every 6 hours, respects "Later".
  static Future<void> maybeCheck() async {
    if (!PlatformInfos.isAndroid || _busy) return;
    await load();
    final store = AppSettings.store;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = store.getInt(_lastCheckKey) ?? 0;
    if (now - last < const Duration(hours: 6).inMilliseconds) return;
    _busy = true;
    try {
      await store.setInt(_lastCheckKey, now);
      final r = await refresh();
      if (r == null) return;
      final laterVersion = store.getString(_laterVersionKey);
      final laterUntil = store.getInt(_laterUntilKey) ?? 0;
      if (laterVersion == r.version && now < laterUntil) return;
      final ctx =
          FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      await _show(ctx, r);
    } catch (e) {
      Logs().w('Vibe update check failed', e);
    } finally {
      _busy = false;
    }
  }

  /// "Check for updates" button in About Vibe.
  static Future<void> checkNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Checking for updates…')),
    );
    try {
      final r = await refresh();
      messenger.hideCurrentSnackBar();
      if (r == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('✅ You have the latest version')),
        );
        return;
      }
      if (!context.mounted) return;
      await _show(context, r);
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not check for updates. Are you online?'),
        ),
      );
    }
  }

  /// Opens the download / install sheet for [r].
  static Future<void> install(BuildContext context, VibeRelease r) =>
      _show(context, r);

  static Future<void> _show(BuildContext context, VibeRelease r) =>
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _UpdateSheet(release: r),
      );

  static Future<void> _later(String version) async {
    await AppSettings.store.setString(_laterVersionKey, version);
    await AppSettings.store.setInt(
      _laterUntilKey,
      DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
    );
  }
}

enum _Stage { info, downloading, needsPermission, installing, failed }

class _UpdateSheet extends StatefulWidget {
  final VibeRelease release;
  const _UpdateSheet({required this.release});

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  _Stage _stage = _Stage.info;
  int? _id;
  double? _progress;
  Timer? _poll;
  String? _error;

  VibeRelease get r => widget.release;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _openInBrowser() => launchUrlString(
    r.apkUrl,
    mode: LaunchMode.externalApplication,
  );

  Future<void> _start() async {
    setState(() {
      _stage = _Stage.downloading;
      _progress = null;
      _error = null;
    });
    try {
      final id = await VibeUpdater._channel.invokeMethod<int>('download', {
        'url': r.apkUrl,
        'name': r.apkName,
      });
      _id = id;
      _poll = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    } catch (e) {
      Logs().w('Vibe update download failed to start', e);
      // Fallback: let the browser download it.
      await _openInBrowser();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _tick() async {
    final id = _id;
    if (id == null) return;
    try {
      final s = await VibeUpdater._channel.invokeMapMethod<String, Object?>(
        'status',
        {'id': id},
      );
      if (!mounted || s == null) return;
      final status = s['status'];
      final done = (s['done'] as num?)?.toDouble() ?? 0;
      var total = (s['total'] as num?)?.toDouble() ?? 0;
      if (total <= 0) total = r.size.toDouble();
      if (status == 'done') {
        _poll?.cancel();
        setState(() => _progress = 1);
        await _install();
      } else if (status == 'failed' || status == 'missing') {
        _poll?.cancel();
        setState(() {
          _stage = _Stage.failed;
          _error = 'The download failed. Check your connection and try again.';
        });
      } else {
        setState(() => _progress = total > 0 ? done / total : null);
      }
    } catch (e) {
      Logs().w('Vibe update status failed', e);
    }
  }

  Future<void> _install() async {
    final id = _id;
    if (id == null) return;
    try {
      final allowed =
          await VibeUpdater._channel.invokeMethod<bool>('canInstall') ?? true;
      if (!allowed) {
        if (mounted) setState(() => _stage = _Stage.needsPermission);
        return;
      }
      if (mounted) setState(() => _stage = _Stage.installing);
      await VibeUpdater._channel.invokeMethod('install', {'id': id});
    } catch (e) {
      Logs().w('Vibe update install failed', e);
      if (mounted) {
        setState(() {
          _stage = _Stage.failed;
          _error = 'Could not open the installer.';
        });
      }
    }
  }

  Future<void> _cancel() async {
    _poll?.cancel();
    final id = _id;
    if (id != null) {
      try {
        await VibeUpdater._channel.invokeMethod('cancel', {'id': id});
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mb = r.size > 0 ? ' · ${(r.size / 1e6).toStringAsFixed(0)} MB' : '';
    const blurple = Color(0xFF5865F2);
    final buttonStyle = FilledButton.styleFrom(
      backgroundColor: blurple,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(50),
    );

    Widget action;
    switch (_stage) {
      case _Stage.info:
        action = Column(
          children: [
            FilledButton.icon(
              style: buttonStyle,
              onPressed: _start,
              icon: const Icon(Icons.system_update_alt),
              label: const Text(
                'Update now',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () {
                VibeUpdater._later(r.version);
                Navigator.of(context).pop();
              },
              child: const Text('Later'),
            ),
          ],
        );
      case _Stage.downloading:
        action = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                color: blurple,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _progress == null
                  ? 'Starting download…'
                  : 'Downloading… ${((_progress ?? 0) * 100).round()}%',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: _cancel, child: const Text('Cancel')),
          ],
        );
      case _Stage.needsPermission:
        action = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Android needs your OK once: allow Vibe to install updates, '
              'then come back and tap Install.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: () =>
                  VibeUpdater._channel.invokeMethod('allowInstall'),
              child: const Text('1. Allow in settings'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: buttonStyle,
              onPressed: _install,
              child: const Text('2. Install'),
            ),
          ],
        );
      case _Stage.installing:
        action = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tap "Update" in the Android installer. Your chats stay.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _install,
              child: const Text('Installer didn\'t open? Try again'),
            ),
          ],
        );
      case _Stage.failed:
        action = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.error),
            ),
            const SizedBox(height: 10),
            FilledButton(
              style: buttonStyle,
              onPressed: _start,
              child: const Text('Try again'),
            ),
            TextButton(
              onPressed: () {
                _openInBrowser();
                Navigator.of(context).pop();
              },
              child: const Text('Download in browser instead'),
            ),
          ],
        );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: blurple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.rocket_launch, color: blurple),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Update available',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Vibe ${r.version}$mb',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (r.notes.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  "WHAT'S NEW",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (final line in r.notes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      line,
                      style: const TextStyle(fontSize: 15, height: 1.35),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              action,
            ],
          ),
        ),
      ),
    );
  }
}

/// Small red dot on [child] while an update is waiting (gear, settings).
class VibeUpdateDot extends StatelessWidget {
  final Widget child;
  const VibeUpdateDot({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    VibeUpdater.load();
    return ValueListenableBuilder<VibeRelease?>(
      valueListenable: VibeUpdater.pending,
      builder: (context, r, child) => Badge(
        isLabelVisible: r != null,
        smallSize: 10,
        backgroundColor: const Color(0xFFF23F43),
        child: child,
      ),
      child: child,
    );
  }
}

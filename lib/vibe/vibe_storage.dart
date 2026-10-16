// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_dialog.dart';
import 'dart:io';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/builder.dart';
import 'package:fluffychat/vibe/vibe_settings_style.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Storage & cache, like Telegram's: pictures, videos and files you've
/// opened stay on the phone (so they appear instantly and don't download
/// again), up to a size you choose; decoded pictures stay in memory for
/// smooth scrolling.
abstract class VibeStorage {
  static const List<(int, String)> cacheLimits = [
    (1024, '1 GB'),
    (5 * 1024, '5 GB'),
    (16 * 1024, '16 GB'),
    (32 * 1024, '32 GB'),
    (0, 'No limit'),
  ];

  static const List<(int, String)> keepOptions = [
    (7, '1 week'),
    (30, '1 month'),
    (365, '1 year'),
    (0, 'Forever'),
  ];

  static const List<(int, String, String)> memoryOptions = [
    (128, 'Standard', '128 MB'),
    (256, 'More', '256 MB'),
    (512, 'Maximum', '512 MB'),
  ];

  static String label(List<(int, String)> options, int value) =>
      options.firstWhere((o) => o.$1 == value, orElse: () => options.last).$2;

  /// Pictures kept decoded in memory (fast scrolling, no flashing).
  static void applyMemoryCache() {
    final mb = AppSettings.vibeMemoryCacheMb.value.clamp(64, 1024);
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = mb << 20
      ..maximumSize = 4000;
  }

  static Future<Directory?> _dir() => getFileStorageLocation();

  static Future<List<File>> _files() async {
    final dir = await _dir();
    if (dir == null || !await dir.exists()) return [];
    final files = <File>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) files.add(e);
    }
    return files;
  }

  /// Bytes used by the media cache.
  static Future<int> usage() async {
    var total = 0;
    for (final f in await _files()) {
      try {
        total += await f.length();
      } catch (_) {}
    }
    return total;
  }

  /// Deletes the oldest cached files until the cache fits the limit.
  static Future<void> trim() async {
    final limitMb = AppSettings.vibeCacheLimitMb.value;
    if (limitMb <= 0) return;
    final limit = limitMb * 1024 * 1024;
    final entries = <(File, int, DateTime)>[];
    var total = 0;
    for (final f in await _files()) {
      try {
        final st = await f.stat();
        entries.add((f, st.size, st.modified));
        total += st.size;
      } catch (_) {}
    }
    if (total <= limit) return;
    entries.sort((a, b) => a.$3.compareTo(b.$3)); // oldest first
    for (final e in entries) {
      if (total <= limit * 0.9) break; // leave some room
      try {
        await e.$1.delete();
        total -= e.$2;
      } catch (_) {}
    }
    Logs().i('Vibe storage: trimmed media cache to ${_mb(total)}');
  }

  /// Empties the media cache (files download again when opened).
  static Future<void> clear() async {
    for (final f in await _files()) {
      try {
        await f.delete();
      } catch (_) {}
    }
    MxcImage.clearCache('');
    PaintingBinding.instance.imageCache.clear();
  }

  static String _mb(int bytes) {
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
    return '${(bytes / (1 << 20)).toStringAsFixed(bytes < 10 << 20 ? 1 : 0)} MB';
  }

  static String formatBytes(int bytes) => _mb(bytes);

  /// On start: memory size now, cache trim a bit later (never blocks start).
  static void start() {
    applyMemoryCache();
    Future<void>.delayed(const Duration(seconds: 45), () => trim().ignore());
  }
}

/// Settings > Chat > Storage & cache.
class VibeStoragePage extends StatefulWidget {
  const VibeStoragePage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const VibeSettingsTheme(child: VibeStoragePage()),
    ),
  );

  @override
  State<VibeStoragePage> createState() => _VibeStoragePageState();
}

class _VibeStoragePageState extends State<VibeStoragePage> {
  int? _used;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final u = await VibeStorage.usage();
    if (mounted) setState(() => _used = u);
  }

  Future<T?> _pick<T>(String title, List<(T, String)> options, T current) =>
      showVibeDialog<T>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(title),
          children: [
            for (final o in options)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, o.$1),
                child: Row(
                  children: [
                    Icon(
                      o.$1 == current
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(o.$2),
                  ],
                ),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final used = _used;
    final mem = AppSettings.vibeMemoryCacheMb.value;
    final memLabel = VibeStorage.memoryOptions
        .firstWhere(
          (o) => o.$1 == mem,
          orElse: () => VibeStorage.memoryOptions[1],
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Storage & cache')),
      body: ListView(
        children: [
          VibeGroups(
            children: [
              ListTile(
                leading: const Icon(Icons.pie_chart_outline),
                title: const Text('Media on this phone'),
                subtitle: Text(
                  used == null
                      ? 'Measuring…'
                      : '${VibeStorage.formatBytes(used)} of photos, videos '
                            'and files you\'ve opened',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.sd_storage_outlined),
                title: const Text('Maximum cache size'),
                subtitle: Text(
                  VibeStorage.label(
                    VibeStorage.cacheLimits,
                    AppSettings.vibeCacheLimitMb.value,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final v = await _pick(
                    'Maximum cache size',
                    VibeStorage.cacheLimits,
                    AppSettings.vibeCacheLimitMb.value,
                  );
                  if (v == null) return;
                  await AppSettings.vibeCacheLimitMb.setItem(v);
                  setState(() {});
                  await VibeStorage.trim();
                  await _measure();
                },
              ),
              ListTile(
                leading: const Icon(Icons.history_outlined),
                title: const Text('Keep media'),
                subtitle: Text(
                  VibeStorage.label(
                    VibeStorage.keepOptions,
                    AppSettings.vibeKeepMediaDays.value,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final v = await _pick(
                    'Keep media',
                    VibeStorage.keepOptions,
                    AppSettings.vibeKeepMediaDays.value,
                  );
                  if (v == null) return;
                  await AppSettings.vibeKeepMediaDays.setItem(v);
                  setState(() {});
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.memory_outlined),
                title: const Text('Memory for smooth scrolling'),
                subtitle: Text('${memLabel.$2} · ${memLabel.$3}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final v = await _pick(
                    'Memory for smooth scrolling',
                    [
                      for (final o in VibeStorage.memoryOptions)
                        (o.$1, '${o.$2} · ${o.$3}'),
                    ],
                    mem,
                  );
                  if (v == null) return;
                  await AppSettings.vibeMemoryCacheMb.setItem(v);
                  VibeStorage.applyMemoryCache();
                  setState(() {});
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  Icons.delete_sweep_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Clear cache',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                subtitle: const Text(
                  'Frees space. Media downloads again when you open it; your '
                  'chats and messages are not touched.',
                ),
                trailing: _clearing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _clearing
                    ? null
                    : () async {
                        setState(() => _clearing = true);
                        await VibeStorage.clear();
                        await _measure();
                        if (mounted) setState(() => _clearing = false);
                      },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Text(
              'A bigger cache means photos and videos appear instantly and '
              'don\'t download again. "Keep media" changes apply after '
              'restarting Vibe. Memory is only used while Vibe is open.',
              style: TextStyle(
                fontSize: 12.5,
                color: VibeSettingsStyle.text2(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

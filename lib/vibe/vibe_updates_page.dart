// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_updater.dart';
import 'package:fluffychat/vibe/vibe_whats_new.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Settings → Updates: current version, update status, what's new and a
/// refresh button.
class VibeUpdatesPage extends StatefulWidget {
  const VibeUpdatesPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute(builder: (_) => const VibeUpdatesPage()));

  @override
  State<VibeUpdatesPage> createState() => _VibeUpdatesPageState();
}

class _VibeUpdatesPageState extends State<VibeUpdatesPage> {
  static const _blurple = Color(0xFF5865F2);
  static const _green = Color(0xFF23A55A);

  String _version = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    VibeUpdater.currentVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
    VibeUpdater.load().then((_) {
      // Fresh check when the page opens, unless we just checked.
      final last = VibeUpdater.lastChecked.value;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(minutes: 2)) {
        _refresh();
      }
    });
  }

  Future<void> _refresh() async {
    if (VibeUpdater.checking.value) return;
    setState(() => _error = null);
    try {
      await VibeUpdater.refresh();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not reach GitHub. Are you online?');
      }
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  /// Notes bundled in this app for the installed version.
  List<String> _currentNotes() {
    final short = _version.split('.').take(2).join('.');
    final n = vibeReleaseNotes.where((e) => e.version == short).firstOrNull;
    return n == null ? const [] : n.items.map((i) => '${i.$1}  ${i.$2}').toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Updates'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: VibeUpdater.checking,
            builder: (context, busy, _) => IconButton(
              tooltip: 'Check for updates',
              onPressed: busy ? null : _refresh,
              icon: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          VibeUpdater.pending,
          VibeUpdater.checking,
          VibeUpdater.lastChecked,
        ]),
        builder: (context, _) {
          final r = VibeUpdater.pending.value;
          final busy = VibeUpdater.checking.value;
          final last = VibeUpdater.lastChecked.value;

          final IconData icon;
          final Color color;
          final String title;
          final String sub;
          if (r != null) {
            icon = Icons.system_update;
            color = const Color(0xFFF23F43);
            title = 'Update available';
            sub = 'Vibe ${r.version}'
                '${r.size > 0 ? ' · ${(r.size / 1e6).toStringAsFixed(0)} MB' : ''}';
          } else if (busy) {
            icon = Icons.sync;
            color = _blurple;
            title = 'Checking for updates…';
            sub = 'Asking GitHub for the latest release';
          } else if (_error != null) {
            icon = Icons.cloud_off;
            color = cs.error;
            title = 'Could not check';
            sub = _error!;
          } else if (last != null) {
            icon = Icons.check_circle;
            color = _green;
            title = 'You\'re up to date';
            sub = 'This is the newest Vibe';
          } else {
            icon = Icons.help_outline;
            color = cs.onSurfaceVariant;
            title = 'Not checked yet';
            sub = 'Tap refresh to check';
          }

          final notes = r?.notes ?? _currentNotes();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // Status card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(icon, color: color, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                sub,
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(height: 1, color: cs.outlineVariant),
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: 'Installed version',
                      value: _version.isEmpty ? '…' : _version,
                    ),
                    if (r != null)
                      _InfoRow(label: 'New version', value: r.version),
                    _InfoRow(
                      label: 'Last checked',
                      value: last == null ? 'Never' : _ago(last),
                    ),
                    const SizedBox(height: 14),
                    if (r != null)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _blurple,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => VibeUpdater.install(context, r),
                          icon: const Icon(Icons.system_update_alt),
                          label: const Text(
                            'Update now',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Check for updates'),
                        ),
                      ),
                  ],
                ),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    r != null
                        ? 'WHAT\'S NEW IN ${r.version}'
                        : 'IN YOUR VERSION',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in notes)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            line,
                            style: const TextStyle(fontSize: 15, height: 1.35),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => launchUrlString(
                  r?.pageUrl.isNotEmpty == true
                      ? r!.pageUrl
                      : 'https://github.com/blackshadowde/Vibe-flutter/releases',
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('All releases on GitHub'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

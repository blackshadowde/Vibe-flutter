// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

class VibeEncryptionPage extends StatefulWidget {
  const VibeEncryptionPage({super.key});

  @override
  State<VibeEncryptionPage> createState() => _VibeEncryptionPageState();
}

class _VibeEncryptionPageState extends State<VibeEncryptionPage> {
  late Future<dynamic> _state;

  @override
  void initState() {
    super.initState();
    _state = Matrix.of(context).client.getCryptoIdentityState();
  }

  void _reload() {
    setState(() {
      _state = Matrix.of(context).client.getCryptoIdentityState();
    });
  }

  Future<void> _open(String route) async {
    await context.push(route);
    if (mounted) _reload();
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset recovery key?'),
        content: const Text(
          'This creates a new recovery key. Old encrypted messages that are '
          'not on this device may become unreadable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _open('/backup?reset=true');
  }

  void _technical(dynamic state) {
    final client = Matrix.of(context).client;
    String safe(String Function() f) {
      try {
        return f();
      } catch (_) {
        return '—';
      }
    }

    final rows = <(String, String)>[
      ('User ID', safe(() => client.userID ?? '—')),
      ('Device ID', safe(() => client.deviceID ?? '—')),
      ('Device key', safe(() => client.fingerprintKey)),
      ('Identity key', safe(() => client.identityKey)),
      ('Encryption', safe(() => client.encryptionEnabled ? 'Enabled' : 'Off')),
      (
        'Cross-signing',
        safe(() => state.crossSigningEnabled == true ? 'Enabled' : 'Not ready'),
      ),
      (
        'Key backup',
        safe(() => state.keyBackupEnabled == true ? 'Enabled' : 'Not ready'),
      ),
    ];
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Technical details',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.$1,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        SelectableText(
                          r.$2,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontFamily: 'RobotoMono',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text(
          'Encryption & Keys',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () =>
                Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
      body: FutureBuilder<dynamic>(
        future: _state,
        builder: (context, snap) {
          final st = snap.data;
          bool f(bool Function() g) {
            try {
              return st != null && g();
            } catch (_) {
              return false;
            }
          }

          final initialized = f(() => st.initialized == true);
          final connected = f(() => st.connected == true);
          final crossSigning = f(() => st.crossSigningEnabled == true);
          final keyBackup = f(() => st.keyBackupEnabled == true);
          final active = initialized && connected;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Card(
                onTap: () => context.push('/rooms/settings/devices'),
                child: Row(
                  children: [
                    _Tile(Icons.lock_outline),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Encryption & Keys Status',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _Badge(active),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Tile(Icons.cloud_outlined),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'Message backup',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _Badge(keyBackup),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your encrypted messages are backed up with your recovery '
                      'key, so you can read your history on a new device.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _Stat(
                          'Device backup',
                          keyBackup ? 'Enabled' : 'Not ready',
                        ),
                        const SizedBox(width: 10),
                        _Stat(
                          'Server backup',
                          initialized ? 'Available' : 'Not ready',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _Stat(
                          'Secret storage',
                          connected ? 'Ready' : 'Not ready',
                        ),
                        const SizedBox(width: 10),
                        _Stat(
                          'Cross-signing',
                          crossSigning ? 'Ready' : 'Not ready',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, color: cs.outlineVariant),
                    const SizedBox(height: 12),
                    Text(
                      'Lost your key?',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: _reset,
                      child: const Text(
                        'Forgot your recovery key?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFC9CFFF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Card(
                onTap: () => _open('/backup'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Tile(Icons.history),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'Restore Message History',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _reset,
                      child: const Text(
                        'Forgot your recovery key?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFC9CFFF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Card(
                onTap: () => _technical(st),
                child: Row(
                  children: [
                    _Tile(Icons.terminal),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Technical details',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Card({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  const _Tile(this.icon);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, size: 22, color: const Color(0xFFC9CFFF)),
    );
  }
}

class _Badge extends StatelessWidget {
  final bool on;
  const _Badge(this.on);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = on ? const Color(0xFFC9CFFF) : cs.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: (on ? cs.primary : cs.error).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        on ? 'Active' : 'Not set up',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

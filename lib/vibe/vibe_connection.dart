// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Server connection state shown on the user's own avatar.
enum VibeConn { online, connecting, offline }

const Color vibeDotGreen = Color(0xFF23A55A);
const Color vibeDotOrange = Color(0xFFF59E0B);
const Color vibeDotGrey = Color(0xFF80848E);

extension VibeConnX on VibeConn {
  Color get color => switch (this) {
    VibeConn.online => vibeDotGreen,
    VibeConn.connecting => vibeDotOrange,
    VibeConn.offline => vibeDotGrey,
  };

  String get label => switch (this) {
    VibeConn.online => 'Online',
    VibeConn.connecting => 'Connecting…',
    VibeConn.offline => 'Offline',
  };
}

/// Rebuilds whenever the sync connection to the server changes.
class VibeConnectionBuilder extends StatefulWidget {
  final Client client;
  final Widget Function(BuildContext context, VibeConn conn) builder;

  const VibeConnectionBuilder({
    required this.client,
    required this.builder,
    super.key,
  });

  @override
  State<VibeConnectionBuilder> createState() => _VibeConnectionBuilderState();
}

class _VibeConnectionBuilderState extends State<VibeConnectionBuilder> {
  late VibeConn _conn;
  StreamSubscription<SyncStatusUpdate>? _sub;

  @override
  void initState() {
    super.initState();
    _conn = widget.client.prevBatch == null
        ? VibeConn.connecting
        : VibeConn.online;
    _sub = widget.client.onSyncStatus.stream.listen(_onStatus);
  }

  void _onStatus(SyncStatusUpdate update) {
    final VibeConn next;
    if (update.status == SyncStatus.error) {
      next = VibeConn.offline;
    } else if (update.status == SyncStatus.waitingForResponse &&
        _conn == VibeConn.offline) {
      next = VibeConn.connecting;
    } else if (update.status == SyncStatus.waitingForResponse &&
        widget.client.prevBatch == null) {
      next = VibeConn.connecting;
    } else {
      next = VibeConn.online;
    }
    if (next != _conn && mounted) setState(() => _conn = next);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _conn);
}

/// The chat's top bar while connecting: •-•-• with a light running along
/// the line; once connected the three dots turn green one by one, stay a
/// few seconds, then [idle] (their time) takes the spot again.
class VibeConnectBar extends StatefulWidget {
  final bool syncing;
  final String label;
  final Widget idle;
  const VibeConnectBar({
    required this.syncing,
    required this.label,
    required this.idle,
    super.key,
  });

  @override
  State<VibeConnectBar> createState() => _VibeConnectBarState();
}

class _VibeConnectBarState extends State<VibeConnectBar>
    with TickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _green = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  Timer? _hide;
  bool _showDone = false;

  @override
  void initState() {
    super.initState();
    if (widget.syncing) _run.repeat();
  }

  @override
  void didUpdateWidget(VibeConnectBar old) {
    super.didUpdateWidget(old);
    if (widget.syncing && !old.syncing) {
      _hide?.cancel();
      _showDone = false;
      _green.value = 0;
      _run.repeat();
    } else if (!widget.syncing && old.syncing) {
      _run.stop();
      _showDone = true;
      _green.forward(from: 0);
      _hide?.cancel();
      _hide = Timer(const Duration(milliseconds: 6500), () {
        if (mounted) setState(() => _showDone = false);
      });
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    _run.dispose();
    _green.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.syncing && !_showDone) return widget.idle;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        RepaintBoundary(
          child: CustomPaint(
            size: const Size(34, 10),
            painter: _ConnectDots(
              run: _run,
              green: _green,
              grey: cs.onSurfaceVariant.withValues(alpha: 0.45),
              light: cs.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            widget.syncing ? widget.label : 'Connected',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: widget.syncing ? null : vibeDotGreen,
              fontWeight: widget.syncing ? null : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectDots extends CustomPainter {
  final Animation<double> run, green;
  final Color grey, light;
  _ConnectDots({
    required this.run,
    required this.green,
    required this.grey,
    required this.light,
  }) : super(repaint: Listenable.merge([run, green]));

  static const _xs = [5.0, 17.0, 29.0];

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final g = green.value;
    // how green dot i is (one after another)
    double on(int i) => ((g - i * 0.28) / 0.28).clamp(0.0, 1.0);
    final p = -4 + run.value * 42; // the running light
    final line = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 2; i++) {
      final a = _xs[i] + 4, b = _xs[i + 1] - 4;
      final gl = on(i + 1);
      line.color = Color.lerp(grey, vibeDotGreen, gl)!;
      canvas.drawLine(Offset(a, cy), Offset(b, cy), line);
      if (g == 0 && p > a - 3 && p < b + 3) {
        final s = p.clamp(a, b);
        canvas.drawLine(
          Offset((s - 3).clamp(a, b), cy),
          Offset((s + 3).clamp(a, b), cy),
          Paint()
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round
            ..color = light,
        );
      }
    }
    for (var i = 0; i < 3; i++) {
      final near = g == 0
          ? (1 - ((_xs[i] - p).abs() / 7)).clamp(0.0, 1.0)
          : 0.0;
      final gi = on(i);
      final base = Color.lerp(grey, light, near)!;
      // a little pop as it turns green
      final r = 3.0 + 0.8 * near + 1.2 * (gi > 0 && gi < 1 ? (1 - (2 * gi - 1).abs()) : 0);
      canvas.drawCircle(
        Offset(_xs[i], cy),
        r,
        Paint()..color = Color.lerp(base, vibeDotGreen, gi)!,
      );
    }
  }

  @override
  bool shouldRepaint(_ConnectDots old) =>
      old.grey != grey || old.light != light;
}

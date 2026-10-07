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

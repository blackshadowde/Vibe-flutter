// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Own profile is fetched once and shared (it used to be re-requested from the
/// server on every rebuild, which made the home screen laggy).
abstract class VibeProfileCache {
  static final ValueNotifier<int> version = ValueNotifier<int>(0);
  static Future<Profile>? _future;
  static String? _userId;

  static Future<Profile> get(Client client) {
    if (_future == null || _userId != client.userID) {
      _userId = client.userID;
      _future = client.fetchOwnProfile().then<Profile>(
        (p) => p,
        onError: (Object e, StackTrace st) {
          _future = null;
          throw e;
        },
      );
    }
    return _future!;
  }

  static void refresh() {
    _future = null;
    version.value++;
  }
}

class VibeOwnProfileBuilder extends StatefulWidget {
  final Client client;
  final Widget Function(BuildContext context, Profile? profile) builder;
  const VibeOwnProfileBuilder({
    required this.client,
    required this.builder,
    super.key,
  });

  @override
  State<VibeOwnProfileBuilder> createState() => _VibeOwnProfileBuilderState();
}

class _VibeOwnProfileBuilderState extends State<VibeOwnProfileBuilder> {
  late Future<Profile> _f = VibeProfileCache.get(widget.client);

  void _reload() {
    if (!mounted) return;
    setState(() => _f = VibeProfileCache.get(widget.client));
  }

  @override
  void initState() {
    super.initState();
    VibeProfileCache.version.addListener(_reload);
  }

  @override
  void dispose() {
    VibeProfileCache.version.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Profile>(
    future: _f,
    builder: (context, snap) => widget.builder(context, snap.data),
  );
}

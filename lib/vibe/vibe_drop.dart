// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';

/// Photos and videos dragged in from other apps on Android (a screenshot
/// preview, Photos, Files in split screen). The open chat listens; the
/// native side is VibeDropNative.kt.
abstract class VibeDrop {
  static const _channel = MethodChannel('vibe/drop');
  static Object? _owner;
  static void Function(bool hovering)? _hover;
  static void Function(List<XFile> files)? _drop;

  /// The chat on screen takes the drops (the newest one wins).
  static void attach(
    Object owner, {
    required void Function(bool hovering) hover,
    required void Function(List<XFile> files) drop,
  }) {
    _owner = owner;
    _hover = hover;
    _drop = drop;
    _channel.setMethodCallHandler(_handle);
  }

  static void detach(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _hover = null;
    _drop = null;
  }

  static Future<void> _handle(MethodCall call) async {
    switch (call.method) {
      case 'enter':
        _hover?.call(true);
      case 'exit':
        _hover?.call(false);
      case 'drop':
        _hover?.call(false);
        final files = <XFile>[
          for (final f in (call.arguments as List? ?? const []))
            if (f is Map)
              XFile(
                f['path'] as String,
                mimeType: f['mime'] as String?,
                name: f['name'] as String?,
              ),
        ];
        if (files.isNotEmpty) _drop?.call(files);
    }
  }
}

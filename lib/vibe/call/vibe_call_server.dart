// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

/// Serves the bundled call files (Element Call + Vibe's host page) to the
/// in-app WebView from http://127.0.0.1:<random port>.
///
/// A loopback origin counts as secure, so the microphone and camera work,
/// and Element Call's ES modules load (they don't from file://). Only the
/// call's static files are served; all Matrix traffic goes through Dart.
abstract class VibeCallServer {
  static HttpServer? _server;
  static final Map<String, Uint8List> _cache = {};

  static const _types = <String, String>{
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'json': 'application/json',
    'wasm': 'application/wasm',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'ico': 'image/x-icon',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
    'ogg': 'audio/ogg',
    'mp3': 'audio/mpeg',
    'webm': 'video/webm',
    'txt': 'text/plain; charset=utf-8',
  };

  static Uri get origin => Uri.parse('http://127.0.0.1:${_server!.port}');

  /// Is Element Call bundled in this build?
  static Future<bool> available() async {
    try {
      await rootBundle.load('assets/element-call/index.html');
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Uri> start() async {
    if (_server != null) return origin;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle, onError: (e) => Logs().w('Vibe call server', e));
    _server = server;
    return origin;
  }

  static Future<void> stop() async {
    final s = _server;
    _server = null;
    _cache.clear();
    await s?.close(force: true);
  }

  static Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      // Only the app itself (the WebView) should load these.
      final remote = req.connectionInfo?.remoteAddress;
      if (remote != null && !remote.isLoopback) {
        res.statusCode = HttpStatus.forbidden;
        await res.close();
        return;
      }
      var path = Uri.decodeComponent(req.uri.path);
      if (path.contains('..') || !path.startsWith('/')) {
        res.statusCode = HttpStatus.badRequest;
        await res.close();
        return;
      }
      if (path.endsWith('/')) path = '${path}index.html';
      final allowed =
          path.startsWith('/element-call/') || path.startsWith('/vibe_call/');
      if (!allowed) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      final key = 'assets$path';
      final bytes = _cache[key] ?? await _load(key);
      final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
      res.headers.set(
        HttpHeaders.contentTypeHeader,
        _types[ext] ?? 'application/octet-stream',
      );
      res.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      res.headers.set('Cross-Origin-Resource-Policy', 'same-origin');
      res.contentLength = bytes.length;
      if (req.method != 'HEAD') res.add(bytes);
      await res.close();
    } catch (_) {
      try {
        res.statusCode = HttpStatus.notFound;
        await res.close();
      } catch (_) {}
    }
  }

  static Future<Uint8List> _load(String key) async {
    final data = await rootBundle.load(key);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    // Keep the small files (html, js, css) in memory during the call; the
    // big wasm and model files are read from the bundle each time.
    if (bytes.length <= 4 * 1024 * 1024) _cache[key] = bytes;
    return bytes;
  }
}

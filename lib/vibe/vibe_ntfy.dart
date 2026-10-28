// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/utils/start_push_foreground_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// "Built-in" notifications: no Google / Firebase, no Worker, no extra app.
///
/// Vibe gets a private random ntfy.sh topic, tells the Matrix server to send
/// push alerts to ntfy's Matrix gateway for that topic, and keeps one live
/// connection to the topic while a small foreground service keeps Vibe
/// alive. Alerts are shown by Vibe's normal notification code.
abstract class VibeNtfy {
  static const server = 'https://ntfy.sh';
  static const gateway = '$server/_matrix/push/v1/notify';
  static const _serviceName = 'vibe_builtin_push';

  static bool get enabled => AppSettings.vibePushMode.value == 'builtin';

  /// ntfy.sh only accepts Matrix (UnifiedPush, `?up=1`) pushes on topics
  /// named "up" + 12 characters: the phone that subscribes then "pays" the
  /// rate limit instead of the Matrix server. Any other name is rejected
  /// with HTTP 507, which is why older Vibe topics ("vibe…") never got a
  /// single notification.
  static final RegExp _validTopic = RegExp(r'^up[A-Za-z0-9]{12}$');

  static String topic() {
    var t = AppSettings.vibeNtfyTopic.value;
    if (!_validTopic.hasMatch(t)) {
      const chars =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final r = Random.secure();
      t = 'up${List.generate(12, (_) => chars[r.nextInt(chars.length)]).join()}';
      AppSettings.vibeNtfyTopic.setItem(t);
      // New topic: old message ids mean nothing here.
      AppSettings.vibeNtfyLastId.setItem('');
      _lastId = null;
    }
    return t;
  }

  /// The UnifiedPush endpoint the Matrix server pushes to (pusher pushkey).
  static String endpoint() => '$server/${topic()}?up=1';

  static http.Client? _http;
  static StreamSubscription<String>? _sub;
  static Timer? _retry;
  static int _backoff = 2;
  static bool _running = false;
  static String? _lastId;
  static void Function(Map<String, dynamic> notification)? _onPush;

  // ---------------------------------------------------------------- service

  static Future<void> _startService() async {
    if (!ForegroundServices.runningServices.contains(_serviceName)) {
      // Stops ForegroundServices.stopService() (file sending) from killing
      // our long-running service.
      ForegroundServices.runningServices.add(_serviceName);
    }
    try {
      if (await FlutterForegroundTask.isRunningService) {
        if (ForegroundServices.longLived) return;
        // A short job (sending files, a background push) holds the service
        // slot: restart it as the long-lived connection, or Android 14+
        // would stop it after ~3 minutes and notifications would die.
        await FlutterForegroundTask.stopService();
      }
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'vibe_connection',
          channelName: 'Vibe connection',
          channelDescription: 'Keeps Vibe connected for built-in notifications',
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
          showWhen: false,
          priority: NotificationPriority.MIN,
          channelImportance: NotificationChannelImportance.MIN,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      ForegroundServices.longLived = true;
      await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.remoteMessaging],
        notificationTitle: 'Vibe',
        notificationText: 'Connected for notifications',
        notificationIcon: NotificationIcon(metaDataName: 'ic_launcher'),
      );
    } catch (e, s) {
      Logs().w('[VibeNtfy] Could not start service', e, s);
    }
  }

  static Future<void> _stopService() async {
    ForegroundServices.runningServices.remove(_serviceName);
    if (ForegroundServices.runningServices.isNotEmpty) return;
    ForegroundServices.longLived = false;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  /// The always-on service, shared with Direct connection notifications.
  static Future<void> keepAlive() => _startService();

  static Future<void> releaseKeepAlive() => _stopService();

  /// Asks Android not to put Vibe to sleep (needed on many phones).
  /// Is Vibe allowed to run in the background (not battery-optimised)?
  static Future<bool> backgroundAllowed() async {
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return true;
    }
  }

  static Future<void> askBatteryExemption() async {
    try {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------- listening

  static Future<void> start(
    void Function(Map<String, dynamic> notification) onPush,
  ) async {
    _onPush = onPush;
    if (_running) return;
    _running = true;
    await _startService();
    _connect();
  }

  static Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    await _sub?.cancel();
    _sub = null;
    _http?.close();
    _http = null;
    await _stopService();
  }

  static void _scheduleReconnect() {
    if (!_running) return;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _backoff), _connect);
    _backoff = min(_backoff * 2, 120);
  }

  static Future<void> _connect() async {
    if (!_running) return;
    await _sub?.cancel();
    _http?.close();
    final client = _http = http.Client();
    try {
      final since = _lastId ?? AppSettings.vibeNtfyLastId.value;
      final uri = Uri.parse(
        '$server/${topic()}/json',
      ).replace(queryParameters: {if (since.isNotEmpty) 'since': since});
      final res = await client.send(http.Request('GET', uri));
      if (res.statusCode != 200) {
        Logs().w('[VibeNtfy] HTTP ${res.statusCode}');
        _scheduleReconnect();
        return;
      }
      _backoff = 2;
      _sub = res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onLine,
            onError: (e) {
              Logs().w('[VibeNtfy] stream error', e);
              _scheduleReconnect();
            },
            onDone: _scheduleReconnect,
            cancelOnError: true,
          );
    } catch (e) {
      Logs().w('[VibeNtfy] connect failed', e);
      _scheduleReconnect();
    }
  }

  static void _onLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final j = jsonDecode(line);
      if (j is! Map || j['event'] != 'message') return;
      final id = j['id'];
      if (id is String) {
        _lastId = id;
        AppSettings.vibeNtfyLastId.setItem(id);
      }
      var body = j['message'];
      if (body is! String) return;
      if (j['encoding'] == 'base64') {
        body = utf8.decode(base64.decode(body));
      }
      final payload = jsonDecode(body);
      if (payload is! Map || payload['notification'] is! Map) return;
      final data = Map<String, dynamic>.from(payload['notification'] as Map);
      data['devices'] ??= [];
      _onPush?.call(data);
    } catch (e) {
      Logs().w('[VibeNtfy] bad message', e);
    }
  }
}

// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:universal_html/html.dart' as html;


abstract class ForegroundServices {
  static final List<String> runningServices = [];

  static bool get platformSupported =>
      PlatformInfos.isMobile || PlatformInfos.isWeb;

  static bool _beforeUnload(html.Event e) {
    e.preventDefault();
    return true;
  }

  static Future<void> stopService(String name) async {
    runningServices.remove(name);
    if (runningServices.isNotEmpty) return;
    if (kIsWeb) {
      html.window.removeEventListener('beforeunload', _beforeUnload);
      return;
    }
    FlutterForegroundTask.stopService();
  }

  /// Start the connection service again after something else (a call)
  /// used the foreground slot.
  static Future<void> resume() async {
    if (runningServices.isEmpty || kIsWeb) return;
    final names = List<String>.of(runningServices);
    runningServices.clear();
    await startService(names.first);
    runningServices
      ..clear()
      ..addAll(names);
  }

  static Future<void> startService(String name) async {
    try {
      runningServices.add(name);
      if (kIsWeb) {
        html.window.addEventListener('beforeunload', _beforeUnload);
        return;
      }
      if (PlatformInfos.isMobile) {
        FlutterForegroundTask.init(
          // Same quiet category as Vibe's connection: no sound, no status
          // bar icon, and one switch hides it (see VibeHideService).
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'vibe_connection',
            channelName: 'Vibe connection',
            channelDescription: 'Keeps Vibe connected for notifications',
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
          ),
        );
        if (await FlutterForegroundTask.isRunningService) {
          Logs().d('[PushHelper] Foreground service already running');
          return;
        }
        final result = await FlutterForegroundTask.startService(
          serviceTypes: [ForegroundServiceTypes.shortService],
          notificationTitle: 'Vibe',
          notificationText: 'Connected for notifications',
          notificationIcon: NotificationIcon(metaDataName: 'ic_launcher'),
        );
        final started = result is ServiceRequestSuccess;
        Logs().d('[PushHelper] Foreground service start: $started ($result)');
      } else if (kIsWeb) {
        // TODO: Implement window.onBeforeUnload overwrite
      }
      return;
    } catch (e, s) {
      Logs().w('[PushHelper] Unable to start foreground service', e, s);
      return;
    }
  }
}

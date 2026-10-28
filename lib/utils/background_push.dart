// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// Copyright (C) 2020, 2021 Famedly GmbH
// Copyright (C) 2021 Fluffychat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

//<GOOGLE_SERVICES>import 'package:fcm_shared_isolate/fcm_shared_isolate.dart';
import 'package:vibe/vibe/vibe_direct.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/main.dart';
import 'package:vibe/utils/notification_background_handler.dart';
import 'package:vibe/utils/push_helper.dart';
import 'package:vibe/widgets/vibe_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:unifiedpush_ui/unifiedpush_ui.dart';

import 'package:vibe/vibe/vibe_ntfy.dart';

import '../config/app_config.dart';
import '../config/setting_keys.dart';
import '../widgets/matrix.dart';
import 'platform_infos.dart';

class BackgroundPush {
  static BackgroundPush? _instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  List<Client> _clients;

  List<Client> get clients => matrix?.widget.clients ?? _clients;

  MatrixState? matrix;
  String? _fcmToken;

  String? get fcmToken => _fcmToken;
  void Function(String errorMsg, {Uri? link})? onFcmError;
  L10n? l10n;

  Future<void> loadLocale() async {
    final context = matrix?.context;
    // inspired by _lookupL10n in .dart_tool/flutter_gen/gen_l10n/l10n.dart
    l10n ??=
        (context != null && context.mounted ? L10n.of(context) : null) ??
        (await L10n.delegate.load(PlatformDispatcher.instance.locale));
  }

  final pendingTests = <String, Completer<void>>{};
  bool firebaseEnabled = false;

  //<GOOGLE_SERVICES>final firebase = FcmSharedIsolate();

  DateTime? lastReceivedPush;

  bool upAction = false;

  Future<void> _init() async {
    //<GOOGLE_SERVICES>firebaseEnabled = true;
    try {
      mainIsolateReceivePort?.listen((message) async {
        try {
          await notificationTap(
            NotificationResponseJson.fromJsonString(message),
            clients: clients,
            router: VibeApp.router,
            l10n: l10n,
          );
        } catch (e, s) {
          Logs().wtf('Main Notification Tap crashed', e, s);
        }
      });
      if (PlatformInfos.isAndroid) {
        final port = ReceivePort();
        IsolateNameServer.removePortNameMapping('background_tab_port');
        IsolateNameServer.registerPortWithName(
          port.sendPort,
          'background_tab_port',
        );
        port.listen((message) async {
          try {
            await notificationTap(
              NotificationResponseJson.fromJsonString(message),
              clients: clients,
              router: VibeApp.router,
              l10n: l10n,
            );
          } catch (e, s) {
            Logs().wtf('Main Notification Tap crashed', e, s);
          }
        });
      }
      await _flutterLocalNotificationsPlugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('vibe_notification'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (response) => notificationTap(
          response,
          clients: clients,
          router: VibeApp.router,
          l10n: l10n,
        ),
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );
      Logs().v('Flutter Local Notifications initialized');
      // Vibe: make sure the message channel exists with HIGH importance, so
      // notifications pop up on screen (heads-up). Pushes shown by Android
      // itself also use this channel (see AndroidManifest meta-data).
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              AppConfig.pushNotificationsChannelId,
              'Incoming messages',
              importance: Importance.high,
            ),
          );
      //<GOOGLE_SERVICES>firebase.setListeners(
      //<GOOGLE_SERVICES>  onMessage: (message) => pushHelper(
      //<GOOGLE_SERVICES>    PushNotification.fromJson(
      //<GOOGLE_SERVICES>       message.tryGetMap<String, Object>('data') ?? message,
      //<GOOGLE_SERVICES>    ),
      //<GOOGLE_SERVICES>    clients: clients,
      //<GOOGLE_SERVICES>    l10n: l10n,
      //<GOOGLE_SERVICES>    activeRoomId: matrix?.activeRoomId,
      //<GOOGLE_SERVICES>    flutterLocalNotificationsPlugin: _flutterLocalNotificationsPlugin,
      //<GOOGLE_SERVICES>  ),
      //<GOOGLE_SERVICES>);
      if (Platform.isAndroid) {
        await UnifiedPush.initialize(
          onNewEndpoint: _newUpEndpoint,
          onRegistrationFailed: (_, i) => _upUnregistered(i),
          onUnregistered: _upUnregistered,
          onMessage: _onUpMessage,
        );
      }
    } catch (e, s) {
      Logs().e('Unable to initialize Flutter local notifications', e, s);
    }
  }

  BackgroundPush._(this._clients) {
    _init();
  }

  factory BackgroundPush.clientOnly(List<Client> clients) {
    return _instance ??= BackgroundPush._(clients);
  }

  factory BackgroundPush(
    MatrixState matrix, {
    final void Function(String errorMsg, {Uri? link})? onFcmError,
  }) {
    final instance = BackgroundPush.clientOnly(matrix.widget.clients);
    instance.matrix = matrix;
    // ignore: prefer_initializing_formals
    instance.onFcmError = onFcmError;
    return instance;
  }

  /// Makes sure that there is exactly ONE pusher with these settings for this
  /// client and deletes all other pushers if not.
  Future<void> setupPusher({
    required Client client,
    String? gatewayUrl,
    String? token,
  }) async {
    if (PlatformInfos.isIOS) {
      //<GOOGLE_SERVICES>await firebase.requestPermission();
    }
    if (PlatformInfos.isAndroid && !isIntegrationTest) {
      _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    final appDisplayName = PlatformInfos.appDisplayName;

    final pushers =
        await (client.getPushers().catchError((e) {
          Logs().w('[Push] Unable to request pushers', e);
          return <Pusher>[];
        })) ??
        [];

    // we need the deviceAppId to remove potential legacy pusher
    var deviceAppId = '${AppConfig.pushNotificationsAppId}.${client.deviceID}';
    // appId may only be up to 64 chars as per spec
    if (deviceAppId.length > 64) {
      deviceAppId = deviceAppId.substring(0, 64);
    }
    final thisAppId = deviceAppId;
    if (gatewayUrl == null || token == null) {
      Logs().w('[Push] Missing required push credentials');
      return;
    }

    if (pushers.any(
      (currentPusher) =>
          currentPusher.pushkey == token &&
          currentPusher.data.additionalProperties['client_name'] ==
              client.clientName &&
          currentPusher.kind == 'http' &&
          currentPusher.appId == thisAppId &&
          currentPusher.appDisplayName == appDisplayName &&
          currentPusher.deviceDisplayName == client.deviceName &&
          currentPusher.lang == 'en' &&
          currentPusher.data.url.toString() == gatewayUrl &&
          currentPusher.data.format ==
              AppSettings.pushNotificationsPusherFormat.value &&
          currentPusher.data.additionalProperties['data_message'] ==
              pusherDataMessageFormat,
    )) {
      Logs().i('[Push] Pusher already set for ${client.deviceID}');
      return;
    }

    if (!client.isLogged()) return;

    final legacyPushers = pushers.where(
      (pusher) =>
          pusher.appId == thisAppId || // To migrate older app-id format:
          ((pusher.appId == 'chat.fluffy.fluffychat.data_message' ||
                  pusher.appId == 'chat.fluffy.fluffychat' ||
                  // before Vibe had its own app ID
                  pusher.appId.startsWith('chat.fluffy.fluffychat.')) &&
              pusher.pushkey == token),
    );
    for (final pusher in legacyPushers) {
      try {
        await client.deletePusher(pusher);
        Logs().i('[Push] Removed legacy pusher for ${client.deviceID}');
      } catch (err) {
        Logs().w(
          '[Push] Failed to remove old pusher for ${client.deviceID}',
          err,
        );
      }
    }

    Logs().i('Need to set new pusher for ${client.clientName}');
    try {
      await client.postPusher(
        Pusher(
          pushkey: token,
          appId: thisAppId,
          appDisplayName: appDisplayName,
          deviceDisplayName: PlatformInfos.appDisplayName,
          lang: 'en',
          data: PusherData(
            url: Uri.parse(gatewayUrl),
            format: AppSettings.pushNotificationsPusherFormat.value,
            additionalProperties: {
              'client_name': client.clientName,
              'data_message': pusherDataMessageFormat,
            },
          ),
          kind: 'http',
        ),
        append: true,
      );
    } catch (e, s) {
      Logs().e('[Push] Unable to set pushers', e, s);
    }
  }

  final pusherDataMessageFormat = Platform.isAndroid;

  static bool _wentToRoomOnStartup = false;

  /// Vibe built-in notifications (ntfy, no Google): register this device's
  /// pusher at ntfy's Matrix gateway and keep a live connection.
  Future<void> setupBuiltinPush() async {
    for (final client in clients) {
      if (!client.isLogged()) continue;
      await removeFirebasePusher(client);
      await setupPusher(
        client: client,
        gatewayUrl: VibeNtfy.gateway,
        token: VibeNtfy.endpoint(),
      );
    }
    await VibeNtfy.start(
      (data) => pushHelper(
        PushNotification.fromJson(data),
        clients: clients,
        l10n: l10n,
        activeRoomId: matrix?.activeRoomId,
        flutterLocalNotificationsPlugin: _flutterLocalNotificationsPlugin,
      ),
    );
  }

  /// After a restart, before the app is opened: listen again (no screen,
  /// so no permission prompts; the pushers are already on the server).
  Future<void> startHeadless() async {
    try {
      if (VibeDirect.enabled) {
        await VibeDirect.start(
          clients,
          (client, event) => pushHelper(
            VibeDirect.pushFor(client, event),
            knownEvent: event,
            clients: clients,
            flutterLocalNotificationsPlugin: _flutterLocalNotificationsPlugin,
          ),
          headless: true,
        );
      } else if (VibeNtfy.enabled) {
        await VibeNtfy.start(
          (data) => pushHelper(
            PushNotification.fromJson(data),
            clients: clients,
            flutterLocalNotificationsPlugin: _flutterLocalNotificationsPlugin,
          ),
        );
      }
    } catch (e, s) {
      Logs().w('[Push] Could not reconnect after a restart', e, s);
    }
  }

  /// Vibe Direct connection (like Vibgram): Vibe's own Matrix connection
  /// stays open and notifies straight away; Firebase is only a backup.
  Future<void> setupDirectPush() async {
    // Android 13+: no notifications at all until the app asks (Direct mode
    // never registered a pusher, so it never asked: new installs stayed
    // silent)
    if (PlatformInfos.isAndroid && !isIntegrationTest) {
      try {
        await _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } catch (e) {
        Logs().w('[Push] Could not ask for the notification permission', e);
      }
    }
    await VibeNtfy.stop();
    await VibeDirect.start(
      clients,
      (client, event) => pushHelper(
        VibeDirect.pushFor(client, event),
        knownEvent: event,
        clients: clients,
        l10n: l10n,
        activeRoomId: matrix?.activeRoomId,
        flutterLocalNotificationsPlugin: _flutterLocalNotificationsPlugin,
      ),
    );
    // Firebase is no longer used on Android: Vibe's own connection shows
    // everything, and a second Firebase copy made duplicate notifications.
    for (final client in clients) {
      if (client.isLogged()) await removeFirebasePusher(client);
    }
  }

  /// Remove this device's Firebase pusher from the server, so the push
  /// gateway stops sending copies of every message.
  Future<void> removeFirebasePusher(Client client) async {
    try {
      final gateway = AppSettings.pushNotificationsGatewayUrl.value;
      var thisAppId =
          '${AppConfig.pushNotificationsAppId}.${client.deviceID}';
      if (thisAppId.length > 64) thisAppId = thisAppId.substring(0, 64);
      final pushers = await client.getPushers() ?? [];
      for (final p in pushers) {
        final url = p.data.url.toString();
        if (url != gateway && url != vibeLegacyGateway) continue;
        if (p.appId != thisAppId) continue;
        await client.deletePusher(p);
        Logs().i('[Push] Removed Firebase pusher for ${client.deviceID}');
      }
    } catch (e) {
      Logs().w('[Push] Could not remove Firebase pusher', e);
    }
  }

  Future<void> setupPush(BuildContext context) async {
    // Firebase mode was removed on Android: move to the direct connection.
    if (PlatformInfos.isAndroid &&
        AppSettings.vibePushMode.value == 'standard') {
      await AppSettings.vibePushMode.setItem('direct');
    }
    if (!(PlatformInfos.isAndroid && VibeDirect.enabled)) {
      await VibeDirect.stop();
    }
    if (PlatformInfos.isAndroid && VibeDirect.enabled) {
      await setupDirectPush();
    } else if (PlatformInfos.isAndroid && VibeNtfy.enabled) {
      await setupBuiltinPush();
    } else if (PlatformInfos.isAndroid &&
        (await UnifiedPush.getDistributors()).isNotEmpty &&
        context.mounted) {
      await UnifiedPushUi(
        context: context,
        instances: ['default'],
        unifiedPushFunctions: UPFunctions(),
        showNoDistribDialog: false,
        onNoDistribDialogDismissed: () {}, // TODO: Implement me
      ).registerAppWithDialog();
    } else {
      for (final client in clients) {
        Logs().d('SetupPush for Client ${client.clientName}');
        if (client.onLoginStateChanged.value != LoginState.loggedIn ||
            !PlatformInfos.isMobile ||
            matrix == null) {
          return;
        }
        // Do not setup unifiedpush if this has been initialized by
        // an unifiedpush action
        if (upAction) {
          return;
        }
        await setupFirebase(client);
      }
    }

    // ignore: unawaited_futures
    _flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails().then((
      details,
    ) {
      if (details == null ||
          !details.didNotificationLaunchApp ||
          _wentToRoomOnStartup) {
        return;
      }
      _wentToRoomOnStartup = true;
      final response = details.notificationResponse;
      if (response != null) {
        notificationTap(
          response,
          clients: clients,
          router: VibeApp.router,
          l10n: l10n,
        );
      }
    });
  }

  Future<void> _noFcmWarning() async {
    if (matrix == null) {
      return;
    }
    if (AppSettings.showNoGoogle.value) {
      return;
    }
    await loadLocale();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (PlatformInfos.isAndroid) {
        onFcmError?.call(
          l10n!.noGoogleServicesWarning,
          link: Uri.parse(AppConfig.enablePushTutorial),
        );
        return;
      }
      onFcmError?.call(l10n!.oopsPushError);
    });
  }

  Future<void> setupFirebase(Client client) async {
    Logs().v('Setup firebase');
    if (!firebaseEnabled) {
      await _noFcmWarning();
      return;
    }
    if (_fcmToken?.isEmpty ?? true) {
      if (PlatformInfos.isIOS) {
        //<GOOGLE_SERVICES>await firebase.requestPermission();
      }
      const max = 5;
      for (var i = 0; i < max; i++) {
        try {
          await Future.delayed(const Duration(seconds: 1));
          //<GOOGLE_SERVICES>_fcmToken = await firebase.getToken();
          if (_fcmToken != null) break;
        } catch (e, s) {
          Logs().w(
            '[Push] cannot get token - try ($i/$max)',
            e,
            e is String ? null : s,
          );
        }
      }
      if (_fcmToken == null) {
        await _noFcmWarning();
        return;
      }
    }
    await setupPusher(
      client: client,
      gatewayUrl: AppSettings.pushNotificationsGatewayUrl.value,
      token: _fcmToken,
    );
  }

  Future<void> _newUpEndpoint(PushEndpoint newPushEndpoint, String i) async {
    final newEndpoint = newPushEndpoint.url;
    upAction = true;
    if (newEndpoint.isEmpty) {
      await _upUnregistered(i);
      return;
    }
    var endpoint =
        'https://matrix.gateway.unifiedpush.org/_matrix/push/v1/notify';
    try {
      final url = Uri.parse(newEndpoint)
          .replace(path: '/_matrix/push/v1/notify', query: '')
          .toString()
          .split('?')
          .first;
      final res = json.decode(
        utf8.decode((await http.get(Uri.parse(url))).bodyBytes),
      );
      if (res['gateway'] == 'matrix' ||
          (res['unifiedpush'] is Map &&
              res['unifiedpush']['gateway'] == 'matrix')) {
        endpoint = url;
      }
    } catch (e) {
      Logs().i(
        '[Push] No self-hosted unified push gateway present: $newEndpoint',
      );
    }
    Logs().i('[Push] UnifiedPush using endpoint $endpoint');

    for (final client in clients) {
      await setupPusher(
        client: client,
        gatewayUrl: endpoint,
        token: newEndpoint,
      );
    }
    await AppSettings.unifiedPushEndpoint.setItem(newEndpoint);
    await AppSettings.unifiedPushRegistered.setItem(true);
  }

  Future<void> _upUnregistered(String i) async {
    upAction = true;
    Logs().i('[Push] Removing UnifiedPush endpoint...');
    await AppSettings.unifiedPushEndpoint.setItem(
      AppSettings.unifiedPushEndpoint.defaultValue,
    );
    await AppSettings.unifiedPushRegistered.setItem(false);
  }

  Future<void> _onUpMessage(PushMessage pushMessage, String i) async {
    final message = pushMessage.content;
    upAction = true;
    final data = Map<String, dynamic>.from(
      json.decode(utf8.decode(message))['notification'],
    );
    // UP may strip the devices list
    data['devices'] ??= [];
    await pushHelper(
      PushNotification.fromJson(data),
      clients: clients,
      l10n: l10n,
      activeRoomId: matrix?.activeRoomId,
      flutterLocalNotificationsPlugin: _flutterLocalNotificationsPlugin,
    );
  }
}

class UPFunctions extends UnifiedPushFunctions {
  final List<String> features = [
    /*list of features*/
  ];

  @override
  Future<String?> getDistributor() async {
    return await UnifiedPush.getDistributor();
  }

  @override
  Future<List<String>> getDistributors() async {
    return await UnifiedPush.getDistributors(features);
  }

  @override
  Future<void> registerApp(String instance) async {
    await UnifiedPush.register(instance: instance, features: features);
  }

  @override
  Future<void> saveDistributor(String distributor) async {
    await UnifiedPush.saveDistributor(distributor);
  }
}

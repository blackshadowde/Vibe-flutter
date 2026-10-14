// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/start_push_foreground_service.dart';
import 'package:fluffychat/vibe/call/vibe_call_driver.dart';
import 'package:fluffychat/vibe/call/vibe_call_members.dart';
import 'package:fluffychat/vibe/call/vibe_call_server.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:matrix/matrix.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

enum VibeCallStage { idle, connecting, inCall, leaving }

/// One voice / video call at a time, like Sable: Element Call runs in a
/// WebView that stays alive while you move around the app. The call can be
/// full screen or shrunk to the green bar at the top.
class VibeCall extends ChangeNotifier {
  VibeCall._();
  static final VibeCall instance = VibeCall._();

  static const _system = MethodChannel('vibe/system');

  Room? room;
  VibeCallStage stage = VibeCallStage.idle;
  WebViewController? web;
  VibeCallDriver? _driver;
  Map<String, Object?>? _config;

  /// Full screen (true) or the green bar (false).
  bool expanded = true;

  bool micOn = true;
  bool videoOn = false;
  bool soundOn = true;
  bool speakerOn = false;
  bool _wantVideo = false;
  bool _firstMedia = true;
  bool _hadService = false;

  DateTime? joinedAt;

  /// Show Element Call's video view (video calls, or "show video" in a
  /// voice call). Otherwise Vibe's own call screen is shown.
  bool showStage = false;

  /// Something went wrong before the call connected.
  String? problem;

  /// What happened during the call, for "Copy call log".
  final List<String> log = [];

  void _log(String line) {
    final t = DateTime.now().toIso8601String().substring(11, 23);
    log.add('$t $line');
    if (log.length > 400) log.removeRange(0, log.length - 400);
    Logs().v('[Vibe call] $line');
  }

  Future<void> copyLog() async {
    final head = [
      'Vibe call log',
      'room: ${room?.id}',
      'server: ${room?.client.homeserver}',
      'stage: ${stage.name}',
      'call service: ${VibeCallServer.livekitServiceUrl ?? 'none found'}',
    ];
    await Clipboard.setData(ClipboardData(text: [...head, ...log].join('\n')));
    _snack('Call log copied');
  }

  /// People in the call other than you.
  List<String> get others {
    final r = room;
    if (r == null) return const [];
    final me = r.client.userID;
    return VibeCallMembers.userIds(r).where((u) => u != me).toList();
  }

  Timer? _connectTimeout;
  Completer<void>? _left;

  bool get active => web != null;
  bool isIn(Room r) => active && room?.id == r.id;

  String get roomName => room?.getLocalizedDisplayname() ?? 'Call';

  static BuildContext? get _navContext =>
      FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;

  static void _snack(String text) {
    final ctx = _navContext;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------------------------------------------------------------
  // Start / join
  // ---------------------------------------------------------------------

  /// Join (or start) the call in [room].
  static Future<void> join(
    BuildContext context,
    Room room, {
    bool video = false,
  }) async {
    final call = instance;
    if (call.isIn(room)) {
      call.expand();
      return;
    }
    if (call.active) {
      final name = call.roomName;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Switch call?'),
          content: Text('You\'ll leave the call in $name.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Switch'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await call.hangup();
    }
    if (!await VibeCallServer.available()) {
      _snack('Calls aren\'t included in this build of Vibe.');
      return;
    }
    if (!context.mounted) return;
    if (!await VibeCallSupport.ensure(context, room)) return;
    if (!context.mounted) return;
    if (!await VibeCallPower.ensureAllowed(context, room)) return;
    if (PlatformInfos.isMobile) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        _snack(
          mic.isPermanentlyDenied
              ? 'Allow the microphone for Vibe in Android settings to call.'
              : 'Vibe needs the microphone for calls.',
        );
        if (mic.isPermanentlyDenied) await openAppSettings();
        return;
      }
      if (video) {
        final cam = await Permission.camera.request();
        if (!cam.isGranted) video = false;
      }
    }
    if (!context.mounted) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    await call._start(room, video: video, dark: dark);
  }

  Future<void> _start(
    Room room, {
    required bool video,
    required bool dark,
  }) async {
    final client = room.client;
    this.room = room;
    stage = VibeCallStage.connecting;
    expanded = true;
    micOn = true;
    videoOn = video;
    _wantVideo = video;
    soundOn = true;
    // Loudspeaker by default (switch to the earpiece with the button).
    speakerOn = true;
    showStage = video;
    _firstMedia = true;
    joinedAt = null;
    problem = null;
    log.clear();
    _log('start ${room.id} video=$video encrypted=${room.encrypted}');
    notifyListeners();
    VibeHaptics.medium();

    try {
      await room.postLoad();
      final count = room.summary.mJoinedMemberCount ?? 0;
      if (count > 0 && count <= 300) {
        await room.requestParticipants([Membership.join]);
      }
    } catch (e) {
      Logs().w('Vibe call: could not load room members', e);
    }

    final origin = await VibeCallServer.start();
    final dm = room.isDirectChat;
    final ongoing = VibeCallMembers.active(room);
    final intent = dm
        ? (ongoing
              ? (video ? 'join_existing_dm' : 'join_existing_dm_voice')
              : (video ? 'start_call_dm' : 'start_call_dm_voice'))
        : (ongoing ? 'join_existing' : 'start_call');
    _log('intent $intent, already in call: ${VibeCallMembers.userIds(room)}');
    const widgetId = 'vibe-call';
    final params = <String, String>{
      'widgetId': widgetId,
      'parentUrl': origin.toString(),
      'baseUrl': client.homeserver.toString(),
      'roomId': room.id,
      'userId': client.userID!,
      'deviceId': client.deviceID ?? '',
      'intent': intent,
      'skipLobby': 'true',
      'returnToLobby': 'false',
      'confineToRoom': 'true',
      'appPrompt': 'false',
      'preload': 'false',
      'hideScreensharing': 'true',
      'perParticipantE2EE': room.encrypted.toString(),
      'lang': 'en',
      'theme': dark ? 'dark' : 'light',
      // Vibe has its own header and controls
      'header': 'none',
      'hideHeader': 'true',
    };
    final url = origin
        .replace(path: '/element-call/index.html', queryParameters: params)
        .toString();
    _config = {
      'widgetId': widgetId,
      'userId': client.userID,
      'roomId': room.id,
      'url': url,
      'knownRooms': [room.id],
    };

    final driver = VibeCallDriver(
      client: client,
      roomId: room.id,
      toWidget: _js,
      onMembership: (inCall) {
        _log('own membership: ${inCall ? 'joined' : 'left'}');
        if (inCall) _markJoined();
      },
    );
    _driver = driver;

    final PlatformWebViewControllerCreationParams params0 =
        WebViewPlatform.instance is AndroidWebViewPlatform
        ? AndroidWebViewControllerCreationParams()
        : const PlatformWebViewControllerCreationParams();
    final c = WebViewController.fromPlatformCreationParams(
      params0,
      // Our own bundled Element Call, on our own loopback origin.
      onPermissionRequest: (request) => request.grant(),
    );
    await c.setJavaScriptMode(JavaScriptMode.unrestricted);
    await c.setOnConsoleMessage((m) {
      if (m.level == JavaScriptLogLevel.error ||
          m.level == JavaScriptLogLevel.warning) {
        _log('js ${m.level.name}: ${m.message}');
      }
    });
    await c.setBackgroundColor(
      dark ? const Color(0xFF1A191E) : const Color(0xFFF2F3F5),
    );
    await c.addJavaScriptChannel(
      'VibeHost',
      onMessageReceived: (m) => _onMessage(m.message),
    );
    await c.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (req) {
          final u = Uri.tryParse(req.url);
          if (u == null) return NavigationDecision.prevent;
          if (u.host == origin.host && u.port == origin.port) {
            return NavigationDecision.navigate;
          }
          if (u.scheme == 'about' || u.scheme == 'blob' || u.scheme == 'data') {
            return NavigationDecision.navigate;
          }
          // links from inside the call open in the browser
          unawaited(launchUrl(u, mode: LaunchMode.externalApplication));
          return NavigationDecision.prevent;
        },
        onWebResourceError: (e) {
          _log(
            'load error ${e.errorCode} ${e.description} '
            '${e.url ?? ''} main=${e.isForMainFrame}',
          );
        },
      ),
    );
    final platform = c.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
    }
    web = c;
    notifyListeners();
    await c.loadRequest(origin.replace(path: '/vibe_call/host.html'));

    driver.startFeeding();
    unawaited(_startService());
    _connectTimeout?.cancel();
    _connectTimeout = Timer(const Duration(seconds: 30), () {
      if (stage == VibeCallStage.connecting) {
        _log('timed out connecting');
        problem =
            'The call didn\'t connect. Copy the call log and send it to '
            'support so we can see what went wrong.';
        notifyListeners();
      }
    });
  }

  // ---------------------------------------------------------------------
  // Messages from the host page
  // ---------------------------------------------------------------------

  void _js(String fn, List<Object?> args) {
    final w = web;
    if (w == null) return;
    final code = 'window.vibe && vibe.$fn(${args.map(jsonEncode).join(',')});';
    w.runJavaScript(code).catchError((Object e) {
      Logs().v('Vibe call js failed: $e');
    });
  }

  Future<void> _onMessage(String raw) async {
    Map<String, Object?> m;
    try {
      m = Map<String, Object?>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return;
    }
    final data = m['data'] is Map
        ? Map<String, Object?>.from(m['data'] as Map)
        : const <String, Object?>{};
    switch (m['kind']) {
      case 'host_ready':
        if (_config != null) _js('start', [_config]);
      case 'rpc':
        await _rpc(m);
      case 'joined':
        _log('element call joined');
        _markJoined();
      case 'error':
        _log('error ${data['where']}: ${data['message']}');
      case 'ready':
      case 'preparing':
      case 'frame_loaded':
        _log(m['kind'] as String);
      case 'media':
        final a = data['audio_enabled'];
        final v = data['video_enabled'];
        if (_firstMedia) {
          // Element Call tells us its starting state once; apply ours.
          _firstMedia = false;
          _js('action', [
            'io.element.device_mute',
            {'audio_enabled': micOn, 'video_enabled': _wantVideo},
          ]);
        } else {
          if (a is bool) micOn = a;
          if (v is bool) videoOn = v;
          notifyListeners();
        }
      case 'hangup':
      case 'close':
        _log('element call ${m['kind']}');
        if (_left?.isCompleted == false) _left?.complete();
        await _teardown();
    }
  }

  void _markJoined() {
    if (stage == VibeCallStage.inCall || stage == VibeCallStage.leaving) {
      return;
    }
    _connectTimeout?.cancel();
    stage = VibeCallStage.inCall;
    joinedAt = DateTime.now();
    problem = null;
    VibeHaptics.light();
    notifyListeners();
    unawaited(_applySpeaker());
  }

  Future<void> _rpc(Map<String, Object?> m) async {
    final id = m['id'];
    final method = m['method'] as String? ?? '';
    final args = m['args'] is Map
        ? Map<String, Object?>.from(m['args'] as Map)
        : <String, Object?>{};
    final driver = _driver;
    if (driver == null) return;
    try {
      final result = await driver.handle(method, args);
      if (method != 'readRoomState' && method != 'readRoomTimeline') {
        _log('$method ${args['type'] ?? ''} ok');
      }
      _js('reply', [id, true, result]);
    } catch (e) {
      _log('$method ${args['type'] ?? ''} FAILED: $e');
      _js('reply', [id, false, VibeCallDriver.errorJson(e)]);
    }
  }

  // ---------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------

  void expand() {
    if (!active) return;
    expanded = true;
    notifyListeners();
  }

  void minimize() {
    if (!active) return;
    expanded = false;
    notifyListeners();
  }

  void toggleStage() {
    if (!active) return;
    showStage = !showStage;
    notifyListeners();
  }

  void toggleMic() {
    if (!active) return;
    VibeHaptics.selection();
    micOn = !micOn;
    if (micOn && !soundOn) {
      soundOn = true;
      _js('setSound', [true]);
    }
    _js('action', [
      'io.element.device_mute',
      {'audio_enabled': micOn, 'video_enabled': videoOn},
    ]);
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    if (!active) return;
    VibeHaptics.selection();
    if (!videoOn && PlatformInfos.isMobile) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        _snack('Vibe needs the camera for video.');
        return;
      }
    }
    videoOn = !videoOn;
    if (videoOn) showStage = true;
    _js('action', [
      'io.element.device_mute',
      {'audio_enabled': micOn, 'video_enabled': videoOn},
    ]);
    if (videoOn && !speakerOn) await setSpeaker(true);
    notifyListeners();
  }

  /// Deafen, Discord style: hear nobody, and your mic goes off too.
  void toggleSound() {
    if (!active) return;
    VibeHaptics.selection();
    soundOn = !soundOn;
    _js('setSound', [soundOn]);
    if (!soundOn && micOn) {
      micOn = false;
      _js('action', [
        'io.element.device_mute',
        {'audio_enabled': false, 'video_enabled': videoOn},
      ]);
    }
    notifyListeners();
  }

  Future<void> setSpeaker(bool on) async {
    speakerOn = on;
    notifyListeners();
    await _applySpeaker();
  }

  Future<void> _applySpeaker() async {
    if (!PlatformInfos.isAndroid) return;
    try {
      // The WebView takes the audio route when the call starts; set ours
      // after it.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _system.invokeMethod('setSpeaker', {'on': speakerOn});
    } catch (e) {
      Logs().v('Vibe call: speaker switch failed $e');
    }
  }

  /// Leave the call.
  Future<void> hangup() async {
    if (!active) return;
    VibeHaptics.medium();
    if (stage == VibeCallStage.inCall) {
      stage = VibeCallStage.leaving;
      notifyListeners();
      final left = _left = Completer<void>();
      _js('action', ['im.vector.hangup', <String, Object?>{}]);
      // Element Call answers once it has left; don't wait forever.
      await left.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () {},
      );
    }
    await _teardown();
  }

  Future<void> _teardown() async {
    final w = web;
    if (w == null) return;
    _connectTimeout?.cancel();
    _driver?.dispose();
    _driver = null;
    _config = null;
    web = null;
    stage = VibeCallStage.idle;
    joinedAt = null;
    expanded = true;
    notifyListeners();
    try {
      // stops the microphone and camera right away
      await w.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    if (PlatformInfos.isAndroid) {
      try {
        await _system.invokeMethod('resetAudio');
      } catch (_) {}
    }
    await _stopService();
    room = null;
  }

  // ---------------------------------------------------------------------
  // Keep the call alive with the screen off
  // ---------------------------------------------------------------------

  Future<void> _startService() async {
    if (!PlatformInfos.isAndroid) return;
    try {
      _hadService = await FlutterForegroundTask.isRunningService;
      if (_hadService) await FlutterForegroundTask.stopService();
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'vibe_call',
          channelName: 'Calls',
          channelDescription: 'Shows while you are in a call',
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
          showWhen: true,
          priority: NotificationPriority.LOW,
          channelImportance: NotificationChannelImportance.LOW,
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
      final camera = _wantVideo && await Permission.camera.isGranted;
      await FlutterForegroundTask.startService(
        serviceTypes: [
          ForegroundServiceTypes.microphone,
          if (camera) ForegroundServiceTypes.camera,
        ],
        notificationTitle: 'Vibe call',
        notificationText: 'In a call · $roomName',
        notificationIcon: NotificationIcon(metaDataName: 'ic_launcher'),
      );
    } catch (e, s) {
      Logs().w('Vibe call: foreground service failed', e, s);
    }
  }

  Future<void> _stopService() async {
    if (!PlatformInfos.isAndroid) return;
    try {
      await FlutterForegroundTask.stopService();
      if (_hadService || ForegroundServices.runningServices.isNotEmpty) {
        await ForegroundServices.resume();
      }
    } catch (e) {
      Logs().w('Vibe call: could not restore service', e);
    }
    _hadService = false;
  }
}

/// Calls need everyone to be allowed to post their "I'm in the call" state.
/// Matrix rooms block that for normal members by default, so Vibe opens it
/// up when creating groups, and asks admins to switch it on for old ones.
abstract class VibeCallPower {
  /// Default Matrix power levels for state events, plus call membership
  /// for everyone (use as `powerLevelContentOverride` when creating rooms).
  static Map<String, Object?> get createOverride => {
    'events': {
      'm.room.name': 50,
      'm.room.avatar': 50,
      'm.room.canonical_alias': 50,
      'm.room.topic': 50,
      'm.room.power_levels': 100,
      'm.room.history_visibility': 100,
      'm.room.encryption': 100,
      'm.room.tombstone': 100,
      'm.room.server_acl': 100,
      'm.space.child': 50,
      'm.room.pinned_events': 50,
      VibeCallMembers.memberType: 0,
      'org.matrix.msc3401.call': 50,
    },
  };

  static bool allowed(Room room) =>
      room.canChangeStateEvent(VibeCallMembers.memberType);

  static Future<bool> ensureAllowed(BuildContext context, Room room) async {
    if (allowed(room)) return true;
    if (!room.canChangePowerLevel) {
      _snack('Calls are off in this group. Ask an admin to turn them on.');
      return false;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn on calls?'),
        content: const Text(
          'This group only lets admins join calls. Turn calls on so '
          'everyone in it can join?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      final content = Map<String, Object?>.from(
        room.getState(EventTypes.RoomPowerLevels)?.content ?? const {},
      );
      final events = Map<String, Object?>.from(
        content['events'] as Map? ?? const {},
      );
      events[VibeCallMembers.memberType] = 0;
      content['events'] = events;
      await room.client.setRoomStateWithKey(
        room.id,
        EventTypes.RoomPowerLevels,
        '',
        content,
      );
      return true;
    } catch (e) {
      _snack('Couldn\'t turn on calls: $e');
      return false;
    }
  }

  static void _snack(String text) => VibeCall._snack(text);
}

/// Does your server offer Matrix calls? Element Call needs a call service
/// (a LiveKit "focus") announced by the server. Without one you can still
/// join calls other people start (they bring their own), but you can't
/// start one.
abstract class VibeCallSupport {
  static final Map<String, (DateTime, String?)> _cache = {};

  /// The call service URL for [client]'s server, or null if it has none.
  static Future<String?> serviceUrl(Client client) async {
    final key = client.homeserver.toString();
    final hit = _cache[key];
    if (hit != null &&
        DateTime.now().difference(hit.$1) < const Duration(minutes: 10)) {
      return hit.$2;
    }
    String? url;
    String? pick(Object? list) {
      if (list is! List) return null;
      for (final f in list) {
        if (f is Map && f['type'] == 'livekit') {
          final u = f['livekit_service_url'];
          if (u is String && u.isNotEmpty) return u;
        }
      }
      return null;
    }

    try {
      final wk = await client.getWellknown();
      url = pick(wk.additionalProperties['org.matrix.msc4143.rtc_foci']);
    } catch (e) {
      Logs().v('Vibe call: no well-known foci ($e)');
    }
    if (url == null) {
      for (final path in const [
        '/client/v1/rtc/transports',
        '/client/unstable/org.matrix.msc4143/rtc/transports',
      ]) {
        try {
          final r = await client.request(RequestType.GET, path);
          url = pick(r['rtc_transports']);
          if (url != null) break;
        } catch (_) {}
      }
    }
    _cache[key] = (DateTime.now(), url);
    return url;
  }

  static Future<bool> ensure(BuildContext context, Room room) async {
    final url = await serviceUrl(room.client);
    VibeCallServer.livekitServiceUrl = url;
    if (url != null) return true;
    // Someone else's call brings its own call service: joining works.
    if (VibeCallMembers.active(room)) return true;
    if (!context.mounted) return false;
    final server = room.client.userID?.domain ?? 'your server';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Calls aren\'t set up on your server'),
        content: Text(
          '$server doesn\'t offer Matrix calls yet, so Vibe can\'t start '
          'one from this account.\n\n'
          'You can still join calls that others start (from servers like '
          'matrix.org). To start calls yourself, use an account on a '
          'server with calls, or ask your server\'s admin to add a '
          'MatrixRTC (LiveKit) call service.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return false;
  }
}

// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fluffychat/vibe/vibe_palette.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Voice and video calls inside Vibe, on Element Call (open source,
/// MatrixRTC + LiveKit), shown full screen in the app.
///
/// Every call is end-to-end encrypted: Element Call makes a fresh call room
/// with a random key, and the key only lives in the link's "#" part, which
/// browsers never send to any server. The link travels inside your
/// (encrypted) chat. Element's call service carries the media, so calls
/// work whatever your home server supports.
///
/// Quality: Element Call sends HD (720p) with simulcast and adapts to the
/// network; Opus voice with echo cancelling. Vibe shows your own preview
/// unmirrored, and voice calls switch the camera off before joining.
abstract class VibeCall {
  static const _key = 'chat.vibe.call';
  static const _channel = MethodChannel('vibe/system');

  static String get server {
    final s = AppSettings.vibeCallServer.value.trim();
    return s.isEmpty ? 'https://call.element.io' : s;
  }

  static Map<String, Object?>? info(Event e) {
    final v = e.content[_key];
    return v is Map ? Map<String, Object?>.from(v) : null;
  }

  /// Calls this phone has already joined and left: their Join is gone.
  static final done = ValueNotifier<Set<String>>({});

  static bool ended(Event e) => info(e)?['ended'] == true;

  static bool _inCall = false;

  /// Start a call from the chat pane ("voice-call" / "video-call").
  static Future<void> startFrom(
    BuildContext context,
    Room room, {
    required bool video,
  }) => _open(context, room, video: video);

  /// Voice or video? (kept for older entry points)
  static Future<void> pickAndStart(BuildContext context, Room room) async {
    final video = await showVibeSheet<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: const Text('Voice call'),
              onTap: () => Navigator.of(c).pop(false),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video call'),
              onTap: () => Navigator.of(c).pop(true),
            ),
          ],
        ),
      ),
    );
    if (video == null || !context.mounted) return;
    await startFrom(context, room, video: video);
  }

  /// Joins the call behind a call message.
  static Future<void> join(
    BuildContext context,
    Room room,
    String url, {
    required bool video,
    String? callEventId,
  }) => _open(context, room, video: video, url: url, callEventId: callEventId);

  static Future<void> _open(
    BuildContext context,
    Room room, {
    required bool video,
    String? url,
    String? callEventId,
  }) async {
    if (_inCall) return;
    stopRinging();
    final perms = await [
      Permission.microphone,
      if (video) Permission.camera,
    ].request();
    if (perms[Permission.microphone] != PermissionStatus.granted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vibe needs the microphone for calls')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    // The call lives above every screen (not as a page), so it can shrink
    // into a small window inside Vibe while you keep chatting.
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) return;
    _inCall = true;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _VibeCallScreen(
        room: room,
        video: video,
        url: url,
        callEventId: callEventId,
        onClosed: () {
          entry.remove();
          _inCall = false;
        },
      ),
    );
    overlay.insert(entry);
  }

  /// The caller's link is ready: tell the chat (this rings the others).
  static Future<String?> _announce(Room room, String url, bool video) async {
    final data = {'url': url, 'server': server, 'video': video, 'e2ee': true};
    return room.sendEvent({
      'msgtype': MessageTypes.Text,
      'body': '${video ? '📹 Video' : '📞 Voice'} call · join: $url',
      _key: data,
    });
  }

  /// The caller hangs up: the call message is edited to "ended" so the
  /// Join button disappears for everyone.
  static Future<void> _markEnded(
    Room room,
    String eventId,
    String url,
    bool video,
  ) async {
    final body = '${video ? '📹 Video' : '📞 Voice'} call ended';
    try {
      await room.sendEvent({
        'msgtype': MessageTypes.Text,
        'body': '* $body',
        'm.new_content': {
          'msgtype': MessageTypes.Text,
          'body': body,
          _key: {'url': url, 'server': server, 'video': video, 'ended': true},
        },
        'm.relates_to': {'rel_type': 'm.replace', 'event_id': eventId},
      });
    } catch (e) {
      Logs().w('Vibe call: could not mark ended', e);
    }
  }

  /// Extra settings for the in-app view only (never in the shared link).
  static String _inApp(String url) {
    const extra = 'lang=en&confineToRoom=true&header=none&theme=dark';
    final h = url.indexOf('#');
    if (h < 0) return url;
    return url.indexOf('?', h) >= 0 ? '$url&$extra' : '$url?$extra';
  }

// ---- incoming calls ------------------------------------------------------

  static final Set<String> _seen = {};
  static StreamSubscription? _sub;

  /// Rings for a call someone just started in one of your chats.
  static void watch(Client client) {
    _sub?.cancel();
    _sub = client.onTimelineEvent.stream.listen((e) {
      final i = info(e);
      if (i == null || i['ended'] == true || e.senderId == client.userID) {
        return;
      }
      if (!_seen.add(e.eventId)) return;
      if (DateTime.now().difference(e.originServerTs).inSeconds.abs() > 45) {
        return;
      }
      final room = e.room;
      final ctx = FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted || _inCall) return;
      _ring(ctx, room, e, i);
    });
  }

  static Timer? _ringTimer;

  static Future<void> startRinging() async {
    try {
      await _channel.invokeMethod('ring', {'on': true});
    } catch (_) {}
    _ringTimer?.cancel();
    _ringTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      VibeHaptics.heavy();
    });
  }

  static void stopRinging() {
    _ringTimer?.cancel();
    _ringTimer = null;
    try {
      _channel.invokeMethod('ring', {'on': false});
    } catch (_) {}
  }

  static void _ring(BuildContext ctx, Room room, Event e, Map<String, Object?> i) {
    final video = i['video'] == true;
    final url = i['url'] as String?;
    if (url == null) return;
    startRinging();
    // stop by itself after 40 s
    final auto = Timer(const Duration(seconds: 40), () {
      stopRinging();
      final nav = Navigator.of(ctx, rootNavigator: true);
      if (nav.canPop()) nav.maybePop();
    });
    final name = e.senderFromMemoryOrFallback.calcDisplayname();
    showVibeSheet<void>(
      context: ctx,
      useRootNavigator: true,
      isDismissible: false,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(video ? Icons.videocam : Icons.call, size: 40, color: VibePalette.accent),
              const SizedBox(height: 10),
              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(video ? 'Incoming video call' : 'Incoming voice call'),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDA373C),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () {
                        auto.cancel();
                        stopRinging();
                        Navigator.of(c).pop();
                      },
                      icon: const Icon(Icons.call_end),
                      label: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF23A55A),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () {
                        auto.cancel();
                        stopRinging();
                        Navigator.of(c).pop();
                        join(ctx, room, url, video: video, callEventId: e.eventId);
                      },
                      icon: Icon(video ? Icons.videocam : Icons.call),
                      label: const Text('Answer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      auto.cancel();
      stopRinging();
    });
  }

}

/// The card a call message shows in the chat: Join while the call is on,
/// "call ended" once the caller hangs up (or you have joined and left).
class VibeCallCard extends StatelessWidget {
  final Event event;
  const VibeCallCard(this.event, {super.key});

  @override
  Widget build(BuildContext context) {
    final i = VibeCall.info(event)!;
    final video = i['video'] == true;
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Set<String>>(
      valueListenable: VibeCall.done,
      builder: (context, done, _) {
        final live = !VibeCall.ended(event) &&
            !done.contains(event.eventId) &&
            DateTime.now().difference(event.originServerTs).inHours < 3;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                live
                    ? (video ? Icons.videocam_outlined : Icons.call_outlined)
                    : (video ? Icons.videocam_off_outlined : Icons.call_end_outlined),
                color: live ? VibePalette.accent : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  '${video ? 'Video' : 'Voice'} call${live ? '' : ' ended'}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: live ? null : cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (live) ...[
                const SizedBox(width: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF23A55A),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => VibeCall.join(
                    context,
                    event.room,
                    i['url'] as String? ?? '',
                    video: video,
                    callEventId: event.eventId,
                  ),
                  child: const Text('Join'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The call itself: Element Call, full screen. Vibe fills in the boring
/// steps (call name, your name, "Join") so it feels like one tap.
class _VibeCallScreen extends StatefulWidget {
  final Room room;
  final bool video;

  /// Call link to join; null = start a new call.
  final String? url;
  final String? callEventId;
  final VoidCallback onClosed;
  const _VibeCallScreen({
    required this.room,
    required this.video,
    required this.onClosed,
    this.url,
    this.callEventId,
  });

  @override
  State<_VibeCallScreen> createState() => _VibeCallScreenState();
}

class _VibeCallScreenState extends State<_VibeCallScreen> {
  late final WebViewController _web;
  String? _link;
  String? _eventId;
  bool _closed = false;

  /// Shrunk into a small window inside Vibe (you can keep chatting).
  bool _mini = false;

  /// Where the small window sits (its top-left corner), draggable.
  Offset? _miniAt;
  final _webKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _pipAllowed(true);
    _eventId = widget.callEventId;
    _web = WebViewController(
      onPermissionRequest: (r) => r.grant(),
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('VibeCall', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => _inject()),
      );
    final p = _web.platform;
    if (p is AndroidWebViewController) {
      p.setMediaPlaybackRequiresUserGesture(false);
    }
    final url = widget.url;
    _web.loadRequest(
      Uri.parse(
        url != null && url.isNotEmpty
            ? VibeCall._inApp(url)
            : '${VibeCall.server}/?lang=en&theme=dark',
      ),
    );
  }

  /// Leaving the app (home / app switch) during a call: Android floats the
  /// call in a picture-in-picture window.
  static void _pipAllowed(bool on) {
    VibeCall._channel.invokeMethod('callActive', {'on': on}).catchError((_) {});
  }

  void _minimize() => setState(() => _mini = true);
  void _expand() => setState(() => _mini = false);

  String get _name {
    final me = widget.room.client.userID!;
    return widget.room.unsafeGetUserFromMemoryOrFallback(me).calcDisplayname();
  }

  void _inject() {
    final rnd = Random.secure();
    final callName =
        'vibe-${List.generate(10, (_) => rnd.nextInt(36).toRadixString(36)).join()}';
    final cfg = jsonEncode({
      'start': widget.url == null,
      'voice': !widget.video,
      'name': _name,
      'callName': callName,
    });
    _web.runJavaScript('''
(function(){
  if (window.__vibe) return; window.__vibe = true;
  var cfg = $cfg;
  var st = {};
  var css = document.createElement('style');
  // your own preview like a camera, not a mirror
  // and a touch brighter / crisper on screen (faces look less dull)
  css.textContent = '[class*="mirror"] video, video[class*="mirror"]{transform:none!important}' +
    'video{filter:brightness(1.07) contrast(1.06) saturate(1.1)}';
  document.head.appendChild(css);
  // your camera: keep auto exposure / focus / white balance on and lift the
  // exposure a little (the phone camera app does this; the web view doesn't)
  var tuned = {};
  function tune(){
    document.querySelectorAll('video').forEach(function(v){
      var s = v.srcObject; if (!s || !s.getVideoTracks) return;
      s.getVideoTracks().forEach(function(t){
        if (tuned[t.id] || !t.getCapabilities) return;
        var c = t.getCapabilities(); if (!c || !c.deviceId) return; // only your own camera
        tuned[t.id] = true;
        var adv = {};
        if (c.exposureMode && c.exposureMode.indexOf('continuous') >= 0) adv.exposureMode = 'continuous';
        if (c.focusMode && c.focusMode.indexOf('continuous') >= 0) adv.focusMode = 'continuous';
        if (c.whiteBalanceMode && c.whiteBalanceMode.indexOf('continuous') >= 0) adv.whiteBalanceMode = 'continuous';
        if (c.exposureCompensation && c.exposureCompensation.max > 0) {
          var step = c.exposureCompensation.step || 0.1;
          adv.exposureCompensation = Math.round((c.exposureCompensation.max * 0.3) / step) * step;
        }
        t.applyConstraints({advanced: [adv]}).catch(function(){});
      });
    });
  }
  function q(id){ return document.querySelector('[data-testid="'+id+'"]'); }
  function setVal(el, v){
    var s = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    s.call(el, v); el.dispatchEvent(new Event('input', {bubbles:true}));
  }
  function post(o){ try { VibeCall.postMessage(JSON.stringify(o)); } catch(e){} }
  var last = '';
  setInterval(function(){
    tune();
    if (location.href !== last){ last = location.href; post({href:last}); }
    var c = q('home_callName');
    if (cfg.start && c && !st.create){
      st.create = true;
      setVal(c, cfg.callName);
      var d = q('home_displayName'); if (d) setVal(d, cfg.name);
      setTimeout(function(){ var g = q('home_go'); if (g) g.click(); }, 300);
    }
    var n = q('joincall_displayName');
    if (n && !st.auth){
      st.auth = true; setVal(n, cfg.name);
      setTimeout(function(){ var g = q('joincall_joincall'); if (g) g.click(); }, 300);
    }
    var j = q('lobby_joinCall');
    if (j && !st.join){
      st.join = true;
      var v = q('incall_videomute');
      var on = v && /stop video/i.test((v.getAttribute('aria-label')||'') + v.textContent);
      if (cfg.voice && on) v.click();
      setTimeout(function(){ j.click(); post({joined:true}); }, cfg.voice && on ? 600 : 250);
    }
    if (st.join && !st.left && (document.getElementById('feedbackText') ||
        location.hash.indexOf('roomId=') < 0)){
      st.left = true; post({left:true});
    }
  }, 400);
})();
''');
  }

  void _onMessage(JavaScriptMessage m) {
    Map<String, Object?> msg;
    try {
      msg = Map<String, Object?>.from(jsonDecode(m.message) as Map);
    } catch (_) {
      return;
    }
    final href = msg['href'];
    if (href is String) _maybeAnnounce(href);
    if (msg['left'] == true) _close();
  }

  /// Caller: the call room exists → post the clean link into the chat.
  Future<void> _maybeAnnounce(String href) async {
    if (widget.url != null || _link != null) return;
    final u = Uri.tryParse(href);
    if (u == null || !u.path.startsWith('/room')) return;
    if (!u.fragment.contains('roomId=') || !u.fragment.contains('password=')) {
      return;
    }
    final link = href.split('&lang=').first;
    _link = link;
    try {
      _eventId = await VibeCall._announce(widget.room, link, widget.video);
    } catch (e) {
      Logs().w('Vibe call: could not post the call', e);
    }
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    widget.onClosed();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _pipAllowed(false);
    final id = _eventId;
    if (id != null) {
      VibeCall.done.value = {...VibeCall.done.value, id};
      final link = _link;
      if (link != null) {
        VibeCall._markEnded(widget.room, id, link, widget.video);
      }
    }
    // stop camera and microphone right away
    _web.loadRequest(Uri.parse('about:blank'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    // Android's picture-in-picture window is tiny: always the full call there
    final pip = screen.shortestSide < 300;
    final mini = _mini && !pip;
    final w = widget.video ? 112.0 : 96.0;
    final h = widget.video ? 168.0 : 96.0;
    final at = _clamp(
      _miniAt ?? Offset(screen.width - w - 12, mq.padding.top + 72),
      screen,
      mq,
      w,
      h,
    );
    final rect = mini
        ? Rect.fromLTWH(at.dx, at.dy, w, h)
        : Offset.zero & screen;
    return BackButtonListener(
      // back shrinks the call instead of leaving it
      onBackButtonPressed: () async {
        if (mini || pip) return false;
        _minimize();
        return true;
      },
      child: Stack(
        children: [
          AnimatedPositioned.fromRect(
            rect: rect,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: GestureDetector(
              onPanUpdate: mini
                  ? (d) => setState(() => _miniAt = at + d.delta)
                  : null,
              onTap: mini ? _expand : null,
              child: Material(
                color: Colors.black,
                elevation: mini ? 8 : 0,
                borderRadius: BorderRadius.circular(mini ? 16 : 0),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: mini || pip
                            ? EdgeInsets.zero
                            : EdgeInsets.only(
                                top: mq.padding.top,
                                bottom: mq.padding.bottom,
                              ),
                        // taps go to the call only when it's full size
                        child: AbsorbPointer(
                          absorbing: mini,
                          child: WebViewWidget(key: _webKey, controller: _web),
                        ),
                      ),
                    ),
                    if (!mini && !pip)
                      Positioned(
                        top: mq.padding.top + 4,
                        left: 4,
                        child: IconButton(
                          tooltip: 'Keep chatting',
                          color: Colors.white,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black38,
                          ),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          onPressed: _minimize,
                        ),
                      ),
                    if (mini)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: GestureDetector(
                          onTap: _close,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              color: Color(0xFFDA373C),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.call_end,
                              size: 17,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Keeps the small window on screen (and above the keyboard).
  static Offset _clamp(Offset o, Size s, MediaQueryData mq, double w, double h) {
    final maxX = s.width - w - 8;
    final maxY = s.height - mq.viewInsets.bottom - h - 8;
    return Offset(
      o.dx.clamp(8.0, maxX < 8 ? 8.0 : maxX),
      o.dy.clamp(mq.padding.top + 8, maxY < mq.padding.top + 8 ? mq.padding.top + 8 : maxY),
    );
  }
}

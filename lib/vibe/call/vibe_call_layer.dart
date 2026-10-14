// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:fluffychat/vibe/call/vibe_call.dart';
import 'package:fluffychat/vibe/call/vibe_call_members.dart';
import 'package:fluffychat/vibe/call/vibe_call_ring.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _green = Color(0xFF23A55A);
const _red = Color(0xFFDA373C);

/// Wraps the whole app (above the router). Holds the call's WebView so the
/// call keeps going while you use the rest of Vibe:
/// - full screen: Element Call with Vibe's top bar;
/// - minimized: a green bar at the top (Telegram style) that pushes the app
///   down a little; tap it to go back to the call;
/// - an incoming call screen when someone rings you.
class VibeCallHost extends StatefulWidget {
  final Widget child;
  const VibeCallHost({required this.child, super.key});

  @override
  State<VibeCallHost> createState() => _VibeCallHostState();
}

class _VibeCallHostState extends State<VibeCallHost>
    with WidgetsBindingObserver {
  final _call = VibeCall.instance;
  final _ring = VibeCallRing.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ring.attach(Matrix.of(context).client);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Android back: shrink the call instead of leaving the screen under it.
  @override
  Future<bool> didPopRoute() async {
    if (_ring.ringing.value != null) {
      _ring.stop();
      return true;
    }
    if (_call.active && _call.expanded) {
      _call.minimize();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_call, _ring.ringing]),
      builder: (context, _) {
        final mq = MediaQuery.of(context);
        final web = _call.web;
        final showBar = web != null && !_call.expanded;
        final barHeight = mq.padding.top + 44;
        final chromeTop = mq.padding.top + 60;
        final ring = _ring.ringing.value;
        return Stack(
          children: [
            Column(
              key: const ValueKey('app'),
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  height: showBar ? barHeight : 0,
                  width: double.infinity,
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(color: _green),
                  child: showBar
                      ? _CallBar(call: _call, topPadding: mq.padding.top)
                      : null,
                ),
                Expanded(
                  child: MediaQuery(
                    data: showBar
                        ? mq.copyWith(
                            padding: mq.padding.copyWith(top: 0),
                            viewPadding: mq.viewPadding.copyWith(top: 0),
                          )
                        : mq,
                    child: widget.child,
                  ),
                ),
              ],
            ),
            if (web != null)
              Positioned.fill(
                key: const ValueKey('chrome'),
                child: IgnorePointer(
                  ignoring: !_call.expanded,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _call.expanded ? 1 : 0,
                    child: _CallChrome(call: _call, top: chromeTop),
                  ),
                ),
              ),
            if (web != null)
              // Same widget in both modes, so the WebView is never rebuilt:
              // full size under the top bar, or 1×1 out of sight.
              Positioned(
                key: const ValueKey('web'),
                left: 0,
                top: _call.expanded ? chromeTop : 0,
                width: _call.expanded ? mq.size.width : 1,
                height: _call.expanded ? mq.size.height - chromeTop : 1,
                child: IgnorePointer(
                  ignoring: !_call.expanded,
                  child: Opacity(
                    opacity: _call.expanded ? 1 : 0.01,
                    child: WebViewWidget(controller: web),
                  ),
                ),
              ),
            if (web != null && _call.expanded && _call.problem != null)
              Positioned(
                key: const ValueKey('problem'),
                left: 16,
                right: 16,
                bottom: mq.padding.bottom + 24,
                child: _Problem(call: _call),
              ),
            if (ring != null)
              Positioned.fill(
                key: const ValueKey('ring'),
                child: _Incoming(ring: ring),
              ),
          ],
        );
      },
    );
  }
}

/// "In call · 03:12" — the green bar while the call is minimized.
class _CallBar extends StatelessWidget {
  final VibeCall call;
  final double topPadding;
  const _CallBar({required this.call, required this.topPadding});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _green,
      child: InkWell(
        onTap: call.expand,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, topPadding, 6, 0),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                const Icon(Icons.graphic_eq, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    call.stage == VibeCallStage.connecting
                        ? 'Connecting · ${call.roomName}'
                        : call.roomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                ),
                _Clock(
                  since: call.joinedAt,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 4),
                _BarButton(
                  icon: call.micOn ? Icons.mic : Icons.mic_off,
                  onTap: call.toggleMic,
                ),
                _BarButton(
                  icon: Icons.call_end,
                  background: _red,
                  onTap: call.hangup,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? background;
  const _BarButton({required this.icon, required this.onTap, this.background});

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: background ?? Colors.white.withAlpha(0x33),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 19),
      ),
    ),
  );
}

/// Ticking call timer.
class _Clock extends StatelessWidget {
  final DateTime? since;
  final TextStyle style;
  const _Clock({required this.since, required this.style});

  static String format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final start = since;
    if (start == null) return const SizedBox.shrink();
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) =>
          Text(format(DateTime.now().difference(start)), style: style),
    );
  }
}

/// The top of the full-screen call: shrink, who/where, timer, speaker.
class _CallChrome extends StatelessWidget {
  final VibeCall call;
  final double top;
  const _CallChrome({required this.call, required this.top});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF1A191E) : const Color(0xFFF2F3F5);
    final fg = dark ? Colors.white : const Color(0xFF060607);
    final muted = dark ? const Color(0xFFB5BAC1) : const Color(0xFF5C5E66);
    final room = call.room;
    final people = room == null ? 0 : VibeCallMembers.userIds(room).length;
    final status = switch (call.stage) {
      VibeCallStage.connecting => 'Connecting…',
      VibeCallStage.leaving => 'Leaving…',
      _ => people > 1 ? '$people in the call' : 'Waiting for others',
    };
    return Material(
      color: bg,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: top,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              6,
              MediaQuery.paddingOf(context).top + 6,
              10,
              6,
            ),
            child: Row(
              children: [
                _RoundButton(
                  icon: Icons.keyboard_arrow_down,
                  color: fg,
                  onTap: call.minimize,
                ),
                const SizedBox(width: 4),
                if (room != null)
                  Avatar(
                    mxContent: room.avatar,
                    name: call.roomName,
                    size: 34,
                    client: room.client,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        call.roomName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: muted, fontSize: 12.5),
                            ),
                          ),
                          if (call.joinedAt != null) ...[
                            Text(
                              '  ·  ',
                              style: TextStyle(color: muted, fontSize: 12.5),
                            ),
                            _Clock(
                              since: call.joinedAt,
                              style: TextStyle(color: muted, fontSize: 12.5),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                _RoundButton(
                  icon: call.soundOn ? Icons.headset : Icons.headset_off,
                  color: call.soundOn ? fg : _red,
                  onTap: call.toggleSound,
                ),
                _RoundButton(
                  icon: call.speakerOn ? Icons.volume_up : Icons.phone_in_talk,
                  color: fg,
                  onTap: () => call.setSpeaker(!call.speakerOn),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => VibePressable(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(icon, color: color, size: 24),
      ),
    ),
  );
}

class _Problem extends StatelessWidget {
  final VibeCall call;
  const _Problem({required this.call});

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF2B2D31),
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            call.problem ?? '',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: call.hangup,
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Someone is calling you.
class _Incoming extends StatelessWidget {
  final VibeRing ring;
  const _Incoming({required this.ring});

  @override
  Widget build(BuildContext context) {
    final room = ring.room;
    final caller = room.unsafeGetUserFromMemoryOrFallback(ring.callerId);
    final name = room.isDirectChat
        ? caller.calcDisplayname()
        : room.getLocalizedDisplayname();
    final pad = MediaQuery.paddingOf(context);
    return Material(
      color: const Color(0xFF111214),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: vibeSpring,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 40),
            child: child,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, pad.top + 48, 24, pad.bottom + 40),
          child: Column(
            children: [
              Text(
                ring.video ? 'Incoming video call' : 'Incoming voice call',
                style: const TextStyle(
                  color: Color(0xFFB5BAC1),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _Pulse(
                child: Avatar(
                  mxContent: room.isDirectChat
                      ? caller.avatarUrl
                      : room.avatar,
                  name: name,
                  size: 120,
                  client: room.client,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!room.isDirectChat)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${caller.calcDisplayname()} is calling',
                    style: const TextStyle(color: Color(0xFFB5BAC1)),
                  ),
                ),
              const Spacer(flex: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _BigButton(
                    icon: Icons.call_end,
                    color: _red,
                    label: 'Decline',
                    onTap: VibeCallRing.instance.decline,
                  ),
                  _BigButton(
                    icon: ring.video ? Icons.videocam : Icons.call,
                    color: _green,
                    label: 'Accept',
                    onTap: () {
                      final ctx =
                          FluffyChatApp
                              .router
                              .routerDelegate
                              .navigatorKey
                              .currentContext ??
                          context;
                      unawaited(VibeCallRing.instance.accept(ctx));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _BigButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      VibePressable(
        scale: 0.9,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    ],
  );
}

/// Soft rings around the caller's picture.
class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    height: 200,
    child: Stack(
      alignment: Alignment.center,
      children: [
        for (final offset in const [0.0, 0.5])
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = (_c.value + offset) % 1.0;
              return Container(
                width: 120 + 80 * t,
                height: 120 + 80 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _green.withAlpha(((1 - t) * 70).round()),
                ),
              );
            },
          ),
        RepaintBoundary(child: widget.child),
      ],
    ),
  );
}

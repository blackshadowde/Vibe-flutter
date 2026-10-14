// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:fluffychat/vibe/call/vibe_call.dart';
import 'package:fluffychat/vibe/call/vibe_call_members.dart';
import 'package:fluffychat/vibe/call/vibe_call_ring.dart';
import 'package:fluffychat/vibe/vibe_crash_report.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:fluffychat/vibe/call/vibe_call_stage.dart';

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
    // Did Vibe crash last time? Offer the report once.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Future<void>.delayed(
        const Duration(seconds: 3),
        VibeCrashReport.check,
      ),
    );
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
        final live = _call.active;
        final showBar = live && !_call.expanded;
        final barHeight = mq.padding.top + 44;
        final stage = live && _call.expanded && _call.showStage;
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
            // 1) Vibe's call screen background (avatar, name, status) —
            //    hidden behind the video when Element Call's view is shown.
            if (live)
              Positioned.fill(
                key: const ValueKey('backdrop'),
                child: IgnorePointer(
                  ignoring: !_call.expanded,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _call.expanded ? 1 : 0,
                    child: _CallBackdrop(call: _call),
                  ),
                ),
              ),
            // 2) The video view (native, LiveKit).
            if (stage)
              Positioned.fill(
                key: const ValueKey('stage'),
                child: VibeCallStageView(call: _call),
              ),
            // 3) Vibe's controls on top: minimize, status, buttons.
            if (live)
              Positioned.fill(
                key: const ValueKey('controls'),
                child: IgnorePointer(
                  ignoring: !_call.expanded,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _call.expanded ? 1 : 0,
                    // Material gives the labels the app's text style (without
                    // it Flutter shows yellow-underlined debug text).
                    child: Material(
                      type: MaterialType.transparency,
                      child: _CallControls(call: _call, stage: stage),
                    ),
                  ),
                ),
              ),
            if (live && _call.expanded && _call.problem != null)
              Positioned(
                key: const ValueKey('problem'),
                left: 16,
                right: 16,
                top: mq.padding.top + 70,
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

class _Problem extends StatelessWidget {
  final VibeCall call;
  const _Problem({required this.call});

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xEE2B2D31),
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            call.problem ?? '',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: call.copyLog,
                child: const Text('Copy call log'),
              ),
              TextButton(
                onPressed: call.hangup,
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// The call screen (Vibgram / Telegram style)
// ---------------------------------------------------------------------------

/// Slowly moving Vibe-coloured gradient, then the person (or group) in the
/// middle with the call status.
class _CallBackdrop extends StatefulWidget {
  final VibeCall call;
  const _CallBackdrop({required this.call});

  @override
  State<_CallBackdrop> createState() => _CallBackdropState();
}

class _CallBackdropState extends State<_CallBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final room = call.room;
    final pad = MediaQuery.paddingOf(context);
    return Material(
      color: const Color(0xFF111214),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final a = _c.value * 2 * math.pi;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(math.cos(a), math.sin(a)),
                        end: Alignment(-math.cos(a), -math.sin(a)),
                        colors: const [
                          Color(0xFF3C45A5),
                          Color(0xFF1E1F22),
                          Color(0xFF1B4D3E),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (room != null)
            Positioned(
              left: 24,
              right: 24,
              top: pad.top + 110,
              child: _Who(call: call, room: room),
            ),
        ],
      ),
    );
  }
}

/// Avatar (pulsing while it rings or someone talks), name, status.
class _Who extends StatelessWidget {
  final VibeCall call;
  final Room room;
  const _Who({required this.call, required this.room});

  @override
  Widget build(BuildContext context) {
    final others = call.others;
    final dm = room.isDirectChat;
    final otherId = dm ? room.directChatMatrixID : null;
    final other = otherId == null
        ? null
        : room.unsafeGetUserFromMemoryOrFallback(otherId);
    final name = other?.calcDisplayname() ?? call.roomName;
    final waiting = call.stage == VibeCallStage.inCall && others.isEmpty;
    final String status = switch (call.stage) {
      VibeCallStage.connecting => 'Connecting…',
      VibeCallStage.leaving => 'Ending call…',
      VibeCallStage.idle => '',
      VibeCallStage.inCall =>
        waiting ? (dm ? 'Ringing…' : 'Waiting for others to join') : '',
    };
    final avatar = Avatar(
      mxContent: other?.avatarUrl ?? room.avatar,
      name: name,
      size: 128,
      client: room.client,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (call.stage != VibeCallStage.inCall || waiting)
          _Pulse(child: avatar)
        else
          SizedBox(width: 200, height: 200, child: Center(child: avatar)),
        const SizedBox(height: 18),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        if (status.isNotEmpty)
          Text(
            status,
            style: const TextStyle(color: Color(0xFFDBDEE1), fontSize: 15),
          )
        else
          _Clock(
            since: call.joinedAt,
            style: const TextStyle(
              color: Color(0xFFDBDEE1),
              fontSize: 15,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        if (!dm && others.isNotEmpty) ...[
          const SizedBox(height: 22),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 12,
            children: [
              for (final id in others.take(8))
                SizedBox(
                  width: 64,
                  child: Builder(
                    builder: (context) {
                      final u = room.unsafeGetUserFromMemoryOrFallback(id);
                      return Column(
                        children: [
                          Avatar(
                            mxContent: u.avatarUrl,
                            name: u.calcDisplayname(),
                            size: 48,
                            client: room.client,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            u.calcDisplayname(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Top: shrink + encryption + (video) layout. Bottom: Speaker, Camera,
/// Mute, End — round buttons with labels, like Telegram.
class _CallControls extends StatelessWidget {
  final VibeCall call;
  final bool stage;
  const _CallControls({required this.call, required this.stage});

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final room = call.room;
    final dm = room?.isDirectChat ?? true;
    const scrim = [Color(0xAA000000), Color(0x00000000)];
    return Stack(
      children: [
        // reactions float up the screen (yours and everyone else's)
        Positioned.fill(
          child: IgnorePointer(child: _FloatingReactions(call: call)),
        ),
        // top bar
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(6, pad.top + 4, 8, 12),
            decoration: stage
                ? const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: scrim,
                    ),
                  )
                : null,
            child: Row(
              children: [
                _TopButton(
                  icon: Icons.keyboard_arrow_down,
                  onTap: call.minimize,
                ),
                Expanded(
                  child: Center(
                    child: stage && room != null
                        ? Text(
                            call.roomName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          )
                        : (room?.encrypted ?? false)
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(0x1F),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'End-to-end encrypted',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                if (!dm)
                  _TopButton(
                    icon: call.soundOn ? Icons.headset : Icons.headset_off,
                    color: call.soundOn ? Colors.white : _red,
                    onTap: call.toggleSound,
                  ),
                if (call.videoOn)
                  _TopButton(
                    icon: Icons.flip_camera_android,
                    onTap: call.flipCamera,
                  ),
                _TopButton(
                  icon: Icons.add_reaction_outlined,
                  onTap: () => _pickReaction(context, call),
                ),
                _TopButton(
                  icon: call.handRaised
                      ? Icons.back_hand
                      : Icons.back_hand_outlined,
                  color: call.handRaised ? const Color(0xFFFFC542) : Colors.white,
                  onTap: call.toggleHand,
                ),
                _TopButton(
                  icon: stage ? Icons.person : Icons.grid_view_rounded,
                  onTap: call.toggleStage,
                ),
              ],
            ),
          ),
        ),
        // bottom buttons
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(8, 28, 8, pad.bottom + 26),
            decoration: stage
                ? const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: scrim,
                    ),
                  )
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CallButton(
                  icon: call.speakerOn ? Icons.volume_up : Icons.phone_in_talk,
                  label: call.speakerOn ? 'Speaker' : 'Earpiece',
                  on: call.speakerOn,
                  onTap: () => call.setSpeaker(!call.speakerOn),
                ),
                _CallButton(
                  icon: call.videoOn ? Icons.videocam : Icons.videocam_off,
                  label: 'Camera',
                  on: call.videoOn,
                  onTap: call.toggleVideo,
                ),
                _CallButton(
                  icon: call.screenOn
                      ? Icons.stop_screen_share
                      : Icons.screen_share,
                  label: call.screenOn ? 'Stop' : 'Share',
                  on: call.screenOn,
                  onTap: call.toggleScreenShare,
                ),
                _CallButton(
                  icon: call.micOn ? Icons.mic : Icons.mic_off,
                  label: call.micOn ? 'Mute' : 'Unmute',
                  on: !call.micOn,
                  onTap: call.toggleMic,
                ),
                _CallButton(
                  icon: Icons.call_end,
                  label: 'End',
                  background: _red,
                  onTap: call.hangup,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _pickReaction(BuildContext context, VibeCall call) async {
  final picked = await showModalBottomSheet<(String, String)>(
    context: context,
    useRootNavigator: true,
    backgroundColor: const Color(0xFF232428),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in VibeCallReaction.choices)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(ctx).pop(r),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Center(
                    child: Text(r.$1, style: const TextStyle(fontSize: 28)),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked != null) await call.react(picked.$1, picked.$2);
}

class _FloatingReactions extends StatefulWidget {
  final VibeCall call;
  const _FloatingReactions({required this.call});

  @override
  State<_FloatingReactions> createState() => _FloatingReactionsState();
}

class _FloatingReactionsState extends State<_FloatingReactions> {
  final Set<int> _done = {};

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<List<VibeCallReaction>>(
        valueListenable: widget.call.reactions,
        builder: (context, list, _) {
          final size = MediaQuery.sizeOf(context);
          final live = list.where((r) => !_done.contains(r.id)).toList();
          return Stack(
            children: [
              for (final r in live)
                TweenAnimationBuilder<double>(
                  key: ValueKey(r.id),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 2800),
                  curve: Curves.easeOutCubic,
                  onEnd: () => setState(() => _done.add(r.id)),
                  builder: (context, t, child) {
                    // each reaction gets its own lane and a gentle sway
                    final lane = (r.id * 37 % 60) / 100 + 0.2;
                    final x = size.width * lane +
                        18 * math.sin(t * math.pi * 3 + r.id);
                    final y = size.height * (0.78 - 0.55 * t);
                    return Positioned(
                      left: x - 22,
                      top: y,
                      child: Opacity(
                        opacity: t < 0.75 ? 1 : (1 - t) * 4,
                        child: Transform.scale(
                          scale: 0.6 + 0.6 * (t * 4).clamp(0.0, 1.0).toDouble(),
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: Text(r.emoji, style: const TextStyle(fontSize: 40)),
                ),
            ],
          );
        },
      );
}

class _TopButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _TopButton({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) => VibePressable(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Icon(icon, color: color, size: 26),
      ),
    ),
  );
}

/// Round call button: translucent white, or solid white when switched on
/// (icon turns dark), red for End.
class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool on;
  final Color? background;
  const _CallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.on = false,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final bg = background ?? (on ? Colors.white : Colors.white.withAlpha(0x2E));
    final fg = background != null
        ? Colors.white
        : (on ? const Color(0xFF111214) : Colors.white);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        VibePressable(
          scale: 0.9,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(icon, key: ValueKey(icon), color: fg, size: 28),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
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

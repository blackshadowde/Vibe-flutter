// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/call/vibe_call.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// The call's video view, drawn by Vibe:
/// - one-to-one: their video full screen, yours small in the corner. Tap
///   the small one to swap (WhatsApp style);
/// - a shared screen fills the view, uncropped;
/// - groups: a grid, a green ring around whoever is talking.
class VibeCallStageView extends StatelessWidget {
  final VibeCall call;
  const VibeCallStageView({required this.call, super.key});

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final tiles = call.tiles;
    final me = tiles.where((t) => t.local).firstOrNull;
    final remote = tiles.where((t) => !t.local).toList();
    final shared = remote.where((t) => t.screen != null).firstOrNull;

    Widget body;
    if (shared != null) {
      body = Stack(
        fit: StackFit.expand,
        children: [
          _Video(track: shared.screen!, fit: lk.VideoViewFit.contain),
          Positioned(
            left: 12,
            bottom: pad.bottom + 130,
            child: _Label(text: '${_name(shared)} is sharing'),
          ),
        ],
      );
    } else if (remote.length <= 1) {
      final them = remote.firstOrNull;
      final big = call.swapped ? me : them;
      final small = call.swapped ? them : me;
      final showSmall =
          small != null && (small.camera != null || call.swapped);
      body = Stack(
        fit: StackFit.expand,
        children: [
          if (big != null) _Tile(call: call, tile: big, big: true),
          if (big == null) const ColoredBox(color: Color(0xFF111214)),
          if (me?.screen != null)
            Positioned(
              left: 12,
              bottom: pad.bottom + 130,
              child: const _Label(text: 'You\'re sharing your screen'),
            ),
          if (showSmall)
            Positioned(
              right: 12,
              top: pad.top + 64,
              width: 112,
              height: 164,
              child: GestureDetector(
                onTap: call.toggleSwap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _Tile(call: call, tile: small, big: false),
                ),
              ),
            ),
        ],
      );
    } else {
      final all = [?me, ...remote];
      body = SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 60, 8, 120),
          child: LayoutBuilder(
            builder: (context, c) {
              final cols = all.length <= 2 ? 1 : 2;
              final rows = (all.length / cols).ceil();
              final h = (c.maxHeight - (rows - 1) * 8) / rows;
              final w = (c.maxWidth - (cols - 1) * 8) / cols;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in all)
                    SizedBox(
                      width: w,
                      height: h,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _Tile(call: call, tile: t, big: false),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
    }
    return ColoredBox(color: const Color(0xFF111214), child: body);
  }

  String _name(VibeCallTile t) => call.room
          ?.unsafeGetUserFromMemoryOrFallback(t.userId)
          .calcDisplayname() ??
      t.userId;
}

class _Video extends StatelessWidget {
  final lk.VideoTrack track;
  final lk.VideoViewFit fit;
  const _Video({required this.track, required this.fit});

  @override
  Widget build(BuildContext context) => lk.VideoTrackRenderer(
    track,
    key: ValueKey(track),
    fit: fit,
  );
}

class _Tile extends StatelessWidget {
  final VibeCall call;
  final VibeCallTile tile;
  final bool big;
  const _Tile({required this.call, required this.tile, required this.big});

  @override
  Widget build(BuildContext context) {
    final room = call.room;
    final user = room?.unsafeGetUserFromMemoryOrFallback(tile.userId);
    final name = tile.local ? 'You' : (user?.calcDisplayname() ?? tile.userId);
    final video = tile.camera ?? tile.screen;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: !big && tile.speaking
            ? Border.all(color: const Color(0xFF23A55A), width: 3)
            : null,
        borderRadius: big ? null : BorderRadius.circular(16),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (video != null)
            _Video(
              track: video,
              fit: tile.camera != null
                  ? lk.VideoViewFit.cover
                  : lk.VideoViewFit.contain,
            )
          else
            ColoredBox(
              color: const Color(0xFF232428),
              child: Center(
                child: Avatar(
                  mxContent: user?.avatarUrl,
                  name: user?.calcDisplayname() ?? tile.userId,
                  size: big ? 120 : 64,
                  client: room?.client,
                ),
              ),
            ),
          if (!big)
            Positioned(
              left: 6,
              bottom: 6,
              right: 6,
              child: Row(
                children: [
                  if (tile.muted)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.mic_off, size: 14, color: Colors.white),
                    ),
                  Flexible(child: _Label(text: name, small: true)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final bool small;
  const _Label({required this.text, this.small = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? 6 : 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: small ? 11.5 : 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

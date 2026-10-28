// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:vibe/vibe/vibe_status.dart';
import 'package:vibe/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Discord's "Listening to Spotify" card on a profile: the cover, song and
/// artist, and a progress bar that moves while the song plays.
class VibeActivityCard extends StatefulWidget {
  final VibeStatus? status;
  final Client client;
  const VibeActivityCard({
    required this.status,
    required this.client,
    super.key,
  });

  @override
  State<VibeActivityCard> createState() => _VibeActivityCardState();
}

class _VibeActivityCardState extends State<VibeActivityCard> {
  Timer? _tick;

  Map<String, Object?>? get _a {
    final s = widget.status;
    final a = s?.activity;
    if (s == null || !s.active || a == null || a['kind'] != 'listening') {
      return null;
    }
    return a;
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _a != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _clock(int ms) {
    final s = (ms / 1000).floor();
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    if (a == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final app = a['app'] is String && (a['app'] as String).isNotEmpty
        ? a['app'] as String
        : 'music';
    final title = a['title'] is String ? a['title'] as String : '';
    final artist = a['artist'] is String ? a['artist'] as String : '';
    final duration = a['duration'] is int ? a['duration'] as int : 0;
    final start = a['start'] is int ? a['start'] as int : 0;
    final cover = a['cover'] is String ? Uri.tryParse(a['cover'] as String) : null;
    final elapsed = (DateTime.now().millisecondsSinceEpoch - start)
        .clamp(0, duration > 0 ? duration : 1 << 31);
    final progress = duration > 0 ? elapsed / duration : 0.0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  'Listening to $app',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.graphic_eq, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: cover == null
                      ? ColoredBox(
                          color: cs.surfaceContainerHighest,
                          child: Icon(Icons.music_note, color: cs.onSurfaceVariant),
                        )
                      : MxcImage(
                          client: widget.client,
                          uri: cover,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          isThumbnail: true,
                          cacheKey: 'vibe_activity_$cover',
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (artist.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        artist,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (duration > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.toDouble(),
                minHeight: 5,
                color: cs.primary,
                backgroundColor: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _clock(elapsed),
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                Text(
                  _clock(duration),
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

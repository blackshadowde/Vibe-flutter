// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:fluffychat/vibe/telegram/vibe_telegram.dart';
import 'package:fluffychat/vibe/vibe_animated_emoji.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : null;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

String _size(int bytes) {
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
  return '$bytes B';
}

String _duration(int s) =>
    '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// The caption text of a media message, or null.
String? tgCaption(Map<String, dynamic> message) {
  final c = _map(message['content']);
  final t = (_map(c?['caption'])?['text'] as String?)?.trim();
  return t == null || t.isEmpty ? null : t;
}

/// Whether [message] has something [TgMedia] can draw.
bool tgHasMedia(Map<String, dynamic> message) => const {
  'messagePhoto',
  'messageVideo',
  'messageAnimation',
  'messageSticker',
  'messageDocument',
  'messageVoiceNote',
  'messageAudio',
  'messageVideoNote',
}.contains(_map(message['content'])?['@type']);

/// Photos, videos, GIFs, stickers, files and voice messages of a Telegram
/// message.
class TgMedia extends StatelessWidget {
  final Map<String, dynamic> message;
  const TgMedia(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = _map(message['content']) ?? const {};
    switch (c['@type']) {
      case 'messagePhoto':
        final photo = _map(c['photo']);
        final sizes = (photo?['sizes'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        if (sizes.isEmpty) return const SizedBox.shrink();
        // A medium size for the chat, the biggest for the viewer.
        final medium = sizes.lastWhere(
          (s) => _int(s['width']) <= 1000,
          orElse: () => sizes.first,
        );
        return _Picture(
          file: _map(medium['photo']),
          full: _map(sizes.last['photo']),
          width: _int(medium['width']),
          height: _int(medium['height']),
          mini: _map(photo?['minithumbnail']),
        );
      case 'messageVideo':
      case 'messageAnimation':
      case 'messageVideoNote':
        final key = switch (c['@type']) {
          'messageVideo' => 'video',
          'messageAnimation' => 'animation',
          _ => 'video_note',
        };
        final v = _map(c[key]) ?? const {};
        final file = _map(v[key == 'video_note' ? 'video' : key]);
        final thumb = _map(_map(v['thumbnail'])?['file']);
        final w = _int(v['width'] ?? v['length']);
        final h = _int(v['height'] ?? v['length']);
        return _VideoTile(
          file: file,
          thumb: thumb,
          mini: _map(v['minithumbnail']),
          width: w == 0 ? 240 : w,
          height: h == 0 ? 240 : h,
          seconds: _int(v['duration']),
          gif: key == 'animation',
          round: key == 'video_note',
        );
      case 'messageSticker':
        final st = _map(c['sticker']) ?? const {};
        final fmt = _map(st['format'])?['@type'];
        final emoji = st['emoji'] as String? ?? '';
        if (fmt == 'stickerFormatWebp') {
          final path = VibeTelegram.instance.pathOf(_map(st['sticker']));
          if (path != null) {
            return SizedBox(
              width: 160,
              height: 160,
              child: Image.file(File(path), fit: BoxFit.contain),
            );
          }
        }
        // Animated Telegram stickers: show the sticker's emoji, animated.
        return VibeAnimatedEmoji(emoji.isEmpty ? '🙂' : emoji, size: 110);
      case 'messageDocument':
        final d = _map(c['document']) ?? const {};
        return _FileTile(
          file: _map(d['document']),
          name: d['file_name'] as String? ?? 'File',
          icon: Icons.insert_drive_file_outlined,
        );
      case 'messageAudio':
        final a = _map(c['audio']) ?? const {};
        final title = [a['performer'], a['title']]
            .whereType<String>()
            .where((e) => e.isNotEmpty)
            .join(' – ');
        return _FileTile(
          file: _map(a['audio']),
          name: title.isEmpty ? (a['file_name'] as String? ?? 'Audio') : title,
          icon: Icons.music_note_outlined,
        );
      case 'messageVoiceNote':
        final vn = _map(c['voice_note']) ?? const {};
        return TgVoicePlayer(
          file: _map(vn['voice']),
          seconds: _int(vn['duration']),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _Mini extends StatelessWidget {
  final Map<String, dynamic>? mini;
  const _Mini(this.mini);

  @override
  Widget build(BuildContext context) {
    final data = mini?['data'] as String?;
    if (data == null || data.isEmpty) {
      return ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHigh);
    }
    try {
      return Image.memory(
        base64Decode(data),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } catch (_) {
      return ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHigh);
    }
  }
}

Size _fit(int w, int h, {double maxW = 280, double maxH = 320}) {
  if (w <= 0 || h <= 0) return Size(maxW, maxW * 0.75);
  var scale = maxW / w;
  if (h * scale > maxH) scale = maxH / h;
  return Size(w * scale, h * scale);
}

class _Picture extends StatelessWidget {
  final Map<String, dynamic>? file;
  final Map<String, dynamic>? full;
  final Map<String, dynamic>? mini;
  final int width;
  final int height;
  const _Picture({
    required this.file,
    required this.full,
    required this.mini,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final tg = VibeTelegram.instance;
    final path = tg.pathOf(file);
    final size = _fit(width, height);
    return GestureDetector(
      onTap: path == null
          ? null
          : () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => _PhotoViewer(preview: path, full: full),
              ),
            ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Mini(mini),
              if (path != null)
                Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true)
              else
                const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  final String preview;
  final Map<String, dynamic>? full;
  const _PhotoViewer({required this.preview, required this.full});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  String? _full;

  @override
  void initState() {
    super.initState();
    VibeTelegram.instance.fetch(widget.full).then((p) {
      if (mounted && p != null) setState(() => _full = p);
    }).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final path = _full ?? widget.preview;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Share or save',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => SharePlus.instance.share(
              ShareParams(files: [XFile(path)]),
            ),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.file(File(path), gaplessPlayback: true),
        ),
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  final Map<String, dynamic>? file;
  final Map<String, dynamic>? thumb;
  final Map<String, dynamic>? mini;
  final int width;
  final int height;
  final int seconds;
  final bool gif;
  final bool round;
  const _VideoTile({
    required this.file,
    required this.thumb,
    required this.mini,
    required this.width,
    required this.height,
    required this.seconds,
    required this.gif,
    required this.round,
  });

  @override
  Widget build(BuildContext context) {
    final tg = VibeTelegram.instance;
    final thumbPath = tg.pathOf(thumb);
    final progress = tg.progressOf(file);
    final size = round ? const Size(200, 200) : _fit(width, height);
    return GestureDetector(
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        final nav = Navigator.of(context, rootNavigator: true);
        final path = await tg.fetch(file);
        if (path == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Couldn\'t download the video')),
          );
          return;
        }
        await nav.push(
          MaterialPageRoute(builder: (_) => _VideoPage(path: path, loop: gif)),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(round ? 100 : 14),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Mini(mini),
              if (thumbPath != null)
                Image.file(File(thumbPath), fit: BoxFit.cover, gaplessPlayback: true),
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: progress != null
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          gif ? Icons.gif_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                ),
              ),
              if (seconds > 0 && !gif)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _duration(seconds),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final String path;
  final bool loop;
  const _VideoPage({required this.path, required this.loop});

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  late final VideoPlayerController _video =
      VideoPlayerController.file(File(widget.path));
  ChewieController? _chewie;

  @override
  void initState() {
    super.initState();
    _video.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _chewie = ChewieController(
          videoPlayerController: _video,
          autoPlay: true,
          looping: widget.loop,
          aspectRatio: _video.value.aspectRatio,
        );
      });
    });
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chewie = _chewie;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Share or save',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => SharePlus.instance.share(
              ShareParams(files: [XFile(widget.path)]),
            ),
          ),
        ],
      ),
      body: Center(
        child: chewie == null
            ? const CircularProgressIndicator.adaptive()
            : Chewie(controller: chewie),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  final Map<String, dynamic>? file;
  final String name;
  final IconData icon;
  const _FileTile({required this.file, required this.name, required this.icon});

  @override
  Widget build(BuildContext context) {
    final tg = VibeTelegram.instance;
    final cs = Theme.of(context).colorScheme;
    final ready = tg.pathOf(file, download: false);
    final progress = tg.progressOf(file);
    final bytes = _int(file?['size'] ?? file?['expected_size']);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        final path = ready ?? await tg.fetch(file);
        if (path == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Couldn\'t download the file')),
          );
          return;
        }
        await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
      },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Color(0xFF5865F2),
                shape: BoxShape.circle,
              ),
              child: progress != null
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      ready != null ? icon : Icons.download_rounded,
                      color: Colors.white,
                    ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (bytes > 0)
                    Text(
                      _size(bytes),
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Voice message: play/pause, progress bar and time.
class TgVoicePlayer extends StatefulWidget {
  final Map<String, dynamic>? file;
  final int seconds;
  const TgVoicePlayer({required this.file, required this.seconds, super.key});

  @override
  State<TgVoicePlayer> createState() => _TgVoicePlayerState();
}

class _TgVoicePlayerState extends State<TgVoicePlayer> {
  static AudioPlayer? _shared; // one voice message plays at a time
  AudioPlayer? _player;
  StreamSubscription<Duration>? _pos;
  StreamSubscription<PlayerState>? _state;
  Duration _at = Duration.zero;
  bool _playing = false;
  bool _loading = false;

  @override
  void dispose() {
    _pos?.cancel();
    _state?.cancel();
    if (_player != null && identical(_player, _shared)) {
      _player!.dispose();
      _shared = null;
    }
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player?.pause();
      return;
    }
    if (_player == null || !identical(_player, _shared)) {
      setState(() => _loading = true);
      final path = await VibeTelegram.instance.fetch(widget.file);
      if (!mounted) return;
      setState(() => _loading = false);
      if (path == null) return;
      await _shared?.dispose();
      final p = _shared = _player = AudioPlayer();
      _pos = p.positionStream.listen((d) {
        if (mounted) setState(() => _at = d);
      });
      _state = p.playerStateStream.listen((s) {
        if (!mounted) return;
        final done = s.processingState == ProcessingState.completed;
        setState(() => _playing = s.playing && !done);
        if (done) {
          p.pause();
          p.seek(Duration.zero);
        }
      });
      await p.setFilePath(path);
    }
    await _player!.play();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = widget.seconds <= 0 ? 1 : widget.seconds;
    final value = (_at.inMilliseconds / (total * 1000)).clamp(0.0, 1.0);
    return Container(
      width: 250,
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _loading ? null : _toggle,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF5865F2),
              foregroundColor: Colors.white,
            ),
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 4,
                color: const Color(0xFF5865F2),
                backgroundColor: cs.outlineVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _duration(_playing || _at > Duration.zero ? _at.inSeconds : widget.seconds),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

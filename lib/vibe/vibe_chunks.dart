// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';
import 'dart:typed_data';

import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/utils/size_string.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Large file transfer between Vibe users.
///
/// A file bigger than the server allows is cut into parts. Each part is sent
/// as a normal (end-to-end encrypted, in encrypted rooms) file message with
/// a `chat.vibe.chunk` block. The LAST part also lists the event ids of all
/// earlier parts, so the receiver can fetch them and join the file back.
/// Other Matrix apps just see "part 1 of 3" files.
abstract class VibeChunks {
  static const key = 'chat.vibe.chunk';

  /// Used when the server does not tell us its limit.
  static const _fallbackLimit = 50 * 1000 * 1000;

  /// Part size. Small enough to finish quickly on a slow connection.
  static const _partSize = 20 * 1000 * 1000;

  /// Never send more than this many parts (= 2 GB at 20 MB each).
  static const _maxParts = 100;

  static int _limit(int? serverLimit) =>
      min(serverLimit ?? _fallbackLimit, _fallbackLimit);

  /// True if [size] should be split (10% safety margin under the limit).
  static bool needsSplit(int size, int? serverLimit) =>
      size > _limit(serverLimit) * 0.9;

  static int _partSizeFor(int? serverLimit) =>
      min(_partSize, (_limit(serverLimit) * 0.8).floor());

  static int partCount(int size, int? serverLimit) =>
      (size / _partSizeFor(serverLimit)).ceil();

  /// The caution dialog. Returns true if the user wants to send in parts.
  static Future<bool> confirm(
    BuildContext context,
    MatrixFile file,
    int? serverLimit,
  ) async {
    final parts = partCount(file.bytes.length, serverLimit);
    if (parts > _maxParts) {
      await showOkAlertDialog(
        context: context,
        title: 'File too big',
        message:
            '${file.name} is ${file.bytes.length.sizeString}. '
            'Vibe can send files up to '
            '${(_maxParts * _partSizeFor(serverLimit)).sizeString}.',
      );
      return false;
    }
    final result = await showOkCancelAlertDialog(
      context: context,
      title: 'Large file',
      message:
          'Your file (${file.bytes.length.sizeString}) is more than the '
          'allowed size limit (${_limit(serverLimit).sizeString}).\n\n'
          'To send it, Vibe will split it into $parts parts.\n\n'
          'This only works if the person on the other side also uses Vibe. '
          'Other Matrix apps will only see separate parts.',
      okLabel: 'Send in $parts parts',
      cancelLabel: 'Cancel',
    );
    return result == OkCancelResult.ok;
  }

  /// Sends [file] in parts. Each part is retried up to 5 times; if one still
  /// fails, sending stops and that part shows "Could not be sent".
  static Future<void> send(
    Room room,
    MatrixFile file,
    int? serverLimit, {
    String? threadRootEventId,
    String? threadLastEventId,
  }) async {
    final bytes = file.bytes;
    final size = bytes.length;
    final partSize = _partSizeFor(serverLimit);
    final total = (size / partSize).ceil();
    final id =
        '${DateTime.now().millisecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final mime = file.mimeType;
    final sent = <String>[];

    for (var i = 0; i < total; i++) {
      final start = i * partSize;
      final end = min(start + partSize, size);
      final part = MatrixFile(
        bytes: Uint8List.sublistView(bytes, start, end),
        name: '${file.name}.part${i + 1}of$total',
        mimeType: 'application/octet-stream',
      );
      final last = i == total - 1;
      final extra = <String, Object?>{
        'body': '📦 ${file.name} (part ${i + 1} of $total, open in Vibe)',
        key: {
          'v': 1,
          'id': id,
          'index': i,
          'total': total,
          'name': file.name,
          'mimetype': mime,
          'size': size,
          if (last) 'parts': List<String>.of(sent),
        },
      };

      // Same txid on every attempt, so a retry replaces the failed bubble
      // instead of adding a new one. Ship/satellite links drop a lot.
      final txid = room.client.generateUniqueTransactionId();
      String? eventId;
      for (var attempt = 0; attempt < 5 && eventId == null; attempt++) {
        if (attempt > 0) {
          await Future.delayed(Duration(seconds: 4 * attempt));
        }
        try {
          eventId = await room.sendFileEvent(
            part,
            txid: txid,
            extraContent: extra,
            threadRootEventId: threadRootEventId,
            threadLastEventId: threadLastEventId,
          );
        } on FileTooBigMatrixException {
          rethrow;
        } on MatrixException catch (e) {
          final retryAfterMs = e.retryAfterMs;
          if (e.error == MatrixError.M_LIMIT_EXCEEDED && retryAfterMs != null) {
            await Future.delayed(Duration(milliseconds: retryAfterMs));
          } else if (e.error == MatrixError.M_TOO_LARGE || attempt == 4) {
            rethrow;
          }
        } catch (_) {
          if (attempt == 4) rethrow;
        }
      }
      if (eventId == null) {
        throw Exception('Part ${i + 1} of $total could not be sent.');
      }
      sent.add(eventId);
    }
  }

  /// The `chat.vibe.chunk` block of [event], or null if it is not a part.
  static Map<String, Object?>? info(Event event) {
    final c = event.content[key];
    if (c is! Map) return null;
    final m = Map<String, Object?>.from(c);
    if (m['id'] is! String || m['index'] is! int || m['total'] is! int) {
      return null;
    }
    return m;
  }
}

/// What a part looks like in the chat. Earlier parts are a small line; the
/// last part is the card with "Download & save".
class VibeChunkCard extends StatefulWidget {
  final Event event;
  const VibeChunkCard(this.event, {super.key});

  @override
  State<VibeChunkCard> createState() => _VibeChunkCardState();
}

class _VibeChunkCardState extends State<VibeChunkCard> {
  String? _progress;
  String? _error;
  MatrixFile? _joined;

  Map<String, Object?> get _info => VibeChunks.info(widget.event)!;

  Future<void> _join() async {
    final info = _info;
    final total = info['total'] as int;
    final size = info['size'];
    final name = (info['name'] as String?) ?? 'file';
    final mime = info['mimetype'] as String?;
    final earlier = (info['parts'] is List)
        ? (info['parts'] as List).whereType<String>().toList()
        : <String>[];
    final ids = [...earlier, widget.event.eventId];

    setState(() {
      _error = null;
      _progress = 'Starting…';
    });
    try {
      if (ids.length != total) {
        throw Exception(
          'Only ${ids.length} of $total parts are listed. Ask the sender to '
          'send the file again.',
        );
      }
      final out = BytesBuilder(copy: false);
      for (var i = 0; i < total; i++) {
        if (!mounted) return;
        setState(() => _progress = 'Downloading part ${i + 1} of $total…');
        final ev = ids[i] == widget.event.eventId
            ? widget.event
            : await widget.event.room.getEventById(ids[i]);
        if (ev == null) {
          throw Exception('Part ${i + 1} of $total is missing.');
        }
        final pInfo = VibeChunks.info(ev);
        if (pInfo == null ||
            pInfo['id'] != info['id'] ||
            pInfo['index'] != i) {
          throw Exception('Part ${i + 1} of $total does not match.');
        }
        final f = await ev.downloadAndDecryptAttachment();
        out.add(f.bytes);
      }
      final bytes = out.takeBytes();
      if (size is int && bytes.length != size) {
        throw Exception(
          'Joined file is ${bytes.length.sizeString}, expected '
          '${size.sizeString}. A part may be damaged.',
        );
      }
      final file = MatrixFile(
        bytes: bytes,
        name: name,
        mimeType: mime,
      ).detectFileType;
      if (!mounted) return;
      VibeHaptics.medium();
      setState(() {
        _joined = file;
        _progress = null;
      });
      await file.save(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _progress = null;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = _info;
    final index = info['index'] as int;
    final total = info['total'] as int;
    final name = (info['name'] as String?) ?? 'file';
    final size = info['size'];
    final isLast = index == total - 1;

    if (!isLast) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 15, color: cs.outline),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Part ${index + 1} of $total · $name',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final sending = !widget.event.status.isSent;
    final joined = _joined;
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF5865F2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${size is int ? size.sizeString : ''} · $total parts',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_progress != null)
            Row(
              children: [
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _progress!,
                    style: TextStyle(fontSize: 12.5, color: cs.onSurface),
                  ),
                ),
              ],
            )
          else if (sending)
            Text(
              'Sending last part…',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            )
          else if (joined != null)
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => joined.save(context),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => joined.share(context),
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share'),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5865F2),
                  foregroundColor: Colors.white,
                ),
                onPressed: _join,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Download & save'),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(fontSize: 12, color: cs.error),
            ),
          ],
        ],
      ),
    );
  }
}

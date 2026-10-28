// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart' show Result;
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:mime/mime.dart';
import 'package:vibe/utils/localized_exception_extension.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/utils/resize_video.dart';
import 'package:vibe/vibe/vibe_chunks.dart';
import 'package:vibe/vibe/vibe_low_data.dart';

/// Files dropped on a chat wait above the text box until you press send.
abstract class VibePendingFiles {
  static bool _isImage(XFile f) =>
      (f.mimeType ?? lookupMimeType(f.path) ?? '').startsWith('image');

  /// Sends the files one by one; a file that fails says why.
  static Future<void> send(
    BuildContext context,
    Room room,
    List<XFile> files, {
    String? threadRootEventId,
    String? threadLastEventId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final config = await Result.capture(room.client.getConfig());
    final serverLimit = config.asValue?.value.mUploadSize;
    for (final x in files) {
      try {
        final mime = x.mimeType ?? lookupMimeType(x.path);
        final isVideo = mime != null && mime.startsWith('video');
        MatrixImageFile? thumbnail;
        final MatrixFile file;
        if (PlatformInfos.isMobile && isVideo) {
          thumbnail = await x.getVideoThumbnail();
          file = await x.getVideoInfo(
            compress: (await x.length()) > 20 * 1000,
          );
        } else {
          file = MatrixFile(
            bytes: await x.readAsBytes(),
            name: x.name,
            mimeType: mime,
          ).detectFileType;
        }
        if (VibeChunks.needsSplit(file.bytes.length, serverLimit)) {
          if (!context.mounted) return;
          if (!await VibeChunks.confirm(context, file, serverLimit)) continue;
          await VibeChunks.send(
            room,
            file,
            serverLimit,
            threadRootEventId: threadRootEventId,
            threadLastEventId: threadLastEventId,
          );
          continue;
        }
        await room.sendFileEvent(
          file,
          thumbnail: thumbnail,
          shrinkImageMaxDimension: VibeLowData.sendMaxDimension,
          threadRootEventId: threadRootEventId,
          threadLastEventId: threadLastEventId,
        );
      } catch (e, s) {
        Logs().w('Unable to send dropped file', e, s);
        if (!context.mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('${x.name}: ${e.toLocalizedString(context)}')),
        );
      }
    }
  }
}

/// The strip of waiting files above the text box; tap × to take one out.
class VibePendingFilesStrip extends StatelessWidget {
  final List<XFile> files;
  final void Function(XFile file) onRemove;
  const VibePendingFilesStrip({
    required this.files,
    required this.onRemove,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = files[i];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 64,
                  height: 64,
                  color: cs.surfaceContainerHighest,
                  child: VibePendingFiles._isImage(f)
                      ? FutureBuilder(
                          future: f.readAsBytes(),
                          builder: (context, snap) => snap.hasData
                              ? Image.memory(
                                  snap.data!,
                                  fit: BoxFit.cover,
                                  cacheWidth: 192,
                                )
                              : const SizedBox.shrink(),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                (f.mimeType ?? '').startsWith('video')
                                    ? Icons.movie_outlined
                                    : Icons.insert_drive_file_outlined,
                                size: 22,
                              ),
                              Text(
                                f.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              Positioned(
                top: -4,
                right: -4,
                child: Material(
                  color: cs.inverseSurface,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onRemove(f),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: cs.onInverseSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

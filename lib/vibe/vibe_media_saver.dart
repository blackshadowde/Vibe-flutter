// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

/// Settings > Chat > "Save media to gallery": photos and videos you RECEIVE
/// are saved to the phone's gallery automatically, so they survive the
/// server deleting old media. Works while Vibe is open or syncing.
abstract class VibeMediaSaver {
  static final Set<String> _done = {};
  static Future<void> _queue = Future.value();

  /// Skip anything bigger than this (keeps memory and data use sane).
  static const _maxBytes = 60 * 1000 * 1000;

  /// Ask for gallery permission when the user turns the setting on.
  static Future<bool> requestPermission() async {
    final p = await PhotoManager.requestPermissionExtend();
    return p.hasAccess;
  }

  static void onEvent(Event e) {
    if (!AppSettings.vibeSaveMedia.value) return;
    if (e.type != EventTypes.Message) return;
    if (e.senderId == e.room.client.userID) return;
    if (!e.status.isSynced || e.redacted) return;
    final type = e.messageType;
    if (type != MessageTypes.Image && type != MessageTypes.Video) return;
    // Only new messages, not old history loading in.
    if (DateTime.now().difference(e.originServerTs).inMinutes > 15) return;
    final size = e.infoMap['size'];
    if (size is int && size > _maxBytes) return;
    if (!_done.add(e.eventId)) return;
    // One at a time, in order.
    _queue = _queue.then((_) => _save(e)).catchError((Object err, StackTrace s) {
      Logs().w('Vibe: could not save media to gallery', err, s);
    });
  }

  static Future<void> _save(Event e) async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.hasAccess) return;
    final file = await e.downloadAndDecryptAttachment();
    var name = file.name;
    if (name.isEmpty) name = 'vibe_${e.originServerTs.millisecondsSinceEpoch}';
    if (e.messageType == MessageTypes.Image) {
      await PhotoManager.editor.saveImage(
        file.bytes,
        filename: name,
        title: name,
      );
    } else {
      final dir = await getTemporaryDirectory();
      final tmp = File('${dir.path}/$name');
      await tmp.writeAsBytes(file.bytes, flush: true);
      try {
        await PhotoManager.editor.saveVideo(tmp, title: name);
      } finally {
        if (await tmp.exists()) await tmp.delete();
      }
    }
  }
}

// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:matrix/matrix.dart';

/// Your stickers live in your Matrix account (your personal emoji pack,
/// im.ponies.user_emotes), so they're on all your devices and show for the
/// people you send them to. Each sticker remembers which pack it came from
/// ("Vibey", "Love", or an imported pack's name), so the sticker tray can
/// show the packs as tabs and each pack can be hidden.
abstract class VibeStickers {
  static const _field = 'chat.vibe.pack';
  static const _type = 'im.ponies.user_emotes';

  static Map<String, Object?> _raw(Client c) =>
      c.accountData[_type]?.content.tryGetMap<String, Object?>('images') ?? {};

  /// Which pack a sticker of your personal pack belongs to.
  static String packOf(Client c, String shortcode) {
    final img = _raw(c)[shortcode];
    final named = img is Map ? img[_field] : null;
    if (named is String && named.isNotEmpty) return named;
    if (shortcode.startsWith('vibe_')) return 'Vibey';
    if (shortcode.startsWith('love_')) return 'Love';
    return 'My stickers';
  }

  static List<String> packNames(Client c) {
    final out = <String>[];
    for (final k in _raw(c).keys) {
      final p = packOf(c, k);
      if (!out.contains(p)) out.add(p);
    }
    return out;
  }

  static Set<String> hidden() => AppSettings.vibeHiddenStickerPacks.value
      .split('\n')
      .where((s) => s.isNotEmpty)
      .toSet();

  static Future<void> setShown(String pack, bool shown) async {
    final h = hidden();
    shown ? h.remove(pack) : h.add(pack);
    await AppSettings.vibeHiddenStickerPacks.setItem(h.join('\n'));
  }

  static String _slug(String s) {
    final t = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final u = t.replaceAll(RegExp(r'^_+|_+$'), '');
    return u.isEmpty ? 'sticker' : (u.length > 20 ? u.substring(0, 20) : u);
  }

  static String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    return 'image/png';
  }

  static bool isImage(String name) =>
      RegExp(r'\.(webp|png|gif|jpe?g)$', caseSensitive: false).hasMatch(name);

  static bool isPackFile(String name) =>
      RegExp(r'\.(wastickers|zip)$', caseSensitive: false).hasMatch(name);

  /// Uploads [files] (name, bytes) as stickers of [pack]. Returns how many.
  static Future<int> add(
    Client c,
    List<(String, Uint8List)> files,
    String pack,
  ) async {
    final images = Map<String, Object?>.from(_raw(c));
    final base = _slug(pack);
    var n = 1;
    var added = 0;
    for (final (name, bytes) in files) {
      if (bytes.isEmpty) continue;
      while (images.containsKey('${base}_$n')) {
        n++;
      }
      final key = '${base}_$n';
      final mime = _mime(name);
      final uri = await c.uploadContent(bytes, filename: name, contentType: mime);
      images[key] = {
        'url': uri.toString(),
        'body': key,
        'info': {'mimetype': mime, 'size': bytes.length},
        'usage': ['sticker'],
        _field: pack,
      };
      added++;
    }
    if (added == 0) return 0;
    final content = Map<String, Object?>.from(c.accountData[_type]?.content ?? {});
    content['images'] = images;
    content['pack'] ??= {'display_name': 'My stickers'};
    await c.setAccountData(c.userID!, _type, content);
    c.accountData[_type] = BasicEvent(type: _type, content: content);
    return added;
  }

  /// A WhatsApp sticker pack file (.wastickers) or a zip of pictures:
  /// imports its stickers as one pack (named from its title.txt).
  static Future<(String, int)> importPack(
    Client c,
    Uint8List zip,
    String fileName,
  ) async {
    final archive = ZipDecoder().decodeBytes(zip);
    var title = fileName.replaceAll(RegExp(r'\.(wastickers|zip)$', caseSensitive: false), '');
    final files = <(String, Uint8List)>[];
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final name = f.name.split('/').last;
      if (name.toLowerCase() == 'title.txt') {
        final t = String.fromCharCodes(f.content).trim();
        if (t.isNotEmpty) title = t;
        continue;
      }
      // WhatsApp packs: the stickers are .webp, the tray icon is a .png
      if (name.toLowerCase().endsWith('.webp')) files.add((name, f.content));
    }
    if (files.isEmpty) {
      for (final f in archive.files) {
        final name = f.name.split('/').last;
        if (f.isFile && isImage(name)) files.add((name, f.content));
      }
    }
    final n = await add(c, files, title);
    return (title, n);
  }
}

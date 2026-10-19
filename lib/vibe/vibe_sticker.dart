// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

extension VibeStickerX on Event {
  /// A sticker sent as a picture: Vibe's text stickers, stickers from the
  /// keyboard (Gboard, etc.), and WebP pictures (how stickers usually come).
  /// Shown without a frame and left out of the media pane.
  bool get isVibeSticker {
    if (messageType == MessageTypes.Sticker) return true;
    if (messageType != MessageTypes.Image) return false;
    if (content['chat.vibe.sticker'] == true) return true;
    final mime = content.tryGetMap<String, Object?>('info')?.tryGet<String>('mimetype');
    return mime == 'image/webp';
  }
}

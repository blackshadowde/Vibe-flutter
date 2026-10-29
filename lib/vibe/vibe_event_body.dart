// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// A message's one-line text (notifications, chat list, replies), with
/// Vibe's text stickers called stickers: they're sent as pictures with a
/// `chat.vibe.sticker` mark, so Matrix alone would say "sent a picture".
extension VibeEventBody on Event {
  String? _vibeSticker(MatrixLocalizations i18n) {
    if (redacted || content['chat.vibe.sticker'] != true) return null;
    return i18n.sentASticker(
      senderFromMemoryOrFallback.calcDisplayname(i18n: i18n),
    );
  }

  Future<String> vibeBody(
    MatrixLocalizations i18n, {
    bool withSenderNamePrefix = false,
    bool hideReply = false,
    bool hideEdit = false,
    bool plaintextBody = false,
    bool removeMarkdown = false,
  }) async =>
      _vibeSticker(i18n) ??
      await calcLocalizedBody(
        i18n,
        withSenderNamePrefix: withSenderNamePrefix,
        hideReply: hideReply,
        hideEdit: hideEdit,
        plaintextBody: plaintextBody,
        removeMarkdown: removeMarkdown,
      );

  String vibeBodyFallback(
    MatrixLocalizations i18n, {
    bool withSenderNamePrefix = false,
    bool hideReply = false,
    bool hideEdit = false,
    bool plaintextBody = false,
    bool removeMarkdown = false,
  }) =>
      _vibeSticker(i18n) ??
      calcLocalizedBodyFallback(
        i18n,
        withSenderNamePrefix: withSenderNamePrefix,
        hideReply: hideReply,
        hideEdit: hideEdit,
        plaintextBody: plaintextBody,
        removeMarkdown: removeMarkdown,
      );
}

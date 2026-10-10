// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/vibe/vibe_low_data.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Discord-style link preview card under a text message.
///
/// The preview is fetched by your homeserver (Matrix `preview_url`), so the
/// server learns which links appear in your chats. That is why it can be
/// switched off in Settings → Security & sign-in.
class VibeLinkPreview extends StatelessWidget {
  final Event event;
  const VibeLinkPreview({required this.event, super.key});

  static final RegExp _urlRegex = RegExp(
    r'https?://[^\s<>"]+[^\s<>".,;:!?)\]}' "'" r']',
    caseSensitive: false,
  );

  /// One request per link per app run.
  static final Map<String, Future<PreviewForUrl?>> _cache = {};

  static String? firstUrl(Event e) {
    if (e.redacted || e.type != EventTypes.Message) return null;
    final type = e.messageType;
    if (type != MessageTypes.Text &&
        type != MessageTypes.Notice &&
        type != MessageTypes.Emote) {
      return null;
    }
    final m = _urlRegex.firstMatch(e.body);
    return m?.group(0);
  }

  static Future<PreviewForUrl?> _fetch(Client client, String url, int ts) {
    return _cache.putIfAbsent(url, () async {
      final uri = Uri.parse(url);
      try {
        return await client.getUrlPreviewAuthed(uri, ts: ts);
      } catch (_) {
        try {
          // Older servers without authenticated media.
          return await client.getUrlPreview(uri, ts: ts);
        } catch (e) {
          Logs().v('Vibe link preview failed for $url', e);
          return null;
        }
      }
    });
  }

  static String? _str(PreviewForUrl p, String key) {
    final v = p.additionalProperties[key];
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    if (!AppSettings.vibeLinkPreviews.value) return const SizedBox.shrink();
    final url = firstUrl(event);
    if (url == null) return const SizedBox.shrink();

    return FutureBuilder<PreviewForUrl?>(
      future: _fetch(
        event.room.client,
        url,
        event.originServerTs.millisecondsSinceEpoch,
      ),
      builder: (context, snap) {
        final p = snap.data;
        if (p == null) return const SizedBox.shrink();
        final title = _str(p, 'og:title');
        final desc = _str(p, 'og:description');
        final site = _str(p, 'og:site_name') ?? Uri.tryParse(url)?.host;
        final image = VibeLowData.on ? null : p.ogImage;
        if (title == null && desc == null && image == null) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () =>
                    launchUrlString(url, mode: LaunchMode.externalApplication),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: cs.outlineVariant, width: 4),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (site != null)
                        Text(
                          site,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      if (title != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF00A8FC),
                          ),
                        ),
                      ],
                      if (desc != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          desc,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: cs.onSurface.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                      if (image != null) ...[
                        const SizedBox(height: 10),
                        LayoutBuilder(
                          builder: (context, c) {
                            final w = c.maxWidth.isFinite ? c.maxWidth : 300.0;
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: MxcImage(
                                client: event.room.client,
                                uri: image,
                                width: w,
                                height: w * 0.52,
                                fit: BoxFit.cover,
                                isThumbnail: true,
                                cacheKey: 'vibe_link_preview_$image',
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

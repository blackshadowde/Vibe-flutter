// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_dialog.dart';
import 'package:vibe/config/app_config.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/vibe_share.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart';
import 'package:matrix/matrix.dart';
import 'package:particles_network/particles_network.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:qr_image/qr_image.dart';

import '../config/themes.dart';

Future<void> showQrCodeViewer(BuildContext context, String content) =>
    showVibeDialog(
      context: context,
      builder: (context) => QrCodeViewer(content: content),
    );

class QrCodeViewer extends StatelessWidget {
  final String content;

  const QrCodeViewer({required this.content, super.key});

  Future<void> _save(BuildContext context) async {
    final imageResult = await showFutureLoadingDialog(
      context: context,
      future: () {
        final inviteLink = _link(content);
        final image = QRImage(inviteLink, size: 256, radius: 1).generate();
        return compute(encodePng, image);
      },
    );
    final bytes = imageResult.result;
    if (bytes == null) return;
    if (!context.mounted) return;

    MatrixImageFile(
      bytes: bytes,
      name: 'QR_Code_$content.png',
      mimeType: 'image/png',
    ).save(context);
  }

  /// People get Vibe's share link (opens Vibe and starts a chat); rooms keep
  /// the matrix.to link every Matrix app understands.
  static String _link(String content) => content.startsWith('@')
      ? AppConfig.shareLink(content)
      : 'https://matrix.to/#/$content';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inviteLink = _link(content);
    return Scaffold(
      backgroundColor: Colors.black.withAlpha(128),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withAlpha(128),
          ),
          icon: const Icon(Icons.close),
          onPressed: Navigator.of(context).pop,
          color: Colors.white,
          tooltip: L10n.of(context).close,
        ),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withAlpha(128),
            ),
            icon: Icon(Icons.adaptive.share_outlined),
            onPressed: () => VibeShare.share(
              content.startsWith('@')
                  ? 'Chat with me on Vibe: $inviteLink'
                  : inviteLink,
              context,
            ),
            color: Colors.white,
            tooltip: L10n.of(context).share,
          ),
          const SizedBox(width: 8),
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withAlpha(128),
            ),
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _save(context),
            color: Colors.white,
            tooltip: L10n.of(context).downloadFile,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          if (!MediaQuery.disableAnimationsOf(context))
            ParticleNetwork(maxSpeed: 0.25),
          Center(
            child: Container(
              margin: const EdgeInsets.all(32.0),
              padding: const EdgeInsets.all(32.0),
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.colorScheme.onSurface,
                  width: 8,
                ),
                color: theme.colorScheme.surfaceBright,
                borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              ),
              child: Column(
                mainAxisSize: .min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: VibeThemes.columnWidth,
                    ),
                    child: PrettyQrView.data(
                      data: inviteLink,
                      decoration: PrettyQrDecoration(
                        shape: PrettyQrSmoothSymbol(
                          roundFactor: 1,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  SelectableText(
                    content,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/bootstrap/view_model/bootstrap_view_model.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/vibe/vibe_security_ui.dart';
import 'package:flutter/material.dart';

class StoreRecoveryKeyView extends StatelessWidget {
  final BootstrapViewModel viewModel;
  const StoreRecoveryKeyView(this.viewModel, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final key = viewModel.value.recoveryKey ?? '';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        VibeHeader(
          icon: Icons.vpn_key_outlined,
          title: 'Save your recovery key',
          description: L10n.of(context).storeRecoveryKeyDescription,
        ),
        const VibeSectionLabel('Recovery key'),
        VibeCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  key,
                  style: const TextStyle(
                    fontFamily: 'RobotoMono',
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy_outlined, color: cs.onSurfaceVariant),
                onPressed: () => FluffyShare.share(key, context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const VibeSectionLabel('Keep it safe'),
        VibeCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              CheckboxListTile.adaptive(
                value: viewModel.value.recoveryKeyDownloaded,
                activeColor: cs.primary,
                onChanged: (copied) =>
                    viewModel.toggleRecoveryKeyDownloaded(copied, context),
                title: Text(L10n.of(context).saveAsFile),
              ),
              if (viewModel.supportsSecureStorage)
                CheckboxListTile.adaptive(
                  value: viewModel.value.recoveryKeyStoredInSecureStorage,
                  activeColor: cs.primary,
                  onChanged: viewModel.toggleRecoveryKeyStoredInSecureStorage,
                  title: Text(_getSecureStorageLocalizedName(context)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _getSecureStorageLocalizedName(BuildContext context) {
    if (PlatformInfos.isAndroid) {
      return L10n.of(context).storeInAndroidKeystore;
    }
    if (PlatformInfos.isIOS || PlatformInfos.isMacOS) {
      return L10n.of(context).storeInAppleKeyChain;
    }
    return L10n.of(context).storeSecurlyOnThisDevice;
  }
}

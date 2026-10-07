// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/bootstrap/view_model/bootstrap_view_model.dart';
import 'package:fluffychat/pages/key_verification/key_verification_dialog.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/device_extension.dart';
import 'package:fluffychat/vibe/vibe_security_ui.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:flutter/material.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';

class RestoreBootstrapView extends StatelessWidget {
  final BootstrapViewModel viewModel;

  const RestoreBootstrapView(this.viewModel, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final keyVerification = viewModel.value.keyVerification;
    if (keyVerification != null) {
      Logs().v('Key verification state:', keyVerification.state);
      if (keyVerification.state == KeyVerificationState.askSas) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          KeyVerificationDialog(request: keyVerification).show(context);
        });
      }
    }
    final devices =
        viewModel.value.connectedDevices
            ?.map(
              (device) => (
                title: device.displayname,
                lastActive: device.lastActive,
                icon: device.icon,
              ),
            )
            .toList() ??
        [];
    final failed =
        keyVerification != null &&
        (keyVerification.state == KeyVerificationState.error ||
            viewModel.value.noSecretsreceived);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        VibeHeader(
          icon: Icons.vpn_key_outlined,
          title: 'Unlock your messages',
          description: keyVerification == null
              ? L10n.of(context).restoreBootstrapEmptyDevicesDescription
              : null,
        ),
        if (keyVerification != null) ...[
          VibeCard(
            child: Row(
              children: [
                failed
                    ? IconButton(
                        onPressed: viewModel.value.isLoading
                            ? null
                            : viewModel.retryKeyVerification,
                        tooltip: L10n.of(context).tryAgain,
                        icon: const Icon(Icons.refresh_outlined),
                      )
                    : const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    viewModel.value.waitingForSecrets
                        ? L10n.of(context).waitingForKeys
                        : viewModel.value.noSecretsreceived
                        ? L10n.of(context).noKeysTransmitted
                        : L10n.of(context).restoreBootstrapDevicesDescription,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: cs.surfaceContainerHigh,
            clipBehavior: Clip.hardEdge,
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 168),
              child: Scrollbar(
                thumbVisibility: true,
                controller: viewModel.devicesScrollController,
                child: ListView.builder(
                  controller: viewModel.devicesScrollController,
                  shrinkWrap: true,
                  itemCount: devices.length,
                  itemBuilder: (context, i) => ListTile(
                    leading: CircleAvatar(
                      foregroundColor: cs.onSurface,
                      backgroundColor: cs.surfaceContainerHighest,
                      child: Icon(devices[i].icon),
                    ),
                    title: Text(
                      devices[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      L10n.of(context).lastActiveAgo(
                        devices[i].lastActive.localizedTime(context),
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(child: Divider(height: 40, color: cs.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  L10n.of(context).or,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
              Expanded(child: Divider(height: 40, color: cs.outlineVariant)),
            ],
          ),
        ],
        const VibeSectionLabel('Passphrase or recovery key'),
        TextField(
          readOnly: viewModel.value.isLoading,
          obscureText: viewModel.value.obscureText,
          controller: viewModel.enterPassphraseOrRecovController,
          minLines: 1,
          maxLines: viewModel.value.obscureText ? 1 : 4,
          onSubmitted: (_) => viewModel.unlock(context),
          decoration: vibeFieldDecoration(
            context,
            hint: L10n.of(context).passphraseOrKey,
            errorText: viewModel.value.unlockWithError?.toLocalizedString(
              context,
            ),
            suffix: IconButton(
              icon: Icon(
                viewModel.value.obscureText
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: cs.onSurfaceVariant,
              ),
              onPressed: viewModel.toggleObscureText,
            ),
          ),
        ),
        const SizedBox(height: 16),
        VibeButton(
          label: viewModel.value.passphraseOrRecoveryKeyEntered
              ? L10n.of(context).unlock
              : L10n.of(context).openFile,
          tonal: !viewModel.value.passphraseOrRecoveryKeyEntered,
          loading: viewModel.value.isLoading,
          onPressed: viewModel.value.passphraseOrRecoveryKeyEntered
              ? () => viewModel.unlock(context)
              : () => viewModel.openRecoveryKeyFile(context),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () async {
            final consent = await showOkCancelAlertDialog(
              context: context,
              title: L10n.of(context).warning,
              message: L10n.of(context).resetAccountWarning,
              isDestructive: true,
              okLabel: L10n.of(context).resetAccount,
            );
            if (consent != OkCancelResult.ok) return;
            if (!context.mounted) return;
            viewModel.startResetAccount();
          },
          style: TextButton.styleFrom(
            foregroundColor: cs.error,
            minimumSize: const Size.fromHeight(44),
          ),
          child: Text(L10n.of(context).resetAccount),
        ),
      ],
    );
  }
}

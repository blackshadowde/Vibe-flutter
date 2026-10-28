// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Password recovery: the email addresses (or phone numbers) your server
/// can use to reset your password.
class VibeRecoveryEmailPage extends StatefulWidget {
  const VibeRecoveryEmailPage({super.key});

  @override
  State<VibeRecoveryEmailPage> createState() => _VibeRecoveryEmailPageState();
}

class _VibeRecoveryEmailPageState extends State<VibeRecoveryEmailPage> {
  static int _sendAttempt = 0;
  Future<List<ThirdPartyIdentifier>?>? _request;

  Future<void> _add() async {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.enterAnEmailAddress,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: l10n.enterAnEmailAddress,
      keyboardType: TextInputType.emailAddress,
    );
    if (input == null || !mounted) return;
    final secret = DateTime.now().millisecondsSinceEpoch.toString();
    final response = await showFutureLoadingDialog(
      context: context,
      future: () =>
          client.requestTokenToRegisterEmail(secret, input, _sendAttempt++),
    );
    if (response.error != null || !mounted) return;
    final ok = await showOkAlertDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.weSentYouAnEmail,
      message: l10n.pleaseClickOnLink,
      okLabel: l10n.iHaveClickedOnLink,
    );
    if (ok != OkCancelResult.ok || !mounted) return;
    final done = await showFutureLoadingDialog(
      context: context,
      delay: false,
      future: () => client.uiaRequestBackground(
        (auth) => client.add3PID(secret, response.result!.sid, auth: auth),
      ),
    );
    if (done.error == null && mounted) setState(() => _request = null);
  }

  Future<void> _delete(ThirdPartyIdentifier id) async {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    if (await showOkCancelAlertDialog(
          useRootNavigator: false,
          context: context,
          title: l10n.areYouSure,
          okLabel: l10n.yes,
          cancelLabel: l10n.cancel,
        ) !=
        OkCancelResult.ok) {
      return;
    }
    if (!mounted) return;
    final done = await showFutureLoadingDialog(
      context: context,
      future: () => client.delete3pidFromAccount(id.address, id.medium),
    );
    if (done.error == null && mounted) setState(() => _request = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final t2 = VibeSettingsStyle.text2(context);
    _request ??= Matrix.of(context).client.getAccount3PIDs();
    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        title: Text(l10n.passwordRecovery),
      ),
      body: MaxWidthBody(
        child: FutureBuilder<List<ThirdPartyIdentifier>?>(
          future: _request,
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${snap.error}', textAlign: TextAlign.center),
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator.adaptive()),
              );
            }
            final ids = snap.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Text(
                    ids.isEmpty
                        ? l10n.noPasswordRecoveryDescription
                        : l10n.withTheseAddressesRecoveryDescription,
                    style: TextStyle(fontSize: 14, color: t2),
                  ),
                ),
                VibeCard(
                  children: [
                    for (final id in ids)
                      ListTile(
                        leading: Icon(
                          id.medium == ThirdPartyIdentifierMedium.msisdn
                              ? Icons.phone_android_outlined
                              : Icons.mail_outline_rounded,
                        ),
                        title: Text(id.address),
                        trailing: IconButton(
                          tooltip: l10n.delete,
                          icon: const Icon(Icons.delete_outline),
                          color: Theme.of(context).colorScheme.error,
                          onPressed: () => _delete(id),
                        ),
                      ),
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: Text(l10n.addEmail),
                      onTap: _add,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

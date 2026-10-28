// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/localized_exception_extension.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/widgets/layouts/login_scaffold.dart';

class Login extends StatefulWidget {
  final Client client;
  const Login({required this.client, super.key});

  @override
  _LoginState createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  String? usernameError;
  String? passwordError;
  bool loading = false;
  bool showPassword = false;

  void toggleShowPassword() =>
      setState(() => showPassword = !loading && !showPassword);

  Future<void> login() async {
    final matrix = Matrix.of(context);
    if (usernameController.text.isEmpty) {
      setState(() => usernameError = L10n.of(context).pleaseEnterYourUsername);
    } else {
      setState(() => usernameError = null);
    }
    if (passwordController.text.isEmpty) {
      setState(() => passwordError = L10n.of(context).pleaseEnterYourPassword);
    } else {
      setState(() => passwordError = null);
    }

    if (usernameController.text.isEmpty || passwordController.text.isEmpty) {
      return;
    }

    setState(() => loading = true);

    _coolDown?.cancel();

    try {
      final username = usernameController.text;
      AuthenticationIdentifier identifier;
      if (username.isEmail) {
        identifier = AuthenticationThirdPartyIdentifier(
          medium: 'email',
          address: username,
        );
      } else if (username.isPhoneNumber) {
        identifier = AuthenticationThirdPartyIdentifier(
          medium: 'msisdn',
          address: username,
        );
      } else {
        identifier = AuthenticationUserIdentifier(user: username);
      }
      final client = await matrix.getLoginClient();
      await client.login(
        LoginType.mLoginPassword,
        identifier: identifier,
        // To stay compatible with older server versions
        // ignore: deprecated_member_use
        user: identifier.type == AuthenticationIdentifierTypes.userId
            ? username
            : null,
        password: passwordController.text,
        initialDeviceDisplayName: PlatformInfos.appDisplayName,
      );
      if (mounted) {
        context.go('/backup');
      }
    } on MatrixException catch (exception) {
      setState(() => passwordError = exception.errorMessage);
      return setState(() => loading = false);
    } catch (exception) {
      setState(() => passwordError = exception.toString());
      return setState(() => loading = false);
    }

    if (mounted) setState(() => loading = false);
  }

  Timer? _coolDown;

  void checkWellKnownWithCoolDown(String userId) {
    _coolDown?.cancel();
    _coolDown = Timer(
      const Duration(seconds: 1),
      () => _checkWellKnown(userId),
    );
  }

  Future<void> _checkWellKnown(String userId) async {
    if (mounted) setState(() => usernameError = null);
    if (!userId.isValidMatrixIdStrict()) return;
    final oldHomeserver = widget.client.homeserver;
    try {
      var newDomain = Uri.https(userId.domain!, '');
      widget.client.homeserver = newDomain;
      DiscoveryInformation? wellKnownInformation;
      try {
        wellKnownInformation = await widget.client.getWellknown();
        if (wellKnownInformation.mHomeserver.baseUrl.toString().isNotEmpty) {
          newDomain = wellKnownInformation.mHomeserver.baseUrl;
        }
      } catch (_) {
        // do nothing, newDomain is already set to a reasonable fallback
      }
      if (newDomain != oldHomeserver) {
        await widget.client.checkHomeserver(newDomain);

        if (widget.client.homeserver == null) {
          widget.client.homeserver = oldHomeserver;
          // okay, the server we checked does not appear to be a matrix server
          Logs().v(
            '$newDomain is not running a homeserver, asking to use $oldHomeserver',
          );
          if (!mounted) return;
          final l10n = L10n.of(context);
          final dialogResult = await showOkCancelAlertDialog(
            context: context,
            useRootNavigator: false,
            title: l10n.noMatrixServer(
              newDomain.toString(),
              oldHomeserver.toString(),
            ),
            okLabel: l10n.ok,
            cancelLabel: l10n.cancel,
          );
          if (!mounted) return;
          if (dialogResult == OkCancelResult.ok) {
            if (mounted) setState(() => usernameError = null);
          } else {
            Navigator.of(context, rootNavigator: false).pop();
            return;
          }
        }
        usernameError = null;
        if (mounted) setState(() {});
      } else {
        widget.client.homeserver = oldHomeserver;
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      widget.client.homeserver = oldHomeserver;
      if (!mounted) return;
      usernameError = e.toLocalizedString(context);
      if (mounted) setState(() {});
    }
  }

  Future<void> passwordForgotten() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.passwordForgotten,
      message: l10n.enterAnEmailAddress,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      initialText: usernameController.text.isEmail
          ? usernameController.text
          : '',
      hintText: l10n.enterAnEmailAddress,
      keyboardType: TextInputType.emailAddress,
    );
    if (input == null) return;
    if (!mounted) return;
    final clientSecret = DateTime.now().millisecondsSinceEpoch.toString();
    final response = await showFutureLoadingDialog(
      context: context,
      future: () => widget.client.requestTokenToResetPasswordEmail(
        clientSecret,
        input,
        sendAttempt++,
      ),
    );
    if (response.error != null) return;
    if (!mounted) return;
    final password = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.passwordForgotten,
      message: l10n.chooseAStrongPassword,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: '******',
      obscureText: true,
      minLines: 1,
      maxLines: 1,
    );
    if (password == null) return;
    if (!mounted) return;
    final ok = await showOkAlertDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.weSentYouAnEmail,
      message: l10n.pleaseClickOnLink,
      okLabel: l10n.iHaveClickedOnLink,
    );
    if (ok != OkCancelResult.ok) return;
    if (!mounted) return;
    final data = <String, dynamic>{
      'new_password': password,
      'logout_devices': false,
      'auth': AuthenticationThreePidCreds(
        type: AuthenticationTypes.emailIdentity,
        threepidCreds: ThreepidCreds(
          sid: response.result!.sid,
          clientSecret: clientSecret,
        ),
      ).toJson(),
    };
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => widget.client.request(
        RequestType.POST,
        '/client/v3/account/password',
        data: data,
      ),
    );
    if (!mounted) return;
    if (success.error == null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.passwordHasBeenChanged)),
      );
      usernameController.text = input;
      passwordController.text = password;
      login();
    }
  }

  static int sendAttempt = 0;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final homeserver = widget.client.homeserver
        ?.toString()
        .replaceFirst('https://', '');
    final title = homeserver == null
        ? L10n.of(context).loginWithMatrixId
        : L10n.of(context).logInTo(homeserver);

    return LoginScaffold(
      appBar: AppBar(
        leading: loading ? null : const Center(child: BackButton()),
        automaticallyImplyLeading: !loading,
        titleSpacing: !loading ? 0 : null,
        title: Text(title),
      ),
      body: Builder(
        builder: (context) {
          return AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: <Widget>[
                Center(
                  child: Hero(
                    tag: 'info-logo',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(128),
                      child: Image.asset(
                        './assets/logo/mini/logo_mini.png',
                        width: 128,
                        height: 128,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: TextField(
                    readOnly: loading,
                    autocorrect: false,
                    autofocus: true,
                    onChanged: checkWellKnownWithCoolDown,
                    controller: usernameController,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: loading
                        ? null
                        : [AutofillHints.username],
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.account_box_outlined),
                      errorText: usernameError,
                      errorStyle: const TextStyle(color: Color(0xFFF23F42)),
                      hintText: '@username:domain',
                      labelText: L10n.of(context).matrixId,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: TextField(
                    readOnly: loading,
                    autocorrect: false,
                    autofillHints: loading
                        ? null
                        : [AutofillHints.password],
                    controller: passwordController,
                    textInputAction: TextInputAction.go,
                    obscureText: !showPassword,
                    onSubmitted: (_) => login(),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outlined),
                      errorText: passwordError,
                      errorStyle: const TextStyle(color: Color(0xFFF23F42)),
                      suffixIcon: IconButton(
                        onPressed: toggleShowPassword,
                        icon: Icon(
                          showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.black,
                        ),
                      ),
                      hintText: '******',
                      labelText: L10n.of(context).password,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                    ),
                    onPressed: loading ? null : login,
                    child: loading
                        ? const LinearProgressIndicator()
                        : Text(L10n.of(context).login),
                  ),
                ),
                const SizedBox(height: 16),
                if (homeserver != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: TextButton(
                      onPressed: loading
                          ? () {}
                          : passwordForgotten,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      child: Text(L10n.of(context).passwordForgotten),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}

extension on String {
  static final RegExp _phoneRegex = RegExp(
    r'^[+]*[(]{0,1}[0-9]{1,4}[)]{0,1}[-\s\./0-9]*$',
  );
  static final RegExp _emailRegex = RegExp(r'(.+)@(.+)\.(.+)');

  bool get isEmail => _emailRegex.hasMatch(this);

  bool get isPhoneNumber => _phoneRegex.hasMatch(this);
}


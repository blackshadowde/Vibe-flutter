// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/pages/intro/flows/restore_backup_flow.dart';
import 'package:vibe/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/utils/sign_in_flows/check_homeserver.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/vibe/vibe_sign_up.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Vibe start screen. Opens on "Create your account" (on Unredacted by
/// default, all inside the app); "Already have an account? Log in" switches
/// to username + password.
class IntroPage extends StatefulWidget {
  final bool isLoading, hasPresetHomeserver;
  final String? loggingInToHomeserver, welcomeText;
  final VoidCallback login;

  const IntroPage({
    required this.isLoading,
    required this.loggingInToHomeserver,
    super.key,
    required this.hasPresetHomeserver,
    required this.welcomeText,
    required this.login,
  });

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage>
    with VibeSignUpMixin<IntroPage> {
  /// Start on "Create your account": most people are new to Matrix.
  bool _creating = true;

  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  bool _showPass = false;
  bool _busy = false;
  String? _error;
  late String _homeserver = _initialHomeserver();

  static String _initialHomeserver() {
    final preset = AppSettings.presetHomeserver.value;
    final def = AppSettings.defaultHomeserver.value;
    final raw = preset.isNotEmpty
        ? preset
        : (def.isNotEmpty ? def : 'matrix.unredacted.org');
    return raw.startsWith('http') ? raw : 'https://$raw';
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  String get suHomeserver => _homeserver;

  @override
  Future<Client> suClient() => Matrix.of(context).getLoginClient();

  @override
  Future<void> suOpenWebSignUp() => _web(signUp: true);

  @override
  bool get suEmailRequired => true;

  Future<void> _signIn() async {
    final username = _user.text.trim();
    final password = _pass.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your username and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // "@you:server" logs in on that server, whatever is picked below.
      final full = RegExp(r'^@[^:\s]+:([^\s]+)$').firstMatch(username);
      if (full != null) {
        final server = full.group(1)!;
        if (Uri.tryParse(_homeserver)?.host != server) {
          setState(() => _homeserver = 'https://$server');
        }
      }
      final client = await Matrix.of(context).getLoginClient();
      await client.checkHomeserver(Uri.parse(_homeserver));
      final AuthenticationIdentifier identifier =
          RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(username)
          ? AuthenticationThirdPartyIdentifier(
              medium: 'email',
              address: username,
            )
          : AuthenticationUserIdentifier(user: username);
      await client.login(
        LoginType.mLoginPassword,
        identifier: identifier,
        password: password,
        initialDeviceDisplayName: PlatformInfos.appDisplayName,
      );
      TextInput.finishAutofillContext(); // offer to save it in the password manager
      if (mounted) context.go('/backup');
    } on MatrixException catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().contains('SocketException') ||
                  e.toString().contains('ClientException')
              ? 'Can\'t reach the server. Check your internet and try again.'
              : e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(MatrixException e) => switch (e.errcode) {
    'M_FORBIDDEN' => 'Wrong username or password',
    'M_USER_DEACTIVATED' => 'This account was closed',
    'M_LIMIT_EXCEEDED' => 'Too many tries. Wait a minute, then try again.',
    _ => e.errorMessage,
  };

  /// Google (also Apple, GitHub) sign-in through matrix.org's account page.
  Future<void> _google() async {
    setState(() => _homeserver = 'https://matrix.org');
    await _web(signUp: _creating);
  }

  Future<void> _web({required bool signUp}) => connectToHomeserverFlow(
    PublicHomeserverData(name: _homeserver),
    context,
    (snapshot) {
      if (mounted) {
        setState(() => _busy = snapshot.connectionState == ConnectionState.waiting);
      }
    },
    signUp,
  );

  /// Popular servers shown first. `name` is what we connect to (server
  /// discovery via .well-known finds the real address).
  static const _quickServers = [
    (
      name: 'matrix.unredacted.org',
      title: 'Unredacted',
      note: 'Recommended · free · sign up right here · 100 MB files',
    ),
    (
      name: 'matrix.org',
      title: 'Matrix.org',
      note: 'Largest server · sign-up opens in the browser',
    ),
    (name: '4d2.org', title: '4d2.org', note: 'Community · 150 MiB files'),
    (name: 'tchncs.de', title: 'tchncs.de', note: 'Community · Germany'),
  ];

  Future<void> _editHomeserver() async {
    final ctrl = TextEditingController();
    final current = Uri.tryParse(_homeserver)?.host ?? _homeserver;
    final value = await showVibeSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: VibeSettingsStyle.page(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final t1 = VibeSettingsStyle.text(ctx);
        final t2 = VibeSettingsStyle.text2(ctx);
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(
                      'Choose a server',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: t1,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'Your account lives on this server. People on any '
                      'server can chat with each other.',
                      style: TextStyle(fontSize: 13.5, color: t2),
                    ),
                  ),
                  VibeCard(
                    children: [
                      for (final s in _quickServers)
                        ListTile(
                          title: Text(s.title),
                          subtitle: Text(s.note),
                          trailing: s.name == current
                              ? Icon(
                                  Icons.check_circle,
                                  size: 22,
                                  color: VibeSettingsStyle.accent,
                                )
                              : Icon(
                                  Icons.circle_outlined,
                                  size: 22,
                                  color: VibeSettingsStyle.line(ctx),
                                ),
                          onTap: () => Navigator.pop(ctx, s.name),
                        ),
                    ],
                  ),
                  VibeCard(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    children: [
                      ListTile(
                        title: const Text('Browse all public servers'),
                        trailing: Icon(Icons.chevron_right, color: t2),
                        onTap: () => Navigator.pop(ctx, 'vibe:browse'),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                      style: TextStyle(fontSize: 15, color: t1),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Other server, e.g. example.com',
                        hintStyle: TextStyle(color: t2),
                        filled: true,
                        fillColor: VibeSettingsStyle.card(ctx),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(Icons.arrow_forward, size: 20, color: t1),
                          onPressed: () =>
                              Navigator.pop(ctx, ctrl.text.trim()),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    ctrl.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    if (value == 'vibe:browse') {
      // FluffyChat's public server list (searchable), at <this page>/sign_in
      var path = GoRouterState.of(context).uri.path;
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
      context.go('$path/sign_in');
      return;
    }
    setState(
      () => _homeserver = value.startsWith('http') ? value : 'https://$value',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = VibeSettingsStyle.page(context);
    final field = VibeSettingsStyle.card(context);
    final text = VibeSettingsStyle.text(context);
    final muted = VibeSettingsStyle.text2(context);
    final blurple = VibeSettingsStyle.accent;
    const danger = Color(0xFFDA373C);

    if (widget.isLoading) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: blurple),
              if (widget.loggingInToHomeserver != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Logging in to ${widget.loggingInToHomeserver}',
                  style: TextStyle(color: muted),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Plain filled field, no outline until focused.
    InputDecoration deco(String hint, {Widget? suffix}) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 15, color: muted),
      suffixIcon: suffix,
      isDense: true,
      filled: true,
      fillColor: field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: blurple, width: 1.4),
      ),
    );

    Widget label(String t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 14),
      child: Row(
        children: [
          Text(
            t,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );

    Widget field0(
      TextEditingController c,
      String hint, {
      bool obscure = false,
      bool enabled = true,
      TextInputType? keyboard,
      TextInputAction action = TextInputAction.next,
      ValueChanged<String>? onSubmitted,
      Widget? suffix,
      Iterable<String>? hints,
    }) => TextField(
      controller: c,
      autofillHints: hints,
      enabled: enabled,
      obscureText: obscure,
      autocorrect: false,
      keyboardType: keyboard,
      textInputAction: action,
      onSubmitted: onSubmitted,
      style: TextStyle(color: text, fontSize: 15.5),
      decoration: deco(hint, suffix: suffix),
    );

    Widget eye(bool shown, VoidCallback toggle) => IconButton(
      icon: Icon(
        shown ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 20,
        color: muted,
      ),
      onPressed: toggle,
    );

    Widget primary(String title, VoidCallback? onTap, {String? busy}) =>
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: blurple,
              foregroundColor: Colors.white,
              disabledBackgroundColor: blurple.withValues(alpha: 0.5),
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(fontFamily: 'Figtree', 
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: busy != null
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(busy, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  )
                : Text(title),
          ),
        );

    final error = _creating ? suError : _error;
    final busy = _creating ? suBusy : _busy;

    return AutofillGroup(
      child: Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              children: [
                // Server, small and tappable, top right.
                Align(
                  alignment: Alignment.centerRight,
                  child: Material(
                    color: field,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: busy ? null : _editHomeserver,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.dns_rounded, size: 15, color: muted),
                            const SizedBox(width: 6),
                            Text(
                              VibeSignUpMixin.prettyServer(_homeserver),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: text,
                              ),
                            ),
                            Icon(
                              Icons.keyboard_arrow_down,
                              size: 18,
                              color: muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/logo/mini/logo_mini.png',
                      width: 56,
                      height: 56,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Column(
                    key: ValueKey(_creating),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _creating ? 'Create your account' : 'Welcome back',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: text,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _creating
                            ? 'Free and end-to-end encrypted. No phone number needed.'
                            : 'Log in with your Matrix account.',
                        style: TextStyle(fontSize: 14.5, color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (_creating) ...[
                  label('Username'),
                  field0(suUser, 'Pick a username', enabled: !suBusy, hints: const [AutofillHints.newUsername]),
                  label('Password'),
                  field0(
                    suPass,
                    'At least 8 characters',
                    hints: const [AutofillHints.newPassword],
                    obscure: !suShowPass,
                    enabled: !suBusy,
                    suffix: eye(
                      suShowPass,
                      () => setState(() => suShowPass = !suShowPass),
                    ),
                  ),
                  const SizedBox(height: 8),
                  field0(
                    suPass2,
                    'Repeat password',
                    obscure: !suShowPass,
                    enabled: !suBusy,
                  ),
                  label('Email'),
                  field0(
                    suEmail,
                    'you@example.com',
                    hints: const [AutofillHints.email],
                    enabled: !suBusy,
                    keyboard: TextInputType.emailAddress,
                    action: TextInputAction.done,
                    onSubmitted: (_) => suBusy ? null : suSubmit(),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'We\'ll send a link to confirm your account.',
                      style: TextStyle(fontSize: 12.5, color: muted),
                    ),
                  ),
                ] else ...[
                  label('Username or email'),
                  field0(
                    _user,
                    'username or @you:server',
                    hints: const [AutofillHints.username],
                    enabled: !_busy,
                    keyboard: TextInputType.emailAddress,
                  ),
                  label(
                    'Password',
                    trailing: GestureDetector(
                      onTap: () => launchUrlString(
                        'https://app.element.io/#/forgot_password',
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text(
                        'Forgot?',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: blurple,
                        ),
                      ),
                    ),
                  ),
                  field0(
                    _pass,
                    'Your password',
                    hints: const [AutofillHints.password],
                    obscure: !_showPass,
                    enabled: !_busy,
                    action: TextInputAction.done,
                    onSubmitted: (_) => _signIn(),
                    suffix: eye(
                      _showPass,
                      () => setState(() => _showPass = !_showPass),
                    ),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error,
                      style: const TextStyle(color: danger, fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 22),
                if (_creating)
                  primary(
                    'Create account',
                    suBusy ? null : suSubmit,
                    busy: suBusy ? (suStatus ?? 'Please wait…') : null,
                  )
                else
                  primary(
                    'Log in',
                    _busy ? null : _signIn,
                    busy: _busy ? 'Logging in…' : null,
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _google,
                    icon: const Text(
                      'G',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4285F4),
                      ),
                    ),
                    label: Text(
                      'Continue with Google',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: text,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: muted.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (!_creating)
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : () => _web(signUp: false),
                      child: Text(
                        'Use the server\'s login page',
                        style: TextStyle(fontSize: 13.5, color: muted),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            _creating = !_creating;
                            _error = null;
                            suError = null;
                          }),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: _creating
                                ? 'Already have an account? '
                                : 'New to Vibe? ',
                            style: TextStyle(color: muted),
                          ),
                          TextSpan(
                            text: _creating ? 'Log in' : 'Create an account',
                            style: TextStyle(
                              color: blurple,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 14.5),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => PlatformInfos.showDialog(context),
                      child: Text(
                        'About',
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ),
                    Text('·', style: TextStyle(color: muted)),
                    TextButton(
                      onPressed: _busy ? null : () => restoreBackupFlow(context),
                      child: Text(
                        'Restore backup',
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

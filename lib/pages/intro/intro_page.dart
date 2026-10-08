// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/intro/flows/restore_backup_flow.dart';
import 'package:fluffychat/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/sign_in_flows/check_homeserver.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Vibe sign-in screen (matches the web app): username + password, or the
/// matrix.org web login, plus create account.
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

class _IntroPageState extends State<IntroPage> {
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  bool _showPass = false;
  bool _busy = false;
  String? _error;
  late String _homeserver = _initialHomeserver();

  static String _initialHomeserver() {
    final preset = AppSettings.presetHomeserver.value;
    final def = AppSettings.defaultHomeserver.value;
    final raw = preset.isNotEmpty ? preset : (def.isNotEmpty ? def : 'matrix.org');
    return raw.startsWith('http') ? raw : 'https://$raw';
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

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
      if (mounted) context.go('/backup');
    } on MatrixException catch (e) {
      if (mounted) setState(() => _error = e.errorMessage);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    (name: 'matrix.org', note: 'Default · free 10 MB files'),
    (name: 'mozilla.org', note: 'Mozilla · sign in with a Mozilla account'),
    (name: '4d2.org', note: 'Community · 150 MiB files'),
    (name: 'tchncs.de', note: 'Community · Germany'),
  ];

  Future<void> _editHomeserver() async {
    final ctrl = TextEditingController();
    final current = Uri.tryParse(_homeserver)?.host ?? _homeserver;
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(
                      'Choose a server',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      'Your account lives on this server. People on any '
                      'server can chat with each other.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                  for (final s in _quickServers)
                    ListTile(
                      leading: Icon(
                        s.name == current
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: s.name == current ? cs.primary : null,
                      ),
                      title: Text(
                        s.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(s.note),
                      onTap: () => Navigator.pop(ctx, s.name),
                    ),
                  ListTile(
                    leading: const Icon(Icons.public),
                    title: const Text(
                      'Browse all public servers',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Full list with details'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(ctx, 'vibe:browse'),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                      decoration: InputDecoration(
                        labelText: 'Other / self-hosted server',
                        hintText: 'example.com',
                        prefixIcon: const Icon(Icons.dns_outlined),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF313338) : const Color(0xFFF2F3F5);
    final card = dark ? const Color(0xFF2B2D31) : Colors.white;
    final border = dark ? const Color(0xFF3F4147) : const Color(0xFFD4D7DC);
    final field = dark ? const Color(0xFF1E1F22) : const Color(0xFFE3E5E8);
    final text = dark ? const Color(0xFFF2F3F5) : const Color(0xFF1E1F22);
    final muted = dark ? const Color(0xFFB5BAC1) : const Color(0xFF5C5E66);
    const blurple = Color(0xFF5865F2);
    const link = Color(0xFF8C96F6);

    if (widget.isLoading) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: blurple),
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

    InputDecoration deco(String hint, IconData icon, {Widget? suffix}) =>
        InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: muted.withValues(alpha: 0.8)),
          prefixIcon: Icon(icon, color: muted, size: 22),
          suffixIcon: suffix,
          filled: true,
          fillColor: field,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: blurple, width: 1.5),
          ),
        );

    Widget label(String t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Text(
            t,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: muted,
            ),
          ),
          const Text(
            ' *',
            style: TextStyle(color: Color(0xFFF23F42), fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: blurple.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: blurple.withValues(alpha: 0.45),
                          ),
                        ),
                        child: const Icon(
                          Icons.sensors,
                          size: 42,
                          color: Color(0xFF8C96F6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Welcome back!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "We're so excited to see you again!",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: muted),
                    ),
                    const SizedBox(height: 26),
                    label('ACCOUNT / USERNAME'),
                    TextField(
                      controller: _user,
                      enabled: !_busy,
                      autocorrect: false,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: text, fontSize: 16),
                      decoration: deco(
                        'username or @user:matrix.org',
                        Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 14),
                    label(
                      'PASSWORD',
                      trailing: GestureDetector(
                        onTap: () => launchUrlString(
                          'https://app.element.io/#/forgot_password',
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: link,
                          ),
                        ),
                      ),
                    ),
                    TextField(
                      controller: _pass,
                      enabled: !_busy,
                      obscureText: !_showPass,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _signIn(),
                      style: TextStyle(color: text, fontSize: 16),
                      decoration: deco(
                        'Enter your password',
                        Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(
                            _showPass
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: muted,
                          ),
                          onPressed: () =>
                              setState(() => _showPass = !_showPass),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFF23F42),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed: _busy ? null : _signIn,
                        style: FilledButton.styleFrom(
                          backgroundColor: blurple,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: blurple.withValues(
                            alpha: 0.55,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Sign In'),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward, size: 20),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(child: Divider(color: border)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: muted,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: border)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 54,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _web(signUp: false),
                        icon: const Icon(
                          Icons.open_in_new,
                          size: 20,
                          color: link,
                        ),
                        label: Text(
                          'Log in with ${Uri.tryParse(_homeserver)?.host.isNotEmpty == true ? _prettyHost(_homeserver) : 'Matrix.org'}',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: text,
                          backgroundColor: field,
                          side: BorderSide(color: border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: TextButton(
                        onPressed: _busy ? null : () => _web(signUp: true),
                        child: const Text(
                          'Create account',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: link,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _busy ? null : _editHomeserver,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.circle, size: 9, color: blurple),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Server: ${_prettyHost(_homeserver)} · Change',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: link,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => PlatformInfos.showDialog(context),
                          child: const Text(
                            'About Vibe',
                            style: TextStyle(fontSize: 15, color: link),
                          ),
                        ),
                        Text('•', style: TextStyle(color: muted)),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => restoreBackupFlow(context),
                          child: Text(
                            'Restore backup',
                            style: TextStyle(fontSize: 15, color: muted),
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
      ),
    );
  }

  static String _prettyHost(String url) {
    final h = Uri.parse(url).host;
    if (h.isEmpty) return 'Matrix.org';
    return h == 'matrix.org' ? 'Matrix.org' : h;
  }
}

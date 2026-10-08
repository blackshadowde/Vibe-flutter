// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

/// In-app account creation for servers that use classic Matrix sign-up
/// (username + password + steps like email, terms, captcha, invite token).
/// Unknown steps open the server's own fallback page in the in-app browser.
class VibeSignUpPage extends StatefulWidget {
  final Client client;
  final String homeserver; // e.g. https://matrix.unredacted.org
  const VibeSignUpPage({
    required this.client,
    required this.homeserver,
    super.key,
  });

  @override
  State<VibeSignUpPage> createState() => _VibeSignUpPageState();
}

class _VibeSignUpPageState extends State<VibeSignUpPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;
  bool _showPass = false;
  String? _error;
  String? _status;

  static const _registrationToken = 'm.login.registration_token';
  static const _terms = 'm.login.terms';

  /// Steps Vibe can do itself (others go to the web fallback).
  static const _native = {
    AuthenticationTypes.dummy,
    AuthenticationTypes.emailIdentity,
    _terms,
    _registrationToken,
  };

  String get _host => Uri.tryParse(widget.homeserver)?.host ?? widget.homeserver;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _pass2.dispose();
    _email.dispose();
    super.dispose();
  }

  void _say(String? s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _submit() async {
    final username = _user.text.trim().toLowerCase().replaceFirst('@', '');
    final password = _pass.text;
    setState(() {
      _error = null;
      _status = null;
    });
    if (!RegExp(r'^[a-z0-9._=\-/]+$').hasMatch(username)) {
      setState(
        () => _error =
            'Username can use only a–z, 0–9 and . _ - = /',
      );
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (password != _pass2.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() => _busy = true);
    final client = widget.client;
    try {
      _say('Checking username…');
      try {
        final free = await client.checkUsernameAvailability(username);
        if (free == false) {
          throw _Friendly('@$username:$_host is already taken');
        }
      } on MatrixException catch (e) {
        if (e.errcode == 'M_USER_IN_USE') {
          throw _Friendly('@$username:$_host is already taken');
        }
        if (e.errcode == 'M_INVALID_USERNAME') {
          throw _Friendly('That username is not allowed here');
        }
        // Other errors: let register() report them.
      }

      final clientSecret = _secret();
      var sendAttempt = 0;
      String? emailSid;
      AuthenticationData? auth;
      String? lastStage;
      var sameStageCount = 0;

      while (true) {
        _say('Creating account…');
        try {
          await client.register(
            username: username,
            password: password,
            initialDeviceDisplayName: PlatformInfos.appDisplayName,
            auth: auth,
          );
          break; // success, logged in
        } on MatrixException catch (e) {
          final session = e.session;
          final flows = e.authenticationFlows;
          if (session == null || flows == null) {
            if (e.errcode == 'M_FORBIDDEN') {
              throw _Friendly(
                '$_host does not allow sign-up from apps. Create the '
                'account on their website, then sign in here.',
              );
            }
            rethrow;
          }
          final completed = e.completedAuthenticationFlows;
          final params = e.authenticationParams ?? const {};
          final stage = _nextStage(flows, completed);
          if (stage == null) {
            throw _Friendly(e.errorMessage);
          }
          if (stage == lastStage) {
            sameStageCount++;
          } else {
            sameStageCount = 0;
            lastStage = stage;
          }
          if (sameStageCount >= 4) {
            throw _Friendly('Sign-up step "$stage" did not complete.');
          }
          if (!mounted) return;

          switch (stage) {
            case AuthenticationTypes.dummy:
              auth = AuthenticationData(
                type: AuthenticationTypes.dummy,
                session: session,
              );
            case _terms:
              final ok = await _askTerms(params[_terms]);
              if (!ok) throw _Friendly('You need to accept the terms.');
              auth = AuthenticationData(type: _terms, session: session);
            case _registrationToken:
              final token = await _askText(
                'Invite token',
                'This server needs an invite / registration token.',
              );
              if (token == null || token.isEmpty) {
                throw _Friendly('An invite token is needed for $_host.');
              }
              auth = AuthenticationData(
                type: _registrationToken,
                session: session,
                additionalFields: {'token': token},
              );
            case AuthenticationTypes.emailIdentity:
              if (emailSid == null || sameStageCount > 0) {
                var email = _email.text.trim();
                if (email.isEmpty) {
                  email =
                      await _askText(
                        'Email',
                        '$_host needs an email to confirm your account.',
                        keyboard: TextInputType.emailAddress,
                      ) ??
                      '';
                  _email.text = email;
                }
                if (email.isEmpty) throw _Friendly('Email is required.');
                if (emailSid == null) {
                  _say('Sending confirmation email…');
                  sendAttempt++;
                  final res = await client.requestTokenToRegisterEmail(
                    clientSecret,
                    email,
                    sendAttempt,
                  );
                  emailSid = res.sid;
                }
              }
              final done = await _waitForEmail(_email.text.trim());
              if (!done) throw _Friendly('Sign-up cancelled.');
              auth = AuthenticationThreePidCreds(
                type: AuthenticationTypes.emailIdentity,
                session: session,
                threepidCreds: ThreepidCreds(
                  sid: emailSid!,
                  clientSecret: clientSecret,
                ),
              );
            default:
              // Captcha and anything else: the server's own web page.
              final ok = await _webStep(stage, session, params);
              if (!ok) throw _Friendly('Sign-up cancelled.');
              auth = AuthenticationData(session: session);
          }
        }
      }

      if (!mounted) return;
      _say(null);
      context.go('/backup');
    } on _Friendly catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on MatrixException catch (e) {
      if (mounted) setState(() => _error = e.errorMessage);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  /// Pick the next stage. Prefer a flow Vibe can complete natively.
  String? _nextStage(List<AuthenticationFlow> flows, List<String> completed) {
    final candidates = flows.where(
      (f) =>
          f.stages.length > completed.length &&
          f.stages.take(completed.length).toSet().containsAll(completed),
    );
    if (candidates.isEmpty) return null;
    final sorted = candidates.toList()
      ..sort((a, b) {
        int unsupported(AuthenticationFlow f) =>
            f.stages.where((s) => !_native.contains(s)).length;
        final c = unsupported(a).compareTo(unsupported(b));
        return c != 0 ? c : a.stages.length.compareTo(b.stages.length);
      });
    return sorted.first.stages[completed.length];
  }

  static String _secret() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<bool> _askTerms(Object? termsParams) async {
    final links = <({String name, String url})>[];
    if (termsParams is Map) {
      final policies = termsParams['policies'];
      if (policies is Map) {
        for (final p in policies.values) {
          if (p is! Map) continue;
          final lang = (p['en'] ?? p.values.whereType<Map>().firstOrNull);
          if (lang is Map && lang['url'] is String) {
            links.add((
              name: (lang['name'] as String?) ?? 'Terms',
              url: lang['url'] as String,
            ));
          }
        }
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$_host terms'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please read and accept the server\'s policies:'),
            const SizedBox(height: 8),
            for (final l in links)
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(l.name),
                onPressed: () => launchUrl(
                  Uri.parse(l.url),
                  mode: LaunchMode.inAppBrowserView,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('I agree'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<String?> _askText(
    String title,
    String message, {
    TextInputType keyboard = TextInputType.text,
  }) async {
    final ctrl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: keyboard,
              autocorrect: false,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return v;
  }

  Future<bool> _waitForEmail(String email) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.mark_email_unread_outlined, size: 36),
        title: const Text('Check your email'),
        content: Text(
          'We sent a link to $email.\n\nOpen it, tap the confirm link, '
          'then come back and tap Continue. Check spam if you don\'t see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('I confirmed — Continue'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<bool> _webStep(
    String stage,
    String session,
    Map<String, Object?> params,
  ) async {
    final stageParams = params[stage];
    final stageUrl = stageParams is Map ? stageParams['url'] : null;
    final url = stageUrl is String
        ? Uri.parse(stageUrl)
        : widget.client.homeserver!.replace(
            path: '/_matrix/client/v3/auth/$stage/fallback/web',
            queryParameters: {'session': session},
          );
    await launchUrl(url, mode: LaunchMode.inAppBrowserView);
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('One more step'),
        content: Text(
          stage == AuthenticationTypes.recaptcha
              ? 'Solve the captcha on the page that opened, then come back '
                    'and tap Continue.'
              : 'Finish the step on the page that opened ($stage), then '
                    'come back and tap Continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                launchUrl(url, mode: LaunchMode.inAppBrowserView),
            child: const Text('Open again'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    InputDecoration deco(String label, IconData icon, {Widget? suffix}) =>
        InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: suffix,
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'on $_host',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _user,
              enabled: !_busy,
              autocorrect: false,
              decoration: deco(
                'Username',
                Icons.alternate_email,
              ).copyWith(helperText: 'Your address: @username:$_host'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pass,
              enabled: !_busy,
              obscureText: !_showPass,
              decoration: deco(
                'Password',
                Icons.lock_outline,
                suffix: IconButton(
                  icon: Icon(
                    _showPass ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pass2,
              enabled: !_busy,
              obscureText: !_showPass,
              decoration: deco('Repeat password', Icons.lock_outline),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: deco(
                'Email (if the server asks)',
                Icons.mail_outline,
              ),
            ),
            const SizedBox(height: 22),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: cs.error)),
              ),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5865F2),
                  foregroundColor: Colors.white,
                ),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(_status ?? 'Please wait…'),
                        ],
                      )
                    : const Text(
                        'Create account',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your account and messages live on $_host. Pick a strong '
              'password — it can\'t be recovered without the email.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Friendly implements Exception {
  final String message;
  _Friendly(this.message);
}

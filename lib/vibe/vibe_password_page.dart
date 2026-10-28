// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/localized_exception_extension.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Change your password: the current one, then the new one twice.
class VibePasswordPage extends StatefulWidget {
  const VibePasswordPage({super.key});

  @override
  State<VibePasswordPage> createState() => _VibePasswordPageState();
}

class _VibePasswordPageState extends State<VibePasswordPage> {
  final _old = TextEditingController();
  final _new1 = TextEditingController();
  final _new2 = TextEditingController();
  String? _oldError, _new1Error, _new2Error;
  bool _loading = false;

  @override
  void dispose() {
    _old.dispose();
    _new1.dispose();
    _new2.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _oldError = _new1Error = _new2Error = null);
    if (_old.text.isEmpty) {
      setState(() => _oldError = l10n.pleaseEnterYourPassword);
      return;
    }
    if (_new1.text.length < 6) {
      setState(() => _new1Error = l10n.pleaseChooseAStrongPassword);
      return;
    }
    if (_new1.text != _new2.text) {
      setState(() => _new2Error = l10n.passwordsDoNotMatch);
      return;
    }
    setState(() => _loading = true);
    try {
      await Matrix.of(context).client.changePassword(
        _new1.text,
        oldPassword: _old.text,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.passwordHasBeenChanged)),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _new2Error = e.toLocalizedString(
          context,
          ExceptionContext.changePassword,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon,
    String? error, {
    bool autofocus = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      obscureText: true,
      autocorrect: false,
      autofocus: autofocus,
      readOnly: _loading,
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        labelText: label,
        errorText: error,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.changePassword)),
      body: MaxWidthBody(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                _old,
                l10n.pleaseEnterYourCurrentPassword,
                Icons.lock_outlined,
                _oldError,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              _field(_new1, l10n.newPassword, Icons.lock_reset_outlined, _new1Error),
              _field(_new2, l10n.repeatPassword, Icons.repeat_outlined, _new2Error),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _loading ? null : _change,
                child: _loading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.changePassword),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go('/rooms/settings/security/3pid'),
                child: Text(
                  l10n.passwordRecoverySettings,
                  style: TextStyle(color: VibeSettingsStyle.text2(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

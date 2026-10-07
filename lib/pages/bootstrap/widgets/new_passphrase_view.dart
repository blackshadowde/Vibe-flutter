// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/bootstrap/view_model/bootstrap_view_model.dart';
import 'package:fluffychat/vibe/vibe_security_ui.dart';
import 'package:flutter/material.dart';

class NewPassphraseView extends StatelessWidget {
  final BootstrapViewModel viewModel;

  const NewPassphraseView(this.viewModel, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final v = viewModel.value;
    final checks = [
      (v.newPassphraseEqualsRepeatPassphrase, L10n.of(context).passphrasesMatch),
      (v.newPassphraseLongEnough, L10n.of(context).passphraseLengthRequirement),
      (
        v.newPassphraseUpperAndLowerCase,
        L10n.of(context).passphraseUpperAndLowerCaseRequirement,
      ),
      (
        v.newPassphraseSpecialCharacters,
        L10n.of(context).passphraseSpecialCharactersRequirement,
      ),
      (v.newPassphraseNumbers, L10n.of(context).passphraseNumberRequirement),
    ];
    final met = checks.where((c) => c.$1).length;
    final canCreatePassphrase = met == checks.length;

    Widget eye() => IconButton(
      icon: Icon(
        v.obscureText
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        color: cs.onSurfaceVariant,
      ),
      onPressed: viewModel.toggleObscureText,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        VibeHeader(
          icon: Icons.lock_outline,
          title: 'Protect your messages',
          description: L10n.of(context).newPassphraseDescription,
        ),
        const VibeSectionLabel('Passphrase'),
        TextField(
          obscureText: v.obscureText,
          readOnly: v.isLoading,
          controller: viewModel.newPassphraseController,
          decoration: vibeFieldDecoration(
            context,
            hint: L10n.of(context).newPassphrase,
            suffix: eye(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          obscureText: v.obscureText,
          readOnly: v.isLoading,
          controller: viewModel.repeatPassphraseController,
          decoration: vibeFieldDecoration(
            context,
            hint: L10n.of(context).repeatPassphrase,
          ),
        ),
        const SizedBox(height: 20),
        VibeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < checks.length; i++) ...[
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: i < met ? cs.primary : cs.outlineVariant,
                        ),
                      ),
                    ),
                    if (i < checks.length - 1) const SizedBox(width: 6),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '$met of ${checks.length} requirements met',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              for (final c in checks) _Requirement(checked: c.$1, label: c.$2),
            ],
          ),
        ),
        const SizedBox(height: 20),
        VibeButton(
          label: L10n.of(context).continueText,
          loading: v.isLoading,
          onPressed: canCreatePassphrase
              ? () => viewModel.setOrSkipPassphrase(
                  viewModel.newPassphraseController.text,
                  context,
                )
              : null,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: v.isLoading
              ? null
              : () => viewModel.setOrSkipPassphrase(null, context),
          style: TextButton.styleFrom(
            foregroundColor: cs.onSurfaceVariant,
            minimumSize: const Size.fromHeight(44),
          ),
          child: Text(L10n.of(context).skip),
        ),
      ],
    );
  }
}

class _Requirement extends StatelessWidget {
  final String label;
  final bool checked;
  const _Requirement({required this.label, required this.checked});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Icon(
              checked ? Icons.check_circle : Icons.radio_button_unchecked,
              key: ValueKey(checked),
              size: 20,
              color: checked ? cs.primary : cs.outline,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: checked ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

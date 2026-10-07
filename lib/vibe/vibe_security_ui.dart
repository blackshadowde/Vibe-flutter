// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Shared building blocks for the Vibe passphrase / backup / verification UI.

/// Big round icon with a soft blurple halo.
class VibeHeroIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  const VibeHeroIcon(this.icon, {this.size = 88, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size + 28,
      height: size + 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.primary.withAlpha(28),
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary),
        child: Icon(icon, size: size * 0.46, color: cs.onPrimary),
      ),
    );
  }
}

/// Centered title + gray description under a hero icon.
class VibeHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  const VibeHeader({
    required this.icon,
    required this.title,
    this.description,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 8),
        VibeHeroIcon(icon),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(
            description!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}

class VibeCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const VibeCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class VibeSectionLabel extends StatelessWidget {
  final String text;
  const VibeSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Full-width blurple button.
class VibeButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool destructive;
  final bool tonal;
  const VibeButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.destructive = false,
    this.tonal = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = tonal
        ? cs.surfaceContainerHighest
        : destructive
        ? cs.error
        : cs.primary;
    final fg = tonal
        ? (destructive ? cs.error : cs.onSurface)
        : (destructive ? cs.onError : cs.onPrimary);
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: cs.surfaceContainerHighest,
          disabledForegroundColor: cs.onSurfaceVariant.withAlpha(150),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: loading
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
            : Text(label),
      ),
    );
  }
}

InputDecoration vibeFieldDecoration(
  BuildContext context, {
  required String hint,
  Widget? prefix,
  Widget? suffix,
  String? errorText,
}) {
  final cs = Theme.of(context).colorScheme;
  OutlineInputBorder border(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: c, width: 1.5),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: cs.onSurfaceVariant),
    prefixIcon: prefix,
    suffixIcon: suffix,
    errorText: errorText,
    errorMaxLines: 4,
    filled: true,
    fillColor: cs.surfaceContainerLowest,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: border(Colors.transparent),
    enabledBorder: border(Colors.transparent),
    focusedBorder: border(cs.primary),
    errorBorder: border(cs.error),
    focusedErrorBorder: border(cs.error),
  );
}

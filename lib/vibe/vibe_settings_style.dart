// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Vibgram's Discord-style settings look, shared by Settings and every page
/// under it: a soft grey page, rounded cards a shade lighter, grey section
/// titles inside the cards, filled white (dark) / black (light) icons.
abstract class VibeSettingsStyle {
  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color page(BuildContext context) =>
      _dark(context) ? const Color(0xFF252429) : const Color(0xFFF2F3F5);

  static Color card(BuildContext context) =>
      _dark(context) ? const Color(0xFF2E2D32) : const Color(0xFFFFFFFF);

  static Color line(BuildContext context) =>
      _dark(context) ? const Color(0xFF3A393F) : const Color(0xFFE3E5E8);

  static Color text(BuildContext context) =>
      _dark(context) ? const Color(0xFFF2F3F5) : const Color(0xFF060607);

  static Color text2(BuildContext context) =>
      _dark(context) ? const Color(0xFFB5BAC1) : const Color(0xFF5C5E66);
}

/// Wraps a settings page: page colour behind everything, header bar in the
/// same colour (also while scrolling), grey section titles, no tinting.
class VibeSettingsTheme extends StatelessWidget {
  final Widget child;
  const VibeSettingsTheme({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = VibeSettingsStyle.page(context);
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: page,
        canvasColor: page,
        colorScheme: theme.colorScheme.copyWith(
          // FluffyChat colours section titles with "secondary": Vibgram's are grey.
          secondary: VibeSettingsStyle.text2(context),
        ),
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: page,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
        ),
        dividerTheme: theme.dividerTheme.copyWith(
          color: VibeSettingsStyle.line(context),
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          iconColor: VibeSettingsStyle.text(context),
          tileColor: Colors.transparent,
        ),
      ),
      child: child,
    );
  }
}

/// Drop-in for a settings Column: every run of rows between two [Divider]s
/// becomes one rounded card (Vibgram style). The dividers themselves go away.
class VibeGroups extends StatelessWidget {
  final List<Widget> children;
  const VibeGroups({required this.children, super.key});

  @override
  Widget build(BuildContext context) {
    final groups = <List<Widget>>[[]];
    for (final c in children) {
      if (c is Divider) {
        if (groups.last.isNotEmpty) groups.add([]);
      } else {
        groups.last.add(c);
      }
    }
    if (groups.last.isEmpty) groups.removeLast();
    return Column(
      children: [
        const SizedBox(height: 6),
        for (final g in groups)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            decoration: BoxDecoration(
              color: VibeSettingsStyle.card(context),
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: g,
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// One row in a Vibgram-style settings card: filled icon, title, optional
/// value on the right, chevron.
class VibeSettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final Color? valueColor;
  final Color? color;
  final VoidCallback onTap;
  final bool last;

  const VibeSettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.valueColor,
    this.color,
    this.last = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final text = color ?? VibeSettingsStyle.text(context);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 54,
        child: Stack(
          children: [
            // Fill the row so icon, title and chevron sit in the middle,
            // with the divider at the bottom edge.
            Positioned.fill(
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(width: 16),
                Icon(icon, size: 24, color: text),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, color: text),
                  ),
                ),
                if (value != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      value!,
                      style: TextStyle(
                        fontSize: 15,
                        color: valueColor ?? VibeSettingsStyle.text2(context),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: VibeSettingsStyle.text2(context),
                ),
                const SizedBox(width: 12),
              ],
              ),
            ),
            if (!last)
              Positioned(
                left: 58,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 0.7,
                  color: VibeSettingsStyle.line(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A Vibgram-style settings group: grey title above a rounded card of rows.
class VibeSettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const VibeSettingsGroup({required this.title, required this.rows, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              color: VibeSettingsStyle.text2(context),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: VibeSettingsStyle.card(context),
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Column(children: rows),
          ),
        ),
      ],
    );
  }
}

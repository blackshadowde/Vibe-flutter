// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_palette.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:flutter/material.dart';

/// Vibgram's Discord-style settings look, shared by Settings and every page
/// under it: a soft grey page, rounded cards a shade lighter, grey section
/// titles inside the cards, filled white (dark) / black (light) icons.
abstract class VibeSettingsStyle {
  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color page(BuildContext context) => !VibePalette.isVibe
      ? Theme.of(context).colorScheme.surface
      : _dark(context) ? const Color(0xFF1C1B20) : const Color(0xFFFFFFFF);

  static Color card(BuildContext context) => !VibePalette.isVibe
      ? Theme.of(context).colorScheme.surfaceContainer
      : _dark(context) ? const Color(0xFF26252B) : const Color(0xFFF2F3F5);

  static Color line(BuildContext context) => !VibePalette.isVibe
      ? Theme.of(context).colorScheme.outlineVariant
      : _dark(context) ? const Color(0xFF33323A) : const Color(0xFFE1E2E6);

  static Color get accent => VibePalette.accent;

  /// Row text inside settings cards. Built on the app's text theme so it
  /// uses the app font (a bare TextStyle here fell back to the system font,
  /// because list tiles replace the inherited style instead of merging).
  static TextStyle rowTitle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
        fontSize: 15.5,
        fontWeight: FontWeight.w500,
        color: text(context),
        height: 1.25,
        letterSpacing: 0,
      );

  static TextStyle rowSubtitle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: 13,
        color: text2(context),
        height: 1.3,
        letterSpacing: 0,
      );

  /// Compact list rows for every settings card.
  static ListTileThemeData listTiles(BuildContext context) =>
      ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 11,
        minTileHeight: 52,
        horizontalTitleGap: 14,
        iconColor: text(context),
        titleTextStyle: rowTitle(context),
        subtitleTextStyle: rowSubtitle(context),
        visualDensity: const VisualDensity(vertical: -1),
      );

  /// Slim Discord-style switch colours for any Material [Switch] left over.
  static SwitchThemeData switches(BuildContext context) {
    final dark = _dark(context);
    return SwitchThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      thumbIcon: const WidgetStatePropertyAll(null),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.white
            : (dark ? const Color(0xFFDBDEE1) : const Color(0xFF80848E)),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? accent
            : !VibePalette.isVibe
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : (dark ? const Color(0xFF4E5058) : const Color(0xFFE3E5E8)),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      trackOutlineWidth: const WidgetStatePropertyAll(0),
    );
  }

  static Color text(BuildContext context) => !VibePalette.isVibe
      ? Theme.of(context).colorScheme.onSurface
      : _dark(context) ? const Color(0xFFF2F3F5) : const Color(0xFF060607);

  static Color text2(BuildContext context) => !VibePalette.isVibe
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : _dark(context) ? const Color(0xFFB5BAC1) : const Color(0xFF5C5E66);
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
        listTileTheme: VibeSettingsStyle.listTiles(context),
        switchTheme: VibeSettingsStyle.switches(context),
      ),
      child: child,
    );
  }
}

/// Drop-in for a settings Column: every run of rows between two [Divider]s
/// becomes one rounded card (Discord style), with a thin line between rows.
/// A bold header row at the start of a run (FluffyChat's section titles)
/// becomes a plain grey label above its card.
class VibeGroups extends StatelessWidget {
  final List<Widget> children;
  const VibeGroups({required this.children, super.key});

  /// FluffyChat's section title: a ListTile with only a bold title.
  static String? _headerText(Widget w) {
    if (w is! ListTile) return null;
    if (w.onTap != null ||
        w.subtitle != null ||
        w.leading != null ||
        w.trailing != null) {
      return null;
    }
    final t = w.title;
    if (t is Text && t.style?.fontWeight == FontWeight.bold) return t.data;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final groups = <({String? title, List<Widget> rows})>[];
    String? title;
    var rows = <Widget>[];
    void flush() {
      if (rows.isNotEmpty || title != null) {
        groups.add((title: title, rows: rows));
      }
      title = null;
      rows = [];
    }

    for (final c in children) {
      if (c is Divider) {
        flush();
        continue;
      }
      final h = _headerText(c);
      if (h != null && rows.isEmpty) {
        title = h;
        continue;
      }
      rows.add(c);
    }
    flush();
    return ListTileTheme.merge(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 11,
      minTileHeight: 52,
      titleTextStyle: VibeSettingsStyle.rowTitle(context),
      subtitleTextStyle: VibeSettingsStyle.rowSubtitle(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          for (final g in groups) ...[
            if (g.title != null) VibeSectionLabel(g.title!),
            if (g.rows.isNotEmpty) VibeCard(children: g.rows),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Plain grey section title above a card ("Theme", "Account Information").
class VibeSectionLabel extends StatelessWidget {
  final String text;
  const VibeSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
        color: VibeSettingsStyle.text2(context),
      ),
    ),
  );
}

/// Rounded grey card holding rows, with a thin inset line between them.
class VibeCard extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  const VibeCard({
    required this.children,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 6),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final line = VibeSettingsStyle.line(context);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: VibeSettingsStyle.card(context),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Container(height: 0.6, color: line),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Slim Discord-style toggle: blurple pill with a white knob when on.
class VibeSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const VibeSwitch({required this.value, this.onChanged, super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onChanged != null;
    final track = value
        ? VibeSettingsStyle.accent
        : !VibePalette.isVibe
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : (dark ? const Color(0xFF4E5058) : const Color(0xFFDADCE0));
    final knob = value || dark ? Colors.white : const Color(0xFF80848E);
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 44,
            height: 26,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(13),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: knob,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 2),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings row with a [VibeSwitch]; tap anywhere on the row to toggle.
class VibeSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  const VibeSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    leading: icon == null ? null : Icon(icon, size: 22),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: VibeSwitch(value: value, onChanged: onChanged),
    onTap: onChanged == null ? null : () => onChanged!(!value),
  );
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
    return VibePressable(
      child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Stack(
          children: [
            // Fill the row so icon, title and chevron sit in the middle,
            // with the divider at the bottom edge.
            Positioned.fill(
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(width: 16),
                Icon(icon, size: 22, color: text),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                      color: text,
                    ),
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
                const SizedBox(width: 12),
              ],
              ),
            ),
            if (!last)
              Positioned(
                left: 54,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 0.6,
                  color: VibeSettingsStyle.line(context),
                ),
              ),
          ],
        ),
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
        VibeSectionLabel(title),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: VibeSettingsStyle.card(context),
            borderRadius: BorderRadius.circular(16),
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

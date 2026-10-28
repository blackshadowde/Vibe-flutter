// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_motion.dart';
import 'package:flutter/material.dart';

/// Every question / dialog in Vibe is a pane that slides up from the bottom
/// and slides down (like Vibe X), instead of a box popping up in the middle.
///
/// Drop-in for showDialog / showAdaptiveDialog: an AlertDialog, SimpleDialog
/// or Dialog from [builder] is laid out as a pane; anything else (a full
/// screen photo viewer, say) still opens the old way.
Future<T?> showVibeDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  bool useSafeArea = true,
}) {
  final probe = _unwrap(builder(context));
  final full = probe is Dialog && probe.insetPadding == EdgeInsets.zero;
  if (full ||
      (probe is! AlertDialog && probe is! SimpleDialog && probe is! Dialog)) {
    return showDialog<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      useSafeArea: useSafeArea,
    );
  }
  return showVibeSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
    builder: (ctx) => PopScope(
      canPop: barrierDismissible,
      child: _DialogPane(dialog: _unwrap(builder(ctx))),
    ),
  );
}

/// Looks through simple wrappers around the dialog (a size limit, a back
/// handler that allows going back).
Widget _unwrap(Widget w) {
  for (var i = 0; i < 4; i++) {
    if (w is ConstrainedBox && w.child != null) {
      w = w.child!;
    } else if (w is PopScope && w.canPop) {
      w = w.child;
    } else {
      break;
    }
  }
  return w;
}

class _DialogPane extends StatelessWidget {
  final Widget dialog;
  const _DialogPane({required this.dialog});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final d = dialog;
    Widget? icon, title, content;
    List<Widget>? actions;
    if (d is AlertDialog) {
      icon = d.icon;
      title = d.title;
      content = d.content;
      actions = d.actions;
    } else if (d is SimpleDialog) {
      title = d.title;
      content = d.children == null
          ? null
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: d.children!,
              ),
            );
    } else if (d is Dialog) {
      content = d.child;
    }
    final maxH = MediaQuery.sizeOf(context).height * 0.85;
    return Padding(
      // the keyboard pushes the pane up
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (icon != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: IconTheme.merge(
                      data: IconThemeData(color: cs.primary, size: 28),
                      child: Align(alignment: Alignment.centerLeft, child: icon),
                    ),
                  ),
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                      child: title,
                    ),
                  ),
                if (content != null)
                  Flexible(
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: cs.onSurfaceVariant,
                      ),
                      child: content,
                    ),
                  ),
                if (actions != null && actions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    // On iOS, AdaptiveDialogAction builds a CupertinoDialogAction,
                    // which only reacts to taps inside a CupertinoAlertDialog.
                    // In this pane it ignored every tap (OK / Cancel / Yes / No
                    // did nothing). Material buttons work anywhere, and on
                    // Android this changes nothing (already Material).
                    child: Theme(
                      data: theme.copyWith(platform: TargetPlatform.android),
                      child: OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 8,
                        overflowAlignment: OverflowBarAlignment.end,
                        children: actions,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Drop-in for PopupMenuButton: the menu slides up from the bottom.
class VibeMenuButton<T> extends StatelessWidget {
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final VoidCallback? onCanceled;
  final Widget? icon;
  final Widget? child;
  final String? tooltip;
  final bool enabled;
  final bool useRootNavigator;
  final Color? iconColor;
  final double? iconSize;

  const VibeMenuButton({
    required this.itemBuilder,
    this.onSelected,
    this.onCanceled,
    this.icon,
    this.child,
    this.tooltip,
    this.enabled = true,
    this.useRootNavigator = true,
    this.iconColor,
    this.iconSize,
    super.key,
  });

  Future<void> _open(BuildContext context) async {
    final v = await showVibeMenu<T>(
      context: context,
      items: itemBuilder(context),
      useRootNavigator: useRootNavigator,
    );
    if (v == null) {
      onCanceled?.call();
    } else {
      onSelected?.call(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = child;
    if (c != null) {
      return Tooltip(
        message: tooltip ?? '',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? () => _open(context) : null,
          child: c,
        ),
      );
    }
    return IconButton(
      tooltip: tooltip,
      color: iconColor,
      iconSize: iconSize,
      icon: icon ?? const Icon(Icons.more_vert),
      onPressed: enabled ? () => _open(context) : null,
    );
  }
}

/// Drop-in for showMenu: the items in a pane from the bottom. [position]
/// is accepted and ignored.
Future<T?> showVibeMenu<T>({
  required BuildContext context,
  required List<PopupMenuEntry<T>> items,
  RelativeRect? position,
  bool useRootNavigator = true,
}) {
  return showVibeSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in items)
                  if (e is PopupMenuItem<T>)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: e.enabled
                          ? () {
                              Navigator.of(ctx).pop(e.value);
                              e.onTap?.call();
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        child: Opacity(
                          opacity: e.enabled ? 1 : 0.4,
                          child: IconTheme.merge(
                            data: IconThemeData(color: cs.onSurface, size: 22),
                            child: DefaultTextStyle.merge(
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: e.child ?? const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (e is PopupMenuDivider)
                    const Divider(height: 12),
              ],
            ),
          ),
        ),
      );
    },
  );
}

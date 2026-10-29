// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/vibe/vibe_motion.dart';

/// Quote part of a message (Telegram style): drag over the words to answer,
/// tap Quote. The reply is sent with those words as a quote, which every
/// Matrix app shows.
abstract class VibeQuotePicker {
  static const int maxLength = 300;

  static Future<String?> pick(BuildContext context, Event event) {
    final text = event
        .calcUnlocalizedBody(hideReply: true, hideEdit: true, plaintextBody: true)
        .trim();
    return showVibeSheet<String>(
      context: context,
      sheetAnimationStyle: vibeSheetStyle,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _QuotePicker(text: text),
    );
  }

  /// The quote as Markdown above the reply text.
  static String withQuote(String quote, String text) {
    final q = quote.length > maxLength
        ? '${quote.substring(0, maxLength)}…'
        : quote;
    final lines = q.split('\n').map((l) => '> $l').join('\n');
    return '$lines\n\n$text';
  }
}

class _QuotePicker extends StatefulWidget {
  final String text;
  const _QuotePicker({required this.text});

  @override
  State<_QuotePicker> createState() => _QuotePickerState();
}

class _QuotePickerState extends State<_QuotePicker> {
  String _sel = '';

  void _done() {
    if (_sel.isEmpty) return;
    Navigator.of(context).pop(_sel);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quote part',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Drag over the words you want to answer.',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.text,
                  style: const TextStyle(fontSize: 17, height: 1.4),
                  onSelectionChanged: (sel, _) {
                    final s = sel.textInside(widget.text).trim();
                    if (s != _sel) setState(() => _sel = s);
                  },
                  // a small menu: Quote or Copy
                  contextMenuBuilder: (ctx, state) =>
                      AdaptiveTextSelectionToolbar.buttonItems(
                        anchors: state.contextMenuAnchors,
                        buttonItems: [
                          ContextMenuButtonItem(
                            label: 'Quote',
                            onPressed: () {
                              state.hideToolbar();
                              _done();
                            },
                          ),
                          ContextMenuButtonItem(
                            type: ContextMenuButtonType.copy,
                            onPressed: () => state.copySelection(
                              SelectionChangedCause.toolbar,
                            ),
                          ),
                        ],
                      ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _sel.isEmpty ? null : _done,
                icon: const Icon(Icons.format_quote_rounded),
                label: const Text('Quote selected'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

  /// The quoted words of a reply sent with Quote part, or null.
  static String? quoteOf(Event reply) {
    final lines = reply
        .calcUnlocalizedBody(hideReply: true, plaintextBody: true)
        .split('\n');
    final quote = <String>[];
    for (final l in lines) {
      if (!l.startsWith('> ')) break;
      quote.add(l.substring(2));
    }
    return quote.isEmpty ? null : quote.join(' ');
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
  // Words instead of text handles: tap the first and the last word (or
  // slide a finger across them). Starts with everything picked.
  late final List<String> _words = widget.text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  int _start = 0;
  late int _end = _words.length - 1;
  bool _picking = false;
  final _keys = <GlobalKey>[];

  String get _sel => _words.isEmpty
      ? ''
      : _words.sublist(_start, _end + 1).join(' ');

  void _done() {
    if (_sel.isEmpty) return;
    Navigator.of(context).pop(_sel);
  }

  void _tap(int i) {
    setState(() {
      if (!_picking) {
        // first tap: start a new pick at this word
        _start = _end = i;
      } else {
        // second tap: everything between the two words
        final first = _start;
        _start = i < first ? i : first;
        _end = i < first ? first : i;
      }
      _picking = !_picking;
    });
  }

  /// Sliding over the words picks from where the finger went down.
  int? _wordAt(Offset global) {
    for (var i = 0; i < _keys.length; i++) {
      final box = _keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      if (r.inflate(4).contains(global)) return i;
    }
    return null;
  }

  int? _anchor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    while (_keys.length < _words.length) {
      _keys.add(GlobalKey());
    }
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
              'Tap the first and last word, or slide across them.',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: GestureDetector(
                  onPanStart: (d) {
                    final i = _wordAt(d.globalPosition);
                    if (i == null) return;
                    _anchor = i;
                    setState(() {
                      _start = _end = i;
                      _picking = false;
                    });
                  },
                  onPanUpdate: (d) {
                    final a = _anchor;
                    final i = _wordAt(d.globalPosition);
                    if (a == null || i == null) return;
                    setState(() {
                      _start = i < a ? i : a;
                      _end = i < a ? a : i;
                    });
                  },
                  onPanEnd: (_) => _anchor = null,
                  child: Wrap(
                    spacing: 2,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < _words.length; i++)
                        GestureDetector(
                          key: _keys[i],
                          onTap: () => _tap(i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: i >= _start && i <= _end
                                  ? cs.primary.withValues(alpha: 0.35)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _words[i],
                              style: const TextStyle(fontSize: 18),
                            ),
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

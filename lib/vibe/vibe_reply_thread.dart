// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/localized_exception_extension.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_pending_files.dart';
import 'package:vibe/utils/file_selector.dart';
import 'package:cross_file/cross_file.dart';

/// Replying inside a conversation of replies: the messages that reply to
/// each other float above the blurred chat in their own window, with their
/// own text box. Send, and the window goes away; the reply lands in the chat.
abstract class VibeReplyThread {
  static String? _parentId(Event e) =>
      e.inReplyToEventId(includingFallback: false);

  /// True when [event] is part of a reply chain: it answers a message, or a
  /// message (already loaded) answers it.
  static bool isChained(Event event, Timeline timeline) =>
      _parentId(event) != null ||
      timeline.events.any((e) => _parentId(e) == event.eventId);

  /// The whole conversation [event] belongs to, oldest first.
  static Future<List<Event>> _chain(Event event, Timeline timeline) async {
    final ids = <String>{event.eventId};
    final chain = <Event>[event];
    // up: what it replies to, and what that replies to...
    var cur = event;
    for (var i = 0; i < 30; i++) {
      final parent = await cur.getReplyEvent(timeline);
      if (parent == null || !ids.add(parent.eventId)) break;
      chain.add(parent);
      cur = parent;
    }
    // down: loaded messages replying to anything in the conversation
    var added = true;
    while (added) {
      added = false;
      for (final e in timeline.events) {
        final p = _parentId(e);
        if (p != null && ids.contains(p) && ids.add(e.eventId)) {
          chain.add(e);
          added = true;
        }
      }
    }
    chain.removeWhere((e) => e.redacted);
    chain.sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
    return chain;
  }

  static Future<void> show(
    BuildContext context, {
    required Room room,
    required Timeline timeline,
    required Event replyTo,
    String? threadRootEventId,
    String? threadLastEventId,
  }) async {
    VibeHaptics.light();
    final chain = await _chain(replyTo, timeline);
    if (!context.mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.25),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, _, _) => _ReplyWindow(
        room: room,
        chain: chain,
        replyTo: replyTo,
        threadRootEventId: threadRootEventId,
        threadLastEventId: threadLastEventId,
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final t = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: 14 * anim.value,
            sigmaY: 14 * anim.value,
          ),
          child: FadeTransition(
            opacity: t,
            child: ScaleTransition(
              scale: Tween(begin: 0.94, end: 1.0).animate(t),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _ReplyWindow extends StatefulWidget {
  final Room room;
  final List<Event> chain;
  final Event replyTo;
  final String? threadRootEventId;
  final String? threadLastEventId;
  const _ReplyWindow({
    required this.room,
    required this.chain,
    required this.replyTo,
    this.threadRootEventId,
    this.threadLastEventId,
  });

  @override
  State<_ReplyWindow> createState() => _ReplyWindowState();
}

class _ReplyWindowState extends State<_ReplyWindow> {
  final _text = TextEditingController();
  final List<XFile> _files = [];
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // start at the newest message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    final picked = await selectFiles(context, allowMultiple: true);
    if (picked.isEmpty || !mounted) return;
    setState(() => _files.addAll(picked));
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if ((text.isEmpty && _files.isEmpty) || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    if (_files.isNotEmpty) {
      // photos, videos and files go out as replies too; the chat keeps
      // uploading them after this window closes
      VibePendingFiles.send(
        Navigator.of(context, rootNavigator: true).context,
        widget.room,
        List.of(_files),
        inReplyTo: widget.replyTo,
        threadRootEventId: widget.threadRootEventId,
        threadLastEventId: widget.threadLastEventId,
      );
      _files.clear();
      if (text.isEmpty) {
        VibeHaptics.light();
        Navigator.of(context).pop();
        return;
      }
    }
    try {
      await widget.room.sendTextEvent(
        text,
        inReplyTo: widget.replyTo,
        threadRootEventId: widget.threadRootEventId,
        threadLastEventId: widget.threadLastEventId,
      );
      VibeHaptics.light();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
      Logs().w('Reply from the reply window failed', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final me = widget.room.client.userID;
    final i18n = MatrixLocals(L10n.of(context));
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.chain.length} messages',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.35),
                      ),
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: widget.chain.length,
                  itemBuilder: (context, i) {
                    final e = widget.chain[i];
                    final mine = e.senderId == me;
                    final focus = e.eventId == widget.replyTo.eventId;
                    final body = e.calcLocalizedBodyFallback(
                      i18n,
                      hideReply: true,
                      plaintextBody: true,
                      removeMarkdown: true,
                    );
                    final showName =
                        !mine &&
                        (i == 0 || widget.chain[i - 1].senderId != e.senderId);
                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                        ),
                        child: Column(
                          crossAxisAlignment: mine
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            if (showName)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  6,
                                  12,
                                  2,
                                ),
                                child: Text(
                                  e.senderFromMemoryOrFallback
                                      .calcDisplayname(i18n: i18n),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: mine
                                    ? VibePalette.accent
                                    : cs.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(20),
                                border: focus
                                    ? Border.all(color: Colors.white, width: 2)
                                    : null,
                              ),
                              child: Text(
                                body,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  color: mine ? Colors.white : cs.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_files.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: VibePendingFilesStrip(
                    files: _files,
                    onRemove: (f) => setState(() => _files.remove(f)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 10),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Add photo, video or file',
                      style: IconButton.styleFrom(
                        backgroundColor: cs.surfaceContainer,
                      ),
                      onPressed: _sending ? null : _attach,
                      icon: const Icon(Icons.add),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        autofocus: true,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Reply',
                          filled: true,
                          fillColor: cs.surfaceContainer,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: VibePalette.accent,
                        foregroundColor: Colors.white,
                        fixedSize: const Size(48, 48),
                      ),
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

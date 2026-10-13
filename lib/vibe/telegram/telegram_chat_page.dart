// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/vibe/telegram/telegram_pane.dart';
import 'package:fluffychat/vibe/telegram/vibe_telegram.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A Telegram chat in Vibe's own chat look: picture + name + time above
/// each group of messages, Vibe's message box at the bottom.
class TelegramChatPage extends StatefulWidget {
  final TgChat chat;
  const TelegramChatPage({required this.chat, super.key});

  static Future<void> open(BuildContext context, TgChat chat) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => TelegramChatPage(chat: chat)),
      );

  @override
  State<TelegramChatPage> createState() => _TelegramChatPageState();
}

class _TelegramChatPageState extends State<TelegramChatPage> {
  final _tg = VibeTelegram.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// Newest first (the list is drawn upside down, like every chat app).
  final List<Map<String, dynamic>> _messages = [];
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _loading = false;
  bool _end = false;
  bool _empty = true;

  int get _chatId => widget.chat.id;

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  @override
  void initState() {
    super.initState();
    _tg.addListener(_redraw);
    _sub = _tg.updates.stream.listen(_onUpdate);
    _tg.send({'@type': 'openChat', 'chat_id': _chatId}).ignore();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _loadOlder();
      }
    });
    _loadOlder();
  }

  @override
  void dispose() {
    _tg.removeListener(_redraw);
    _sub?.cancel();
    _tg.send({'@type': 'closeChat', 'chat_id': _chatId}).ignore();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  Future<void> _loadOlder() async {
    if (_loading || _end) return;
    _loading = true;
    try {
      // TDLib may return only a few messages per call at first; ask again
      // until we have a screenful.
      var got = 0;
      for (var round = 0; round < 4 && got < 30; round++) {
        final from = _messages.isEmpty ? 0 : _int(_messages.last['id']);
        final res = await _tg.send({
          '@type': 'getChatHistory',
          'chat_id': _chatId,
          'from_message_id': from,
          'offset': 0,
          'limit': 50,
          'only_local': false,
        });
        final list = (res['messages'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .where((m) => !_messages.any((e) => e['id'] == m['id']))
            .toList();
        if (list.isEmpty) {
          _end = true;
          break;
        }
        _messages.addAll(list);
        got += list.length;
      }
      _markRead();
    } catch (_) {}
    _loading = false;
    _empty = _messages.isEmpty;
    if (mounted) setState(() {});
  }

  void _markRead() {
    if (_messages.isEmpty) return;
    _tg.send({
      '@type': 'viewMessages',
      'chat_id': _chatId,
      'message_ids': _messages.take(50).map((m) => m['id']).toList(),
      'source': {'@type': 'messageSourceChatHistory'},
      'force_read': true,
    }).ignore();
  }

  void _onUpdate(Map<String, dynamic> u) {
    switch (u['@type']) {
      case 'updateNewMessage':
        final m = (u['message'] as Map).cast<String, dynamic>();
        if (_int(m['chat_id']) != _chatId) return;
        if (_messages.any((e) => e['id'] == m['id'])) return;
        _messages.insert(0, m);
        _empty = false;
        if (m['is_outgoing'] != true) {
          VibeHaptics.light();
          _markRead();
        }
      case 'updateMessageSendSucceeded':
        final m = (u['message'] as Map).cast<String, dynamic>();
        if (_int(m['chat_id']) != _chatId) return;
        final i = _messages.indexWhere((e) => e['id'] == u['old_message_id']);
        if (i >= 0) _messages[i] = m;
      case 'updateMessageSendFailed':
        final m = (u['message'] as Map).cast<String, dynamic>();
        if (_int(m['chat_id']) != _chatId) return;
        final i = _messages.indexWhere((e) => e['id'] == u['old_message_id']);
        if (i >= 0) _messages[i] = m;
      case 'updateMessageContent':
        if (_int(u['chat_id']) != _chatId) return;
        final i = _messages.indexWhere((e) => e['id'] == u['message_id']);
        if (i >= 0) {
          _messages[i] = {..._messages[i], 'content': u['new_content']};
        }
      case 'updateMessageEdited':
        if (_int(u['chat_id']) != _chatId) return;
        final i = _messages.indexWhere((e) => e['id'] == u['message_id']);
        if (i >= 0) {
          _messages[i] = {..._messages[i], 'edit_date': u['edit_date']};
        }
      case 'updateDeleteMessages':
        if (_int(u['chat_id']) != _chatId || u['is_permanent'] != true) return;
        final ids = (u['message_ids'] as List? ?? const []).toSet();
        _messages.removeWhere((e) => ids.contains(e['id']));
      default:
        return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    setState(() {});
    try {
      await _tg.send({
        '@type': 'sendMessage',
        'chat_id': _chatId,
        'input_message_content': {
          '@type': 'inputMessageText',
          'text': {'@type': 'formattedText', 'text': text},
        },
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t send: $e')),
      );
    }
  }

  bool _sameGroup(Map<String, dynamic> a, Map<String, dynamic>? b) {
    if (b == null) return false;
    if ((a['sender_id'] as Map?)?.toString() !=
        (b['sender_id'] as Map?)?.toString()) {
      return false;
    }
    return (_int(a['date']) - _int(b['date'])).abs() < 5 * 60;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chat = _tg.chats[_chatId] ?? widget.chat;
    final canWrite = !chat.isChannel;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(
          children: [
            TgAvatar(name: chat.title, file: chat.photo, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                chat.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: _loading || !_empty
                        ? const CircularProgressIndicator.adaptive()
                        : Text(
                            'No messages yet',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final older = i + 1 < _messages.length
                          ? _messages[i + 1]
                          : null;
                      return _MessageRow(
                        message: m,
                        first: !_sameGroup(m, older),
                        read: _int(m['id']) <= chat.lastReadOutbox,
                      );
                    },
                  ),
          ),
          if (canWrite)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 6,
                          onChanged: (_) => setState(() {}),
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: '# Message | ${chat.title}',
                            hintMaxLines: 1,
                            hintStyle: const TextStyle(
                              fontSize: 16,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Send',
                      onPressed: _input.text.trim().isEmpty ? null : _send,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFDCE4FF),
                        foregroundColor: const Color(0xFF226DFD),
                        disabledBackgroundColor: cs.surfaceContainerHigh,
                        fixedSize: const Size(56, 56),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 24),
                    ),
                  ],
                ),
              ),
            )
          else
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'This is a channel: only its admins can post.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool first;
  final bool read;
  const _MessageRow({
    required this.message,
    required this.first,
    required this.read,
  });

  @override
  Widget build(BuildContext context) {
    final tg = VibeTelegram.instance;
    final cs = Theme.of(context).colorScheme;
    final name = message['is_outgoing'] == true && tg.myId != null
        ? tg.userName(tg.myId!)
        : tg.senderName(message);
    final userId = tg.senderUserId(message);
    final photo = userId != 0 ? tg.userPhoto(userId) : null;
    final date = DateTime.fromMillisecondsSinceEpoch(
      ((message['date'] as num?)?.toInt() ?? 0) * 1000,
    );
    final now = DateTime.now();
    final time = DateUtils.isSameDay(date, now)
        ? DateFormat.jm().format(date)
        : DateFormat('d MMM, ').add_jm().format(date);
    final text = VibeTelegram.preview(message);
    final outgoing = message['is_outgoing'] == true;
    final state = (message['sending_state'] as Map?)?['@type'] as String?;
    final edited = ((message['edit_date'] as num?)?.toInt() ?? 0) > 0;

    Widget? status;
    if (outgoing) {
      if (state == 'messageSendingStatePending') {
        status = Text(
          'Sending…',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        );
      } else if (state == 'messageSendingStateFailed') {
        status = Icon(Icons.error_outline, size: 14, color: cs.error);
      } else {
        status = Icon(
          read ? Icons.done_all : Icons.done,
          size: 15,
          color: read ? const Color(0xFF5865F2) : cs.onSurfaceVariant,
        );
      }
    }

    final body = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text),
          if (edited)
            TextSpan(
              text: '  (edited)',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
        ],
      ),
      style: TextStyle(fontSize: 16, height: 1.3, color: cs.onSurface),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(12, first ? 12 : 1, 16, 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: first
                ? TgAvatar(name: name, file: photo, size: 40)
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (first)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15.5,
                              color: name.isEmpty ? cs.onSurface : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(child: body),
                    if (status != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 3),
                        child: status,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

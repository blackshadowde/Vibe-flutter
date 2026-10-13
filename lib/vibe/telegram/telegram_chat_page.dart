// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/vibe/telegram/telegram_media.dart';
import 'package:fluffychat/vibe/telegram/telegram_pane.dart';
import 'package:fluffychat/vibe/telegram/vibe_telegram.dart';
import 'package:fluffychat/vibe/vibe_animated_emoji.dart';
import 'package:fluffychat/vibe/vibe_emoji_sheet.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/vibe/vibe_swipe_reply.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

const Color _blurple = Color(0xFF5865F2);

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : null;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// A Telegram chat in Vibe's own chat look: picture + name + time above
/// each group of messages, swipe left to reply, long-press for reactions
/// and actions, + to send photos, videos and files.
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
  final _focus = FocusNode();
  final _scroll = ScrollController();

  /// Newest first (the list is drawn upside down, like every chat app).
  final List<Map<String, dynamic>> _messages = [];
  final Map<int, Map<String, dynamic>> _replied = {};
  final Set<int> _askedReplies = {};
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _loading = false;
  bool _end = false;
  bool _empty = true;

  Map<String, dynamic>? _replyTo;
  Map<String, dynamic>? _editing;
  DateTime _lastTyping = DateTime(2000);

  /// Who is typing right now: user id -> when we last heard.
  final Map<int, DateTime> _typing = {};
  Timer? _typingTimer;

  int get _chatId => widget.chat.id;

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
    _typingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final before = _typing.length;
      _typing.removeWhere(
        (_, t) => DateTime.now().difference(t).inSeconds > 6,
      );
      if (before != _typing.length && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tg.removeListener(_redraw);
    _sub?.cancel();
    _typingTimer?.cancel();
    _tg.send({'@type': 'closeChat', 'chat_id': _chatId}).ignore();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  int _indexOf(Object? id) => _messages.indexWhere((e) => e['id'] == id);

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
            .where((m) => _indexOf(m['id']) < 0)
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

  void _replace(Object? id, Map<String, dynamic> Function(Map<String, dynamic>) f) {
    final i = _indexOf(id);
    if (i >= 0) _messages[i] = f(_messages[i]);
  }

  void _onUpdate(Map<String, dynamic> u) {
    switch (u['@type']) {
      case 'updateNewMessage':
        final m = (u['message'] as Map).cast<String, dynamic>();
        if (_int(m['chat_id']) != _chatId || _indexOf(m['id']) >= 0) return;
        _messages.insert(0, m);
        _empty = false;
        _typing.remove(_tg.senderUserId(m));
        if (m['is_outgoing'] != true) {
          VibeHaptics.light();
          _markRead();
        }
      case 'updateMessageSendSucceeded':
      case 'updateMessageSendFailed':
        final m = (u['message'] as Map).cast<String, dynamic>();
        if (_int(m['chat_id']) != _chatId) return;
        _replace(u['old_message_id'], (_) => m);
      case 'updateMessageContent':
        if (_int(u['chat_id']) != _chatId) return;
        _replace(u['message_id'], (m) => {...m, 'content': u['new_content']});
      case 'updateMessageEdited':
        if (_int(u['chat_id']) != _chatId) return;
        _replace(u['message_id'], (m) => {...m, 'edit_date': u['edit_date']});
      case 'updateMessageInteractionInfo':
        if (_int(u['chat_id']) != _chatId) return;
        _replace(
          u['message_id'],
          (m) => {...m, 'interaction_info': u['interaction_info']},
        );
      case 'updateDeleteMessages':
        if (_int(u['chat_id']) != _chatId || u['is_permanent'] != true) return;
        final ids = (u['message_ids'] as List? ?? const []).toSet();
        _messages.removeWhere((e) => ids.contains(e['id']));
      case 'updateChatAction':
        if (_int(u['chat_id']) != _chatId) return;
        final sender = _map(u['sender_id']);
        if (sender?['@type'] != 'messageSenderUser') return;
        final id = _int(sender!['user_id']);
        if (_map(u['action'])?['@type'] == 'chatActionCancel') {
          _typing.remove(id);
        } else {
          _typing[id] = DateTime.now();
        }
      default:
        return;
    }
    if (mounted) setState(() {});
  }

  // ---- replies ----

  Map<String, dynamic>? _repliedTo(Map<String, dynamic> m) {
    final r = _map(m['reply_to']);
    if (r?['@type'] != 'messageReplyToMessage') return null;
    final id = _int(r!['message_id']);
    if (_int(r['chat_id']) == _chatId) {
      final i = _indexOf(id);
      if (i >= 0) return _messages[i];
    }
    final cached = _replied[_int(m['id'])];
    if (cached != null) return cached;
    if (_askedReplies.add(_int(m['id']))) {
      _tg.send({
        '@type': 'getRepliedMessage',
        'chat_id': _chatId,
        'message_id': m['id'],
      }).then((res) {
        _replied[_int(m['id'])] = res;
        _redraw();
      }).catchError((_) {});
    }
    return null;
  }

  void _startReply(Map<String, dynamic> m) {
    setState(() {
      _editing = null;
      _replyTo = m;
    });
    _focus.requestFocus();
  }

  void _startEdit(Map<String, dynamic> m) {
    final text = (_map(_map(m['content'])?['text'])?['text'] as String?) ?? '';
    setState(() {
      _replyTo = null;
      _editing = m;
      _input.text = text;
      _input.selection = TextSelection.collapsed(offset: text.length);
    });
    _focus.requestFocus();
  }

  // ---- sending ----

  Map<String, dynamic>? get _replyField => _replyTo == null
      ? null
      : {
          '@type': 'inputMessageReplyToMessage',
          'message_id': _replyTo!['id'],
        };

  Future<void> _sendContent(Map<String, dynamic> content) async {
    final reply = _replyField;
    setState(() => _replyTo = null);
    try {
      await _tg.send({
        '@type': 'sendMessage',
        'chat_id': _chatId,
        'reply_to': ?reply,
        'input_message_content': content,
      });
    } catch (e) {
      _toast('Couldn\'t send: $e');
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final editing = _editing;
    _input.clear();
    setState(() => _editing = null);
    final content = {
      '@type': 'inputMessageText',
      'text': {'@type': 'formattedText', 'text': text},
    };
    if (editing != null) {
      try {
        await _tg.send({
          '@type': 'editMessageText',
          'chat_id': _chatId,
          'message_id': editing['id'],
          'input_message_content': content,
        });
      } catch (e) {
        _toast('Couldn\'t edit: $e');
      }
      return;
    }
    await _sendContent(content);
  }

  void _onTyping(String _) {
    setState(() {});
    if (DateTime.now().difference(_lastTyping).inSeconds < 4) return;
    _lastTyping = DateTime.now();
    _tg.send({
      '@type': 'sendChatAction',
      'chat_id': _chatId,
      'action': {'@type': 'chatActionTyping'},
    }).ignore();
  }

  Map<String, dynamic>? _caption() {
    final t = _input.text.trim();
    if (t.isEmpty) return null;
    _input.clear();
    return {'@type': 'formattedText', 'text': t};
  }

  Future<void> _sendFile(String path, {required String kind}) async {
    final local = {'@type': 'inputFileLocal', 'path': path};
    final caption = _caption();
    final content = switch (kind) {
      'photo' => {
        '@type': 'inputMessagePhoto',
        'photo': {'@type': 'inputPhoto', 'photo': local},
        'caption': ?caption,
      },
      'video' => {
        '@type': 'inputMessageVideo',
        'video': {'@type': 'inputVideo', 'video': local, 'supports_streaming': true},
        'caption': ?caption,
      },
      _ => {
        '@type': 'inputMessageDocument',
        'document': {'@type': 'inputDocument', 'document': local},
        'caption': ?caption,
      },
    };
    await _sendContent(content);
  }

  static String _kindOf(String path) {
    final p = path.toLowerCase();
    if (RegExp(r'\.(jpe?g|png|webp|heic|heif)$').hasMatch(p)) return 'photo';
    if (RegExp(r'\.(mp4|mov|mkv|webm|3gp)$').hasMatch(p)) return 'video';
    return 'file';
  }

  Future<void> _attach() async {
    final cs = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final o in const [
                ('gallery', Icons.photo_library_outlined, 'Gallery'),
                ('camera', Icons.photo_camera_outlined, 'Camera'),
                ('video', Icons.videocam_outlined, 'Record video'),
                ('file', Icons.attach_file, 'File'),
              ])
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(ctx, o.$1),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: _blurple,
                          child: Icon(o.$2, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(o.$3, style: TextStyle(fontSize: 12, color: cs.onSurface)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'gallery':
        final files = await selectFiles(
          context,
          type: FileType.media,
          allowMultiple: true,
        );
        for (final f in files) {
          await _sendFile(f.path, kind: _kindOf(f.path));
        }
      case 'camera':
        final f = await ImagePicker().pickImage(source: ImageSource.camera);
        if (f != null) await _sendFile(f.path, kind: 'photo');
      case 'video':
        final f = await ImagePicker().pickVideo(source: ImageSource.camera);
        if (f != null) await _sendFile(f.path, kind: 'video');
      case 'file':
        if (!mounted) return;
        final files = await selectFiles(context, allowMultiple: true);
        for (final f in files) {
          await _sendFile(f.path, kind: 'file');
        }
    }
  }

  // ---- reactions and actions ----

  static List<Map<String, dynamic>> _reactions(Map<String, dynamic> m) =>
      ((_map(_map(m['interaction_info'])?['reactions'])?['reactions'] as List?) ??
              const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .where((r) => _map(r['type'])?['@type'] == 'reactionTypeEmoji')
          .toList();

  Future<void> _toggleReaction(Map<String, dynamic> m, String emoji) async {
    final mine = _reactions(m).any(
      (r) => r['is_chosen'] == true && _map(r['type'])?['emoji'] == emoji,
    );
    VibeHaptics.selection();
    try {
      await _tg.send({
        '@type': mine ? 'removeMessageReaction' : 'addMessageReaction',
        'chat_id': _chatId,
        'message_id': m['id'],
        'reaction_type': {'@type': 'reactionTypeEmoji', 'emoji': emoji},
        if (!mine) 'is_big': false,
        if (!mine) 'update_recent_reactions': true,
      });
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _menu(Map<String, dynamic> m) async {
    VibeHaptics.medium();
    final cs = Theme.of(context).colorScheme;
    final text = VibeTelegram.preview(m);
    final hasText = _map(m['content'])?['@type'] == 'messageText';
    Map<String, dynamic> props = const {};
    try {
      props = await _tg.send({
        '@type': 'getMessageProperties',
        'chat_id': _chatId,
        'message_id': m['id'],
      });
    } catch (_) {}
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in const ['❤️', '👍', '🔥', '😂', '😮', '😢'])
                    InkResponse(
                      radius: 26,
                      onTap: () => Navigator.pop(ctx, 'react:$e'),
                      child: VibeAnimatedEmoji(e, size: 36),
                    ),
                  InkResponse(
                    radius: 26,
                    onTap: () => Navigator.pop(ctx, 'more'),
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.sentiment_satisfied_alt_outlined),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (props['can_be_replied'] != false)
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () => Navigator.pop(ctx, 'reply'),
              ),
            if (text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy text'),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
            if (hasText && props['can_be_edited'] == true)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
            if (props['can_be_deleted_for_all_users'] == true ||
                props['can_be_deleted_only_for_self'] == true)
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text('Delete', style: TextStyle(color: cs.error)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice.startsWith('react:')) {
      await _toggleReaction(m, choice.substring(6));
    } else if (choice == 'more') {
      final e = await VibeEmojiSheet.pick(context);
      if (e != null) await _toggleReaction(m, e);
    } else if (choice == 'reply') {
      _startReply(m);
    } else if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: tgCaption(m) ?? text));
      _toast('Copied');
    } else if (choice == 'edit') {
      _startEdit(m);
    } else if (choice == 'delete') {
      await _delete(m, forAll: props['can_be_deleted_for_all_users'] == true);
    }
  }

  Future<void> _delete(Map<String, dynamic> m, {required bool forAll}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete message?'),
        content: Text(
          forAll
              ? 'It will be deleted for everyone in this chat.'
              : 'It will be deleted for you only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _tg.send({
        '@type': 'deleteMessages',
        'chat_id': _chatId,
        'message_ids': [m['id']],
        'revoke': forAll,
      });
    } catch (e) {
      _toast('Couldn\'t delete: $e');
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  bool _sameGroup(Map<String, dynamic> a, Map<String, dynamic>? b) {
    if (b == null) return false;
    if (a['reply_to'] != null) return false;
    if ('${a['sender_id']}' != '${b['sender_id']}') return false;
    return (_int(a['date']) - _int(b['date'])).abs() < 5 * 60;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chat = _tg.chats[_chatId] ?? widget.chat;
    final canWrite = !chat.isChannel;
    final typingNames = _typing.keys
        .map((id) => _tg.userName(id).split(' ').first)
        .toList();
    final banner = _editing ?? _replyTo;
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  if (typingNames.isNotEmpty)
                    Text(
                      chat.userId != null
                          ? 'typing…'
                          : '${typingNames.take(2).join(', ')} typing…',
                      style: const TextStyle(fontSize: 12.5, color: _blurple),
                    ),
                ],
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
                      final row = _MessageRow(
                        message: m,
                        first: !_sameGroup(m, older),
                        read: _int(m['id']) <= chat.lastReadOutbox,
                        replied: m['reply_to'] == null ? null : _repliedTo(m),
                        hasReply: _map(m['reply_to'])?['@type'] ==
                            'messageReplyToMessage',
                        reactions: _reactions(m),
                        onReact: (e) => _toggleReaction(m, e),
                        onLongPress: () => _menu(m),
                      );
                      if (!canWrite) return row;
                      return VibeSwipeReply(
                        key: ValueKey('tg_${m['id']}'),
                        onReply: () => _startReply(m),
                        child: row,
                      );
                    },
                  ),
          ),
          if (banner != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    _editing != null ? Icons.edit_outlined : Icons.reply,
                    size: 18,
                    color: _blurple,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: _editing != null
                                ? 'Editing  '
                                : '${_tg.senderName(banner)}  ',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _blurple,
                            ),
                          ),
                          TextSpan(
                            text: VibeTelegram.preview(banner).replaceAll('\n', ' '),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      if (_editing != null) _input.clear();
                      _editing = null;
                      _replyTo = null;
                    }),
                  ),
                ],
              ),
            ),
          if (canWrite)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (_editing == null)
                              IconButton(
                                tooltip: 'Attach',
                                onPressed: _attach,
                                icon: const Icon(Icons.add_circle_outline),
                              )
                            else
                              const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _input,
                                focusNode: _focus,
                                minLines: 1,
                                maxLines: 6,
                                onChanged: _onTyping,
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
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: _editing != null ? 'Save' : 'Send',
                      onPressed: _input.text.trim().isEmpty ? null : _send,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFDCE4FF),
                        foregroundColor: const Color(0xFF226DFD),
                        disabledBackgroundColor: cs.surfaceContainerHigh,
                        fixedSize: const Size(56, 56),
                      ),
                      icon: Icon(
                        _editing != null ? Icons.check_rounded : Icons.send_rounded,
                        size: 24,
                      ),
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
  final Map<String, dynamic>? replied;
  final bool hasReply;
  final List<Map<String, dynamic>> reactions;
  final void Function(String emoji) onReact;
  final VoidCallback onLongPress;
  const _MessageRow({
    required this.message,
    required this.first,
    required this.read,
    required this.replied,
    required this.hasReply,
    required this.reactions,
    required this.onReact,
    required this.onLongPress,
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
    final date = DateTime.fromMillisecondsSinceEpoch(_int(message['date']) * 1000);
    final time = DateUtils.isSameDay(date, DateTime.now())
        ? DateFormat.jm().format(date)
        : DateFormat('d MMM, ').add_jm().format(date);
    final media = tgHasMedia(message);
    final text = media ? tgCaption(message) : VibeTelegram.preview(message);
    final outgoing = message['is_outgoing'] == true;
    final state = _map(message['sending_state'])?['@type'] as String?;
    final edited = _int(message['edit_date']) > 0;

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
          color: read ? _blurple : cs.onSurfaceVariant,
        );
      }
    }

    final textWidget = text == null || text.isEmpty
        ? null
        : Text.rich(
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

    // The last line carries the ticks: the text, or the media if no text.
    Widget withStatus(Widget w) => status == null
        ? w
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(child: w),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 3),
                child: status,
              ),
            ],
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, first ? 12 : 1, 16, 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasReply)
              Padding(
                padding: const EdgeInsets.only(left: 20, bottom: 2),
                child: Row(
                  children: [
                    Icon(Icons.subdirectory_arrow_right, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: replied == null ? '' : '${tg.senderName(replied!)}  ',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            TextSpan(
                              text: replied == null
                                  ? 'Original message'
                                  : VibeTelegram.preview(replied).replaceAll('\n', ' '),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                time,
                                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      if (media)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: textWidget == null
                              ? withStatus(TgMedia(message))
                              : TgMedia(message),
                        ),
                      if (textWidget != null) withStatus(textWidget),
                      if (reactions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final r in reactions)
                                _ReactionChip(
                                  emoji: _map(r['type'])?['emoji'] as String? ?? '',
                                  count: _int(r['total_count']),
                                  mine: r['is_chosen'] == true,
                                  onTap: () => onReact(
                                    _map(r['type'])?['emoji'] as String? ?? '',
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final String emoji;
  final int count;
  final bool mine;
  final VoidCallback onTap;
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.mine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: mine ? _blurple.withAlpha(50) : cs.surfaceContainerHigh,
      shape: StadiumBorder(
        side: BorderSide(color: mine ? _blurple : Colors.transparent, width: 1.2),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: mine ? _blurple : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

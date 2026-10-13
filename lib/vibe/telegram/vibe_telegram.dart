// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fluffychat/vibe/vibe_app_info.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Telegram inside Vibe (proof of concept).
///
/// Talks to Telegram's official TDLib through a small native bridge
/// (VibeTelegramNative.kt). TDLib keeps its own encrypted database on the
/// phone, so you stay logged in and chats open instantly.
///
/// The Telegram API keys come from the build (GitHub secrets TG_API_ID and
/// TG_API_HASH); they are never stored in the code.
class TgError implements Exception {
  final int code;
  final String message;
  const TgError(this.code, this.message);
  @override
  String toString() => message;
}

class TgChat {
  final int id;
  String title;
  Map<String, dynamic>? lastMessage;
  int order = 0;
  bool pinned = false;
  int unread = 0;
  int lastReadOutbox = 0;
  Map<String, dynamic>? photo; // file object (small)
  int? userId; // private chats
  bool isChannel = false;
  TgChat(this.id, this.title);
}

class VibeTelegram extends ChangeNotifier {
  VibeTelegram._();
  static final VibeTelegram instance = VibeTelegram._();

  static const int apiId = int.fromEnvironment('TG_API_ID');
  static const String apiHash = String.fromEnvironment('TG_API_HASH');
  static bool get configured => apiId != 0 && apiHash.isNotEmpty;

  static const _method = MethodChannel('vibe/telegram');
  static const _events = EventChannel('vibe/telegram/updates');
  static const _keyName = 'chat.vibe.telegram_db_key';

  /// TDLib version, or null if this build doesn't include Telegram.
  String? version;
  bool checked = false;
  bool started = false;

  /// Authorization state, e.g. "authorizationStateWaitPhoneNumber".
  String auth = '';
  Map<String, dynamic> authState = const {};
  bool get ready => auth == 'authorizationStateReady';

  int? myId;
  final Map<int, TgChat> chats = {};
  final Map<int, Map<String, dynamic>> users = {};
  final Map<int, String> _paths = {}; // file id -> local path
  final Set<int> _downloading = {};
  bool _allChatsLoaded = false;

  /// Every raw update, for open chat screens.
  final StreamController<Map<String, dynamic>> updates =
      StreamController.broadcast();

  int? _client;
  StreamSubscription<dynamic>? _sub;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  int _nextExtra = 0;
  Timer? _notifyTimer;

  /// Starts TDLib once. Safe to call again.
  Future<void> start() async {
    if (started) return;
    try {
      version = await _method.invokeMethod<String>('available');
    } catch (_) {
      version = null;
    }
    checked = true;
    if (version == null || !configured) {
      notifyListeners();
      return;
    }
    started = true;
    _sub = _events.receiveBroadcastStream().listen(
      (e) => _onEvent(e as String),
      onError: (Object e) => debugPrint('Telegram: $e'),
    );
    _client = await _method.invokeMethod<int>('create');
    // Any request makes TDLib start and report its authorization state.
    unawaited(send({'@type': 'getOption', 'name': 'version'}).catchError((_) => <String, dynamic>{}));
  }

  Future<Map<String, dynamic>> send(Map<String, dynamic> request) async {
    final client = _client;
    if (client == null) throw const TgError(0, 'Telegram isn\'t running');
    final extra = '${_nextExtra++}';
    final c = Completer<Map<String, dynamic>>();
    _pending[extra] = c;
    await _method.invokeMethod('send', {
      'client': client,
      'request': jsonEncode({...request, '@extra': extra}),
    });
    final answer = await c.future;
    if (answer['@type'] == 'error') {
      throw TgError(
        (answer['code'] as num?)?.toInt() ?? 0,
        answer['message'] as String? ?? 'Error',
      );
    }
    return answer;
  }

  void _onEvent(String raw) {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (data['@client_id'] != null && data['@client_id'] != _client) return;
    final extra = data['@extra'];
    if (extra is String && _pending.containsKey(extra)) {
      _pending.remove(extra)!.complete(data);
      return;
    }
    _onUpdate(data);
  }

  /// Many updates arrive at once while chats load: redraw at most ~6x/s.
  void _changed() {
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(const Duration(milliseconds: 150), notifyListeners);
  }

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  void _applyPositions(TgChat chat, Object? positions) {
    if (positions is! List) return;
    for (final p in positions) {
      if (p is Map && (p['list'] as Map?)?['@type'] == 'chatListMain') {
        chat.order = _int(p['order']);
        chat.pinned = p['is_pinned'] == true;
      }
    }
  }

  void _onUpdate(Map<String, dynamic> u) {
    switch (u['@type']) {
      case 'updateAuthorizationState':
        final s = (u['authorization_state'] as Map).cast<String, dynamic>();
        auth = s['@type'] as String;
        authState = s;
        if (auth == 'authorizationStateWaitTdlibParameters') {
          unawaited(_sendParameters());
        } else if (auth == 'authorizationStateReady') {
          unawaited(_afterLogin());
        } else if (auth == 'authorizationStateClosed') {
          // Logged out: start a fresh client for the next login.
          chats.clear();
          users.clear();
          _allChatsLoaded = false;
          myId = null;
          _method.invokeMethod<int>('create').then((id) {
            _client = id;
            send({'@type': 'getOption', 'name': 'version'}).ignore();
          });
        }
        notifyListeners();
      case 'updateNewChat':
        final c = (u['chat'] as Map).cast<String, dynamic>();
        final chat = TgChat(_int(c['id']), c['title'] as String? ?? '');
        chat.lastMessage = (c['last_message'] as Map?)?.cast<String, dynamic>();
        chat.unread = _int(c['unread_count']);
        chat.lastReadOutbox = _int(c['last_read_outbox_message_id']);
        chat.photo = ((c['photo'] as Map?)?['small'] as Map?)
            ?.cast<String, dynamic>();
        final type = (c['type'] as Map?)?.cast<String, dynamic>();
        if (type?['@type'] == 'chatTypePrivate') {
          chat.userId = _int(type!['user_id']);
        }
        chat.isChannel =
            type?['@type'] == 'chatTypeSupergroup' && type?['is_channel'] == true;
        _applyPositions(chat, c['positions']);
        chats[chat.id] = chat;
        _changed();
      case 'updateChatTitle':
        chats[_int(u['chat_id'])]?.title = u['title'] as String? ?? '';
        _changed();
      case 'updateChatPhoto':
        chats[_int(u['chat_id'])]?.photo =
            ((u['photo'] as Map?)?['small'] as Map?)?.cast<String, dynamic>();
        _changed();
      case 'updateChatLastMessage':
        final chat = chats[_int(u['chat_id'])];
        if (chat != null) {
          chat.lastMessage = (u['last_message'] as Map?)?.cast<String, dynamic>();
          _applyPositions(chat, u['positions']);
          _changed();
        }
      case 'updateChatPosition':
        final chat = chats[_int(u['chat_id'])];
        if (chat != null) {
          _applyPositions(chat, [u['position']]);
          _changed();
        }
      case 'updateChatReadInbox':
        chats[_int(u['chat_id'])]?.unread = _int(u['unread_count']);
        _changed();
      case 'updateChatReadOutbox':
        chats[_int(u['chat_id'])]?.lastReadOutbox =
            _int(u['last_read_outbox_message_id']);
        _changed();
      case 'updateUser':
        final user = (u['user'] as Map).cast<String, dynamic>();
        users[_int(user['id'])] = user;
        _changed();
      case 'updateFile':
        final f = (u['file'] as Map).cast<String, dynamic>();
        final local = (f['local'] as Map?)?.cast<String, dynamic>();
        if (local?['is_downloading_completed'] == true) {
          final id = _int(f['id']);
          _paths[id] = local!['path'] as String;
          _downloading.remove(id);
          _changed();
        }
    }
    updates.add(u);
  }

  Future<String> _dbKey() async {
    const storage = FlutterSecureStorage();
    var key = await storage.read(key: _keyName);
    if (key == null) {
      final r = Random.secure();
      key = base64Encode(List<int>.generate(32, (_) => r.nextInt(256)));
      await storage.write(key: _keyName, value: key);
    }
    return key;
  }

  Future<void> _sendParameters() async {
    final dir = await getApplicationSupportDirectory();
    final lang = Platform.localeName.split(RegExp('[_-]')).first;
    try {
      await send({
        '@type': 'setTdlibParameters',
        'use_test_dc': false,
        'database_directory': '${dir.path}/telegram',
        'files_directory': '${dir.path}/telegram/files',
        // The database on the phone is encrypted with a random key kept in
        // the Android Keystore-backed secure storage.
        'database_encryption_key': await _dbKey(),
        'use_file_database': true,
        'use_chat_info_database': true,
        'use_message_database': true,
        'use_secret_chats': false,
        'api_id': apiId,
        'api_hash': apiHash,
        'system_language_code': lang.isEmpty ? 'en' : lang,
        'device_model': 'Android',
        'system_version': Platform.operatingSystemVersion,
        'application_version': 'Vibe ${VibeAppInfo.version}',
      });
    } catch (e) {
      debugPrint('Telegram parameters: $e');
    }
  }

  Future<void> _afterLogin() async {
    try {
      final me = await send({'@type': 'getMe'});
      myId = _int(me['id']);
    } catch (_) {}
    await loadMoreChats();
  }

  Future<void> loadMoreChats() async {
    if (_allChatsLoaded || !ready) return;
    try {
      await send({
        '@type': 'loadChats',
        'chat_list': {'@type': 'chatListMain'},
        'limit': 100,
      });
    } on TgError catch (e) {
      if (e.code == 404) _allChatsLoaded = true; // everything is loaded
    }
  }

  /// Chats in Telegram's own order (pinned first, then newest).
  List<TgChat> get sortedChats {
    final list = chats.values.where((c) => c.order != 0).toList()
      ..sort((a, b) => b.order.compareTo(a.order));
    return list;
  }

  // ---- login ----

  Future<void> sendPhone(String phone) => send({
    '@type': 'setAuthenticationPhoneNumber',
    'phone_number': phone,
    'settings': {'@type': 'phoneNumberAuthenticationSettings'},
  });

  Future<void> sendCode(String code) =>
      send({'@type': 'checkAuthenticationCode', 'code': code});

  Future<void> sendPassword(String password) =>
      send({'@type': 'checkAuthenticationPassword', 'password': password});

  Future<void> requestQr() => send({
    '@type': 'requestQrCodeAuthentication',
    'other_user_ids': <int>[],
  });

  Future<void> logOut() => send({'@type': 'logOut'});

  // ---- files and names ----

  /// Local path of a TDLib file, starting the download when needed.
  String? pathOf(Map<String, dynamic>? file) {
    if (file == null) return null;
    final id = _int(file['id']);
    final known = _paths[id];
    if (known != null) return known;
    final local = (file['local'] as Map?)?.cast<String, dynamic>();
    if (local?['is_downloading_completed'] == true) {
      final p = local!['path'] as String;
      _paths[id] = p;
      return p;
    }
    if (_downloading.add(id)) {
      send({
        '@type': 'downloadFile',
        'file_id': id,
        'priority': 1,
        'offset': 0,
        'limit': 0,
        'synchronous': false,
      }).ignore();
    }
    return null;
  }

  String userName(int id) {
    final u = users[id];
    if (u == null) return 'Telegram user';
    final name = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
    return name.isEmpty ? 'Deleted account' : name;
  }

  Map<String, dynamic>? userPhoto(int id) =>
      ((users[id]?['profile_photo'] as Map?)?['small'] as Map?)
          ?.cast<String, dynamic>();

  int senderUserId(Map<String, dynamic> message) {
    final s = (message['sender_id'] as Map?)?.cast<String, dynamic>();
    if (s?['@type'] == 'messageSenderUser') return _int(s!['user_id']);
    return 0;
  }

  String senderName(Map<String, dynamic> message) {
    final s = (message['sender_id'] as Map?)?.cast<String, dynamic>();
    if (s == null) return '';
    if (s['@type'] == 'messageSenderUser') return userName(_int(s['user_id']));
    return chats[_int(s['chat_id'])]?.title ?? '';
  }

  /// Short text for a message: its text, or a label for media.
  static String preview(Map<String, dynamic>? message) {
    final c = (message?['content'] as Map?)?.cast<String, dynamic>();
    if (c == null) return '';
    String caption() =>
        ((c['caption'] as Map?)?['text'] as String?)?.trim() ?? '';
    String withCaption(String label) {
      final cap = caption();
      return cap.isEmpty ? label : '$label $cap';
    }

    switch (c['@type']) {
      case 'messageText':
        return (c['text'] as Map?)?['text'] as String? ?? '';
      case 'messageAnimatedEmoji':
        return c['emoji'] as String? ?? '';
      case 'messagePhoto':
        return withCaption('📷 Photo');
      case 'messageVideo':
        return withCaption('🎬 Video');
      case 'messageAnimation':
        return withCaption('GIF');
      case 'messageVoiceNote':
        return withCaption('🎤 Voice message');
      case 'messageVideoNote':
        return '⏺ Video message';
      case 'messageAudio':
        return withCaption('🎵 Audio');
      case 'messageDocument':
        final name = (c['document'] as Map?)?['file_name'] as String?;
        return withCaption('📎 ${name ?? 'File'}');
      case 'messageSticker':
        final e = (c['sticker'] as Map?)?['emoji'] as String?;
        return '${e ?? ''} Sticker'.trim();
      case 'messageLocation':
        return '📍 Location';
      case 'messageContact':
        return '👤 Contact';
      case 'messagePoll':
        return '📊 Poll';
      case 'messageCall':
        return '📞 Call';
      case 'messageChatAddMembers':
        return 'joined the group';
      case 'messageChatJoinByLink':
        return 'joined via link';
      case 'messageChatDeleteMember':
        return 'left the group';
      case 'messagePinMessage':
        return 'pinned a message';
      default:
        return 'Message not supported yet';
    }
  }
}

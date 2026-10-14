// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:matrix/matrix.dart';

/// The Matrix side of a call: answers what Element Call (running in the
/// WebView) asks for, using the Matrix Dart SDK, and pushes new events to
/// it. Mirrors Sable's CallWidgetDriver + CallEmbed.
class VibeCallDriver {
  final Client client;
  final String roomId;

  /// Sends a JS call into the host page (`vibe.<fn>(...)`).
  final void Function(String fn, List<Object?> args) toWidget;

  VibeCallDriver({
    required this.client,
    required this.roomId,
    required this.toWidget,
  });

  final List<StreamSubscription> _subs = [];

  Room? get room => client.getRoomById(roomId);

  // ---------------------------------------------------------------------
  // Feeding the widget
  // ---------------------------------------------------------------------

  static bool _callToDevice(String type) =>
      type.startsWith('io.element.call') ||
      type.startsWith('org.matrix.call') ||
      type.startsWith('org.matrix.msc4143') ||
      type.startsWith('m.call') ||
      type.startsWith('m.rtc') ||
      type.startsWith('org.matrix.msc3401');

  void startFeeding() {
    _subs.add(
      client.onTimelineEvent.stream
          .where((e) => e.roomId == roomId)
          .listen((e) {
            if (e.type == EventTypes.Encrypted) return; // couldn't decrypt
            toWidget('feedEvent', [eventJson(e)]);
          }),
    );
    _subs.add(
      client.onRoomState.stream.where((u) => u.roomId == roomId).listen((u) {
        final s = u.state;
        if (s is! Event) return;
        toWidget('feedState', [eventJson(s)]);
      }),
    );
    _subs.add(
      client.onToDeviceEvent.stream.where((e) => _callToDevice(e.type)).listen((
        e,
      ) {
        toWidget('feedToDevice', [
          {'type': e.type, 'sender': e.sender, 'content': e.content},
          e.encryptedContent != null,
        ]);
      }),
    );
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  static Map<String, Object?> eventJson(StrippedStateEvent e) {
    if (e is Event) {
      final json = Map<String, Object?>.from(e.toJson())
        ..remove('original_source');
      json['room_id'] ??= e.roomId;
      return json;
    }
    return {
      'type': e.type,
      'state_key': e.stateKey,
      'sender': e.senderId,
      'content': e.content,
      'event_id': '',
      'origin_server_ts': 0,
    };
  }

  // ---------------------------------------------------------------------
  // Requests from the widget
  // ---------------------------------------------------------------------

  Future<Object?> handle(String method, Map<String, Object?> a) async {
    switch (method) {
      case 'sendEvent':
        return _sendEvent(a);
      case 'sendDelayedEvent':
        return _sendDelayedEvent(a);
      case 'updateDelayedEvent':
        return _updateDelayedEvent(a);
      case 'sendToDevice':
        await _sendToDevice(a);
        return {};
      case 'readRoomState':
        return _readRoomState(a);
      case 'readRoomTimeline':
        return _readRoomTimeline(a);
      case 'readEventRelations':
        return _readEventRelations(a);
      case 'openId':
        final t = await client.requestOpenIdToken(client.userID!, {});
        return t.toJson();
      case 'turnServers':
        final t = await client.getTurnServer();
        return {
          'uris': t.uris,
          'username': t.username,
          'password': t.password,
        };
      case 'searchUserDirectory':
        final r = await client.searchUserDirectory(
          a['term'] as String? ?? '',
          limit: a['limit'] as int?,
        );
        return {
          'limited': r.limited,
          'results': [
            for (final u in r.results)
              {
                'userId': u.userId,
                'displayName': u.displayName,
                'avatarUrl': u.avatarUrl?.toString(),
              },
          ],
        };
      case 'getMediaConfig':
        final c = await client.getConfig();
        return {'m.upload.size': c.mUploadSize};
    }
    throw UnsupportedError('Unknown call request: $method');
  }

  String _room(Map<String, Object?> a) => a['roomId'] as String? ?? roomId;

  Map<String, Object?> _content(Map<String, Object?> a) =>
      Map<String, Object?>.from(a['content'] as Map? ?? const {});

  Future<Map<String, Object?>> _sendEvent(Map<String, Object?> a) async {
    final rid = _room(a);
    final type = a['type'] as String;
    final content = _content(a);
    final stateKey = a['stateKey'] as String?;
    String? eventId;
    if (stateKey != null) {
      eventId = await client.setRoomStateWithKey(rid, type, stateKey, content);
    } else {
      final r = client.getRoomById(rid);
      if (r == null) throw StateError('Not in that room');
      if (type == EventTypes.Redaction) {
        eventId = await r.redactEvent(content['redacts'] as String);
      } else {
        // Encrypted automatically in encrypted rooms. Hidden from the chat.
        eventId = await r.sendEvent(
          content,
          type: type,
          displayPendingEvent: false,
        );
      }
    }
    return {'roomId': rid, 'eventId': eventId ?? ''};
  }

  static String _e(String s) => Uri.encodeComponent(s);

  /// MSC4140 delayed events: Element Call schedules its own "left the
  /// call" so you leave cleanly even if the app is killed.
  Future<Map<String, Object?>> _sendDelayedEvent(Map<String, Object?> a) async {
    final rid = _room(a);
    final type = a['type'] as String;
    final stateKey = a['stateKey'] as String?;
    final delay = a['delay'];
    final parent = a['parentDelayId'] as String?;
    final query = <String, String>{
      if (delay != null) 'org.matrix.msc4140.delay': '$delay',
      if (parent != null) 'org.matrix.msc4140.parent_delay_id': parent,
    };
    final path = stateKey != null
        ? '/client/v3/rooms/${_e(rid)}/state/${_e(type)}/${_e(stateKey)}'
        : '/client/v3/rooms/${_e(rid)}/send/${_e(type)}/${_e(client.generateUniqueTransactionId())}';
    final res = await client.request(
      RequestType.PUT,
      path,
      data: _content(a),
      query: query,
    );
    return {'roomId': rid, 'delayId': res['delay_id']};
  }

  Future<Map<String, Object?>> _updateDelayedEvent(
    Map<String, Object?> a,
  ) async {
    final id = a['delayId'] as String;
    final action = a['action'] as String;
    try {
      await client.request(
        RequestType.POST,
        '/client/unstable/org.matrix.msc4140/delayed_events/${_e(id)}',
        data: {'action': action},
      );
    } on MatrixException catch (e) {
      if (e.errcode != 'M_UNRECOGNIZED') rethrow;
      await client.request(
        RequestType.POST,
        '/client/v1/delayed_events/${_e(id)}/${_e(action)}',
        data: <String, Object?>{},
      );
    }
    return {};
  }

  Future<void> _sendToDevice(Map<String, Object?> a) async {
    final type = a['type'] as String;
    final encrypted = a['encrypted'] == true;
    final map = <String, Map<String, Map<String, Object?>>>{};
    (a['contentMap'] as Map? ?? const {}).forEach((user, devices) {
      final m = <String, Map<String, Object?>>{};
      (devices as Map).forEach((device, content) {
        m['$device'] = Map<String, Object?>.from(content as Map);
      });
      map['$user'] = m;
    });
    if (map.isEmpty) return;

    if (!encrypted) {
      await client.sendToDevice(
        type,
        client.generateUniqueTransactionId(),
        map,
      );
      return;
    }

    // Fetch keys for anyone we don't know yet.
    final unknown = map.keys
        .where((u) => client.userDeviceKeys[u] == null)
        .toSet();
    if (unknown.isNotEmpty) {
      try {
        await client.updateUserDeviceKeys(additionalUsers: unknown);
      } catch (e) {
        Logs().w('Vibe call: could not fetch device keys', e);
      }
    }

    // One encrypted send per distinct content, like Sable does.
    final groups = <String, List<DeviceKeys>>{};
    final contents = <String, Map<String, Object?>>{};
    map.forEach((user, devices) {
      final known = client.userDeviceKeys[user]?.deviceKeys ?? const {};
      devices.forEach((device, content) {
        final key = jsonEncode(content);
        contents[key] = content;
        final targets = device == '*'
            ? known.values
            : [?known[device]];
        groups.putIfAbsent(key, () => []).addAll(targets);
      });
    });
    for (final entry in groups.entries) {
      if (entry.value.isEmpty) continue;
      await client.sendToDeviceEncrypted(
        entry.value,
        type,
        contents[entry.key]!,
      );
    }
  }

  Future<List<Map<String, Object?>>> _readRoomState(
    Map<String, Object?> a,
  ) async {
    final r = client.getRoomById(_room(a));
    if (r == null) return const [];
    final states = r.states[a['type'] as String];
    if (states == null) return const [];
    final stateKey = a['stateKey'] as String?;
    final list = stateKey == null
        ? states.values
        : [?states[stateKey]];
    return [for (final s in list) eventJson(s)];
  }

  Future<List<Map<String, Object?>>> _readRoomTimeline(
    Map<String, Object?> a,
  ) async {
    final r = client.getRoomById(_room(a));
    if (r == null) return const [];
    final type = a['type'] as String;
    final msgtype = a['msgtype'] as String?;
    final stateKey = a['stateKey'] as String?;
    final since = a['since'] as String?;
    final limit = (a['limit'] as int?) ?? 50;
    final max = limit <= 0 ? 50 : (limit > 100 ? 100 : limit);
    final resp = await client.getRoomEvents(r.id, Direction.b, limit: 50);
    final out = <Map<String, Object?>>[];
    for (final m in resp.chunk) {
      if (since != null && m.eventId == since) break;
      var ev = Event.fromMatrixEvent(m, r);
      if (ev.type == EventTypes.Encrypted && client.encryption != null) {
        try {
          ev = await client.encryption!.decryptRoomEvent(ev);
        } catch (_) {}
      }
      if (ev.type != type) continue;
      if (stateKey != null && ev.stateKey != stateKey) continue;
      if (type == EventTypes.Message &&
          msgtype != null &&
          ev.content['msgtype'] != msgtype) {
        continue;
      }
      out.add(eventJson(ev));
      if (out.length >= max) break;
    }
    return out;
  }

  Future<Map<String, Object?>> _readEventRelations(
    Map<String, Object?> a,
  ) async {
    final rid = _room(a);
    final relType = a['relationType'] as String?;
    final evType = a['eventType'] as String?;
    var path =
        '/client/v1/rooms/${_e(rid)}/relations/${_e(a['eventId'] as String)}';
    if (relType != null) {
      path += '/${_e(relType)}';
      if (evType != null) path += '/${_e(evType)}';
    }
    final res = await client.request(
      RequestType.GET,
      path,
      query: {
        if (a['from'] != null) 'from': '${a['from']}',
        if (a['to'] != null) 'to': '${a['to']}',
        if (a['limit'] != null) 'limit': '${a['limit']}',
        if (a['direction'] != null) 'dir': '${a['direction']}',
      },
    );
    return {
      'chunk': res['chunk'] ?? const [],
      'nextBatch': res['next_batch'],
      'prevBatch': res['prev_batch'],
    };
  }

  /// Error shape matrix-widget-api passes on to the widget, so Element Call
  /// can react to "not supported" and similar answers from the server.
  static Map<String, Object?> errorJson(Object e) {
    if (e is MatrixException) {
      return {
        'message': e.errorMessage,
        'matrix_api_error': {
          'http_status': e.response?.statusCode ?? 400,
          'http_headers': <String, String>{},
          'url': '',
          'response': e.raw,
        },
      };
    }
    return {'message': '$e'};
  }
}

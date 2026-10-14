// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fluffychat/vibe/call/vibe_call_members.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';

/// End-to-end encryption of the call's audio and video, compatible with
/// Element Call (matrix-js-sdk RTCEncryptionManager + MatrixKeyProvider):
///
/// - every device makes its own random 16-byte key and sends it to the
///   other devices in the call as an Olm-encrypted to-device message
///   (`io.element.call.encryption_keys`),
/// - a new key when someone leaves (and when someone joins after the key
///   is 10 s old), used by you 1 s after it was sent,
/// - LiveKit derives the frame key with HKDF, like Element Call.
class VibeCallKeys {
  static const type = 'io.element.call.encryption_keys';

  final Client client;
  final String roomId;
  final lk.BaseKeyProvider keyProvider;
  final void Function(String) log;

  /// Called when your own key changes: tracks already being sent must be
  /// switched to it, or the others (who only got the new key) can't
  /// decrypt them. LiveKit keeps each sender on the index it started with.
  Future<void> Function(int index)? onOwnKey;

  VibeCallKeys._(this.client, this.roomId, this.keyProvider, this.log);

  /// Same key settings as Element Call's MatrixKeyProvider.
  static Future<VibeCallKeys> create({
    required Client client,
    required String roomId,
    required void Function(String) log,
  }) async {
    final options = rtc.KeyProviderOptions(
      sharedKey: false,
      ratchetSalt: Uint8List.fromList(lk.defaultRatchetSalt.codeUnits),
      ratchetWindowSize: 10,
      uncryptedMagicBytes: Uint8List.fromList(lk.defaultMagicBytes.codeUnits),
      failureTolerance: lk.defaultFailureTolerance,
      keyRingSize: 256,
      discardFrameWhenCryptorNotReady: false,
      keyDerivationAlgorithm: rtc.KeyDerivationAlgorithm.kHKDF,
    );
    final provider = await rtc.frameCryptorFactory.createDefaultKeyProvider(
      options,
    );
    return VibeCallKeys._(
      client,
      roomId,
      lk.BaseKeyProvider(provider, options),
      log,
    );
  }

  String get ownId => '${client.userID}:${client.deviceID}';

  Uint8List? _key;
  int _index = 0;

  /// Devices (participantId + membership time) that have the current key.
  final Map<String, int> _sharedWith = {};

  /// Someone uses the older room-event transport: send keys that way too.
  bool _roomTransport = false;

  final List<StreamSubscription> _subs = [];
  Future<void> _queue = Future.value();
  List<VibeRtcMember> _members = const [];

  /// Keys we received (newest per participant and index).
  final Map<String, int> _received = {};

  int get receivedCount => _received.length;

  void start() {
    _subs.add(
      client.onToDeviceEvent.stream.where((e) => e.type == type).listen((e) {
        final c = e.content;
        if (c['room_id'] != roomId) return;
        final keys = c['keys'];
        final member = c['member'];
        if (keys is! Map || member is! Map) return;
        final device = member['claimed_device_id'];
        if (device is! String) return;
        if (e.encryptedContent == null) {
          log('ignored unencrypted call key from ${e.sender}');
          return;
        }
        _receive(e.sender, device, keys['key'], keys['index']);
      }),
    );
    _subs.add(
      client.onTimelineEvent.stream
          .where((e) => e.roomId == roomId && e.type == type)
          .listen((e) {
            final c = e.content;
            final device = c['device_id'];
            if (device is! String || (c['call_id'] ?? '') != '') return;
            if (e.senderId == client.userID && device == client.deviceID) {
              return;
            }
            if (!_roomTransport) {
              _roomTransport = true;
              log('peer uses room keys, sending them that way too');
              _sharedWith.clear();
              update(_members);
            }
            final keys = c['keys'];
            if (keys is! List) return;
            for (final k in keys) {
              if (k is Map) _receive(e.senderId, device, k['key'], k['index']);
            }
          }),
    );
  }

  void _receive(String user, String device, Object? key, Object? index) {
    if (key is! String || index is! int) return;
    final bytes = _decode(key);
    if (bytes == null) return;
    final pid = '$user:$device';
    _received['$pid/$index'] = DateTime.now().millisecondsSinceEpoch;
    log('got key $index from $pid');
    unawaited(
      keyProvider.setRawKey(bytes, participantId: pid, keyIndex: index),
    );
  }

  static Uint8List? _decode(String b64) {
    try {
      var s = b64.replaceAll('-', '+').replaceAll('_', '/');
      while (s.length % 4 != 0) {
        s += '=';
      }
      return base64.decode(s);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _randomKey() {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(16, (_) => r.nextInt(256)));
  }

  /// Call when the call's memberships change.
  void update(List<VibeRtcMember> members) {
    _members = members;
    _queue = _queue.then((_) => _rollout()).catchError((Object e) {
      log('key rollout failed: $e');
    });
  }

  Future<void> _rollout() async {
    final members = _members;
    if (_key == null) {
      _key = _randomKey();
      _index = 0;
      await keyProvider.setRawKey(_key!, participantId: ownId, keyIndex: 0);
    }
    final want = <String, int>{
      for (final m in members)
        if (m.participantId != ownId) m.participantId: m.createdTs,
    };
    // someone rejoined: counts as left + joined
    _sharedWith.removeWhere((pid, ts) => want[pid] != null && want[pid] != ts);
    final left = _sharedWith.keys.where((p) => !want.containsKey(p)).toList();
    final joined = want.keys.where((p) => !_sharedWith.containsKey(p)).toList();
    if (left.isEmpty && joined.isEmpty) return;

    // New key only when someone leaves (so they can't listen in later).
    // A joiner gets the current key: they can't have recorded anything
    // before joining, and switching keys right as they join is when their
    // client is most likely to miss the switch.
    final rotate = left.isNotEmpty;
    List<String> targets;
    if (rotate) {
      _key = _randomKey();
      _index = (_index + 1) % 256;
      _sharedWith.clear();
      targets = want.keys.toList();
      log('new call key $_index');
    } else {
      targets = joined;
    }
    if (targets.isNotEmpty) {
      await _send(_key!, _index, targets, members);
      for (final p in targets) {
        _sharedWith[p] = want[p]!;
      }
    }
    if (rotate) {
      // give the others a moment to get it before we switch
      await Future<void>.delayed(const Duration(seconds: 1));
      await keyProvider.setRawKey(
        _key!,
        participantId: ownId,
        keyIndex: _index,
      );
      try {
        await onOwnKey?.call(_index);
      } catch (e) {
        log('switching to key $_index failed: $e');
      }
      log('now sending with key $_index');
    }
  }

  Future<void> _send(
    Uint8List key,
    int index,
    List<String> targets,
    List<VibeRtcMember> members,
  ) async {
    final b64 = base64.encode(key);
    final now = DateTime.now().millisecondsSinceEpoch;
    final devices = <String, Set<String>>{};
    for (final m in members) {
      if (targets.contains(m.participantId)) {
        devices.putIfAbsent(m.userId, () => {}).add(m.deviceId);
      }
    }
    final unknown = devices.keys.where((u) {
      final known = client.userDeviceKeys[u]?.deviceKeys ?? const {};
      return devices[u]!.any((d) => !known.containsKey(d));
    }).toSet();
    if (unknown.isNotEmpty) {
      try {
        await client.updateUserDeviceKeys(additionalUsers: unknown);
      } catch (e) {
        log('could not fetch device keys: $e');
      }
    }
    final keys = <DeviceKeys>[];
    devices.forEach((user, ids) {
      final known = client.userDeviceKeys[user]?.deviceKeys ?? const {};
      for (final id in ids) {
        final k = known[id];
        if (k != null) {
          keys.add(k);
        } else {
          log('no encryption keys for $user:$id');
        }
      }
    });
    if (keys.isNotEmpty) {
      await client.sendToDeviceEncrypted(keys, type, {
        'keys': {'index': index, 'key': b64},
        'room_id': roomId,
        'member': {'claimed_device_id': client.deviceID},
        'session': {'call_id': '', 'application': 'm.call', 'scope': 'm.room'},
        'sent_ts': now,
      });
      log('sent key $index to ${keys.length} device(s)');
    }
    if (_roomTransport) {
      final room = client.getRoomById(roomId);
      await room?.sendEvent(
        {
          'keys': [
            {'index': index, 'key': b64},
          ],
          'device_id': client.deviceID,
          'call_id': '',
          'sent_ts': now,
        },
        type: type,
        displayPendingEvent: false,
      );
    }
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}

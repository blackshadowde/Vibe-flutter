// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Calls that rang and you didn't answer or decline, per chat, split into
/// voice and video. Shown as a counter on "# | audio-call" / "video-call"
/// until you tap one. Kept in shared preferences so a ring the background
/// notification code saw (Vibe closed) counts too.
class VibeMissedCalls extends ChangeNotifier {
  VibeMissedCalls._();
  static final VibeMissedCalls instance = VibeMissedCalls._();

  static const _key = 'vibe_missed_calls';

  /// roomId -> ring event id -> 'video' | 'audio'
  Map<String, Map<String, String>> _data = {};

  int count(String roomId, {required bool video}) =>
      _data[roomId]?.values.where((v) => (v == 'video') == video).length ?? 0;

  static Map<String, Map<String, String>> _parse(String? raw) {
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          e.key: Map<String, String>.from(e.value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  /// Re-read (another part of Vibe may have written meanwhile).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      _data = _parse(prefs.getString(_key));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_data));
    } catch (_) {}
  }

  /// A ring started (answering or declining takes it away again).
  static Future<void> ringing(
    String roomId,
    String eventId, {
    required bool video,
  }) async {
    final self = instance;
    await self.load();
    (self._data[roomId] ??= {})[eventId] = video ? 'video' : 'audio';
    self.notifyListeners();
    await self._save();
  }

  /// Answered or declined: not missed.
  Future<void> handled(String roomId, String eventId) async {
    await load();
    final room = _data[roomId];
    if (room == null || room.remove(eventId) == null) return;
    if (room.isEmpty) _data.remove(roomId);
    notifyListeners();
    await _save();
  }

  /// Seen: you opened the call rows (or called back).
  Future<void> clear(String roomId) async {
    await load();
    if (_data.remove(roomId) == null) return;
    notifyListeners();
    await _save();
  }
}

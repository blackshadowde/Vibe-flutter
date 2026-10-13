// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// One id per message for its whole life. While sending, a message is known
/// by its transaction id; once the server confirms it, it gets a new event
/// id. Using the first id throughout means the message keeps its widget,
/// its pictures and its animation state: only the ticks change.
abstract class VibeStableId {
  static final Map<String, String> _byEventId = {};

  static String of(Event e) {
    final tx = e.transactionId;
    if (tx != null) {
      if (tx != e.eventId) _byEventId[e.eventId] = tx;
      return tx;
    }
    return _byEventId[e.eventId] ?? e.eventId;
  }
}

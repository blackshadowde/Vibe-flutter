// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/size_string.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Low data mode (Settings > Chat): photos load only when tapped, GIFs don't
/// autoplay, photos you send are smaller, nothing is auto-saved.
abstract class VibeLowData {
  static bool get on => AppSettings.vibeLowData.value;

  /// Photos the user tapped to load in this session.
  static final Set<String> _allowed = {};

  static bool blocks(Event e) =>
      on && !_allowed.contains(e.eventId) && e.senderId != e.room.client.userID;

  static void allow(Event e) => _allowed.add(e.eventId);

  /// Longest side of photos you send.
  static int get sendMaxDimension => on ? 1024 : 1600;
}

/// Shows [placeholder] with a "Tap to load" chip until tapped (low data mode).
class VibeTapToLoad extends StatefulWidget {
  final Event event;
  final Widget placeholder;
  final Widget child;
  const VibeTapToLoad({
    required this.event,
    required this.placeholder,
    required this.child,
    super.key,
  });

  @override
  State<VibeTapToLoad> createState() => _VibeTapToLoadState();
}

class _VibeTapToLoadState extends State<VibeTapToLoad> {
  @override
  Widget build(BuildContext context) {
    if (!VibeLowData.blocks(widget.event)) return widget.child;
    final size = widget.event.infoMap['size'];
    return GestureDetector(
      onTap: () => setState(() => VibeLowData.allow(widget.event)),
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.placeholder,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  size is int ? 'Tap to load · ${size.sizeString}' : 'Tap to load',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

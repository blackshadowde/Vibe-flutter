// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Licences of the fonts bundled in Vibe, added to the open-source licences
/// screen (the libraries' licences are added there automatically). The
/// font licences require their text to travel with the fonts.
abstract class VibeLicenses {
  static bool _done = false;

  static const _fonts = {
    'Figtree': 'assets/fonts/Figtree-OFL.txt',
    'Bangers': 'assets/fonts/stickers/bangers-OFL.txt',
    'Caveat Brush': 'assets/fonts/stickers/caveatbrush-OFL.txt',
    'Lobster': 'assets/fonts/stickers/lobster-OFL.txt',
    'Pacifico': 'assets/fonts/stickers/pacifico-OFL.txt',
    'Luckiest Guy': 'assets/fonts/stickers/LuckiestGuy-LICENSE.txt',
    'Permanent Marker': 'assets/fonts/stickers/PermanentMarker-LICENSE.txt',
  };

  static void register() {
    if (_done) return;
    _done = true;
    LicenseRegistry.addLicense(() async* {
      for (final e in _fonts.entries) {
        try {
          final text = await rootBundle.loadString(e.value);
          yield LicenseEntryWithLineBreaks(['${e.key} (font)'], text);
        } catch (_) {}
      }
    });
  }
}

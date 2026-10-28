// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Vibe is laid out for phones; in a big browser window everything looked
/// tiny. On the web, wide windows get the whole app drawn larger (up to 30%),
/// the way a browser zoom would, so it fills the screen comfortably.
class VibeWebScale extends StatelessWidget {
  final Widget child;
  const VibeWebScale({required this.child, super.key});

  static const _base = 1100.0;
  static const _max = 1.3;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;
    final mq = MediaQuery.of(context);
    final scale = (mq.size.width / _base).clamp(1.0, _max);
    if (scale < 1.02) return child;
    final size = mq.size / scale;
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          data: mq.copyWith(
            size: size,
            devicePixelRatio: mq.devicePixelRatio * scale,
            padding: mq.padding / scale,
            viewPadding: mq.viewPadding / scale,
            viewInsets: mq.viewInsets / scale,
          ),
          child: child,
        ),
      ),
    );
  }
}

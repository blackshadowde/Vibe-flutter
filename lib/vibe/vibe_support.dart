// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// "Support Vibe": UPI donations. Settings card → page, plus a gentle
/// pop-up now and then (after a few days of use, at most once a month,
/// with "Don't ask again").
abstract class VibeSupport {
  static const upiId = 'ashish.boddu@ybl';
  static const _payeeName = 'Vibe';
  static const blurple = Color(0xFF5865F2);

  static const _firstSeenKey = 'chat.vibe.support_first_seen';
  static const _lastAskKey = 'chat.vibe.support_last_ask';
  static const _neverKey = 'chat.vibe.support_never';

  /// Standard UPI link: any UPI app (GPay, PhonePe, Paytm, BHIM…) opens it.
  static String get upiLink =>
      'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(_payeeName)}'
      '&tn=${Uri.encodeComponent('Support Vibe')}&cu=INR';

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute(builder: (_) => const VibeSupportPage()));

  static Future<void> payWithApp(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launchUrlString(
        upiLink,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No UPI app found. Copy the UPI ID instead.'),
        ),
      );
    }
  }

  static Future<void> copyId(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: upiId));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('UPI ID copied')));
  }

  /// Called on app start. Shows the pop-up only when it is polite to.
  static Future<void> maybeAsk() async {
    try {
      final store = AppSettings.store;
      if (store.getBool(_neverKey) ?? false) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final first = store.getInt(_firstSeenKey);
      if (first == null) {
        await store.setInt(_firstSeenKey, now);
        return;
      }
      const day = 24 * 60 * 60 * 1000;
      if (now - first < 5 * day) return; // let people try Vibe first
      final last = store.getInt(_lastAskKey) ?? 0;
      if (now - last < 30 * day) return; // at most once a month
      final ctx =
          FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      // Don't stack on top of another sheet or dialog (update, what's new).
      if (Navigator.of(ctx, rootNavigator: true).canPop()) return;
      await store.setInt(_lastAskKey, now);
      await showModalBottomSheet<void>(
        context: ctx,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('❤️', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                const Text(
                  'Enjoying Vibe?',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vibe is free, with no ads and no tracking. It is built by '
                  'one person. If it helps you stay in touch, a small UPI '
                  'donation keeps the notification server running.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.4,
                    color: Theme.of(sheet).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: blurple,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      open(ctx);
                    },
                    icon: const Icon(Icons.favorite),
                    label: const Text(
                      'Support Vibe',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(sheet).pop(),
                      child: const Text('Maybe later'),
                    ),
                    TextButton(
                      onPressed: () {
                        store.setBool(_neverKey, true);
                        Navigator.of(sheet).pop();
                      },
                      child: const Text('Don\'t ask again'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {}
  }
}

class VibeSupportPage extends StatelessWidget {
  const VibeSupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const blurple = VibeSupport.blurple;
    return Scaffold(
      appBar: AppBar(title: const Text('Support Vibe')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Center(child: Text('❤️', style: TextStyle(fontSize: 44))),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Keep Vibe free',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No ads, no tracking, no paid features. Donations pay for the '
            'notification server and development. Any amount helps. Thank you!',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.45, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          // QR: scan it from another phone, or show it to a friend.
          Center(
            child: Container(
              width: 240,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  PrettyQrView.data(
                    data: VibeSupport.upiLink,
                    decoration: PrettyQrDecoration(
                      shape: PrettyQrSmoothSymbol(
                        roundFactor: 1,
                        color: Color(0xFF111214),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Scan with any UPI app',
                    style: TextStyle(
                      color: Color(0xFF4E5058),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          // UPI ID with copy.
          Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => VibeSupport.copyId(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'UPI ID',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const SelectableText(
                            VibeSupport.upiId,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.copy_rounded, size: 20),
                    const SizedBox(width: 6),
                    const Text('Copy'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: blurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () => VibeSupport.payWithApp(context),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text(
                'Pay with a UPI app',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Opens GPay, PhonePe, Paytm or BHIM. If your app blocks it, copy '
            'the UPI ID and pay from inside the app.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

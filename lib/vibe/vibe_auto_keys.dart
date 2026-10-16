import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// No recovery-key screens: right after you log in or sign up, Vibe sets up
/// (or unlocks) your encrypted-chat backup with your password as its
/// security phrase, and keeps the recovery key on this phone.
/// A new phone just logs in and is unlocked. If it can't (the backup was
/// made elsewhere with another phrase), the usual screen shows.
class VibeAutoKeys {
  static String? _pw;
  static DateTime? _at;

  /// Called with the password just before logging in or signing up.
  static void remember(String password) {
    _pw = password;
    _at = DateTime.now();
  }

  static String? _take() {
    final pw = _pw, at = _at;
    _pw = null;
    _at = null;
    if (pw == null || pw.isEmpty || at == null) return null;
    if (DateTime.now().difference(at) > const Duration(minutes: 10)) return null;
    return pw;
  }

  /// True when the backup is set up and unlocked (nothing to show).
  static Future<bool> run(Client client) async {
    final pw = _take();
    if (pw == null) return false;
    try {
      final state = await client.getCryptoIdentityState();
      if (state.connected) return true;
      if (!state.initialized) {
        final key = await client.initCryptoIdentity(
          passphrase: pw,
          wipeCrossSigning: true,
          wipeKeyBackup: true,
          wipeSecureStorage: true,
          setupMasterKey: true,
          setupSelfSigningKey: true,
          setupUserSigningKey: true,
        );
        try {
          await const FlutterSecureStorage().write(
            key: 'ssss_recovery_key_${client.userID}',
            value: key,
          );
        } catch (_) {}
      } else {
        await client.restoreCryptoIdentity(pw);
      }
      return (await client.getCryptoIdentityState()).connected;
    } catch (e, s) {
      Logs().w('Vibe: automatic key backup did not work', e, s);
      return false;
    }
  }
}

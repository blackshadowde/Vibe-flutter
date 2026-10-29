# Security scan notes

Vibe's APK is scanned on every change by **MobSF** (static analysis against
the OWASP MASVS), plus **OSV-Scanner** (dependencies) and **CodeQL**
(workflows). See the *Vibe security scans* runs under Actions. This page
explains every MobSF finding: what it is, where it comes from, and what was
done.

MobSF reads the compiled APK and flags patterns that *could* be risky. It
can't see what the code is for, and most of an app's code is libraries, so a
static score is a starting point, not a verdict.

**Trackers: 0 of the 432 MobSF knows.**

## High

### "AES in CBC mode with PKCS5/PKCS7 padding" (CWE-649)

Two places in the APK, both inside libraries, neither encrypting Vibe data:

| Where (minified name) | What it really is | Why it can't simply change |
| --- | --- | --- |
| `t/i` (`CryptoObjectUtils`) | Google's **AndroidX Biometric** library. It creates a throwaway key in the Android Keystore ("fake crypto object") so the fingerprint prompt can open for Vibe's app lock. No data is encrypted with it. | It's Google's own code; removing it means removing fingerprint unlock. |
| `O0/a` (decrypts a stream with `CipherInputStream`) | The video player's (**ExoPlayer / Media3**) decryptor for **HLS AES-128** streams. The HLS standard (RFC 8216) defines that encryption as AES-128-CBC. | Required by the streaming standard; it's part of the video player library. |

How Vibe itself encrypts:
- **Messages and files:** Matrix end-to-end encryption via vodozemac (Olm/Megolm), and attachments with AES-CTR plus a SHA-256 hash, as the Matrix spec defines.
- **Chat backups:** AES-256-GCM with a PBKDF2-HMAC-SHA256 key (310,000 rounds, random salt).
- **Database password and app lock:** flutter_secure_storage v11 (AES-GCM; v11 removed CBC).
- **The database:** SQLCipher.

### "App Link assetlinks.json not found" for matrix.to

Vibe used to declare that it can open `https://matrix.to` links. Only
matrix.org could verify that, and Android 12+ opens unverified links in the
browser anyway. **Removed** ([660a668](https://github.com/blackshadowde/Vibe-flutter/commit/660a66834)).
`matrix:` and `vibe://` links still open Vibe. (Vibe never used
`autoVerify` on matrix.to.)

## Warnings

| Finding | Status |
| --- | --- |
| `VibeBootReceiver` exported | **Fixed:** not exported. Boot and update broadcasts come from Android itself, which reaches non-exported receivers; it also only acts on those two actions. |
| Foreground-task `RebootReceiver` exported | **Fixed:** overridden to not exported. |
| Google Assistant shortcut `TrampolineActivity` exported | **Fixed:** removed from the app (unused). |
| `ProfileInstallReceiver` protected by `DUMP` | **Fixed:** removed (only used over adb). |
| UnifiedPush `MessagingReceiverImpl` / `RaiseToForegroundService` exported | **By design:** UnifiedPush distributor apps deliver notifications through them. |
| Login `CallbackActivity` exported | **By design:** your server's sign-in page returns to Vibe through it. |
| "Trusts system certificates" | **By design:** normal HTTPS. User-added certificates are not trusted; cleartext HTTP is off. |

## Native libraries

| Finding | What it is |
| --- | --- |
| No stack canary in `libvodozemac_bindings_dart.so` | vodozemac is written in **Rust**, which prevents the buffer overflows stack canaries guard against, and rustc doesn't emit canaries. Expected for Rust libraries. |
| No stack canary / `RUNPATH $ORIGIN` in `libsqlcipher.so` | The prebuilt SQLCipher library from its publisher. `$ORIGIN` points at the app's own private library folder, which other apps can't write to. |

## Other

- **"Secrets" (about 127):** strings that look like keys, mostly public root certificates (ISRG Root X1/X2), elliptic-curve constants and Dart runtime symbols. Release 3.1.114 also contained a Firebase key; Firebase was removed afterwards.
- **Logging calls:** in libraries (image loading, barcode scanner, notifications, UnifiedPush). Since Android 4.1, other apps can't read an app's logs; only the app itself, or a computer connected over adb with developer mode on, can.
- **Permissions also used by malware:** camera, microphone, contacts, location, run at start-up. Each belongs to a feature (calls, voice messages, sharing a contact or location, staying connected for notifications) and is asked for when used. The Google Play build has no "install apps" permission.

Found something this page gets wrong? Please report it privately:
https://github.com/blackshadowde/Vibe-flutter/security/advisories/new

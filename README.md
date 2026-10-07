# Vibe

A Discord-style Matrix messenger for Android, built on [FluffyChat](https://github.com/krille-chan/fluffychat) (Flutter).

Vibe keeps FluffyChat's Matrix engine, end-to-end encryption and sync, and replaces the interface with a Discord-inspired look: a left rail of DM avatars, a middle pane of direct messages, and chats that slide over the top.

## Features

- Direct messages with end-to-end encryption (recovery key / passphrase backup)
- Discord-style palette and GG Sans typography
- Typing indicators: pen animation on avatars and a floating pill when someone in another chat types
- Presence dots (green connected, orange connecting, grey offline)
- Reactions with animations, replies, edit, starred messages, media and links
- Swipe gestures and 120 Hz friendly animations
- Push notifications through Firebase and a Cloudflare Worker gateway
- Haptic feedback (toggle in Settings > Appearance)

## Build

Builds run on GitHub Actions, so no local setup is needed.

- **Vibe build**: debug build for testing (Actions > Vibe build)
- **Vibe release**: signed release APK (Actions > Vibe release)

Release secrets (Settings > Secrets and variables > Actions):

| Secret | What it is |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | base64 of the signing keystore |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `GOOGLE_SERVICES_JSON` | Firebase `google-services.json` (enables push) |

Keep the keystore backed up outside the repository. Without it, installed apps cannot be updated.

## Credits and licence

Vibe is a fork of [FluffyChat](https://github.com/krille-chan/fluffychat) by Christian Kußowski and contributors, licensed under AGPL-3.0-or-later. This project keeps that licence; see `LICENSE`. Matrix is an open standard from the [Matrix.org Foundation](https://matrix.org).

# Vibe: its own Matrix client

Vibe started from FluffyChat's code. This checklist makes it a Matrix client of
its own. FluffyChat's copyright notices and the AGPL licence stay, as the
licence requires; everything else becomes Vibe's.

## Level 1: Vibe's own identity

- [x] Code package `fluffychat` → `vibe` (all `package:` imports)
- [x] Android code folder `chat.fluffy.fluffychat` → `app.vibe.chat`
- [ ] App IDs and links: `im.fluffychat://` → `vibe://`, push/app IDs → Vibe's
- [ ] iPhone app ID `im.fluffychat.app` → `app.vibe.chat` (iPhone users reinstall once)
- [ ] Internal names (`FluffyChatApp`, `fluffy_chat_app.dart`, …) → Vibe
- [ ] Old FluffyChat build scripts and leftovers removed

## Level 2: Vibe's own screens

Each FluffyChat screen is rewritten in `lib/vibe/`, then the old file is deleted.

- [ ] Chat screen parts (input bar, event list, message types)
- [ ] Settings pages
- [ ] Login and sign-up
- [ ] Encryption setup and verification
- [ ] Notifications (push helper)
- [ ] Remaining FluffyChat widgets and utils

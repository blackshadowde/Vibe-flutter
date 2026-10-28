# Vibe: its own Matrix client

Vibe started from FluffyChat's code. This checklist makes it a Matrix client of
its own. FluffyChat's copyright notices and the AGPL licence stay, as the
licence requires; everything else becomes Vibe's.

## Level 1: Vibe's own identity

- [x] Code package `fluffychat` → `vibe` (all `package:` imports)
- [x] Android code folder `chat.fluffy.fluffychat` → `app.vibe.chat`
- [x] App IDs and links: `im.fluffychat://` → `vibe://`, push/app IDs → Vibe's
- [x] iPhone app ID `im.fluffychat.app` → `app.vibe.chat` (iPhone users reinstall once)
- [x] Internal names (`FluffyChatApp`, `fluffy_chat_app.dart`, …) → Vibe
- [ ] Old FluffyChat build scripts and leftovers removed

Kept on purpose (stored data and Matrix event types; renaming would log people
out or lose settings): `im.fluffychat.store.clients`, `im.fluffychat.account_config`,
`im.fluffychat.account_bundles`, `im.fluffychat.checkboxes`, `chat.fluffy.*`
setting keys and the `fluffychat_push` notification channel.

## Level 2: Vibe's own screens

Each FluffyChat screen is rewritten in `lib/vibe/`, then the old file is deleted.

- [ ] Chat screen parts (input bar, event list, message types)
- [ ] Settings pages
- [ ] Login and sign-up
- [ ] Encryption setup and verification
- [ ] Notifications (push helper)
- [ ] Remaining FluffyChat widgets and utils

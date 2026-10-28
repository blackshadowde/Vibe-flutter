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
- [x] Old FluffyChat build scripts and leftovers removed; desktop (Linux, Windows, Mac) named Vibe; Vibe's own privacy, security, contributing and changelog pages
- [x] Settings keys `chat.fluffy.*` → `chat.vibe.*` (old ones carried over on first start)
- [x] Help links, homeserver list, website and logo now on get-vibe.github.io
- [x] iPhone notification extension: app group and ID now Vibe's
- [ ] iPhone: FluffyChat's Firebase file (`GoogleService-Info.plist`) and the "FluffyChat Share" folder name (kept for now: removing them needs an iPhone build to test)

Kept on purpose (stored data and Matrix event types; renaming would log people
out or lose settings): `im.fluffychat.store.clients`, `im.fluffychat.account_config`,
`im.fluffychat.account_bundles`, `im.fluffychat.checkboxes`, the app-lock keys
and the `fluffychat_push` notification channel.

## Level 2: Vibe's own screens

Each FluffyChat screen is rewritten in `lib/vibe/`, then the old file is deleted.

- [x] All screens moved from `lib/pages` to `lib/vibe/screens`
- [x] One file per screen (controller and view merged): chat details, permissions, members, image viewer, invite, login, new group, new chat
- [x] Unused FluffyChat screens removed (old chat list parts, space view, archive list, new-space and add-account pages)

- [ ] Chat screen parts (input bar, event list, message types)
- [x] Settings pages: blocked people, password, password recovery, chat, style, notifications, devices, security, homeserver
- [ ] Custom emoji settings
- [ ] Login and sign-up
- [ ] Encryption setup and verification
- [ ] Notifications (push helper)
- [ ] Remaining FluffyChat widgets and utils

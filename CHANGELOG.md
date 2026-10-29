# Changelog

Vibe's changes are listed on each release:
https://github.com/blackshadowde/Vibe-flutter/releases

## 2026-10-29

### Added
- Quote part of a message: long-press a text message, tap Quote part, pick the words and answer just those (shown as a quote in every Matrix app). New features get a short "New" highlight the first few times ([9953651](https://github.com/blackshadowde/Vibe-flutter/commit/995365198))

### Changed
- Thread pane is now a tree: a line down the side, answers to an older message indented under it, no repeated reply line ([534aac3](https://github.com/blackshadowde/Vibe-flutter/commit/534aac3ae))
- Settings > Chats & storage: switch to turn off the text stickers shown above the text box while typing ([534aac3](https://github.com/blackshadowde/Vibe-flutter/commit/534aac3ae))
- Thread pane stays open after you send: your reply rises from the text box into the thread with the chat's status dots (encrypting, sent, delivered, read), and new replies appear live ([d0d4acf](https://github.com/blackshadowde/Vibe-flutter/commit/d0d4acf86))

### Fixed
- Media, links, files and voice messages in a chat's details open instantly: what's already on the phone shows first, older items load after ([a972b2c](https://github.com/blackshadowde/Vibe-flutter/commit/a972b2c29))
- Server rail: with many chats, the + for a new chat or group was stuck under the profile bar. It now scrolls above it ([741b415](https://github.com/blackshadowde/Vibe-flutter/commit/741b415da))
- Dropping a photo or video from another app on Android failed with "Cannot open file". A desktop drag-and-drop library caught the drop before Vibe's own handler; it's now switched off on Android ([3c67951](https://github.com/blackshadowde/Vibe-flutter/commit/3c67951e6))

### Google Play policies ([fc55515](https://github.com/blackshadowde/Vibe-flutter/commit/fc55515e2))
- Long-press a message from someone else: **Report** sends it to your server's admins
- Sign-in screen: "By continuing you agree to the Terms", with new [terms of use](https://get-vibe.github.io/terms.html) (rules, report and block, child safety)
- Google Play build: no photo-library permission. Sending photos uses the system photo picker; saving to the gallery needs no permission
- Storage permissions only on the old Android versions that use them (read: Android 12 and below, write: Android 10)
- Google Play version is its own app, `app.vibe.chat`, because `com.vibe.app` is taken on Play by another developer. The GitHub version keeps `com.vibe.app`, so nothing changes for existing installs ([68db71c](https://github.com/blackshadowde/Vibe-flutter/commit/68db71cde))
- Play listing name "Vibe – Secure Chat": "Matrix" is the Matrix.org Foundation's trademark, so the listing only says Vibe works with the Matrix protocol

## 2026-10-28

Every change in this release, with the commit that made it.

### Fixed
- Play Protect blocked installing Vibe. Google blocks any downloaded app that declares a notification listener; Vibe used one only for "Listening to". The listener is removed and the feature is off for now ([4519d56](https://github.com/blackshadowde/Vibe-flutter/commit/4519d56e3))
- Android back gesture closed the app instead of the open pane: Android's predictive back is turned off for Vibe ([e3ecdb9](https://github.com/blackshadowde/Vibe-flutter/commit/e3ecdb976))
- Dropped files: the send popup didn't send. They now wait above the text box, upload while Vibe is kept running, retry once, and show the real error if they fail ([e3ecdb9](https://github.com/blackshadowde/Vibe-flutter/commit/e3ecdb976), [9f1bd4c](https://github.com/blackshadowde/Vibe-flutter/commit/9f1bd4c43))
- Device verification: the device list looked tappable but wasn't. The text now says to accept the request on another device, with a Send again button ([e3ecdb9](https://github.com/blackshadowde/Vibe-flutter/commit/e3ecdb976))
- iPhone notification extension used FluffyChat's app group and ID, so it couldn't read Vibe's data ([2c779e9](https://github.com/blackshadowde/Vibe-flutter/commit/2c779e9e3))

### Security (fixes taken from FluffyChat after checking its 768 newer commits) ([625b562](https://github.com/blackshadowde/Vibe-flutter/commit/625b56236))
- Pictures load only from `mxc://` (your Matrix server) and only when signed in, so a message can't make Vibe fetch an outside address
- The recovery key's copy button copies; it no longer opens the share sheet on phones
- Resetting your encryption key really resets it, and moves your old message keys into the new backup
- Notifications arriving while signed out are ignored
- iPhone notifications close the database when done, so it can't stay locked

### Added
- Reply window for conversations of replies, with photo, video and file replies ([9f1bd4c](https://github.com/blackshadowde/Vibe-flutter/commit/9f1bd4c43), [2694875](https://github.com/blackshadowde/Vibe-flutter/commit/269487539))
- Block and unblock from someone's profile ([e3ecdb9](https://github.com/blackshadowde/Vibe-flutter/commit/e3ecdb976))
- Password and email link to the server's account page when it has one ([e3ecdb9](https://github.com/blackshadowde/Vibe-flutter/commit/e3ecdb976))
- Member search; permissions as Everyone / Moderators / Admins; admins can delete groups and communities (everyone removed, joining closed, then left and forgotten) ([c8bc320](https://github.com/blackshadowde/Vibe-flutter/commit/c8bc320b5))
- Share link and QR code for your ID (`get-vibe.github.io/chat.html#@you:server`); mentions shown as pills while typing; role tags and a pickable group tag in groups. The group tag is stored in your own member event in each group (`chat.vibe.tag`), and that update is hidden from the chat ([818c7f0](https://github.com/blackshadowde/Vibe-flutter/commit/818c7f0e4))
- Web: larger layout in wide windows, Vibe name and colours ([2694875](https://github.com/blackshadowde/Vibe-flutter/commit/269487539)); optional "Log out when the browser closes" ([4bf8158](https://github.com/blackshadowde/Vibe-flutter/commit/4bf8158ec))
- Help page and Vibe's own homeserver list on get-vibe.github.io ([2c779e9](https://github.com/blackshadowde/Vibe-flutter/commit/2c779e9e3))

### Changed
- Settings are saved under `chat.vibe.*` instead of `chat.fluffy.*`; old settings are carried over on first start ([2c779e9](https://github.com/blackshadowde/Vibe-flutter/commit/2c779e9e3))
- All screens moved from `lib/pages` to `lib/vibe/screens`, and 8 screens merged into one file each. Code layout only, no visible change ([3950286](https://github.com/blackshadowde/Vibe-flutter/commit/3950286d1), [0f838ca](https://github.com/blackshadowde/Vibe-flutter/commit/0f838ca20))
- Releasing: one run builds Android and starts the iPhone build with the same version number, and updates the web app when publishing ([636ab77](https://github.com/blackshadowde/Vibe-flutter/commit/636ab77fc))

### Removed (for now)
- "Listening to" status (see the Play Protect fix above)

### Security audit (after 3.1.111) ([a160dcb](https://github.com/blackshadowde/Vibe-flutter/commit/a160dcbc0))
- Call links are opened only when they point to a call server (`call.element.io` or your own). Before, a fake call message could open any website inside Vibe with the camera and microphone allowed
- Link previews are off in encrypted chats (your server would see the link); a switch turns them back on
- Firebase is no longer built into Android releases (3.1.111 and earlier included it, unused, and it contacted Google at start)
- The app ID stays `com.vibe.app`, the ID every release has used
- Unused permissions removed: screen capture and full-screen alerts
- PRIVACY.md lists every server Vibe contacts and what each one sees

### Reply threads
- A message with two or more replies opens the whole thread in a pane over the blurred chat, with the chat's own bubbles and text box; swipe a message in the pane to answer that one instead
- Releases list the APK's SHA-256 and, when the VT_API_KEY secret is set, a VirusTotal report

Vibe started from FluffyChat's code. FluffyChat's own history:
https://github.com/krille-chan/fluffychat/blob/main/CHANGELOG.md

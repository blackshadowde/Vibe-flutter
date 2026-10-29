# Vibe on Google Play: listing and forms

Everything to paste into the Play Console. Check each answer against the app
before submitting; you are the one declaring it to Google.

## Build

Actions → **Vibe for Google Play (app bundle)** → Run. Download the `.aab`
under the run's **Artifacts** and upload it in the Play Console.

The Play build is the same app as the GitHub APK (same package `com.vibe.app`,
same signing key) except: no built-in updater and no "install apps"
permission. Play does the updating.

## Store listing

**App name** (max 30): `Vibe – Matrix Chat`

Google Play's metadata policy doesn't allow other companies' brand names in
the listing, so it never mentions Discord (or Telegram, WhatsApp...).

**Short description** (max 80):
`Encrypted chat on Matrix with servers and channels. No ads, no tracking.`

**Full description** (max 4000):

```
Vibe is a free, open-source messenger with a server-and-channel layout, built on Matrix, the open standard for secure chat. Talk to anyone on Element, FluffyChat or any other Matrix app.

PRIVATE BY DESIGN
• End-to-end encryption for direct messages and private groups
• Strict encryption mode that changes keys more often
• No ads, no analytics, no trackers (MobSF finds 0 of 432 known trackers)
• No phone number needed: sign in with any Matrix account, or create one in the app
• Vibe has no servers of its own: your account lives on the Matrix server you choose

FEELS LIKE HOME
• Server rail, direct-message panes and communities
• Reply threads, reactions, stickers, custom emoji and big-emoji messages
• Voice and video calls
• Music links turn into player cards
• Lock or hide chats, disappearing messages, send later
• Encrypted chat backups with your own password

NOTIFICATIONS WITHOUT GOOGLE
Vibe keeps its own connection to your Matrix server, or uses ntfy. No Google push service is involved.

OPEN AND CHECKED
The full source is public (AGPL-3.0). Every release is scanned on VirusTotal and with MobSF, CodeQL and OSV-Scanner, and every change is listed in the changelog.
Source: https://github.com/blackshadowde/Vibe-flutter
Privacy policy: https://github.com/blackshadowde/Vibe-flutter/blob/Vibe/PRIVACY.md

Vibe is based on FluffyChat and is built with the help of AI tools; all changes are reviewed and tested by the developer.
```

**Category:** Communication. **Tags:** Messaging, Chat.
**Contact email:** your public support email. **Website:** https://get-vibe.github.io

**Graphics:** app icon 512×512 PNG, feature graphic 1024×500, at least 2
phone screenshots (the website's `site/assets/*.webp` are a start; Play wants
PNG or JPEG).

## Policy links

- **Privacy policy:** https://github.com/blackshadowde/Vibe-flutter/blob/Vibe/PRIVACY.md
- **Account deletion** (required, Vibe can create Matrix accounts):
  https://get-vibe.github.io/delete-account.html

## App access

Reviewers need to sign in. Create a test Matrix account (for example on
matrix.org), and give its username and password under **App content → App
access**.

## Data safety (draft)

Vibe sends data only to the Matrix server the user picks, never to the
developer. Google still counts data sent to a server as "collected", so
declare it:

| Data type | Collected | Shared | Why | Optional |
| --- | --- | --- | --- | --- |
| Personal info: name (display name), user IDs | Yes | No | App functionality, account management | Name optional |
| Messages: other in-app messages | Yes | No | App functionality | Required |
| Photos and videos | Yes | No | App functionality (when the user sends them) | Optional |
| Audio (voice messages, calls) | Yes | No | App functionality | Optional |
| Files and docs | Yes | No | App functionality | Optional |
| Contacts | Yes | No | App functionality (only a contact the user chooses to send) | Optional |
| Location: precise | Yes | No | App functionality (only when the user shares a location) | Optional |

- **Encrypted in transit:** Yes (HTTPS; plus end-to-end encryption in encrypted chats).
- **Users can request deletion:** Yes (link above).
- **Not collected:** device or other IDs for tracking, app activity,
  analytics, crash logs sent automatically, financial info, health.

## Permission declarations

| Item | What to declare |
| --- | --- |
| Foreground service: **remoteMessaging** | "Vibe can keep its own connection to the user's Matrix server so messages arrive without Google's push service. The user turns this on in Settings → Notifications; a permanent notification shows while it runs." Play may ask for a short screen recording. |
| Foreground service: **shortService** | "Finishes sending a file the user just sent if they leave the app." |
| **Ignore battery optimisations** | Requested so the direct connection keeps delivering messages; real-time chat is the core feature. Expect questions; if Play refuses, the Play build can skip this request. |
| Camera, microphone, contacts, location, photos | Each is asked for only when the user uses that feature (calls, voice messages, sharing a contact or location, sending photos). |

## Content rating

Communication app with user-to-user messaging: answer **Yes** to "users can
interact / exchange content". Rating is usually Teen or similar.

## Closed test (new personal accounts)

At least **12 testers** keep the app installed for **14 days** before a public
release can be requested. Add their Google account emails as testers under
**Testing → Closed testing**.

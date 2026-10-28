# Vibe privacy policy

Vibe is a Matrix chat app. It has no accounts of its own, no analytics, no
ads, no tracking and no Firebase. (When you share your location, Android's
location service, which can be Google's, finds where you are.) This page lists every
server Vibe talks to and what each one can see. If you find anything this
page leaves out, please open an issue.

## Your Matrix server

Your account lives on the Matrix server you pick (for example
unredacted.org or matrix.org). Vibe sends your messages, files, profile and
status there. In encrypted chats, messages and files are encrypted on your
device first, so the server only stores scrambled data. The server can
still see who you talk to and when (Matrix metadata). The server's own
privacy policy applies to it.

Things the server can read even in encrypted chats:

- **Your status and time zone.** They're saved in each direct chat so the
  other person can see them, and Matrix doesn't encrypt that kind of data.
  Choose who sees them (or nobody) in Settings > Security.
- **Your group tag**, if you pick one. It's part of your member info in
  each group.
- **Call links in unencrypted chats.** A call link contains the call's
  password, so in a chat that isn't encrypted anyone in the chat (and the
  server) can join the call.

Link previews are fetched by your server. In encrypted chats they're off
unless you switch them on (Settings > Security), because the server would
then see the links.

## Notifications (Android)

- **Direct connection (default):** Vibe stays connected to your Matrix
  server. Nothing else is involved.
- **Built-in, no Google:** uses ntfy.sh. It only sees a room and message ID
  and when a message arrived, never the message.

There is no Firebase, Google or other push service in Vibe. On iPhone,
Vibe doesn't use a push service.

## Calls

Calls use Element Call (`call.element.io` unless you set another call
server in Settings). Calls are end-to-end encrypted with a password that's
part of the call link; the call service carries encrypted audio and video
and sees the name you join with and your IP address. Vibe only opens call
links that point to a call server.

## Other servers Vibe contacts

- **GitHub:** on Android, Vibe checks for updates every few hours
  (`api.github.com`). iPhone update lists (SideStore / AltStore) and the
  website (get-vibe.github.io) are on GitHub too.
- **get-vibe.github.io:** the list of suggested servers when you sign in,
  and the help page.
- **Google Fonts (`fonts.gstatic.com`):** the animated emoji in reaction
  and effect menus are downloaded from there when shown. Low data mode
  turns them off.
- Only when you use them: wallpapers for the HyDE look (GitHub), sticker
  packs you import from Sticker.ly.

## On your device

On phones, chats are stored in an encrypted database. In the web version,
the browser stores them without that encryption, so anyone using the same
browser profile could read them; use "Log out when the browser closes" on
shared computers.

Permissions are asked for only when you use the feature: camera,
microphone, photos, location (sharing a location) and contacts (sharing a
contact; your contacts never leave the phone unless you send one).
Chat backups are encrypted with your backup password (AES-256).

## Contact

Questions: open an issue at https://github.com/blackshadowde/Vibe-flutter/issues

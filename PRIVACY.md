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

- **GitHub:** the Android version from GitHub checks for updates every few
  hours (`api.github.com`). The Google Play version doesn't; Google Play
  updates it. iPhone update lists (SideStore / AltStore) and the
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

## Who is responsible

Vibe is made by an independent developer (GitHub: blackshadowde). Vibe has
no servers and receives no data about you, so the developer holds nothing
about you. Your Matrix server is responsible for the data stored there
(see its own privacy policy).

## Legal basis

Vibe only sends data to make the features you use work (sending messages,
calls, notifications), on your request. Under the GDPR that is processing
needed to provide the service you asked for (Art. 6(1)(b)).

## How long data is kept

- **On your phone:** until you sign out or uninstall Vibe.
- **On your Matrix server:** as long as that server keeps it (its policy).
- **ntfy.sh** (only with "Built-in" notifications): keeps a notification
  for up to 12 hours so it can be delivered.
- **The developer:** nothing is kept, because nothing is received.

## Your rights

You can see, export or delete your data on your Matrix server (sign in to
your server's account page), and delete your account at any time: see
https://get-vibe.github.io/delete-account.html. As the developer holds no
data about you, there is nothing to request from Vibe itself.

## Data outside your country

Depending on the services you use, data may go to servers in other
countries: your Matrix server, ntfy.sh, call.element.io, GitHub and Google
Fonts (mostly in the EU and the USA). Each has its own privacy policy.

## Children

Vibe is not meant for children. You need to be at least 16 to use it (or
the minimum age in your country, if higher).

## Changes

If this policy changes, the new version is published here, at
https://github.com/blackshadowde/Vibe-flutter/blob/Vibe/PRIVACY.md, and the
change is listed in the changelog.

## Contact

Questions: open an issue at https://github.com/blackshadowde/Vibe-flutter/issues,
or write to the email address on Vibe's Google Play page. Security problems:
report privately at https://github.com/blackshadowde/Vibe-flutter/security/advisories/new

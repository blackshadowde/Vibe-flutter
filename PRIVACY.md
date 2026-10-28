# Vibe privacy policy

Vibe is a Matrix chat app. It has no accounts of its own, no analytics, no
ads and no tracking. This page explains, plainly, which servers Vibe talks
to and what they see.

## Your Matrix server

Your account lives on the Matrix server you pick (for example
unredacted.org or matrix.org). Vibe sends your messages, files, profile and
status there. Messages and files in encrypted chats are encrypted on your
phone first, so the server only stores scrambled data. The server's own
privacy policy applies to it.

Link previews, music covers for the "Listening to" card and uploaded files
go through your Matrix server too.

## Notifications

You choose how notifications arrive (Settings > Notifications):

- **Direct connection (default):** Vibe stays connected to your Matrix
  server. Nothing else is involved.
- **Built-in, no Google:** uses ntfy. The ntfy server only sees a room and
  message ID, never the message.
- **Standard (Firebase):** a push gateway and Google's Firebase receive a
  room and message ID, never the message.

## Calls

Calls inside Vibe use Element Call (`call.element.io` unless you set
another call server). Calls are end-to-end encrypted; the call service
carries encrypted audio and video and sees who joins.

## Updates and the website

On Android, Vibe checks GitHub for new versions. On iPhone, SideStore or
AltStore read Vibe's update list from GitHub. The website
(get-vibe.github.io) is hosted by GitHub Pages and has no tracking.

## On your phone

Chats are stored on your phone in an encrypted database. Optional features
ask for permission first: notification access (only for the "Listening to"
status, music apps only; Vibe never receives your notifications), camera,
microphone, location and contacts when you use them.

## Contact

Questions: open an issue at https://github.com/blackshadowde/Vibe-flutter/issues

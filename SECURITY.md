# Security

Found a security problem in Vibe? Please don't open a public issue.
Report it privately through GitHub:
https://github.com/blackshadowde/Vibe-flutter/security/advisories/new

Vibe's encryption comes from the Matrix Dart SDK and vodozemac. Problems in
those belong to their projects (famedly/matrix-dart-sdk, matrix-org/vodozemac).

## How every release is checked

- Each APK is built by GitHub Actions from this repository; nothing is
  built on a personal computer.
- The release workflow uploads the APK to VirusTotal and writes the result
  (engines that flagged it, out of how many) and the report link into the
  release notes. The notes also give the APK's SHA-256, which matches the
  fingerprint on the VirusTotal report.
- Vibe asks for no notification access, has no Firebase and no analytics.
  PRIVACY.md lists every server it contacts.

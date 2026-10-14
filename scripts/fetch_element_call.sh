#!/usr/bin/env bash
# Downloads Element Call (embedded build) and matrix-widget-api into the app
# assets. Vibe hosts Element Call itself, like Sable does, so calls work
# with Sable, Element and Element X. Pinned versions; npm checks integrity.
set -euo pipefail

EC_VERSION="0.16.3"
MWA_VERSION="1.13.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

npm pack "@element-hq/element-call-embedded@${EC_VERSION}" --silent >/dev/null
npm pack "matrix-widget-api@${MWA_VERSION}" --silent >/dev/null
mkdir ec mwa
tar xzf element-hq-element-call-embedded-${EC_VERSION}.tgz -C ec
tar xzf matrix-widget-api-${MWA_VERSION}.tgz -C mwa

DEST="$ROOT/assets/element-call"
find "$DEST" -mindepth 1 ! -name README.md ! -name .gitkeep -delete 2>/dev/null || true
mkdir -p "$DEST/assets"
cp ec/package/dist/index.html ec/package/dist/config.json "$DEST/"
# Flutter only bundles files directly inside a listed folder.
if find ec/package/dist/assets -mindepth 1 -type d | grep -q .; then
  echo "::error::Element Call assets have sub-folders; update pubspec.yaml"
  exit 1
fi
find ec/package/dist/assets -maxdepth 1 -type f ! -name '*.map' -exec cp {} "$DEST/assets/" \;
cp ec/package/LICENSE-AGPL-3.0 "$DEST/LICENSE-AGPL-3.0"

cp mwa/package/dist/api.min.js "$ROOT/assets/vibe_call/matrix-widget-api.min.js"
# Apache-2.0: ship its licence with it
cp mwa/package/LICENSE "$ROOT/assets/vibe_call/matrix-widget-api.LICENSE" 2>/dev/null || true

echo "Element Call ${EC_VERSION}: $(ls "$DEST/assets" | wc -l) files, $(du -sh "$DEST" | cut -f1)"

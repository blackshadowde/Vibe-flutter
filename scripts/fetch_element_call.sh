#!/usr/bin/env bash
# Downloads Element Call (embedded build) and matrix-widget-api into the app
# assets. Vibe hosts Element Call itself, like Sable does, so calls work
# with Sable, Element and Element X. Pinned versions; npm checks integrity.
set -euo pipefail
trap 'echo "::error::fetch_element_call.sh failed at line $LINENO: $BASH_COMMAND"' ERR

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

# Build the browser file from the library itself (all exports, incl.
# ClientWidgetApi and WidgetDriver) as window.mxwidgets.
(cd mwa/package && npm install --omit=dev --ignore-scripts --no-audit --no-fund --no-package-lock 2>&1 | tail -5)
npx --yes esbuild@0.25.0 mwa/package/lib/index.js --bundle --format=iife \
  --global-name=mxwidgets --minify --platform=browser \
  --outfile="$ROOT/assets/vibe_call/matrix-widget-api.min.js"
node -e '
  const vm = require("vm");
  const ctx = { window: {}, console };
  ctx.self = ctx.window; ctx.globalThis = ctx.window;
  vm.createContext(ctx);
  vm.runInContext(require("fs").readFileSync(process.argv[1], "utf8") + ";window.mxwidgets = mxwidgets;", ctx);
  const m = ctx.window.mxwidgets || {};
  const need = ["WidgetDriver", "ClientWidgetApi", "Widget", "OpenIDRequestState"];
  const missing = need.filter((k) => !m[k]);
  if (missing.length) { console.log("::error::matrix-widget-api build is missing " + missing.join(",")); process.exit(1); }
  console.log("matrix-widget-api ok: " + need.join(", "));
' "$ROOT/assets/vibe_call/matrix-widget-api.min.js"
# Apache-2.0: ship its licence with it
cp mwa/package/LICENSE "$ROOT/assets/vibe_call/matrix-widget-api.LICENSE" 2>/dev/null || true

echo "Element Call ${EC_VERSION}: $(ls "$DEST/assets" | wc -l) files, $(du -sh "$DEST" | cut -f1)"

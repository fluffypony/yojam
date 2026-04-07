#!/usr/bin/env bash
# Packages Chrome and Firefox extensions from shared/ + per-browser manifests.
# Safari is built by Xcode (YojamSafariExtension target).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

rm -rf dist && mkdir -p dist/chrome dist/firefox

# Chrome
cp -R shared/* dist/chrome/
cp chrome/manifest.json dist/chrome/
(cd dist/chrome && zip -r ../yojam-chrome.zip .)

# Firefox
cp -R shared/* dist/firefox/
cp firefox/manifest.json dist/firefox/
(cd dist/firefox && zip -r ../yojam-firefox.xpi .)

echo "Built dist/yojam-chrome.zip and dist/yojam-firefox.xpi"
echo "Signing and store submission are out of scope for this script."

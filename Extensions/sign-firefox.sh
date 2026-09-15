#!/usr/bin/env bash
# Sign the packaged Firefox extension for distribution with GitHub releases.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/dist/firefox"

if [[ -z "${WEB_EXT_API_KEY:-}" || -z "${WEB_EXT_API_SECRET:-}" ]]; then
  echo "Set WEB_EXT_API_KEY and WEB_EXT_API_SECRET from the AMO Developer Hub." >&2
  exit 1
fi
if [[ ! -f "$SOURCE_DIR/manifest.json" ]]; then
  echo "Run Extensions/build.sh before Extensions/sign-firefox.sh." >&2
  exit 1
fi

npm exec --yes --package=web-ext@10.6.0 -- web-ext lint \
  --no-config-discovery --source-dir "$SOURCE_DIR" --self-hosted

SIGNED_DIR="$(mktemp -d "$SCRIPT_DIR/dist/firefox-signed.XXXXXX")"
# web-ext reads the API credentials from the environment, not command arguments.
npm exec --yes --package=web-ext@10.6.0 -- web-ext sign \
  --no-config-discovery --source-dir "$SOURCE_DIR" \
  --artifacts-dir "$SIGNED_DIR" --channel unlisted \
  --timeout 300000 --approval-timeout 900000

shopt -s nullglob
SIGNED_PACKAGES=("$SIGNED_DIR"/*.xpi)
if [[ ${#SIGNED_PACKAGES[@]} -ne 1 ]]; then
  echo "Mozilla has not returned a signed XPI. Check the submission in the AMO Developer Hub." >&2
  exit 1
fi

if ! unzip -l "${SIGNED_PACKAGES[0]}" META-INF/mozilla.rsa | rg -q 'META-INF/mozilla.rsa'; then
  echo "The returned XPI has no Mozilla signature." >&2
  exit 1
fi

cp "${SIGNED_PACKAGES[0]}" "$SCRIPT_DIR/dist/yojam-firefox.xpi"
echo "Mozilla-signed extension: Extensions/dist/yojam-firefox.xpi"

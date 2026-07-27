#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------
# release.sh - Build, sign, notarize, and package a Yojam release
#
# Usage:
#   ./scripts/release.sh [--skip-archive] [--skip-notarize]
#
# Prerequisites (one-time setup):
#   1. Developer ID Application certificate in Keychain
#   2. Sparkle EdDSA private key in Keychain (generate_keys)
#   3. Notarization credentials stored:
#      xcrun notarytool store-credentials "YojamNotarize" \
#        --apple-id "you@email.com" --team-id "TEAMID" \
#        --password "app-specific-password"
#   4. ExportOptions.plist in repo root (see below)
#   5. brew install create-dmg
#
# The script reads version info from project.yml - bump
# MARKETING_VERSION and CURRENT_PROJECT_VERSION there first.
# ------------------------------------------------------------------

SKIP_ARCHIVE=false
SKIP_NOTARIZE=false
for arg in "$@"; do
  case "$arg" in
    --skip-archive)  SKIP_ARCHIVE=true ;;
    --skip-notarize) SKIP_NOTARIZE=true ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/Yojam.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Yojam.app"
EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions.plist"

RS_TEAM_ID="${RS_TEAM_ID:?Set RS_TEAM_ID to your Apple Developer Team ID}"
KEYCHAIN_PROFILE="${YOJAM_NOTARIZE_PROFILE:-YojamNotarize}"
SPARKLE_PRIVATE_KEY_FILE="${YOJAM_SPARKLE_PRIVATE_KEY_FILE:-}"
SPARKLE_KEY_ARGS=()
if [ -n "$SPARKLE_PRIVATE_KEY_FILE" ]; then
  if [[ "$SPARKLE_PRIVATE_KEY_FILE" != /* ]]; then
    SPARKLE_PRIVATE_KEY_FILE="$PROJECT_DIR/$SPARKLE_PRIVATE_KEY_FILE"
  fi
  SPARKLE_KEY_ARGS=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
fi

# Sparkle bin - check common locations
SPARKLE_BIN=""
for candidate in \
  "$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin" \
  "$HOME/Library/Developer/Xcode/DerivedData"/Yojam-*/SourcePackages/artifacts/sparkle/Sparkle/bin \
  "/usr/local/bin"; do
  if [ -f "$candidate/sign_update" ]; then
    SPARKLE_BIN="$candidate"
    break
  fi
done

# ---- Helpers ----

step=0
info()  { step=$((step + 1)); printf "\n\033[1;34m[%d] %s\033[0m\n" "$step" "$1"; }
ok()    { printf "    \033[32m✓ %s\033[0m\n" "$1"; }
fail()  { printf "    \033[31m✗ %s\033[0m\n" "$1"; exit 1; }

ensure_update_signatures() {
  local appcast="$1"
  local releases_dir="$2"
  local download_url_prefix="$3"
  local found_artifact=false
  local artifact artifact_name artifact_url signature signature_value length_value
  local enclosure url local_path

  [ -f "$appcast" ] || fail "appcast.xml not found at $appcast"

  shopt -s nullglob
  for artifact in "$releases_dir"/*.dmg "$releases_dir"/*.delta; do
    found_artifact=true
    artifact_name=$(basename "$artifact")
    artifact_url="${download_url_prefix%/}/$artifact_name"

    if ! grep -Fq "url=\"$artifact_url\"" "$appcast"; then
      continue
    fi

    signature=$("$SPARKLE_BIN/sign_update" "${SPARKLE_KEY_ARGS[@]}" "$artifact")
    signature_value=$(printf '%s\n' "$signature" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
    length_value=$(printf '%s\n' "$signature" | sed -n 's/.*length="\([^"]*\)".*/\1/p')

    [ -n "$signature_value" ] || fail "Could not parse Sparkle signature for $artifact_name"
    [ -n "$length_value" ] || fail "Could not parse Sparkle length for $artifact_name"
    "$SPARKLE_BIN/sign_update" --verify "${SPARKLE_KEY_ARGS[@]}" \
      "$artifact" "$signature_value"

    ARTIFACT_URL="$artifact_url" \
    ARTIFACT_LENGTH="$length_value" \
    ARTIFACT_SIGNATURE="$signature_value" \
      /usr/bin/perl -0pi -e '
        my $url = quotemeta $ENV{"ARTIFACT_URL"};
        my $raw_url = $ENV{"ARTIFACT_URL"};
        my $length = $ENV{"ARTIFACT_LENGTH"};
        my $signature = $ENV{"ARTIFACT_SIGNATURE"};

        s{<enclosure\b([^>]*)\burl="$url"([^>]*)/>}{
          my $attrs = "$1 url=\"$raw_url\"$2";
          $attrs =~ s/\s+length="[^"]*"//g;
          $attrs =~ s/\s+sparkle:edSignature="[^"]*"//g;
          $attrs =~ s/\s+/ /g;
          $attrs =~ s/^\s+|\s+$//g;
          "<enclosure $attrs length=\"$length\" sparkle:edSignature=\"$signature\"/>";
        }eg;
      ' "$appcast"
  done
  shopt -u nullglob

  [ "$found_artifact" = true ] || fail "No update artifacts found in $releases_dir"

  while IFS="$(printf '\t')" read -r url enclosure; do
    artifact_name=$(basename "$url")
    local_path="$releases_dir/$artifact_name"
    [ -f "$local_path" ] || fail "Appcast references missing artifact $artifact_name"

    signature_value=$(printf '%s\n' "$enclosure" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
    [ -n "$signature_value" ] || fail "Appcast enclosure for $artifact_name is missing sparkle:edSignature"
    "$SPARKLE_BIN/sign_update" --verify "${SPARKLE_KEY_ARGS[@]}" \
      "$local_path" "$signature_value" \
      || fail "Sparkle signature verification failed for $artifact_name"
  done < <(/usr/bin/perl -ne 'while (/(<enclosure\b[^>]*\burl="([^"]+\.(?:dmg|delta))"[^>]*\/>)/g) { print "$2\t$1\n" }' "$appcast")

  ok "Update enclosures are Sparkle-signed and verified"
}

# ---- Extract version from project.yml ----

MARKETING_VERSION=$(grep 'MARKETING_VERSION:' "$PROJECT_DIR/project.yml" | head -1 | awk '{print $2}' | tr -d '"')
BUILD_NUMBER=$(grep 'CURRENT_PROJECT_VERSION:' "$PROJECT_DIR/project.yml" | head -1 | awk '{print $2}' | tr -d '"')
DMG_NAME="Yojam-${MARKETING_VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

echo ""
echo "  Yojam release: v${MARKETING_VERSION} (build ${BUILD_NUMBER})"
echo "  Output: $DMG_PATH"
echo ""

# ---- Preflight checks ----

info "Preflight checks"

[ -f "$PROJECT_DIR/project.yml" ] || fail "project.yml not found - run from repo root"
[ -f "$EXPORT_OPTIONS" ]          || fail "ExportOptions.plist not found (see release guide)"
command -v xcodebuild >/dev/null  || fail "xcodebuild not found"
command -v create-dmg >/dev/null  || fail "create-dmg not found (brew install create-dmg)"
command -v xcrun >/dev/null       || fail "xcrun not found"

if [ -z "$SPARKLE_BIN" ]; then
  fail "Sparkle bin not found - cannot generate signed updates"
else
  ok "Sparkle bin: $SPARKLE_BIN"
fi

[ -f "$SPARKLE_BIN/generate_keys" ] || fail "Sparkle generate_keys not found in $SPARKLE_BIN"
[ -z "$SPARKLE_PRIVATE_KEY_FILE" ] || [ -f "$SPARKLE_PRIVATE_KEY_FILE" ] \
  || fail "Sparkle private key file not found"
CONFIGURED_SPARKLE_PUBLIC_KEY=$(grep 'SUPublicEDKey:' "$PROJECT_DIR/project.yml" | head -1 | awk '{print $2}' | tr -d '"')
KEYCHAIN_SPARKLE_PUBLIC_KEY=$("$SPARKLE_BIN/generate_keys" -p)
[ -n "$CONFIGURED_SPARKLE_PUBLIC_KEY" ] || fail "SUPublicEDKey not found in project.yml"
if [ "$CONFIGURED_SPARKLE_PUBLIC_KEY" != "$KEYCHAIN_SPARKLE_PUBLIC_KEY" ]; then
  fail "Sparkle key mismatch: project.yml has $CONFIGURED_SPARKLE_PUBLIC_KEY but keychain has $KEYCHAIN_SPARKLE_PUBLIC_KEY"
fi
ok "Sparkle key matches project.yml"
if [ -n "$SPARKLE_PRIVATE_KEY_FILE" ]; then
  xcrun swift "$SCRIPT_DIR/verify-sparkle-key.swift" \
    "$SPARKLE_PRIVATE_KEY_FILE" "$CONFIGURED_SPARKLE_PUBLIC_KEY" \
    || fail "Explicit Sparkle private key does not match project.yml"
  ok "Sparkle signing will use the explicit private key file"
fi

for manifest in \
  "$PROJECT_DIR/Extensions/chrome/manifest.json" \
  "$PROJECT_DIR/Extensions/firefox/manifest.json" \
  "$PROJECT_DIR/Extensions/safari/manifest.json"; do
  EXTENSION_VERSION=$(plutil -extract version raw -o - "$manifest")
  [ "$EXTENSION_VERSION" = "$MARKETING_VERSION" ] \
    || fail "$(basename "$(dirname "$manifest")") extension version $EXTENSION_VERSION does not match $MARKETING_VERSION"
done
ok "Browser extension versions match the app"

# Check notarization credentials exist (dry run)
if [ "$SKIP_NOTARIZE" = false ]; then
  ok "Notarization will use keychain profile '$KEYCHAIN_PROFILE'"
fi

ok "All checks passed"

# ---- Generate Xcode project ----

info "Generating Xcode project"
cd "$PROJECT_DIR"
xcodegen generate
ok "project.yml -> Yojam.xcodeproj"

# ---- Archive ----

if [ "$SKIP_ARCHIVE" = false ]; then
  info "Archiving"
  rm -rf "$ARCHIVE_PATH"
  # `clean` first so a rotated provisioning profile can't leave a stale
  # build manifest pinning a now-missing .provisionprofile path.
  xcodebuild clean archive \
    -project Yojam.xcodeproj \
    -scheme Yojam \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="${RS_TEAM_ID}" \
    -allowProvisioningUpdates \
    -quiet
  ok "Archive created"
else
  info "Skipping archive (--skip-archive)"
  [ -d "$ARCHIVE_PATH" ] || fail "No existing archive at $ARCHIVE_PATH"
  ok "Using existing archive"
fi

# ---- Export ----

info "Exporting with Developer ID signing"
rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates \
  -quiet
ok "Exported to $EXPORT_PATH"

# ---- Validate bundle ----

info "Validating bundle"
BUNDLE_VALIDATOR="$SCRIPT_DIR/validate-bundle.sh"
[ -x "$BUNDLE_VALIDATOR" ] \
  || fail "validate-bundle.sh is missing or not executable"
"$BUNDLE_VALIDATOR" "$APP_PATH"
ok "Bundle validation passed"

EXPORTED_MARKETING_VERSION=$(plutil -extract CFBundleShortVersionString raw -o - \
  "$APP_PATH/Contents/Info.plist")
EXPORTED_BUILD_NUMBER=$(plutil -extract CFBundleVersion raw -o - \
  "$APP_PATH/Contents/Info.plist")
[ "$EXPORTED_MARKETING_VERSION" = "$MARKETING_VERSION" ] \
  || fail "Exported app version $EXPORTED_MARKETING_VERSION does not match $MARKETING_VERSION"
[ "$EXPORTED_BUILD_NUMBER" = "$BUILD_NUMBER" ] \
  || fail "Exported app build $EXPORTED_BUILD_NUMBER does not match $BUILD_NUMBER"
ok "Exported app is v${MARKETING_VERSION} (build ${BUILD_NUMBER})"

# Verify code signature
codesign --verify --deep --strict "$APP_PATH" 2>/dev/null
ok "Code signature valid"

# ---- Create DMG ----

info "Creating DMG"
rm -f "$DMG_PATH"
create-dmg \
  --volname "Yojam" \
  --icon "Yojam.app" 150 190 \
  --app-drop-link 450 190 \
  --window-size 600 400 \
  --hide-extension "Yojam.app" \
  "$DMG_PATH" \
  "$APP_PATH"
ok "$DMG_NAME created"

# ---- Notarize ----

if [ "$SKIP_NOTARIZE" = false ]; then
  info "Notarizing (this takes a few minutes)"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait
  ok "Notarization accepted"

  info "Stapling"
  xcrun stapler staple "$DMG_PATH"
  ok "Ticket stapled"
else
  info "Skipping notarization (--skip-notarize)"
fi

# ---- Sparkle EdDSA signature ----

info "Signing for Sparkle"
if [ -n "$SPARKLE_BIN" ]; then
  SIGNATURE=$("$SPARKLE_BIN/sign_update" "${SPARKLE_KEY_ARGS[@]}" "$DMG_PATH")
  ok "EdDSA signature generated"
  echo ""
  echo "    Add this to appcast.xml <enclosure>:"
  echo "    $SIGNATURE"
  echo ""
else
  echo "    ⚠ Skipped - set SPARKLE_BIN or build project in Xcode first"
fi

# ---- Generate appcast (optional) ----

RELEASES_DIR="$BUILD_DIR/releases"
DOWNLOAD_URL_PREFIX="https://yoj.am/releases/"
if [ -n "$SPARKLE_BIN" ] && [ -f "$SPARKLE_BIN/generate_appcast" ]; then
  info "Generating appcast"
  mkdir -p "$RELEASES_DIR"
  cp "$DMG_PATH" "$RELEASES_DIR/"
  # --download-url-prefix: enclosures must point at yoj.am/releases/ (where
  # the DMGs/deltas actually live). Without it, generate_appcast infers the
  # prefix from each bundle's SUFeedURL host (yoj.am/) and emits 404 URLs.
  "$SPARKLE_BIN/generate_appcast" "${SPARKLE_KEY_ARGS[@]}" "$RELEASES_DIR" \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX"
  if [ -f "$RELEASES_DIR/appcast.xml" ]; then
    ok "appcast.xml generated at $RELEASES_DIR/appcast.xml"
    ensure_update_signatures "$RELEASES_DIR/appcast.xml" "$RELEASES_DIR" "$DOWNLOAD_URL_PREFIX"
    DELTA_COUNT=$(find "$RELEASES_DIR" -maxdepth 1 -name "*.delta" | wc -l | tr -d ' ')
    if [ "$DELTA_COUNT" -gt 0 ]; then
      ok "$DELTA_COUNT delta file(s) in $RELEASES_DIR — upload alongside DMGs"
    fi
  else
    echo "    ⚠ generate_appcast ran but no appcast.xml found"
  fi
fi

# ---- Standalone browser extensions ----

info "Building browser extension packages"
"$PROJECT_DIR/Extensions/build.sh"
[ -f "$PROJECT_DIR/Extensions/dist/yojam-chrome.zip" ] \
  || fail "Chrome extension package was not created"
[ -f "$PROJECT_DIR/Extensions/dist/yojam-firefox.xpi" ] \
  || fail "Firefox extension package was not created"
ok "Browser extension packages created"

# ---- Homebrew cask ----
#
# Print a ready-to-submit cask block for Homebrew/homebrew-cask, pinned to the
# version + sha256 of the just-built DMG. The canonical cask path is
# Casks/y/yojam.rb.

info "Rendering Homebrew cask block"
DMG_SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')

CASK_CONTENT=$(cat <<EOF
cask "yojam" do
  version "${MARKETING_VERSION}"
  sha256 "${DMG_SHA256}"

  url "https://yoj.am/releases/Yojam-#{version}.dmg"
  name "Yojam"
  desc "Open links in selected browser, profiles, or apps"
  homepage "https://yoj.am/"

  livecheck do
    url "https://yoj.am/appcast.xml"
    strategy :sparkle, &:short_version
  end

  auto_updates true
  depends_on macos: :sonoma

  app "Yojam.app"

  uninstall launchctl: "org.yojam.cleanup",
            quit:      [
              "com.yojam.app",
              "com.yojam.app.NativeHost",
              "com.yojam.app.SafariExtension",
              "com.yojam.app.ShareExtension",
            ]

  zap trash: [
    "~/.config/yojam",
    "~/Library/Application Scripts/group.org.yojam.shared",
    "~/Library/Application Support/*/*/NativeMessagingHosts/org.yojam.host.json",
    "~/Library/Application Support/*/NativeMessagingHosts/org.yojam.host.json",
    "~/Library/Application Support/com.yojam.app",
    "~/Library/Application Support/Yojam",
    "~/Library/Caches/com.yojam.app*",
    "~/Library/Group Containers/group.org.yojam.shared",
    "~/Library/HTTPStorages/com.yojam.app",
    "~/Library/HTTPStorages/com.yojam.app.binarycookies",
    "~/Library/LaunchAgents/org.yojam.cleanup.plist",
    "~/Library/Logs/Yojam",
    "~/Library/Preferences/com.yojam.app.*",
    "~/Library/Saved Application State/com.yojam.app.savedState",
    "~/Library/WebKit/com.yojam.app",
  ]
end
EOF
)

ok "Cask rendered for v${MARKETING_VERSION} (sha256 ${DMG_SHA256:0:12}...)"

echo ""
echo "  ── Homebrew cask (paste into Homebrew/homebrew-cask Casks/y/yojam.rb) ──"
echo ""
printf '%s\n' "$CASK_CONTENT" | sed 's/^/  /'
echo ""
echo "  ──────────────────────────────────────────────────────────"

# ---- Summary ----

echo ""
echo "  ┌──────────────────────────────────────────┐"
echo "  │  Release build complete                   │"
echo "  │                                           │"
printf "  │  Version: %-31s│\n" "v${MARKETING_VERSION} (build ${BUILD_NUMBER})"
printf "  │  DMG:     %-31s│\n" "$DMG_NAME"
echo "  │                                           │"
echo "  │  Next steps:                              │"
echo "  │  1. Upload DMG + any *.delta files to     │"
echo "  │     yoj.am/releases/                      │"
echo "  │  2. Upload appcast.xml to yoj.am/         │"
echo "  │  3. Update Homebrew/homebrew-cask at      │"
echo "  │     Casks/y/yojam.rb, then open a PR      │"
echo "  │  4. Attach the DMG, Chrome ZIP, and       │"
echo "  │     Firefox XPI to the GitHub release     │"
echo "  │  5. Verify: open old version, check for   │"
echo "  │     updates, confirm it finds the new one │"
echo "  └──────────────────────────────────────────┘"
echo ""

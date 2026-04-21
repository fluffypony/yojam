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
  echo "    ⚠ Sparkle bin not found - will skip EdDSA signing"
  echo "    Set SPARKLE_BIN env var or build the project once in Xcode"
else
  ok "Sparkle bin: $SPARKLE_BIN"
fi

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
if [ -x "$SCRIPT_DIR/validate-bundle.sh" ]; then
  "$SCRIPT_DIR/validate-bundle.sh" "$APP_PATH"
  ok "Bundle validation passed"
else
  echo "    ⚠ validate-bundle.sh not found, skipping"
fi

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
  SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG_PATH")
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
if [ -n "$SPARKLE_BIN" ] && [ -f "$SPARKLE_BIN/generate_appcast" ]; then
  info "Generating appcast"
  mkdir -p "$RELEASES_DIR"
  cp "$DMG_PATH" "$RELEASES_DIR/"
  # --download-url-prefix: enclosures must point at yoj.am/releases/ (where
  # the DMGs/deltas actually live). Without it, generate_appcast infers the
  # prefix from each bundle's SUFeedURL host (yoj.am/) and emits 404 URLs.
  "$SPARKLE_BIN/generate_appcast" "$RELEASES_DIR" \
    --download-url-prefix https://yoj.am/releases/
  if [ -f "$RELEASES_DIR/appcast.xml" ]; then
    ok "appcast.xml generated at $RELEASES_DIR/appcast.xml"
    DELTA_COUNT=$(find "$RELEASES_DIR" -maxdepth 1 -name "*.delta" | wc -l | tr -d ' ')
    if [ "$DELTA_COUNT" -gt 0 ]; then
      ok "$DELTA_COUNT delta file(s) in $RELEASES_DIR — upload alongside DMGs"
    fi
  else
    echo "    ⚠ generate_appcast ran but no appcast.xml found"
  fi
fi

# ---- Homebrew cask ----
#
# Render Casks/yojam.rb with the new version + sha256 of the just-built DMG
# and print the cask block so it can be copy-pasted into the homebrew tap.
# The authoritative template lives inline here so the formula stays in lockstep
# with what the release script just shipped.

info "Updating Homebrew cask"
DMG_SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
CASK_PATH="$PROJECT_DIR/Casks/yojam.rb"
mkdir -p "$(dirname "$CASK_PATH")"

CASK_CONTENT=$(cat <<EOF
cask "yojam" do
  version "${MARKETING_VERSION}"
  sha256 "${DMG_SHA256}"

  url "https://yoj.am/releases/Yojam-#{version}.dmg"
  name "Yojam"
  desc "Default-browser router with rules, profiles, and tracker stripping"
  homepage "https://yoj.am/"

  livecheck do
    url "https://yoj.am/appcast.xml"
    strategy :sparkle
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Yojam.app"

  uninstall quit: [
    "com.yojam.app",
    "com.yojam.app.ShareExtension",
    "com.yojam.app.SafariExtension",
    "com.yojam.app.NativeHost",
  ]

  zap trash: [
    "~/.config/yojam",
    "~/Library/Application Support/*/NativeMessagingHosts/org.yojam.host.json",
    "~/Library/Application Support/Yojam",
    "~/Library/Caches/com.yojam.app",
    "~/Library/Caches/com.yojam.app.CLI",
    "~/Library/Caches/com.yojam.app.NativeHost",
    "~/Library/Caches/com.yojam.app.SafariExtension",
    "~/Library/Caches/com.yojam.app.ShareExtension",
    "~/Library/Group Containers/group.org.yojam.shared",
    "~/Library/HTTPStorages/com.yojam.app",
    "~/Library/HTTPStorages/com.yojam.app.binarycookies",
    "~/Library/Logs/Yojam",
    "~/Library/Preferences/com.yojam.app.CLI.plist",
    "~/Library/Preferences/com.yojam.app.NativeHost.plist",
    "~/Library/Preferences/com.yojam.app.SafariExtension.plist",
    "~/Library/Preferences/com.yojam.app.ShareExtension.plist",
    "~/Library/Preferences/com.yojam.app.plist",
    "~/Library/Saved Application State/com.yojam.app.savedState",
    "~/Library/WebKit/com.yojam.app",
  ]
end
EOF
)

printf '%s\n' "$CASK_CONTENT" > "$CASK_PATH"
ok "Casks/yojam.rb updated (v${MARKETING_VERSION}, sha256 ${DMG_SHA256:0:12}...)"

echo ""
echo "  ── Homebrew cask (copy-paste into your tap) ──────────────"
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
echo "  │  3. Copy the cask block above into your   │"
echo "  │     homebrew tap and push                 │"
echo "  │  4. Verify: open old version, check for   │"
echo "  │     updates, confirm it finds the new one │"
echo "  └──────────────────────────────────────────┘"
echo ""

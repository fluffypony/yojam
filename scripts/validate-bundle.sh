#!/bin/bash
set -euo pipefail

APP="$1"

echo "=== Validating $APP ==="

# Check Info.plist keys
echo "Checking CFBundleURLTypes..."
plutil -extract CFBundleURLTypes xml1 -o - "$APP/Contents/Info.plist" | grep -q "http" \
  || { echo "FAIL: CFBundleURLTypes missing http scheme"; exit 1; }

echo "Checking LSUIElement..."
plutil -extract LSUIElement xml1 -o - "$APP/Contents/Info.plist" | grep -q "true" \
  || { echo "FAIL: LSUIElement not set"; exit 1; }

echo "Checking AuthenticationServices support..."
[ "$(plutil -extract ASWebAuthenticationSessionWebBrowserSupportCapabilities.IsSupported \
  raw -o - "$APP/Contents/Info.plist")" = "true" ] \
  || { echo "FAIL: Web authentication session support is missing"; exit 1; }

echo "Checking automation entitlement..."
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "automation.apple-events" || {
  echo "FAIL: Apple Events entitlement missing"
  exit 1
}

echo "Checking App Group profile authorisation..."
REQUIRED_APP_GROUP="group.org.yojam.shared"
PROFILE_CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/yojam-profile-check.XXXXXX")"
cleanup_profile_check() {
  /bin/rm -f "$PROFILE_CHECK_DIR"/*.plist
  /bin/rmdir "$PROFILE_CHECK_DIR"
}
trap cleanup_profile_check EXIT

require_app_group() {
  local plist="$1"
  local key_path="$2"
  local label="$3"
  local value

  if ! value=$(
    /usr/libexec/PlistBuddy -x \
      -c "Print :${key_path}" "$plist" 2>/dev/null
  ); then
    echo "FAIL: $label has no application-groups entitlement"
    exit 1
  fi

  case "$value" in
    *"<string>${REQUIRED_APP_GROUP}</string>"*) ;;
    *)
      echo "FAIL: $label does not authorise $REQUIRED_APP_GROUP"
      exit 1
      ;;
  esac
}

require_profile_string_authorisation() {
  local signed_plist="$1"
  local profile_plist="$2"
  local entitlement="$3"
  local label="$4"
  local signed_value
  local profile_value
  local profile_prefix

  if ! signed_value=$(
    /usr/libexec/PlistBuddy \
      -c "Print :${entitlement}" "$signed_plist" 2>/dev/null
  ); then
    echo "FAIL: Signed entitlements for $label have no $entitlement entitlement"
    exit 1
  fi
  if [ -z "$signed_value" ] || [[ "$signed_value" == *"*"* ]]; then
    echo "FAIL: Signed entitlements for $label have an invalid $entitlement value"
    exit 1
  fi

  if ! profile_value=$(
    /usr/libexec/PlistBuddy \
      -c "Print :Entitlements:${entitlement}" "$profile_plist" 2>/dev/null
  ); then
    echo "FAIL: Provisioning profile for $label has no $entitlement entitlement"
    exit 1
  fi

  if [[ "$profile_value" == *"*"* ]]; then
    profile_prefix="${profile_value%\*}"
    if [ -z "$profile_prefix" ] \
      || [[ "$profile_prefix" == *"*"* ]] \
      || [[ "$signed_value" != "$profile_prefix"* ]]; then
      echo "FAIL: Provisioning profile for $label does not authorise signed $entitlement value"
      exit 1
    fi
  elif [ "$profile_value" != "$signed_value" ]; then
    echo "FAIL: Provisioning profile for $label does not authorise signed $entitlement value"
    exit 1
  fi
}

SHARE_EXTENSION="$APP/Contents/PlugIns/YojamShareExtension.appex"
SAFARI_EXTENSION="$APP/Contents/PlugIns/YojamSafariExtension.appex"
NATIVE_HOST_APP="$APP/Contents/Helpers/YojamNativeHost.app"
NATIVE_HOST="$NATIVE_HOST_APP/Contents/MacOS/YojamNativeHost"
PROFILE_BUNDLES=("$APP" "$SHARE_EXTENSION" "$SAFARI_EXTENSION" "$NATIVE_HOST_APP")
PROFILE_COUNT=0
for BUNDLE in "${PROFILE_BUNDLES[@]}"; do
  [ -d "$BUNDLE" ] || {
    echo "FAIL: Required bundle is missing: $BUNDLE"
    exit 1
  }
  PROFILE="$BUNDLE/Contents/embedded.provisionprofile"
  [ -f "$PROFILE" ] || {
    echo "FAIL: Provisioning profile is missing for $BUNDLE"
    exit 1
  }
  PROFILE_COUNT=$((PROFILE_COUNT + 1))
  DECODED_PROFILE="$PROFILE_CHECK_DIR/profile-${PROFILE_COUNT}.plist"
  SIGNED_ENTITLEMENTS="$PROFILE_CHECK_DIR/entitlements-${PROFILE_COUNT}.plist"

  /usr/bin/security cms -D -i "$PROFILE" > "$DECODED_PROFILE" || {
    echo "FAIL: Could not decode provisioning profile for $BUNDLE"
    exit 1
  }
  /usr/bin/codesign -d --entitlements :- "$BUNDLE" \
    > "$SIGNED_ENTITLEMENTS" 2>/dev/null || {
    echo "FAIL: Could not read signed entitlements for $BUNDLE"
    exit 1
  }

  require_app_group \
    "$SIGNED_ENTITLEMENTS" \
    "com.apple.security.application-groups" \
    "Signed entitlements for $BUNDLE"
  require_app_group \
    "$DECODED_PROFILE" \
    "Entitlements:com.apple.security.application-groups" \
    "Provisioning profile for $BUNDLE"

  # App Group claims need a profile associated with this executable's App ID.
  # A bare helper with only an application-groups entitlement can ask for
  # access on every process launch because that association is missing.
  PROFILE_STRING_ENTITLEMENTS=(
    "com.apple.application-identifier"
    "com.apple.developer.team-identifier"
  )
  if [ "$BUNDLE" = "$APP" ]; then
    PROFILE_STRING_ENTITLEMENTS+=("com.apple.developer.ubiquity-kvstore-identifier")
  fi
  for ENTITLEMENT in "${PROFILE_STRING_ENTITLEMENTS[@]}"; do
    require_profile_string_authorisation \
      "$SIGNED_ENTITLEMENTS" \
      "$DECODED_PROFILE" \
      "$ENTITLEMENT" \
      "$BUNDLE"
  done

  BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw -o - "$BUNDLE/Contents/Info.plist")
  SIGNED_APP_ID=$(/usr/libexec/PlistBuddy -c "Print :com.apple.application-identifier" "$SIGNED_ENTITLEMENTS")
  case "$SIGNED_APP_ID" in
    *."$BUNDLE_ID") ;;
    *) echo "FAIL: Signed App ID does not match the bundle identifier for $BUNDLE"; exit 1 ;;
  esac
  SIGNING_IDENTIFIER=$(/usr/bin/codesign -d --verbose=2 "$BUNDLE" 2>&1 | /usr/bin/sed -n 's/^Identifier=//p')
  [ "$SIGNING_IDENTIFIER" = "$BUNDLE_ID" ] || {
    echo "FAIL: Signing identifier does not match the bundle identifier for $BUNDLE"
    exit 1
  }
done
echo "Validated $REQUIRED_APP_GROUP in $PROFILE_COUNT provisioning profiles"
echo "Validated iCloud KVS provisioning profile authorisation"

echo "Checking Sparkle framework..."
[ -d "$APP/Contents/Frameworks/Sparkle.framework" ] || {
  echo "FAIL: Sparkle.framework not found in bundle"
  exit 1
}

echo "Checking third-party resources..."
for resource in \
  babel-parser-7.28.4.js BabelParser-LICENSE.txt \
  SwiftURL-LICENSE.txt SwiftURL-NOTICE.txt; do
  find "$APP/Contents/Resources" -type f -name "$resource" -print -quit \
    | grep -q . || {
      echo "FAIL: Third-party resource missing: $resource"
      exit 1
    }
done

APP_INFO="$APP/Contents/Info.plist"
SHARE_INFO="$SHARE_EXTENSION/Contents/Info.plist"
SAFARI_INFO="$SAFARI_EXTENSION/Contents/Info.plist"
NATIVE_HOST_INFO="$NATIVE_HOST_APP/Contents/Info.plist"
APP_VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$APP_INFO")
APP_BUILD=$(plutil -extract CFBundleVersion raw -o - "$APP_INFO")

check_bundle_version() {
  local info_plist="$1"
  local label="$2"
  local version
  local build

  version=$(plutil -extract CFBundleShortVersionString raw -o - "$info_plist")
  build=$(plutil -extract CFBundleVersion raw -o - "$info_plist")

  [ "$APP_VERSION" = "$version" ] || {
    echo "FAIL: $label version $version does not match app version $APP_VERSION"
    exit 1
  }
  [ "$APP_BUILD" = "$build" ] || {
    echo "FAIL: $label build $build does not match app build $APP_BUILD"
    exit 1
  }
}

echo "Checking embedded extension versions..."
check_bundle_version "$SHARE_INFO" "Share extension"
check_bundle_version "$SAFARI_INFO" "Safari extension"
check_bundle_version "$NATIVE_HOST_INFO" "Native messaging helper"

echo "Checking native messaging helper identity..."
[ "$(plutil -extract CFBundleIdentifier raw -o - "$NATIVE_HOST_INFO")" = "com.yojam.app.NativeHost" ] || {
  echo "FAIL: Native messaging helper bundle identifier is invalid"
  exit 1
}
[ "$(plutil -extract LSBackgroundOnly raw -o - "$NATIVE_HOST_INFO")" = "true" ] || {
  echo "FAIL: Native messaging helper must be a background-only app"
  exit 1
}
[ -x "$NATIVE_HOST" ] || {
  echo "FAIL: Native messaging helper executable is missing"
  exit 1
}
[ ! -e "$APP/Contents/MacOS/YojamNativeHost" ] || {
  echo "FAIL: Obsolete unprovisioned native host is still bundled"
  exit 1
}

echo "Checking Safari Web Extension..."
[ -d "$SAFARI_EXTENSION" ] || {
  echo "FAIL: YojamSafariExtension.appex not found in bundle"
  exit 1
}
[ "$(plutil -extract NSExtension.NSExtensionPointIdentifier raw -o - "$SAFARI_INFO")" \
  = "com.apple.Safari.web-extension" ] || {
  echo "FAIL: Safari extension point is missing or invalid"
  exit 1
}
[ -n "$(plutil -extract NSExtension.NSExtensionPrincipalClass raw -o - "$SAFARI_INFO")" ] || {
  echo "FAIL: Safari extension principal class is missing"
  exit 1
}
SAFARI_RESOURCES="$SAFARI_EXTENSION/Contents/Resources"
for resource in \
  manifest.json background.js container-error.html yojam-bridge.js popup.html popup.js \
  options.html options.js _locales/en/messages.json \
  icons/16.png icons/48.png icons/128.png; do
  [ -f "$SAFARI_RESOURCES/$resource" ] || {
    echo "FAIL: Safari extension resource missing: $resource"
    exit 1
  }
done

MANIFEST_VERSION=$(plutil -extract version raw -o - "$SAFARI_RESOURCES/manifest.json")
[ "$APP_VERSION" = "$MANIFEST_VERSION" ] || {
  echo "FAIL: Safari manifest version $MANIFEST_VERSION does not match app version $APP_VERSION"
  exit 1
}

echo "Checking Chrome extension ID configuration..."
/bin/bash "$(dirname "$0")/validate-chrome-extension-ids.sh" \
  "$APP/Contents/Resources/chrome-extension-ids.json"

echo "=== All checks passed ==="

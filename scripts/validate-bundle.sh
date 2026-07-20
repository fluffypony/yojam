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

# Check entitlements
echo "Checking entitlements..."
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "ubiquity-kvstore-identifier" \
  || { echo "FAIL: iCloud KVS entitlement missing"; exit 1; }

echo "Checking automation entitlement..."
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "automation.apple-events" || {
  echo "FAIL: Apple Events entitlement missing"
  exit 1
}

echo "Checking Sparkle framework..."
[ -d "$APP/Contents/Frameworks/Sparkle.framework" ] || {
  echo "FAIL: Sparkle.framework not found in bundle"
  exit 1
}

echo "Checking Safari Web Extension..."
SAFARI_EXTENSION="$APP/Contents/PlugIns/YojamSafariExtension.appex"
[ -d "$SAFARI_EXTENSION" ] || {
  echo "FAIL: YojamSafariExtension.appex not found in bundle"
  exit 1
}
SAFARI_INFO="$SAFARI_EXTENSION/Contents/Info.plist"
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

APP_VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")
EXTENSION_VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$SAFARI_INFO")
[ "$APP_VERSION" = "$EXTENSION_VERSION" ] || {
  echo "FAIL: Safari extension version $EXTENSION_VERSION does not match app version $APP_VERSION"
  exit 1
}
MANIFEST_VERSION=$(plutil -extract version raw -o - "$SAFARI_RESOURCES/manifest.json")
[ "$APP_VERSION" = "$MANIFEST_VERSION" ] || {
  echo "FAIL: Safari manifest version $MANIFEST_VERSION does not match app version $APP_VERSION"
  exit 1
}

echo "Checking Chrome extension ID configuration..."
if [ ! -f "$APP/Contents/Resources/chrome-extension-ids.json" ]; then
  echo "WARNING: chrome-extension-ids.json not bundled — Chrome native messaging will not install manifests"
fi

echo "=== All checks passed ==="

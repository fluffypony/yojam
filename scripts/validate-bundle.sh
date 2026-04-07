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

echo "Checking for placeholder extension ID..."
if grep -rq "placeholder_extension_id" "$APP/Contents/MacOS/" 2>/dev/null; then
  echo "WARNING: placeholder_extension_id found in binary — Chrome native messaging will not work"
fi

echo "=== All checks passed ==="

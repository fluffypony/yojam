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

echo "=== All checks passed ==="

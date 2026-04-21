#!/bin/bash
# Xcode Cloud post-clone hook.
#
# The canonical Xcode project is generated from project.yml via xcodegen and
# is not committed to the repo (*.xcodeproj/ is gitignored). Xcode Cloud looks
# for Yojam.xcodeproj at the repo root immediately after cloning, so we must
# install xcodegen and generate the project here before the build step runs.

set -euo pipefail

# Xcode Cloud invokes this script from inside ci_scripts/. Move to repo root.
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing xcodegen via Homebrew"
  brew install xcodegen
fi

echo "Generating Yojam.xcodeproj from project.yml"
xcodegen generate

# Xcode Cloud disables automatic SPM dependency resolution and requires a
# committed Package.resolved inside the xcodeproj. The generated xcodeproj
# is not committed, so seed its xcshareddata/swiftpm/ with the root
# Package.resolved that SPM maintains from Package.swift.
RESOLVED_DEST_DIR="Yojam.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$RESOLVED_DEST_DIR"
cp Package.resolved "$RESOLVED_DEST_DIR/Package.resolved"
echo "Seeded $RESOLVED_DEST_DIR/Package.resolved"

# Xcode Cloud uses ad-hoc code signing for Build/Test actions (no Developer ID
# cert). Entitlements that require a real provisioning profile cause AMFI/
# RunningBoard to refuse launch at test time (Runningboard error 5, POSIX 162).
# Specifically, com.apple.developer.ubiquity-kvstore-identifier expands to
# "com.yojam.app" under ad-hoc (empty $(TeamIdentifierPrefix)) and is rejected.
# Strip provisioning-backed entitlements for CI only — local release.sh builds
# regenerate the full entitlements via `xcodegen generate`.
if [ "${CI:-}" = "TRUE" ]; then
  ENTITLEMENTS="Sources/Yojam/Resources/Yojam.entitlements"
  /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.ubiquity-kvstore-identifier" "$ENTITLEMENTS" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" "$ENTITLEMENTS" 2>/dev/null || true
  echo "Stripped provisioning-backed entitlements from $ENTITLEMENTS for ad-hoc CI build"
fi

# Pre-resolve SPM dependencies with retries. Sparkle is distributed as an SPM
# binary target hosted on github.com/releases/download/... which has flaky DNS
# resolution on Xcode Cloud runners (intermittent "hostname could not be found"
# errors). Warming the DerivedData artifact cache here, with retries, makes the
# subsequent xcodebuild invocations in Build/Test actions a cache hit.
DERIVED_DATA="${CI_DERIVED_DATA_PATH:-/Volumes/workspace/DerivedData}"
for attempt in 1 2 3; do
  if xcodebuild -resolvePackageDependencies \
      -project Yojam.xcodeproj \
      -scheme Yojam \
      -derivedDataPath "$DERIVED_DATA" \
      -hideShellScriptEnvironment; then
    echo "SPM resolve succeeded on attempt $attempt"
    break
  fi
  if [ "$attempt" -eq 3 ]; then
    echo "SPM resolve failed after 3 attempts"
    exit 1
  fi
  delay=$((attempt * 10))
  echo "SPM resolve attempt $attempt failed — retrying in ${delay}s"
  sleep "$delay"
done

echo "Post-clone setup complete"

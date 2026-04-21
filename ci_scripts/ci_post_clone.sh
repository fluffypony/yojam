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

echo "Post-clone setup complete"

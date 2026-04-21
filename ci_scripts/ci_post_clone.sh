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

echo "Post-clone setup complete"

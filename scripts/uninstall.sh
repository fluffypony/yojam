#!/bin/bash
# Yojam Uninstaller (standalone)
#
# Removes all Yojam-owned state from the current user's system.
# This script is self-contained and does not reference files inside
# the app bundle, so it remains usable even after Yojam.app is trashed.
#
# Usage:
#   ./uninstall.sh                # remove manifests, login item, logs only
#   ./uninstall.sh --all          # additionally remove rules/preferences
#
# Files removed:
#   ~/Library/Application Support/*/NativeMessagingHosts/org.yojam.host.json
#   ~/Library/Logs/Yojam
#
# With --all additionally:
#   ~/Library/Group Containers/group.org.yojam.shared
#   ~/Library/Application Support/Yojam
#   ~/Library/Preferences/com.yojam.app.plist
#   ~/.config/yojam

set -u

REMOVE_ALL=0
if [ "${1:-}" = "--all" ]; then
  REMOVE_ALL=1
fi

echo "==> Removing native messaging host manifests"
find "$HOME/Library/Application Support" -name "org.yojam.host.json" -type f -print -delete 2>/dev/null

echo "==> Unloading Yojam login items (best-effort)"
sfltool list-login-items 2>/dev/null | grep -i yojam >/dev/null && {
  # No CLI flag to remove; user can do this in System Settings > General > Login Items
  echo "    Note: open System Settings > General > Login Items to remove Yojam if listed."
}

echo "==> Removing logs"
rm -rf "$HOME/Library/Logs/Yojam" 2>/dev/null

if [ "$REMOVE_ALL" = "1" ]; then
  echo "==> Removing App Group container"
  rm -rf "$HOME/Library/Group Containers/group.org.yojam.shared" 2>/dev/null

  echo "==> Removing Application Support data"
  rm -rf "$HOME/Library/Application Support/Yojam" 2>/dev/null

  echo "==> Removing preferences"
  rm -f "$HOME/Library/Preferences/com.yojam.app.plist" 2>/dev/null
  defaults delete com.yojam.app 2>/dev/null

  echo "==> Removing config directory"
  rm -rf "$HOME/.config/yojam" 2>/dev/null
fi

echo "==> Done. Drag Yojam.app to the Trash if it is still in /Applications."

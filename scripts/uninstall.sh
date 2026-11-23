#!/usr/bin/env bash
set -e

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.tws-mic-switcher.plist"
PLIST_DEST="$LAUNCH_AGENTS_DIR/$PLIST_NAME"
BIN_LINK="$HOME/.local/bin/tws-mic-switcher"
UID_NUM="$(id -u)"

echo "==> Stopping tws-mic-switcher..."
launchctl bootout "gui/$UID_NUM/com.user.tws-mic-switcher" 2>/dev/null || launchctl unload "$PLIST_DEST" 2>/dev/null || true
rm -f "$PLIST_DEST"
rm -f "$BIN_LINK"

pkill -f "tws-mic-switcher" 2>/dev/null || true

echo "==> Uninstalled."

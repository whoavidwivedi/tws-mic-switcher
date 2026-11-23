#!/usr/bin/env bash
set -e

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.tws-mic-switcher.plist"
PLIST_DEST="$LAUNCH_AGENTS_DIR/$PLIST_NAME"
UID_NUM="$(id -u)"

echo "🛑 Uninstalling TWS Mic Switcher..."

if [ -f "$PLIST_DEST" ]; then
    echo "Stopping background daemon..."
    launchctl bootout "gui/$UID_NUM/com.user.tws-mic-switcher" 2>/dev/null || launchctl unload "$PLIST_DEST" 2>/dev/null || true
    rm -f "$PLIST_DEST"
    echo "Removed $PLIST_DEST"
fi

pkill -f "tws-mic-switcher daemon" 2>/dev/null || true
pkill -f "tws-mic-switcher menubar" 2>/dev/null || true

echo "✅ TWS Mic Switcher has been completely uninstalled and stopped."

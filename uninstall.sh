#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$DIR/scripts/uninstall.sh" ]; then
    bash "$DIR/scripts/uninstall.sh"
else
    LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
    PLIST_DEST="$LAUNCH_AGENTS_DIR/com.user.tws-mic-switcher.plist"
    UID_NUM="$(id -u)"
    
    launchctl bootout "gui/$UID_NUM/com.user.tws-mic-switcher" 2>/dev/null || launchctl unload "$PLIST_DEST" 2>/dev/null || true
    rm -f "$PLIST_DEST"
    pkill -f "tws-mic-switcher" 2>/dev/null || true
    echo "==> Uninstalled."
fi

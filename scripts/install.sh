#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_PATH="$DIR/bin/tws-mic-switcher"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.tws-mic-switcher.plist"
PLIST_DEST="$LAUNCH_AGENTS_DIR/$PLIST_NAME"
LOG_DIR="$HOME/Library/Logs"

echo "==> Building binary..."
mkdir -p "$DIR/bin"
mkdir -p "$DIR/tws-mic-switcher.app/Contents/MacOS"
mkdir -p "$DIR/tws-mic-switcher.app/Contents/Resources"

swiftc -O "$DIR"/Sources/*.swift -o "$BIN_PATH"
cp "$BIN_PATH" "$DIR/tws-mic-switcher.app/Contents/MacOS/tws-mic-switcher"

if [ -f "$DIR/AppIcon.icns" ]; then
    cp "$DIR/AppIcon.icns" "$DIR/tws-mic-switcher.app/Contents/Resources/AppIcon.icns"
fi

mkdir -p "$LAUNCH_AGENTS_DIR"
mkdir -p "$LOG_DIR"

echo "==> Configuring LaunchAgent..."
UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM/com.user.tws-mic-switcher" 2>/dev/null || launchctl unload "$PLIST_DEST" 2>/dev/null || true

sed -e "s|__BINARY_PATH__|$BIN_PATH|g" \
    -e "s|__HOME__|$HOME|g" \
    "$DIR/com.user.tws-mic-switcher.plist.template" > "$PLIST_DEST"

echo "==> Starting daemon..."
if launchctl bootstrap "gui/$UID_NUM" "$PLIST_DEST" 2>/dev/null; then
    :
else
    launchctl load -w "$PLIST_DEST" 2>/dev/null || true
fi

echo "==> Installed successfully."
echo "    Binary:  $BIN_PATH"
echo "    Service: $PLIST_DEST"
echo "    Logs:    $LOG_DIR/tws-mic-switcher.log"

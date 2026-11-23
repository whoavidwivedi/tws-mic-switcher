#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_PATH="$DIR/bin/tws-mic-switcher"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.tws-mic-switcher.plist"
PLIST_DEST="$LAUNCH_AGENTS_DIR/$PLIST_NAME"
LOG_DIR="$HOME/Library/Logs"

echo "🎧 Installing TWS Mic Switcher for macOS..."

# 1. Compile binary into both bin/ and the App bundle
echo "🔨 Building Swift binary and macOS App Bundle..."
mkdir -p "$DIR/bin"
mkdir -p "$DIR/TWS Mic Switcher.app/Contents/MacOS"
mkdir -p "$DIR/TWS Mic Switcher.app/Contents/Resources"

swiftc -O "$DIR"/Sources/*.swift -o "$DIR/bin/tws-mic-switcher"
cp "$DIR/bin/tws-mic-switcher" "$DIR/TWS Mic Switcher.app/Contents/MacOS/tws-mic-switcher"

if [ -f "$DIR/AppIcon.icns" ]; then
    cp "$DIR/AppIcon.icns" "$DIR/TWS Mic Switcher.app/Contents/Resources/AppIcon.icns"
fi

# Register the App bundle with LaunchServices
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DIR/TWS Mic Switcher.app" 2>/dev/null || true

# 2. Prepare LaunchAgent directory and logs
mkdir -p "$LAUNCH_AGENTS_DIR"
mkdir -p "$LOG_DIR"

# 3. Stop existing daemon if running
echo "🛑 Checking for running instances..."
UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM/com.user.tws-mic-switcher" 2>/dev/null || launchctl unload "$PLIST_DEST" 2>/dev/null || true

# 4. Generate plist
echo "📝 Configuring LaunchAgent at $PLIST_DEST..."
sed -e "s|__BINARY_PATH__|$BIN_PATH|g" \
    -e "s|__HOME__|$HOME|g" \
    "$DIR/com.user.tws-mic-switcher.plist.template" > "$PLIST_DEST"

# 5. Load and start daemon
echo "🚀 Starting background daemon..."
if launchctl bootstrap "gui/$UID_NUM" "$PLIST_DEST" 2>/dev/null; then
    echo "✅ Loaded via launchctl bootstrap."
else
    launchctl load -w "$PLIST_DEST"
    echo "✅ Loaded via launchctl load."
fi

# 6. Verify service status
sleep 1
if pgrep -f "$BIN_PATH daemon" > /dev/null; then
    echo "🎉 TWS Mic Switcher is running in the background!"
    echo "📋 Logs: $LOG_DIR/tws-mic-switcher.log"
else
    echo "⚠️ Daemon loaded. Check logs at $LOG_DIR/tws-mic-switcher.log if needed."
fi

echo ""
echo "✨ Features now active:"
echo " • Whenever your TWS/Bluetooth headphones connect, input automatically switches back to MacBook Air Mic."
echo " • High-quality stereo audio output (A2DP / AAC) is preserved for calls, music, and videos."
echo " • Native macOS notification banners will alert you whenever auto-switch triggers."
echo ""
echo "Commands:"
echo " • Check status:     $BIN_PATH status"
echo " • Force switch now: $BIN_PATH switch"
echo " • Launch Menu Bar:  $BIN_PATH menubar"
echo " • View live logs:   tail -f ~/Library/Logs/tws-mic-switcher.log"
echo " • Uninstall:        $DIR/scripts/uninstall.sh"

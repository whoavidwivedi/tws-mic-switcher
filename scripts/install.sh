#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_PATH="$DIR/bin/tws-mic-switcher"
BIN_LINK_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_LINK_DIR/tws-mic-switcher"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.tws-mic-switcher.plist"
PLIST_DEST="$LAUNCH_AGENTS_DIR/$PLIST_NAME"
LOG_DIR="$HOME/Library/Logs"
UID_NUM="$(id -u)"

source "$DIR/scripts/ui.sh"
trap 'printf "\n"; ui_fail "Installation cancelled."; exit 130' INT

VERSION="$(sed -n 's/.*appVersion = "\([^"]*\)".*/\1/p' "$DIR/Sources/Version.swift" | head -n 1)"
if [ -f "$PLIST_DEST" ]; then
    RESULT="Update"
else
    RESULT="Installation"
fi

ui_banner "$VERSION"
ui_step "Checking build tools"

if ! command -v swiftc >/dev/null 2>&1; then
    ui_fail "Xcode Command Line Tools are required."
    ui_info "Run: xcode-select --install"
    exit 1
fi

SWIFT_VERSION="$(swiftc --version 2>&1 | sed -n 's/.*Apple Swift version \([0-9.]*\).*/\1/p' | head -n 1)"
if [ -n "$SWIFT_VERSION" ]; then
    ui_success "Swift compiler found (Swift $SWIFT_VERSION)"
else
    ui_success "Swift compiler found"
fi

ui_step "Building tws-mic-switcher"
mkdir -p "$DIR/bin"
mkdir -p "$DIR/tws-mic-switcher.app/Contents/MacOS"
mkdir -p "$DIR/tws-mic-switcher.app/Contents/Resources"

build_binary() {
    swiftc -O "$DIR"/Sources/*.swift -o "$BIN_PATH"
    cp "$BIN_PATH" "$DIR/tws-mic-switcher.app/Contents/MacOS/tws-mic-switcher"
    if [ -f "$DIR/AppIcon.icns" ]; then
        cp "$DIR/AppIcon.icns" "$DIR/tws-mic-switcher.app/Contents/Resources/AppIcon.icns"
    fi
}

ui_run "Compiling binary" build_binary

mkdir -p "$BIN_LINK_DIR"
ln -sf "$BIN_PATH" "$BIN_LINK"

ui_step "Installing background service"
mkdir -p "$LAUNCH_AGENTS_DIR"
mkdir -p "$LOG_DIR"

install_launch_agent() {
    launchctl bootout "gui/$UID_NUM/com.user.tws-mic-switcher" 2>/dev/null || launchctl unload "$PLIST_DEST" 2>/dev/null || true

    sed -e "s|__BINARY_PATH__|$BIN_PATH|g" \
        -e "s|__HOME__|$HOME|g" \
        "$DIR/com.user.tws-mic-switcher.plist.template" > "$PLIST_DEST"

    plutil -lint "$PLIST_DEST" >/dev/null

    if ! launchctl bootstrap "gui/$UID_NUM" "$PLIST_DEST" 2>/dev/null; then
        launchctl load -w "$PLIST_DEST" 2>/dev/null || true
    fi

    launchctl print "gui/$UID_NUM/com.user.tws-mic-switcher" >/dev/null 2>&1
}

if ! ui_run "Loading LaunchAgent" install_launch_agent; then
    ui_info "Check $PLIST_DEST and the system log for details."
    exit 1
fi

PID="$(launchctl print "gui/$UID_NUM/com.user.tws-mic-switcher" 2>/dev/null | awk '/pid =/ {print $3; exit}')"
if [ -n "$PID" ]; then
    ui_success "Daemon running (pid $PID)"
fi

printf '\n%s  %s complete%s\n\n' "$C_BOLD" "$RESULT" "$C_RESET"
printf '    %-9s %s\n' "Version" "$VERSION"
printf '    %-9s %s\n' "CLI" "$BIN_LINK"
printf '    %-9s %s\n' "Binary" "$BIN_PATH"
printf '    %-9s %s\n' "Service" "$PLIST_DEST"
printf '    %-9s %s\n' "Logs" "$LOG_DIR/tws-mic-switcher.log"

case ":$PATH:" in
    *":$BIN_LINK_DIR:"*)
        CLI_CMD="tws-mic-switcher"
        ;;
    *)
        CLI_CMD="$BIN_LINK"
        printf '\n'
        ui_info "Add $BIN_LINK_DIR to PATH to run 'tws-mic-switcher' directly."
        ;;
esac

printf '\n  Next: %s%s status%s\n\n' "$C_CYAN" "$CLI_CMD" "$C_RESET"

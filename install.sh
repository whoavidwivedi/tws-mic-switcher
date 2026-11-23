#!/usr/bin/env bash
set -e

REPO_URL="https://github.com/whoavidwivedi/tws-mic-switcher"
INSTALL_DIR="$HOME/.tws-mic-switcher"

echo "==> Installing tws-mic-switcher..."

if ! command -v swiftc >/dev/null 2>&1; then
    echo "error: Xcode Command Line Tools are required. Run: xcode-select --install" >&2
    exit 1
fi

if [ -d "$INSTALL_DIR/.git" ]; then
    echo "==> Updating existing installation in $INSTALL_DIR..."
    if ! git -C "$INSTALL_DIR" pull --ff-only --quiet; then
        echo "error: could not update $INSTALL_DIR. Check your network connection and try again." >&2
        exit 1
    fi
else
    echo "==> Cloning repository to $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"
chmod +x scripts/*.sh
./scripts/install.sh

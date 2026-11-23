#!/usr/bin/env bash
set -e

REPO_URL="https://github.com/whoavidwivedi/tws-mic-switcher"
INSTALL_DIR="$HOME/.tws-mic-switcher"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_GREEN=$'\033[32m'
    C_RED=$'\033[31m'
    C_CYAN=$'\033[36m'
else
    C_RESET=""
    C_BOLD=""
    C_GREEN=""
    C_RED=""
    C_CYAN=""
fi

printf '\n%s  tws-mic-switcher installer%s\n\n' "$C_BOLD" "$C_RESET"

if [ -d "$INSTALL_DIR/.git" ]; then
    printf '%s  ▸%s Updating source in %s...\n' "$C_CYAN" "$C_RESET" "$INSTALL_DIR"
    if ! git -C "$INSTALL_DIR" pull --ff-only --quiet; then
        printf '%s  ✖%s Could not update %s. Check your network connection.\n' "$C_RED" "$C_RESET" "$INSTALL_DIR" >&2
        exit 1
    fi
else
    printf '%s  ▸%s Downloading source to %s...\n' "$C_CYAN" "$C_RESET" "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
    if ! git clone --quiet --depth 1 "$REPO_URL" "$INSTALL_DIR"; then
        printf '%s  ✖%s Could not download the repository. Check your network connection.\n' "$C_RED" "$C_RESET" >&2
        exit 1
    fi
fi

printf '%s  ✔%s Source ready\n' "$C_GREEN" "$C_RESET"

cd "$INSTALL_DIR"
chmod +x scripts/*.sh
exec ./scripts/install.sh

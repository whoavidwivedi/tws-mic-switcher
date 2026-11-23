#!/usr/bin/env bash
# Shared terminal UI helpers for the tws-mic-switcher installer.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_CYAN=$'\033[36m'
    UI_INTERACTIVE=1
else
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_GREEN=""
    C_YELLOW=""
    C_RED=""
    C_CYAN=""
    UI_INTERACTIVE=0
fi

ui_banner() {
    local version="${1:-}"
    printf '\n%s  tws-mic-switcher%s' "$C_BOLD" "$C_RESET"
    if [ -n "$version" ]; then
        printf ' %s' "$version"
    fi
    printf '\n'
    printf '%s  Keeps Bluetooth audio in high-quality stereo mode%s\n\n' "$C_DIM" "$C_RESET"
}

ui_step() {
    printf '%s  ▸%s %s\n' "$C_CYAN" "$C_RESET" "$*"
}

ui_success() {
    printf '%s  ✔%s %s\n' "$C_GREEN" "$C_RESET" "$*"
}

ui_warn() {
    printf '%s  !%s %s\n' "$C_YELLOW" "$C_RESET" "$*"
}

ui_fail() {
    printf '%s  ✖%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
}

ui_info() {
    printf '    %s%s%s\n' "$C_DIM" "$*" "$C_RESET"
}

# Run a command with a spinner, hiding its output unless it fails.
# Set TWS_INSTALLER_VERBOSE=1 to stream the command output instead.
ui_run() {
    local message="$1"
    shift

    if [ "${TWS_INSTALLER_VERBOSE:-0}" = "1" ]; then
        printf '  %s...\n' "$message"
        if "$@"; then
            ui_success "$message"
            return 0
        fi
        ui_fail "$message"
        return 1
    fi

    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/tws-install.XXXXXX")" || {
        ui_fail "Could not create a temporary directory."
        return 1
    }
    local log="$tmpdir/output"
    local status_file="$tmpdir/status"

    ( "$@" >"$log" 2>&1; printf '%s' "$?" >"$status_file" ) &
    local pid=$!
    local start=$SECONDS
    local frame=0

    if [ "$UI_INTERACTIVE" -eq 1 ]; then
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        while [ ! -f "$status_file" ]; do
            printf '\r  %s%s%s %s' "$C_CYAN" "${frames[$frame]}" "$C_RESET" "$message"
            frame=$(( (frame + 1) % ${#frames[@]} ))
            sleep 0.08
        done
        printf '\r\033[2K'
    fi

    wait "$pid" 2>/dev/null || true

    local status
    status="$(cat "$status_file" 2>/dev/null || echo 1)"
    local elapsed=$(( SECONDS - start ))
    local elapsed_label="${elapsed}s"
    if [ "$elapsed" -le 0 ]; then
        elapsed_label="<1s"
    fi

    if [ "$status" -eq 0 ]; then
        ui_success "$message (${elapsed_label})"
        rm -rf "$tmpdir"
        return 0
    fi

    ui_fail "$message"
    if [ -s "$log" ]; then
        printf '\n' >&2
        sed 's/^/    /' "$log" >&2
    fi
    rm -rf "$tmpdir"
    return "$status"
}

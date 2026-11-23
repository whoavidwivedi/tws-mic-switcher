# tws-mic-switcher

A lightweight, zero-dependency macOS background service that keeps your default audio input on your Mac's built-in microphone when Bluetooth headphones connect.

This prevents macOS from switching Bluetooth audio output from high-quality stereo (A2DP) to low-bitrate hands-free mode (SCO/HFP).

---

## Quick Install

Install and load the background daemon via Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/whoavidwivedi/tws-mic-switcher/main/install.sh | bash
```

The installer clones the source, compiles it locally with the system Swift compiler, and manages the daemon through `launchd`. No prebuilt binaries are downloaded.

To build from source locally instead:

```bash
git clone https://github.com/whoavidwivedi/tws-mic-switcher.git
cd tws-mic-switcher
make install
```

---

## Updating

Existing installations update in place. The installer pulls the latest source, rebuilds the binary, and reloads the LaunchAgent:

```bash
curl -fsSL https://raw.githubusercontent.com/whoavidwivedi/tws-mic-switcher/main/install.sh | bash
```

The installed binary can also update itself:

```bash
tws-mic-switcher update --check   # show whether a newer release exists
tws-mic-switcher update           # update and restart the service
```

Updates are never applied silently; the service only checks when you ask it to. Published releases, checksums, and release notes are available on the [Releases page](https://github.com/whoavidwivedi/tws-mic-switcher/releases).

If you installed from a local clone with `make install`, update that clone instead:

```bash
git pull
make install
```

> **Upgrading from v1.1.0 or earlier:** those releases generated the LaunchAgent with an incorrect hard-coded path. Run the installer once to repair it. The `update` command requires an already working installation.

---

## The Problem

When Bluetooth headphones or earbuds (AirPods, Sony, Bose, Galaxy Buds, OPPO, etc.) connect to a Mac, macOS automatically routes both default output and default input to the connected device.

As soon as an application (Zoom, Meet, Slack, Discord, FaceTime, or a web browser) accesses the microphone:

1. The Bluetooth connection drops from **A2DP stereo (AAC ~256 kbps)** down to **bidirectional hands-free profile (HFP/SCO)**.
2. In HFP mode, audio output bandwidth is throttled to **16 kHz mono (~64 kbps)**.
3. System sounds, music, and voices immediately sound muffled, compressed, and distorted.

By automatically holding the default input on the Mac's built-in microphone, macOS never activates the Bluetooth headset microphone profile. Audio output stays in full stereo A2DP at all times.

---

## Key Features

- **Automatic routing on connect:** Catches the initial connection event and routes default input back to the built-in microphone.
- **Survives login, reboot, and sleep:** Re-checks routing at daemon startup, after system wake, and after reconnects — including earbuds that were already connected before the daemon started.
- **Respects manual overrides:** If you deliberately select your Bluetooth mic in Control Center or System Settings (e.g., to walk away from your desk during a call), the daemon respects your choice and will not override it until the device reconnects.
- **Zero background CPU:** Event-driven via CoreAudio Hardware Abstraction Layer (`AudioObjectAddPropertyListenerBlock`) and IOKit power notifications. Consumes 0.0% CPU when idle; no polling loops or recurring timers.
- **Strictly read-only for audio output:** Output devices, volume sliders, mute states, and audio streams are never altered.
- **USB mic compatible:** Dedicated USB audio interfaces or USB microphones are left untouched.
- **Completely silent:** Runs headless in the background via `launchd` without desktop banners or notification popups.

---

## CLI Reference

The binary is installed to `~/.tws-mic-switcher/bin/tws-mic-switcher` and symlinked to `~/.local/bin/tws-mic-switcher`:

```bash
# Check current audio routing and active devices
tws-mic-switcher status

# Force input back to built-in mic immediately
tws-mic-switcher switch

# Pause or resume automatic switching
tws-mic-switcher disable
tws-mic-switcher enable

# Version and updates
tws-mic-switcher version
tws-mic-switcher update --check
tws-mic-switcher update

# Tail background daemon logs
tail -f ~/Library/Logs/tws-mic-switcher.log
```

If `~/.local/bin` is not on your `PATH`, use the full path or add it:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Optional Menu Bar App

If you prefer a menu bar icon with a live device overview and toggle controls:

```bash
tws-mic-switcher menubar
```

---

## Technical Details

- **Language:** Swift (compiled natively via `/usr/bin/swiftc` to an Apple Silicon `arm64` binary).
- **Frameworks:** CoreAudio HAL (`AudioObjectGetPropertyData`, `AudioObjectSetPropertyData`) and IOKit power management.
- **Process Management:** Managed as a user LaunchAgent (`~/Library/LaunchAgents/com.user.tws-mic-switcher.plist`) with `RunAtLoad` and `KeepAlive`.
- **Startup and wake handling:** The daemon opens a short routing window when it starts and after `kIOMessageSystemHasPoweredOn`, so devices that reconnect during login or sleep/wake are handled even when macOS reuses the same CoreAudio device ID.
- **Dependencies:** None. Links only against macOS system libraries in `/System/Library/Frameworks`.

---

## Uninstall

To remove the LaunchAgent and the CLI symlink:

```bash
curl -fsSL https://raw.githubusercontent.com/whoavidwivedi/tws-mic-switcher/main/uninstall.sh | bash
```

Or from a local clone:

```bash
make uninstall
```

To remove the managed source checkout as well:

```bash
rm -rf ~/.tws-mic-switcher
```

---

## License

MIT

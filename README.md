# GP OpenUI

An open-source graphical front-end and self-contained build for [GlobalProtect-openconnect](https://github.com/yuezk/GlobalProtect-openconnect) (`v2.5.1`), supporting password and SSO (SAML) authentication without the proprietary/paid upstream `gpgui`.

> **Disclaimer:** This is an unofficial third-party client and is not affiliated with or endorsed by Palo Alto Networks. GlobalProtect is a registered trademark of Palo Alto Networks.

<p align="center">
  <img src="https://github.com/user-attachments/assets/f19f05b5-1818-4f48-98be-4fc5b83b605f" />
</p>

## About

GP OpenUI bundles the open-source `gpclient` / `gpservice` / `gpauth` (`v2.5.1`) backend together with a free and open-source GUI (`gpgui`) built with [Tauri v2](https://tauri.app) (Rust + React + Material UI).

### Why?

The upstream `gpgui` binary is proprietary and paid, and newer upstream packages (`v3.x`) automatically download it via `gpgui-helper` whenever versions mismatch. This repository:

- Builds the entire stack (`gpclient`, `gpservice`, `gpauth`, and `gpgui`) locally from source at a matching `v2.5.1`.
- Disables automatic `gpgui-helper` downloads in `gpservice` so it always launches the local open-source `gpgui`.
- Blocks OS package managers (`dnf`, `apt`, `pacman`) from overwriting the binaries with the upstream paid package during system updates.

## Features

- **Password authentication** — standard username/password login
- **SSO/SAML authentication** — embedded WebView or external browser
- **Client certificate authentication** — PKCS#8 (`.pem`) and PKCS#12 (`.p12`/`.pfx`)
- **Cookie reuse** — stay logged in across SAML sessions (with one-click Clear Credentials)
- **System tray integration** — hide to tray on close (`✕`), left-click tray toggle, tray menu (Toggle Window, Settings, Connect/Disconnect, Quit), and live connection duration tooltip
- **Tunnel & connection options** — OS spoofing (Linux/Windows/macOS), HIP report submission, disable IPv6, disable DTLS, custom MTU, VPNC script, reconnect timeout
- **Theme support** — light, dark, and system-follow modes
- **Wayland and X11** — native Wayland support with automatic XWayland fallback on KDE and COSMIC sessions

## Repository Structure

```text
.
├── src/           # React + TypeScript + Material UI frontend
├── src-tauri/     # Tauri v2 Rust desktop shell (gpgui)
├── backend/       # Bundled GlobalProtect-openconnect v2.5.1 (gpclient, gpservice, gpauth)
└── install.sh     # End-to-end build, install, and OS-update-blocking script
```

## Installation

Run the installer as a regular user (it uses `sudo` internally where root privileges are required):

```bash
./install.sh
```

If you have already built the binaries and only want to reinstall them and apply system configuration:

```bash
./install.sh --install-only
```

### What `install.sh` does

1. Installs system build dependencies (`gtk3`, `webkit2gtk-4.1`, `openssl`, `vpnc-script`, etc.) via `apt`, `dnf`, or `pacman`
2. Installs Rust via `rustup`, Node.js LTS, and `pnpm` if not already present
3. Builds `gpclient`, `gpservice`, and `gpauth` (`v2.5.1`) from `backend/`
4. Builds `gpgui` (`v2.5.1`) from `src/` + `src-tauri/` (`pnpm tauri build --no-bundle`)
5. Stops any running GlobalProtect processes, removes any distro-installed `globalprotect-openconnect` package, and deletes `/usr/bin/gpgui-helper` and `/var/lib/gpclient/gpgui`
6. Configures your package manager to block `globalprotect-openconnect` from being reinstalled/upgraded during OS updates:
   - **Fedora/RHEL (`dnf`)**: `/etc/dnf/libdnf5.conf.d/99-exclude-globalprotect.conf` (DNF5) and `exclude=globalprotect-openconnect*` in `/etc/dnf/dnf.conf` (DNF4)
   - **Debian/Ubuntu (`apt`)**: `/etc/apt/preferences.d/99-block-globalprotect-openconnect` (`Pin-Priority: -1`)
   - **Arch Linux (`pacman`)**: `IgnorePkg = globalprotect-openconnect` in `/etc/pacman.conf`
7. Installs `gpclient`, `gpservice`, `gpauth`, and `gpgui` into `/usr/bin/`
8. Installs the Polkit policy (`/usr/share/polkit-1/actions/com.yuezk.gpgui.policy`) and desktop entry (`~/.local/share/applications/gp-openui.desktop`)

**Supported distributions:** Debian/Ubuntu (`apt`), Fedora/RHEL (`dnf`), Arch Linux (`pacman`)

## Usage

Launch **GP OpenUI** from your application launcher, or run:

```bash
gpclient launch-gui
```

To verify all installed binaries match `v2.5.1`:

```bash
gpclient --version && gpservice --version && gpgui --version
```

### Legacy TLS Configurations

Some GlobalProtect portals require older TLS renegotiation settings rejected by modern OpenSSL defaults. If connection fails with a TLS handshake error, launch with `--fix-openssl`:

```bash
gpclient --fix-openssl launch-gui
```

## Requirements

- Linux (Wayland or X11)
- One of: `apt`, `dnf`, or `pacman`
- `pkexec` (Polkit) for launching `gpservice` with root privileges
- Internet access during first build to fetch Rust/Node toolchains and crates/packages

## Credits

- **Original UI (`globalprotect-openconnect-openui`)**: Created by [Elane Faisal-Sage (MagiShira)](https://github.com/MagiShira/globalprotect-openconnect-openui) — licensed under GPL-2.0.
- **Backend (`GlobalProtect-openconnect`)**: Created by [yuezk](https://github.com/yuezk/GlobalProtect-openconnect) (`v2.5.1`) — licensed under GPL-3.0 / GPL-2.0.

## License

GPL-2.0

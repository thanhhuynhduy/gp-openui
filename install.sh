#!/usr/bin/env bash
# install.sh — One-shot build and install for GP OpenUI + gpclient/gpservice/gpauth v2.5.1
# Supported distros: Fedora/RHEL (dnf), Debian/Ubuntu (apt), Arch Linux (pacman)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$REPO_DIR/backend"
INSTALL_DIR="/usr/bin"

export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

info()  { printf '\033[0;32m[INFO]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[0;33m[WARN]\033[0m  %s\n' "$*"; }
error() { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()   { error "$*"; exit 1; }
have()  { command -v "$1" &>/dev/null; }

detect_pm() {
  if have apt-get;  then echo apt
  elif have dnf;    then echo dnf
  elif have pacman; then echo pacman
  else die "Unsupported package manager. Install dependencies manually and re-run."
  fi
}

install_build_deps() {
  local pm
  pm="$(detect_pm)"
  info "Detected package manager: $pm"
  info "Installing system build dependencies..."

  case "$pm" in
    apt)
      sudo apt-get update -q
      sudo apt-get install -y --no-install-recommends \
        curl build-essential pkg-config automake autoconf libtool autopoint \
        libssl-dev libgtk-3-dev libwebkit2gtk-4.1-dev \
        libjavascriptcoregtk-4.1-dev librsvg2-dev libsoup-3.0-dev \
        liblz4-dev libxml2-dev libgnutls28-dev libp11-kit-dev \
        nettle-dev libgmp-dev vpnc-scripts file patchelf
      ;;
    dnf)
      sudo dnf install -y \
        curl gcc gcc-c++ make pkg-config automake autoconf libtool gettext-devel \
        openssl-devel gtk3-devel webkit2gtk4.1-devel \
        javascriptcoregtk4.1-devel librsvg2-devel libsoup3-devel \
        lz4-devel libxml2-devel gnutls-devel p11-kit-devel \
        nettle-devel gmp-devel vpnc-script file patchelf
      ;;
    pacman)
      sudo pacman -Sy --needed --noconfirm \
        curl base-devel openssl gtk3 webkit2gtk-4.1 \
        librsvg lz4 libxml2 gnutls p11-kit nettle gmp vpnc file patchelf
      ;;
  esac
}

install_rust() {
  if ! have cargo; then
    info "Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    # shellcheck source=/dev/null
    source "${HOME}/.cargo/env"
  fi
  info "Rust version: $(rustc --version)"
}

install_node_pnpm() {
  if ! have node; then
    info "Node.js not found. Installing Node.js LTS..."
    local pm
    pm="$(detect_pm)"
    case "$pm" in
      apt)
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y nodejs
        ;;
      dnf)
        curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo -E bash -
        sudo dnf install -y nodejs
        ;;
      pacman)
        sudo pacman -Sy --needed --noconfirm nodejs npm
        ;;
    esac
  fi

  if ! have pnpm; then
    info "Installing pnpm into ~/.local..."
    mkdir -p "${HOME}/.local"
    npm install -g pnpm --prefix "${HOME}/.local"
  fi
  info "Node: $(node --version) | pnpm: $(pnpm --version)"
}

build_backend() {
  info "Building backend (gpclient, gpservice, gpauth v2.5.1)..."
  cd "$BACKEND_DIR"
  cargo build --release -p gpclient -p gpservice -p gpauth
}

build_gui() {
  info "Building GP OpenUI (gpgui v2.5.1)..."
  cd "$REPO_DIR"
  pnpm install --frozen-lockfile
  pnpm tauri build --no-bundle
}

block_upstream_package() {
  local pm
  pm="$(detect_pm)"
  info "Removing upstream globalprotect-openconnect package (if installed) and blocking OS upgrades..."

  case "$pm" in
    dnf)
      if rpm -q globalprotect-openconnect &>/dev/null; then
        sudo dnf remove -y globalprotect-openconnect
      fi
      if [ -d /etc/dnf/libdnf5.conf.d ]; then
        sudo tee /etc/dnf/libdnf5.conf.d/99-exclude-globalprotect.conf >/dev/null <<'EOF'
# Prevent DNF5 from installing/upgrading to upstream paid GlobalProtect GUI
[main]
excludepkgs=globalprotect-openconnect*
EOF
      fi
      if [ -f /etc/dnf/dnf.conf ] && ! grep -q "globalprotect-openconnect" /etc/dnf/dnf.conf; then
        sudo sed -i '/^\[main\]/a exclude=globalprotect-openconnect*' /etc/dnf/dnf.conf
      fi
      info "Blocked globalprotect-openconnect in DNF."
      ;;
    apt)
      if dpkg -s globalprotect-openconnect &>/dev/null; then
        sudo apt-get remove -y globalprotect-openconnect
      fi
      sudo tee /etc/apt/preferences.d/99-block-globalprotect-openconnect >/dev/null <<'EOF'
# Prevent APT from installing/upgrading to upstream paid GlobalProtect GUI
Package: globalprotect-openconnect*
Pin: release *
Pin-Priority: -1
EOF
      info "Blocked globalprotect-openconnect in APT."
      ;;
    pacman)
      if pacman -Qi globalprotect-openconnect &>/dev/null; then
        sudo pacman -Rns --noconfirm globalprotect-openconnect
      fi
      if [ -f /etc/pacman.conf ] && ! grep -q "globalprotect-openconnect" /etc/pacman.conf; then
        sudo sed -i '/^\[options\]/a IgnorePkg = globalprotect-openconnect' /etc/pacman.conf
      fi
      info "Blocked globalprotect-openconnect in pacman."
      ;;
  esac
}

install_all() {
  info "Stopping any running GlobalProtect processes..."
  pkill -f gpgui || true
  pkill -f gpclient || true
  sudo pkill -f gpservice || true

  block_upstream_package

  info "Removing any auto-downloaded paid gpgui and gpgui-helper..."
  sudo rm -f /var/lib/gpclient/gpgui \
    /usr/bin/gpgui-helper \
    /usr/bin/gpgui.upstream \
    /usr/share/applications/gpgui-helper.desktop \
    /usr/share/applications/gpgui.desktop

  info "Installing binaries to $INSTALL_DIR..."
  sudo install -m 755 "$BACKEND_DIR/target/release/gpclient" "$INSTALL_DIR/gpclient"
  sudo install -m 755 "$BACKEND_DIR/target/release/gpservice" "$INSTALL_DIR/gpservice"
  sudo install -m 755 "$BACKEND_DIR/target/release/gpauth" "$INSTALL_DIR/gpauth"
  sudo install -m 755 "$REPO_DIR/src-tauri/target/release/gpgui" "$INSTALL_DIR/gpgui"

  if [ -f "$BACKEND_DIR/packaging/files/usr/share/polkit-1/actions/com.yuezk.gpgui.policy" ]; then
    info "Installing polkit policy for gpservice..."
    sudo install -Dm644 \
      "$BACKEND_DIR/packaging/files/usr/share/polkit-1/actions/com.yuezk.gpgui.policy" \
      /usr/share/polkit-1/actions/com.yuezk.gpgui.policy
  fi

  info "Installing desktop entry and icon..."
  local icon_dir="${HOME}/.local/share/icons/hicolor/128x128/apps"
  local app_dir="${HOME}/.local/share/applications"
  mkdir -p "$icon_dir" "$app_dir"
  cp "$REPO_DIR/src-tauri/icons/128x128.png" "$icon_dir/gp-openui.png"

  cat > "$app_dir/gp-openui.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=GP OpenUI
Comment=Open-source GUI client for GlobalProtect VPN
GenericName=GlobalProtect VPN Client
Categories=Network;Dialup;
Exec=/usr/bin/gpclient launch-gui %u
MimeType=x-scheme-handler/globalprotectcallback;
Icon=gp-openui
Terminal=false
Keywords=GlobalProtect;Openconnect;SAML;connection;VPN;
EOF

  update-desktop-database "$app_dir" 2>/dev/null || true
}

main() {
  info "=== GP OpenUI Complete Installer (v2.5.1) ==="
  if [[ "${1:-}" == "--install-only" ]]; then
    install_all
  else
    install_build_deps
    install_rust
    install_node_pnpm
    build_backend
    build_gui
    install_all
  fi
  info "=== Done! Launch with: gpclient launch-gui ==="
}

main "$@"

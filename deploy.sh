#!/usr/bin/env bash
set -euo pipefail

# reMarkable 2 KOReader + readeck.koplugin deployment script
# Installs: xovi, rm-appload, xovi-tripletap, KOReader, readeck.koplugin

DEVICE_IP="${REMARKABLE_IP:-10.11.99.1}"
BACKUP_DIR="./backups/$(date +%Y%m%d_%H%M%S)"
TMP_DIR="$(mktemp -d)"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# --- SSH setup with password support ---
SSH_ARGS=(-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o ClearAllForwardings=yes)

if [[ -n "${REMARKABLE_PASS:-}" ]]; then
    command -v sshpass >/dev/null 2>&1 || { echo "ERROR: sshpass required when REMARKABLE_PASS is set (brew install sshpass)" >&2; exit 1; }
    export SSHPASS="$REMARKABLE_PASS"
    ssh_cmd() { sshpass -e ssh "${SSH_ARGS[@]}" "root@${DEVICE_IP}" "$@"; }
    scp_to() { sshpass -e scp "${SSH_ARGS[@]}" "$1" "root@${DEVICE_IP}:$2"; }
else
    ssh_cmd() { ssh "${SSH_ARGS[@]}" "root@${DEVICE_IP}" "$@"; }
    scp_to() { scp "${SSH_ARGS[@]}" "$1" "root@${DEVICE_IP}:$2"; }
fi

info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[SKIP]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

# --- Preflight checks ---
info "Checking SSH connectivity to ${DEVICE_IP}..."
ssh_cmd "true" 2>/dev/null || error "Cannot reach device at ${DEVICE_IP}. Is USB connected?"

FIRMWARE=$(ssh_cmd "cat /etc/version" 2>/dev/null || echo "unknown")
info "Device firmware: ${FIRMWARE}"

ARCH=$(ssh_cmd "uname -m")
if [[ "$ARCH" == "armv7l" ]]; then
    XOVI_ARCH="arm32"
elif [[ "$ARCH" == "aarch64" ]]; then
    XOVI_ARCH="aarch64"
else
    error "Unsupported architecture: $ARCH"
fi
info "Device architecture: ${ARCH} (${XOVI_ARCH})"

# --- Confirmation ---
cat <<EOF

╔══════════════════════════════════════════════════════════════╗
║  reMarkable 2 KOReader Deployment                          ║
╠══════════════════════════════════════════════════════════════╣
║  Device:     ${DEVICE_IP}
║  Firmware:   ${FIRMWARE}
║  Arch:       ${ARCH}
║
║  Will install:
║    1. xovi (extension framework)
║    2. rm-appload (app launcher)
║    3. xovi-tripletap (power button trigger)
║    4. KOReader (e-book reader)
║    5. readeck.koplugin (Readeck sync)
║
║  Backup of /home/root/ will be saved locally first.
╚══════════════════════════════════════════════════════════════╝

EOF

read -rp "Proceed with installation? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }

# --- Backup ---
info "Backing up /home/root/ to ${BACKUP_DIR}..."
mkdir -p "$BACKUP_DIR"
ssh_cmd "tar czf - -C /home/root --exclude='*.cache' --exclude='.cache' \
    xovi xovi-tripletap shims 2>/dev/null || true" > "${BACKUP_DIR}/home_root_backup.tar.gz" \
    || warn "Backup had warnings (may be empty on fresh device)"
info "Backup saved to ${BACKUP_DIR}/"

# --- Download components ---
info "Downloading latest releases..."

# 1. xovi (tar.gz)
XOVI_URL=$(curl -sL "https://api.github.com/repos/asivery/rm-xovi-extensions/releases/latest" \
    | grep "browser_download_url.*xovi.*${XOVI_ARCH}.*tar.gz" | head -n 1 | cut -d'"' -f4)
[[ -n "$XOVI_URL" ]] || error "Could not find xovi release for ${XOVI_ARCH}"
info "  xovi: $(basename "$XOVI_URL")"
curl -sL "$XOVI_URL" -o "${TMP_DIR}/xovi.tar.gz"

# 2. rm-appload (zip)
APPLOAD_URL=$(curl -sL "https://api.github.com/repos/asivery/rm-appload/releases/latest" \
    | grep "browser_download_url.*${XOVI_ARCH}" | head -n 1 | cut -d'"' -f4)
[[ -n "$APPLOAD_URL" ]] || error "Could not find rm-appload release for ${XOVI_ARCH}"
info "  rm-appload: $(basename "$APPLOAD_URL")"
curl -sL "$APPLOAD_URL" -o "${TMP_DIR}/appload.zip"

# 3. KOReader (zip)
if [[ "$XOVI_ARCH" == "aarch64" ]]; then
    KOREADER_URL=$(curl -sL "https://api.github.com/repos/koreader/koreader/releases/latest" \
        | grep "browser_download_url.*remarkable.*aarch64" | head -n 1 | cut -d'"' -f4)
else
    KOREADER_URL=$(curl -sL "https://api.github.com/repos/koreader/koreader/releases/latest" \
        | grep "browser_download_url.*remarkable" | grep -v "aarch64" | head -n 1 | cut -d'"' -f4)
fi
[[ -n "$KOREADER_URL" ]] || error "Could not find KOReader release"
info "  KOReader: $(basename "$KOREADER_URL")"
curl -sL "$KOREADER_URL" -o "${TMP_DIR}/koreader.zip"

# 4. readeck.koplugin (zip)
READECK_URL=$(curl -sL "https://api.github.com/repos/iceyear/readeck.koplugin/releases/latest" \
    | grep "browser_download_url.*\.zip" | head -n 1 | cut -d'"' -f4)
[[ -n "$READECK_URL" ]] || READECK_URL="https://github.com/iceyear/readeck.koplugin/archive/refs/heads/main.zip"
info "  readeck.koplugin: $(basename "$READECK_URL")"
curl -sL "$READECK_URL" -o "${TMP_DIR}/readeck.zip"

# --- Install xovi ---
if ssh_cmd "test -d /home/root/xovi" 2>/dev/null; then
    ok "xovi already installed — updating"
fi
info "Installing xovi..."
scp_to "${TMP_DIR}/xovi.tar.gz" "/tmp/xovi.tar.gz"
ssh_cmd "tar -xzf /tmp/xovi.tar.gz -C /home/root && rm -f /tmp/xovi.tar.gz"

# --- Install rm-appload ---
if ssh_cmd "test -d /home/root/shims && ls /home/root/shims/*.so >/dev/null 2>&1" 2>/dev/null; then
    ok "rm-appload shims already present — updating"
fi
info "Installing rm-appload..."
scp_to "${TMP_DIR}/appload.zip" "/tmp/appload.zip"
ssh_cmd 'mkdir -p /home/root/shims /tmp/appload_extract && \
    cd /tmp && unzip -qo appload.zip -d appload_extract && \
    find appload_extract -name "qtfb-shim*.so" -exec cp {} /home/root/shims/ \; && \
    find appload_extract -name "appload*.so" -exec cp {} /home/root/xovi/extensions.d/ \; && \
    rm -rf /tmp/appload_extract /tmp/appload.zip'

# --- Rebuild hashtable ---
info "Rebuilding hashtable (this may take a moment)..."
ssh_cmd "/home/root/xovi/rebuild_hashtable" || warn "Hashtable rebuild had issues — may need manual run"

# --- Install xovi-tripletap ---
if ssh_cmd "test -d /home/root/xovi-tripletap" 2>/dev/null; then
    ok "xovi-tripletap already installed — skipping"
else
    info "Installing xovi-tripletap..."
    ssh_cmd 'wget -qO- https://raw.githubusercontent.com/rmitchellscott/xovi-tripletap/main/install.sh | bash' \
        || warn "xovi-tripletap install had issues"
fi

# --- Install KOReader ---
if ssh_cmd "test -d /home/root/xovi/exthome/appload/koreader" 2>/dev/null; then
    ok "KOReader already installed — updating"
fi
info "Installing KOReader..."
scp_to "${TMP_DIR}/koreader.zip" "/tmp/koreader.zip"
ssh_cmd 'cd /tmp && unzip -qo koreader.zip && \
    mkdir -p /home/root/xovi/exthome/appload && \
    rm -rf /home/root/xovi/exthome/appload/koreader && \
    mv koreader /home/root/xovi/exthome/appload/ && \
    rm -f /tmp/koreader.zip'

# --- Install readeck.koplugin ---
if ssh_cmd "test -d /home/root/xovi/exthome/appload/koreader/plugins/readeck.koplugin" 2>/dev/null; then
    ok "readeck.koplugin already installed — updating"
fi
info "Installing readeck.koplugin..."
scp_to "${TMP_DIR}/readeck.zip" "/tmp/readeck.zip"
ssh_cmd 'cd /tmp && mkdir -p readeck_work && cd readeck_work && unzip -qo /tmp/readeck.zip && \
    rm -rf /home/root/xovi/exthome/appload/koreader/plugins/readeck.koplugin && \
    if [ -d "readeck.koplugin" ]; then \
        cp -r readeck.koplugin /home/root/xovi/exthome/appload/koreader/plugins/; \
    else \
        FOUND=$(find . -type d -name "readeck.koplugin" | sed -n "1p") && \
        if [ -n "$FOUND" ]; then \
            cp -r "$FOUND" /home/root/xovi/exthome/appload/koreader/plugins/readeck.koplugin; \
        else \
            echo "ERROR: readeck.koplugin dir not found in zip"; \
        fi; \
    fi && \
    cd /tmp && rm -rf readeck_work readeck.zip'

# --- Start xovi ---
info "Starting xovi..."
ssh_cmd "/home/root/xovi/start" || warn "xovi start returned non-zero (device may be restarting)"

# --- Done ---
cat <<EOF

╔══════════════════════════════════════════════════════════════╗
║  ✓ Installation complete!                                   ║
╠══════════════════════════════════════════════════════════════╣
║                                                             ║
║  Next steps:                                                ║
║    1. On the device, open the sidebar and tap "AppLoad"     ║
║    2. Launch KOReader from the AppLoad menu                 ║
║    3. In KOReader: Menu > Readeck > Settings                ║
║       - Server URL: (your readeck instance, no /api)        ║
║       - Auth: API Token or OAuth                            ║
║    4. After reboot: triple-tap power button to start xovi   ║
║                                                             ║
║  Backup location: ${BACKUP_DIR}                             ║
╚══════════════════════════════════════════════════════════════╝

EOF

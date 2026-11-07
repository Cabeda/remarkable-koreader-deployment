#!/usr/bin/env bash
set -euo pipefail

# reMarkable 2 KOReader + readeck.koplugin deployment script
# Installs: xovi, rm-appload, xovi-tripletap, KOReader, readeck.koplugin

# Load local config/credentials (gitignored) so launchd runs have the password too.
if [[ -f "$(dirname "$0")/.env" ]]; then
    set -a; . "$(dirname "$0")/.env"; set +a
fi

DEVICE_IP="${REMARKABLE_IP:-10.11.99.1}"
BACKUP_DIR="./backups/$(date +%Y%m%d_%H%M%S)"
TMP_DIR="$(mktemp -d)"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# --- SSH setup with password support ---
# The device regenerates SSH host keys on firmware updates, so don't pin them: this connects
# over USB/LAN with password auth to a device you physically own.
# Multiplex one connection: the device rate-limits repeated logins (seen ~8 in a burst).
SSH_ARGS=(-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o ClearAllForwardings=yes -o ControlMaster=auto
          -o ControlPath="${TMP_DIR}/ssh-%r@%h:%p" -o ControlPersist=60)

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

# --- Options ---
AUTO_CONFIRM=0
IF_CHANGED=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes)     AUTO_CONFIRM=1 ;;
        --if-changed) IF_CHANGED=1 ;;
        -h|--help)    echo "Usage: $0 [--yes] [--if-changed]"; exit 0 ;;
        *)            error "Unknown option: $arg" ;;
    esac
done

# --- Preflight checks ---
info "Checking SSH connectivity to ${DEVICE_IP}..."
ssh_cmd "true" 2>/dev/null || error "Cannot reach device at ${DEVICE_IP}. Is USB connected?"

FIRMWARE=$(ssh_cmd "cat /etc/version" 2>/dev/null || echo "unknown")
info "Device firmware: ${FIRMWARE}"

# reMarkable updates replace the rootfs, so a changed /etc/version is the trigger to reinstall.
LAST_FILE="$(cd "$(dirname "$0")" && pwd)/.last-firmware"
if [[ $IF_CHANGED -eq 1 && -f "$LAST_FILE" && "$(cat "$LAST_FILE")" == "$FIRMWARE" ]]; then
    info "Firmware ${FIRMWARE} already deployed — nothing to do."
    exit 0
fi

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

if [[ $AUTO_CONFIRM -eq 1 || ! -t 0 ]]; then
    info "Auto-confirmed (--yes or non-interactive stdin)."
else
    read -rp "Proceed with installation? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
fi

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
curl -sL "$XOVI_URL" -o "${TMP_DIR}/$(basename "$XOVI_URL")"

# 2. rm-appload (zip or tar.gz)
APPLOAD_URL=$(curl -sL "https://api.github.com/repos/asivery/rm-appload/releases/latest" \
    | grep "browser_download_url.*${XOVI_ARCH}" | head -n 1 | cut -d'"' -f4)
[[ -n "$APPLOAD_URL" ]] || error "Could not find rm-appload release for ${XOVI_ARCH}"
APPLOAD_FILE="$(basename "$APPLOAD_URL")"
info "  rm-appload: ${APPLOAD_FILE}"
curl -sL "$APPLOAD_URL" -o "${TMP_DIR}/${APPLOAD_FILE}"

# 3. KOReader (zip or tar.gz)
if [[ "$XOVI_ARCH" == "aarch64" ]]; then
    KOREADER_URL=$(curl -sL "https://api.github.com/repos/koreader/koreader/releases/latest" \
        | grep "browser_download_url.*remarkable.*aarch64" | head -n 1 | cut -d'"' -f4)
else
    KOREADER_URL=$(curl -sL "https://api.github.com/repos/koreader/koreader/releases/latest" \
        | grep "browser_download_url.*remarkable" | grep -v "aarch64" | head -n 1 | cut -d'"' -f4)
fi
[[ -n "$KOREADER_URL" ]] || error "Could not find KOReader release"
KOREADER_FILE="$(basename "$KOREADER_URL")"
info "  KOReader: ${KOREADER_FILE}"
curl -sL "$KOREADER_URL" -o "${TMP_DIR}/${KOREADER_FILE}"

# 4. readeck.koplugin (zip)
READECK_URL=$(curl -sL "https://api.github.com/repos/iceyear/readeck.koplugin/releases/latest" \
    | grep "browser_download_url.*\.zip" | head -n 1 | cut -d'"' -f4)
[[ -n "$READECK_URL" ]] || READECK_URL="https://github.com/iceyear/readeck.koplugin/archive/refs/heads/main.zip"
READECK_FILE="$(basename "$READECK_URL")"
info "  readeck.koplugin: ${READECK_FILE}"
curl -sL "$READECK_URL" -o "${TMP_DIR}/${READECK_FILE}"

# --- Install xovi ---
if ssh_cmd "test -d /home/root/xovi" 2>/dev/null; then
    info "xovi already installed — updating"
fi
info "Installing xovi..."
XOVI_FILE="$(basename "$XOVI_URL")"
scp_to "${TMP_DIR}/${XOVI_FILE}" "/tmp/${XOVI_FILE}"
ssh_cmd "tar -xzf /tmp/${XOVI_FILE} -C /home/root && rm -f /tmp/${XOVI_FILE}"

# --- Install rm-appload ---
if ssh_cmd "test -d /home/root/shims && ls /home/root/shims/*.so >/dev/null 2>&1" 2>/dev/null; then
    info "rm-appload shims already present — updating"
fi
info "Installing rm-appload..."
scp_to "${TMP_DIR}/${APPLOAD_FILE}" "/tmp/${APPLOAD_FILE}"
ssh_cmd bash -s -- "$APPLOAD_FILE" <<'EOS'
set -e
cd /tmp
rm -rf appload_extract && mkdir appload_extract
case "$1" in
    *.zip) unzip -qo "$1" -d appload_extract ;;
    *)     tar -xzf "$1" -C appload_extract ;;
esac
mkdir -p /home/root/shims /home/root/xovi/extensions.d
find appload_extract -name "qtfb-shim*.so" -exec cp {} /home/root/shims/ \;
find appload_extract -name "appload*.so" -exec cp {} /home/root/xovi/extensions.d/ \;
rm -rf appload_extract "/tmp/$1"
EOS

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
    info "KOReader already installed — updating"
fi
info "Installing KOReader..."
scp_to "${TMP_DIR}/${KOREADER_FILE}" "/tmp/${KOREADER_FILE}"
# Merge over the existing tree so settings/, books and readeck/ survive a reinstall.
# shortcut: files dropped from a release stay behind, wipe the dir manually on major jumps.
ssh_cmd bash -s -- "$KOREADER_FILE" <<'EOS'
set -e
cd /tmp
rm -rf koreader_extract && mkdir koreader_extract
case "$1" in
    *.zip) unzip -qo "$1" -d koreader_extract ;;
    *)     tar -xzf "$1" -C koreader_extract ;;
esac
[ -d koreader_extract/koreader ] || { echo "ERROR: koreader/ not found in archive" >&2; exit 1; }
mkdir -p /home/root/xovi/exthome/appload/koreader
cp -a koreader_extract/koreader/. /home/root/xovi/exthome/appload/koreader/
rm -rf koreader_extract "/tmp/$1"
EOS

# --- Install readeck.koplugin ---
if ssh_cmd "test -d /home/root/xovi/exthome/appload/koreader/plugins/readeck.koplugin" 2>/dev/null; then
    info "readeck.koplugin already installed — updating"
fi
info "Installing readeck.koplugin..."
scp_to "${TMP_DIR}/${READECK_FILE}" "/tmp/${READECK_FILE}"
ssh_cmd bash -s -- "$READECK_FILE" <<'EOS'
set -e
cd /tmp
rm -rf readeck_work && mkdir readeck_work && cd readeck_work
unzip -qo "/tmp/$1"
SRC=$(find . -type d -name "readeck.koplugin" | sed -n 1p)
[ -n "$SRC" ] || { echo "ERROR: readeck.koplugin dir not found in archive" >&2; exit 1; }
rm -rf /home/root/xovi/exthome/appload/koreader/plugins/readeck.koplugin
cp -r "$SRC" /home/root/xovi/exthome/appload/koreader/plugins/
cd /tmp && rm -rf readeck_work "/tmp/$1"
EOS

# --- Start xovi ---
info "Starting xovi..."
# Detached: xovi/start restarts xochitl and can keep the SSH channel open forever.
ssh_cmd "/home/root/xovi/start </dev/null >/tmp/xovi-start.log 2>&1 &"

# --- Done ---
echo "$FIRMWARE" > "$LAST_FILE"

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

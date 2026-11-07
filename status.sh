#!/usr/bin/env bash
# Health check: is KOReader installed and running on the connected device?
# Exits non-zero if anything expected is missing.
set -euo pipefail

if [[ -f "$(dirname "$0")/.env" ]]; then
    set -a; . "$(dirname "$0")/.env"; set +a
fi
REPO="$(cd "$(dirname "$0")" && pwd)"
DEVICE_IP="${REMARKABLE_IP:-10.11.99.1}"
SSH_ARGS=(-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o ClearAllForwardings=yes)
if [[ -n "${REMARKABLE_PASS:-}" ]]; then
    export SSHPASS="$REMARKABLE_PASS"
    ssh_cmd() { sshpass -e ssh "${SSH_ARGS[@]}" "root@${DEVICE_IP}" "$@"; }
else
    ssh_cmd() { ssh "${SSH_ARGS[@]}" "root@${DEVICE_IP}" "$@"; }
fi

ssh_cmd "true" 2>/dev/null || { echo "unreachable: ${DEVICE_IP} (USB connected? SSH enabled?)"; exit 2; }

ssh_cmd '
K=/home/root/xovi/exthome/appload/koreader
fw=$(cat /etc/version 2>/dev/null || echo unknown)
echo "firmware:  $fw"
echo "koreader:  $(cat $K/git-rev 2>/dev/null || echo MISSING)"
echo "settings:  $(ls $K/settings 2>/dev/null | wc -l) files"
echo "readeck:   $(ls -d $K/plugins/readeck.koplugin 2>/dev/null || echo MISSING)"
echo "readeck dir: $(ls -d /home/root/readeck 2>/dev/null || echo MISSING)"
if pidof xochitl >/dev/null 2>&1 && tr "\0" "\n" < /proc/$(pidof xochitl)/environ | grep -q LD_PRELOAD; then
    echo "xovi:      running"
else
    echo "xovi:      NOT running (triple-tap power, or run xovi/start)"
fi
' 2>/dev/null | grep -v 'Permanently added'

[[ -f "$REPO/.last-firmware" ]] && [[ "$(cat "$REPO/.last-firmware")" == "$(ssh_cmd 'cat /etc/version' 2>/dev/null)" ]] \
    || echo "note:      firmware differs from .last-firmware - deploy.sh will reinstall"

#!/usr/bin/env bash
# One-time setup: a launchd job that reruns deploy.sh whenever the device firmware changes.
# Usage: ./autoupdate.sh [install|remove]
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.$(id -un).remarkable-koreader"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ "${1:-install}" == "remove" ]]; then
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "Removed $LABEL."
    exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$REPO/deploy.sh</string>
        <string>--yes</string>
        <string>--if-changed</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>WorkingDirectory</key><string>$REPO</string>
    <key>RunAtLoad</key><true/>
    <key>StartInterval</key><integer>900</integer>
    <key>StandardOutPath</key><string>$REPO/autoupdate.log</string>
    <key>StandardErrorPath</key><string>$REPO/autoupdate.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed $LABEL."
echo "Checks the device every 15 min and reinstalls only when /etc/version changed."
echo "Log: $REPO/autoupdate.log"

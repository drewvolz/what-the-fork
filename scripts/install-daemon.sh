#!/bin/bash
set -e

# install-daemon.sh — builds WTFDaemon and installs it as a LaunchDaemon
# (runs as root). ESF requires root even with SIP disabled.
#
# Requires sudo. Usage:
#   sudo bash scripts/install-daemon.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_NAME="com.whatthefork.daemon"
PLIST_DEST="/Library/LaunchDaemons/${PLIST_NAME}.plist"
DERIVED_DATA="$REPO_ROOT/build/DerivedData"

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: this script must be run as root (use 'sudo bash scripts/install-daemon.sh')" >&2
  exit 1
fi

# Build as the calling user (not root) so Xcode/signing works correctly
CALLER="${SUDO_USER:-$(logname)}"
echo "Building WTFDaemon as user $CALLER..."
sudo -u "$CALLER" xcodebuild \
  -project "$REPO_ROOT/WhatTheFork.xcodeproj" \
  -scheme WTFDaemon \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build 2>&1 | grep -E "error:|BUILD"

DAEMON_BIN="$DERIVED_DATA/Build/Products/Debug/WTFDaemon"

if [ ! -f "$DAEMON_BIN" ]; then
  echo "Error: daemon binary not found at $DAEMON_BIN" >&2
  exit 1
fi

DAEMON_INSTALL_DIR="/Library/Application Support/WhatTheFork"
DAEMON_INSTALLED="$DAEMON_INSTALL_DIR/WTFDaemon"

echo "Installing daemon binary..."
mkdir -p "$DAEMON_INSTALL_DIR"
cp "$DAEMON_BIN" "$DAEMON_INSTALLED"
chown root:wheel "$DAEMON_INSTALLED"
chmod 755 "$DAEMON_INSTALLED"

echo "Writing LaunchDaemon plist..."
cat > "$PLIST_DEST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>MachServices</key>
    <dict>
        <key>${PLIST_NAME}</key>
        <true/>
    </dict>
    <key>ProgramArguments</key>
    <array>
        <string>${DAEMON_INSTALLED}</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/wtf-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/wtf-daemon.log</string>
</dict>
</plist>
EOF

chown root:wheel "$PLIST_DEST"
chmod 644 "$PLIST_DEST"

# Unload if already loaded
launchctl bootout "system/${PLIST_NAME}" 2>/dev/null || true

# Load into system context (starts on demand when wtf connects)
launchctl bootstrap system "$PLIST_DEST"

echo ""
echo "✅ WTFDaemon installed as LaunchDaemon (root)."
echo "   Mach service: ${PLIST_NAME}"
echo "   Logs: /tmp/wtf-daemon.log"
echo "   Starts on demand when 'wtf' connects."
echo ""
echo "To uninstall:"
echo "   sudo launchctl bootout system/${PLIST_NAME}"
echo "   sudo rm \"$PLIST_DEST\""
echo "   sudo rm -rf \"$DAEMON_INSTALL_DIR\""

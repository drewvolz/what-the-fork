#!/bin/bash
set -e

# install-daemon.sh — builds WTFDaemon and installs it as a LaunchAgent
# for local development. This registers it with launchd so the wtf CLI
# can connect to it via the com.whatthefork.daemon Mach service.
#
# Note: for full ESF (Endpoint Security) support, SIP must be disabled
# or the daemon binary must have the Apple-approved entitlement.
# For local dev, this wires up the XPC plumbing so you can test the
# architecture.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_NAME="com.whatthefork.daemon"
PLIST_DEST="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"
DERIVED_DATA="$REPO_ROOT/build/DerivedData"

echo "Building WTFDaemon..."
xcodebuild \
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

DAEMON_INSTALL_DIR="$HOME/Library/Application Support/WhatTheFork"
DAEMON_INSTALLED="$DAEMON_INSTALL_DIR/WTFDaemon"

echo "Installing daemon binary..."
mkdir -p "$DAEMON_INSTALL_DIR"
cp "$DAEMON_BIN" "$DAEMON_INSTALLED"
chmod 755 "$DAEMON_INSTALLED"

echo "Writing LaunchAgent plist..."
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

# Unload if already loaded
launchctl bootout "gui/$(id -u)/${PLIST_NAME}" 2>/dev/null || true

# Load (registers the Mach service with launchd; daemon starts on first connection)
launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"

echo ""
echo "✅ WTFDaemon installed and registered."
echo "   Mach service: ${PLIST_NAME}"
echo "   Logs: /tmp/wtf-daemon.log"
echo "   The daemon will start on demand when 'wtf' connects to it."
echo ""
echo "To uninstall:"
echo "   launchctl bootout gui/\$(id -u)/${PLIST_NAME}"
echo "   rm $PLIST_DEST"

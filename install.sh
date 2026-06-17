#!/usr/bin/env bash
set -euo pipefail

# claude-lamp installer.
# Compiles the app locally (no shipped binary -> no Gatekeeper/notarization),
# writes a LaunchAgent with this machine's paths, and merges the hooks into
# ~/.claude/settings.json (backed up first). Re-running is safe (idempotent).

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.claude/lamp"
SETTINGS="$HOME/.claude/settings.json"
LABEL="claude-lamp"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN="$INSTALL_DIR/claude-lamp"
HOOKS_BIN="$INSTALL_DIR/claude-lamp-hooks"
SCRIPT="$INSTALL_DIR/set-lamp.sh"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "error: swiftc not found. Install the Xcode Command Line Tools first:" >&2
    echo "       xcode-select --install" >&2
    exit 1
fi

echo "Installing claude-lamp to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents"

# Copy source + hook script and compile both tools locally.
cp "$REPO_DIR/lamp.swift" "$INSTALL_DIR/lamp.swift"
cp "$REPO_DIR/set-lamp.sh" "$SCRIPT"
chmod +x "$SCRIPT"
swiftc -O "$INSTALL_DIR/lamp.swift" -o "$BIN"
codesign -s - --force "$BIN" 2>/dev/null  # ad-hoc sign so the iTerm Automation grant persists
swiftc -O "$REPO_DIR/hooks.swift" -o "$HOOKS_BIN"

# Merge the hooks into settings.json (backs the file up first).
"$HOOKS_BIN" install "$SETTINGS" "$SCRIPT"

# Write the LaunchAgent with this machine's absolute paths.
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
</dict>
</plist>
PLIST_EOF

# (Re)load the agent.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo
echo "Done — the lamp is live in your menu bar (dim when idle)."
echo "Restart Claude Code so the hooks load, then it lights on activity."
echo "Quick test:  printf notify > ~/.claude/lamp/state   (red)"
echo "             printf done   > ~/.claude/lamp/state   (green)"
echo "             printf off    > ~/.claude/lamp/state   (idle)"

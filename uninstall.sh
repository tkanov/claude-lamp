#!/usr/bin/env bash
set -euo pipefail

# Removes claude-lamp: unloads the agent, un-merges the hooks (settings.json is
# backed up to .bak first by the helper), and deletes the install directory.

INSTALL_DIR="$HOME/.claude/lamp"
SETTINGS="$HOME/.claude/settings.json"
LABEL="claude-lamp"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

if [ -x "$INSTALL_DIR/claude-lamp-hooks" ] && [ -f "$SETTINGS" ]; then
    "$INSTALL_DIR/claude-lamp-hooks" uninstall "$SETTINGS" "$INSTALL_DIR/set-lamp.sh"
fi

rm -f "$PLIST"
rm -rf "$INSTALL_DIR"

echo "claude-lamp removed. Restart Claude Code to drop the hooks from the running session."

#!/bin/bash
# Hook target: write one state word for the menu-bar app to pick up.
mkdir -p "$HOME/.claude/lamp"
printf '%s' "${1:-off}" > "$HOME/.claude/lamp/state"

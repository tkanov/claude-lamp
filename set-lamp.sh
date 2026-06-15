#!/bin/bash
# Hook target. Records which terminal app is Claude's (macOS sets
# $__CFBundleIdentifier to the launching app's bundle id, inherited down to
# here) so the lamp can clear/raise it, then writes the state word. The term
# file is written first so the lamp sees a current value when it reads state.
DIR="$HOME/.claude/lamp"
mkdir -p "$DIR"
printf '%s' "${__CFBundleIdentifier:-}" > "$DIR/term"
printf '%s' "${1:-off}" > "$DIR/state"

#!/bin/bash
# Hook target for claude-lamp. Records per-session state under
# ~/.claude/lamp/sessions/<session_id> so the lamp can aggregate signals across
# parallel Claude Code sessions. The state word arrives as $1; the session id is
# pulled from the event JSON the hook pipes on stdin (with sed — no jq
# dependency), and the terminal app from $__CFBundleIdentifier. Writing "off"
# clears this session.
DIR="$HOME/.claude/lamp/sessions"
mkdir -p "$DIR"
word="${1:-off}"

# session id from stdin JSON; skip the read if stdin is a terminal (manual run)
sid=""
if [ ! -t 0 ]; then
    sid=$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi
[ -z "$sid" ] && sid="default"

f="$DIR/$sid"
if [ "$word" = "off" ]; then
    rm -f "$f"
else
    printf '%s\t%s' "$word" "${__CFBundleIdentifier:-}" > "$f"
fi

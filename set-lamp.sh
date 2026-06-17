#!/bin/bash
# claude-lamp hook target. Writes per-session state to
# ~/.claude/lamp/sessions/<session_id> (state word + terminal bundle id + iTerm
# session GUID; session id parsed from the event JSON on stdin with sed, no jq).
#   notify -> red, EXCEPT Claude's idle "waiting for your input" nudge, which
#             fires ~60s after every turn and re-fires each minute. Ignoring it
#             is what keeps a finished session from flipping back to red forever.
#             Permission prompts ("Claude needs your permission ...") stay red.
#   done   -> green;  off (UserPromptSubmit) -> clear this session.
DIR="$HOME/.claude/lamp/sessions"
mkdir -p "$DIR"
word="${1:-off}"
json=""
[ -t 0 ] || json=$(cat)

# Ignore the idle nudge (not urgent, and it never stops re-firing).
if [ "$word" = "notify" ]; then
    case "$json" in
        *'waiting for your input'*) exit 0 ;;
    esac
fi

sid=$(printf '%s' "$json" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$sid" ] && sid="default"

f="$DIR/$sid"
if [ "$word" = "off" ]; then
    rm -f "$f"
else
    printf '%s\t%s\t%s' "$word" "${__CFBundleIdentifier:-}" "${ITERM_SESSION_ID##*:}" > "$f"
fi

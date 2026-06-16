# Contributing

Thanks for taking a look. claude-lamp is small on purpose, a single Swift file plus a hook script, so it stays easy to read and tweak.

## How it's built

- `lamp.swift` — the menu-bar app. Every look-and-feel knob (colors, pulse speed, hold, cool-down, dim floor, timeouts, bar size) is a constant at the top.
- `set-lamp.sh` — the hook target. Writes per-session state to `~/.claude/lamp/sessions/<id>`.
- `install.sh` / `uninstall.sh` — compile locally, manage the LaunchAgent, and merge/unmerge the hooks in `settings.json`.
- `hooks.swift` — the settings.json merge helper (pure Foundation, no jq).

There is no build system. Compile the app with:

```bash
swiftc -O lamp.swift -o claude-lamp
```

## Testing a change

Edit your installed copy and reload:

```bash
swiftc -O ~/.claude/lamp/lamp.swift -o ~/.claude/lamp/claude-lamp
launchctl kickstart -k gui/$(id -u)/claude-lamp
```

Drive the lamp directly without waiting on real hooks:

```bash
printf 'notify\t' > ~/.claude/lamp/sessions/test   # red
printf 'done\t'   > ~/.claude/lamp/sessions/test   # green
rm ~/.claude/lamp/sessions/test                     # clear
```

## PRs

Keep it small and in the existing style. Describe what changed and why. Issues and ideas welcome, see the templates when you open one.

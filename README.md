# claude-lamp

A menu-bar status light for [Claude Code](https://claude.com/claude-code) on macOS. Glance up to see whether Claude needs you, without watching the terminal.

A small bar pulses on activity, styled like an old incandescent indicator behind a diffuser: quick flash, brief hold, exponential cool-down.

## What it shows

| Bar | Meaning |
|-----|---------|
| **Red** | Claude needs you (permission prompt or idle wait). Pulses until acknowledged. |
| **Green** | Turn finished. Auto-dims after ~2.5 min if you step away. |
| **Dim grey** | Idle. |

## Requirements

macOS, plus Xcode Command Line Tools for `swiftc`: `xcode-select --install`.

## Install

```bash
git clone https://github.com/tkanov/claude-lamp.git
cd claude-lamp
./install.sh
```

Restart Claude Code afterward so the hooks load. Nothing prebuilt is downloaded: the app compiles locally, so there is no Gatekeeper prompt and nothing to notarize.

## What the installer touches

1. Installs the app into `~/.claude/lamp/`.
2. Adds a LaunchAgent at `~/Library/LaunchAgents/claude-lamp.plist` (starts at login, relaunches on crash, stays quit when you quit it).
3. Merges three hooks (`Notification`, `Stop`, `UserPromptSubmit`) into `~/.claude/settings.json`. Existing hooks are preserved, the file is backed up to `settings.json.bak`, and re-running never duplicates.

## Using it

- **Left-click** the bar to jump to the terminal that lit it and clear the light.
- **Refocus that terminal** any other way and it also clears.
- **Right-click** to Quit.

Red persists until you act; green clears on your next prompt or the timeout. The lamp assumes the app frontmost when it lit is the terminal. That holds for turn-done; an idle notification fired after you switched away can capture the wrong app.

## Tuning

Every knob is a constant at the top of `lamp.swift` (colors, pulse speed, hold fraction, cool-down, dim floor, green timeout, bar size). Edit your installed copy and rebuild:

```bash
swiftc -O ~/.claude/lamp/lamp.swift -o ~/.claude/lamp/claude-lamp
launchctl kickstart -k gui/$(id -u)/claude-lamp
```

## How it works

A Claude Code hook is a short-lived command and can't hold an animated icon, so there are two pieces: a persistent menu-bar app that runs the animation, and hooks that write one word (`notify` / `done` / `off`) to `~/.claude/lamp/state` on each event. The app polls that file, and watches `NSWorkspace` activation events for the focus-clear and click-to-front behavior.

## Uninstall

```bash
./uninstall.sh
```

Restart Claude Code afterward to drop the hooks from the running session.

## Caveats

- One lamp per machine: all Claude Code windows share the one state file (last writer wins, any prompt clears it). Fine one session at a time.
- macOS only (AppKit menu bar).

## License

MIT. See [LICENSE](LICENSE).

# claude-lamp

A menu-bar status light for [Claude Code](https://claude.com/claude-code) on macOS. Glance up and know whether Claude needs you, without watching the terminal.

It puts a small pulsing bar in your menu bar that lights up on Claude Code activity. The pulse is styled like an old incandescent indicator behind a diffuser: a quick flash, a brief hold, then an exponential cool-down.

## What it shows

| Bar | Meaning |
|-----|---------|
| **Red** | Claude needs your input or attention (a permission prompt, or an idle wait). Pulses until you acknowledge. |
| **Green** | Claude finished its turn. Auto-dims after ~2.5 minutes if you step away. |
| **Dim grey** | Idle. |

## Requirements

- macOS
- Xcode Command Line Tools (for `swiftc`): `xcode-select --install`

## Install

```bash
git clone https://github.com/tkanov/claude-lamp.git
cd claude-lamp
./install.sh
```

Then restart Claude Code so the hooks load. After that it lights up on its own.

No binary is downloaded. The app compiles on your machine, so there is no "unidentified developer" Gatekeeper prompt and nothing to notarize.

## What the installer touches

For full transparency, `install.sh`:

1. Compiles and installs the app into `~/.claude/lamp/`.
2. Adds a LaunchAgent at `~/Library/LaunchAgents/claude-lamp.plist` so the lamp starts at login and relaunches if it crashes (a clean Quit stays quit).
3. Merges three hooks into `~/.claude/settings.json` (`Notification`, `Stop`, `UserPromptSubmit`). The file is backed up to `settings.json.bak` first, your existing hooks are preserved, and re-running never duplicates them.

## Using it

- **Left-click** the bar to jump to the terminal that lit it and clear the light in one go.
- **Refocus that terminal** by any means and the light clears on its own.
- **Right-click** for Quit.
- Red persists until you act. Green clears when you send your next prompt or after the timeout.

The lamp treats whichever app was frontmost when it lit as "the terminal." That is reliable for turn-done (you were just there); the soft spot is an idle notification that arrives after you have already switched away, which can capture the wrong app.

## Tuning

Every look-and-feel knob is a constant at the top of `lamp.swift`: colors, pulse speed, the hold fraction, the cool-down time constant, the dim floor, the green timeout, and the bar size. Edit your installed copy and rebuild:

```bash
swiftc -O ~/.claude/lamp/lamp.swift -o ~/.claude/lamp/claude-lamp
launchctl kickstart -k gui/$(id -u)/claude-lamp
```

## How it works

A Claude Code hook is a short-lived command, so it cannot itself hold an animated icon in the menu bar. So there are two pieces:

1. **A persistent menu-bar app** that owns the status item and runs the fade animation.
2. **Hooks** that, on each event, write one word (`notify` / `done` / `off`) to `~/.claude/lamp/state`.

The app polls that file and animates the bar to match. It also watches `NSWorkspace` app-activation events so it can clear itself (and know where to jump on click) when the terminal regains focus. That split is the whole design.

## Uninstall

```bash
./uninstall.sh
```

Restart Claude Code afterward to drop the hooks from the running session.

## Caveats

- One lamp per machine: all Claude Code windows share the single state file (last writer wins, any prompt clears it). Fine for one session at a time.
- macOS only (it uses AppKit's menu bar).

## License

MIT. See [LICENSE](LICENSE).

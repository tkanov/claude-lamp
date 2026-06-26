# claude-lamp

[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white)

A macOS menu-bar light for [Claude Code](https://claude.com/claude-code): **red** when a session is blocked on a permission prompt, **green** when a turn finishes. Know the moment Claude needs you, without watching the terminal or relying on notifications you'll miss.

<p align="center">
  <img src="assets/demo.gif" alt="claude-lamp in the macOS menu bar: the bar glows red when Claude needs you and green when a turn finishes" width="310">
</p>

A small bar pulses on activity, styled like an old incandescent indicator behind a diffuser: quick flash, brief hold, exponential cool-down.

## What it solves

Running Claude Code, you hit some version of these:

| The pain | What the lamp does |
|----------|--------------------|
| Alt-tabbing to the terminal to check whether Claude is done or waiting on you. | Red or green in the menu bar. No terminal-watching. |
| Claude blocks on a permission prompt and sits idle while you're in another window. | Turns **red** the moment a prompt blocks; clears when you answer or click it. |
| You start a long task and don't know when the turn ends. | Turns **green** the instant Claude finishes, holds until you're back. |
| Several sessions in parallel, no idea which one needs you. | Shows the most urgent state across all of them; click jumps to the exact session. |
| Desktop notifications are too noisy or too easy to miss. | One light, not a stream of toasts, and it ignores Claude's repeat "waiting for input" pings. |

## What it shows

| Bar | Meaning |
|-----|---------|
| **Red** | Claude is blocked on a permission prompt. Pulses until you answer it (or click the bar). |
| **Green** | Turn finished, your move. Pulses for a few minutes to catch your eye, then holds steady until you come back. |
| **Dim grey** | Idle, nothing pending. |

Claude Code also emits a "waiting for your input" nudge ~60s after every turn; that one is deliberately ignored, so a finished session shows green and holds steady instead of nagging you in red forever.

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
3. Merges four hooks (`Notification`, `Stop`, `UserPromptSubmit`, `PostToolUse`) into `~/.claude/settings.json`. Existing hooks are preserved, the file is backed up to `settings.json.bak`, and re-running never duplicates.

## Using it

- **Left-click** the bar to jump to the longest-waiting session's terminal and clear that signal. In iTerm this raises the exact window/tab that lit the bar; macOS will ask once to allow controlling iTerm.
- **Right-click** to Quit.

Red persists until you act on it: submit a prompt in that session (its `off` hook) or click the lamp. Green clears on your next prompt, on the timeout, or, running a single session, when you focus its terminal after a brief grace. With multiple sessions active that focus-clear stands down, because focusing one window can't say which session you meant.

## Tuning

Every knob is a constant at the top of `lamp.swift` (colors, pulse speed, hold fraction, cool-down, dim floor, green timeout, bar size). Edit your installed copy and rebuild:

```bash
swiftc -O ~/.claude/lamp/lamp.swift -o ~/.claude/lamp/claude-lamp
launchctl kickstart -k gui/$(id -u)/claude-lamp
```

## How it works

A Claude Code hook is a short-lived command and can't hold an animated icon, so there are two pieces: a persistent menu-bar app that runs the animation, and hooks that write a state word, the terminal's bundle id, and (in iTerm) its session id to `~/.claude/lamp/sessions/<session-id>`, one file per session. The app polls that directory and shows the most urgent state across sessions (red outranks green), pruning each as it clears or times out.

## Uninstall

```bash
./uninstall.sh
```

Restart Claude Code afterward to drop the hooks from the running session.

## Caveats

- The bar is a single color: with parallel sessions it shows the most urgent (red over green), not a count.
- In iTerm, click jumps to the exact window that lit the bar (matched by its session id). Other terminals raise the *app*, not a specific window, so across several windows they can't jump to the exact one.
- A session that exits without firing its `off` hook can leave a stale red; left-clicking the bar clears the shown signal.
- macOS only (AppKit menu bar).

## License

MIT. See [LICENSE](LICENSE).

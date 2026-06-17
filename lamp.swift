import Cocoa

// claude-lamp — a menu-bar status light for Claude Code.
// Each Claude session's hooks write its state to ~/.claude/lamp/sessions/<id>
// (one word + the terminal's bundle id). The lamp aggregates across sessions:
//   any session needs input -> red    (pulses until that session is handled)
//   else any session is done -> green  (pulses, then holds steady until acknowledged)
//   else                     -> dim idle bar
// Red outranks green. The click target and the single-session focus-clear use
// the longest-waiting session of the shown color. Knobs are the constants below.

let sessionsDir = ("~/.claude/lamp/sessions" as NSString).expandingTildeInPath
let blinkInterval = 0.25   // half-cycle of the pulse, seconds
let frameInterval = 1.0/30 // redraw cadence for the fade
let minAlpha = 0.05        // dimmest point of the fade (filament never fully cools)
let holdFrac = 0.5         // fraction of the cycle held at full brightness before fading
let coolTau  = 0.05        // exponential cool-down time constant, seconds (smaller = snuffs out faster)
let pollInterval  = 0.25   // sessions re-scan cadence
let greenPulseDuration = 300.0  // green pulses this long to catch your eye, then holds steady (no auto-dim — it clears on click, focus, or your next prompt)
let greenSteadyAlpha   = 0.75   // brightness of the steady green held after the pulse window
let redTimeout    = 600.0  // self-heal: drop a red older than this (abandoned permission prompt)
let graceDelay    = 2.0    // keep a single-session lamp lit this long before a frontmost terminal clears it
let idleColor   = NSColor(white: 0.42, alpha: 1.0)                             // dim idle bar
let notifyColor = NSColor(srgbRed: 0.88, green: 0.27, blue: 0.22, alpha: 1.0)  // red: input/attention needed
let doneColor   = NSColor(srgbRed: 0.00, green: 0.70, blue: 0.32, alpha: 1.0)  // green: turn done

struct Session { let word: String; let bundle: String; let guid: String; let mtime: TimeInterval; let path: String }

final class Lamp: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var blink: Timer?, phase: TimeInterval = 0, color = idleColor
    var pulseWindow: TimeInterval = .infinity   // pulse for this long, then hold steady (green); red pulses forever
    var steadyShown = false                     // drew the steady frame once, so the live timer can idle-skip
    var currentKey: String?     // "notify" / "done" / nil — what the lamp is showing now
    var targetBundle: String?   // terminal of the session to jump to on click
    var targetGuid: String?     // iTerm session GUID, to raise its exact window/tab
    var targetPath: String?     // that session's state file, cleared when clicked

    override init() {
        super.init()
        if let b = item.button {
            b.image = Lamp.bar(idleColor)
            b.target = self
            b.action = #selector(click)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    static func bar(_ c: NSColor) -> NSImage {
        let img = NSImage(size: NSSize(width: 34, height: 14))
        img.lockFocus()
        c.setFill()
        NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 30, height: 10), xRadius: 2, yRadius: 2).fill()
        img.unlockFocus()
        img.isTemplate = false   // keep our color; don't let macOS monochrome it
        return img
    }

    func scanSessions() -> [Session] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: sessionsDir) else { return [] }
        var out: [Session] = []
        for name in names {
            let path = sessionsDir + "/" + name
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let d = attrs[.modificationDate] as? Date,
                  let raw = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
            out.append(Session(word: parts.first ?? "",
                               bundle: parts.count > 1 ? parts[1] : "",
                               guid: parts.count > 2 ? parts[2] : "",
                               mtime: d.timeIntervalSince1970, path: path))
        }
        return out
    }

    func poll() {
        let now = Date().timeIntervalSince1970
        let fm = FileManager.default

        // Self-heal backstop: drop a red older than redTimeout so an abandoned
        // permission prompt can't pin the lamp. Greens don't auto-expire — they
        // hold steady until you click, focus the terminal, or send your next prompt.
        func expired(_ s: Session) -> Bool {
            s.word == "notify" && now - s.mtime > redTimeout
        }
        var sessions = scanSessions()
        for s in sessions where expired(s) { try? fm.removeItem(atPath: s.path) }
        sessions.removeAll(where: expired)

        let reds = sessions.filter { $0.word == "notify" }.sorted { $0.mtime < $1.mtime }
        let greens = sessions.filter { $0.word == "done" }.sorted { $0.mtime < $1.mtime }
        let active = reds + greens

        // Focus-clear the green "done" when its single session's terminal is
        // frontmost (after a grace). Red ("needs input") is left to nag until you
        // act on it — submit a prompt (its off hook) or click the lamp. Only with
        // one active session, since focusing one window can't say which you meant.
        if active.count == 1, let only = active.first, only.word == "done",
           blink != nil, phase >= graceDelay,
           !only.bundle.isEmpty, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == only.bundle {
            try? fm.removeItem(atPath: only.path)
            apply(nil, winner: nil)
            return
        }

        // Red outranks green; jump/clear target is the longest-waiting of the shown color.
        let winner = reds.first ?? greens.first
        apply(winner?.word, winner: winner)
    }

    func apply(_ key: String?, winner: Session?) {
        targetBundle = (winner?.bundle.isEmpty == false) ? winner?.bundle : nil
        targetGuid = (winner?.guid.isEmpty == false) ? winner?.guid : nil
        targetPath = winner?.path
        guard key != currentKey else { return }   // same color — keep the pulse running
        currentKey = key
        switch key {
        case "notify": start(notifyColor, pulseWindow: .infinity)
        case "done":   start(doneColor, pulseWindow: greenPulseDuration)
        default:       stop()
        }
    }

    func start(_ c: NSColor, pulseWindow: TimeInterval) {
        color = c; phase = 0; self.pulseWindow = pulseWindow; steadyShown = false
        blink?.invalidate()
        blink = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            s.phase += frameInterval
            if s.phase > s.pulseWindow {            // pulse window elapsed -> stop blinking, hold steady
                if !s.steadyShown {                 // draw the steady frame once; then the timer just idles,
                    s.steadyShown = true            // kept alive so the focus-clear still sees blink != nil
                    s.item.button?.image = Lamp.bar(s.color.withAlphaComponent(greenSteadyAlpha))
                }
                return
            }
            let cycle = 2 * blinkInterval
            let t = s.phase.truncatingRemainder(dividingBy: cycle)   // seconds into the pulse
            let riseT = 0.02, holdT = holdFrac * cycle               // snap on, then hold at full
            let glow: Double
            if t < riseT                { glow = t / riseT }                            // near-instant flash
            else if t < riseT + holdT   { glow = 1.0 }                                  // hold at full
            else                        { glow = exp(-(t - riseT - holdT) / coolTau) }  // exponential cool-down
            s.item.button?.image = Lamp.bar(s.color.withAlphaComponent(minAlpha + (1 - minAlpha) * glow))
        }
    }

    func stop() {
        blink?.invalidate(); blink = nil
        item.button?.image = Lamp.bar(idleColor)
    }

    @objc func click() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let m = NSMenu()
            m.addItem(withTitle: "Quit Claude Lamp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = m
            item.button?.performClick(nil)
            item.menu = nil            // detach so left-click dismisses next time
        } else {
            // Bundle id only names the app; with several terminal windows open it
            // can't say which one asked. For iTerm we have the session GUID, so raise
            // that exact window/tab. Other terminals fall back to app activation.
            if targetBundle == "com.googlecode.iterm2", let guid = targetGuid {
                raiseITermSession(guid)
            } else if let id = targetBundle {
                NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.activate()
            }
            if let p = targetPath { try? FileManager.default.removeItem(atPath: p) }  // acknowledge this signal
            // the next poll re-aggregates the remaining sessions
        }
    }

    // Bring just the one iTerm window forward. Two steps, deliberately split:
    //   1. AppleScript `select` makes the target iTerm's current window/tab/session.
    //      No `activate` here — that command raises ALL of iTerm's windows. select
    //      alone reorders within iTerm while it's still in the background, unseen.
    //   2. App-level activate raises only the front (now = target) window, leaving
    //      the sibling windows where they were.
    // `return` after selecting: select reorders windows, corrupting the loop's
    // positional refs if iteration continued.
    func raiseITermSession(_ guid: String) {
        let script = """
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if (id of s) is "\(guid)" then
                  select w
                  select t
                  select s
                  return
                end if
              end repeat
            end repeat
          end repeat
        end tell
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
        p.waitUntilExit()   // select must finish before we bring iTerm forward
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first?.activate()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)    // menu-bar only, no Dock icon
let lamp = Lamp()
app.run()

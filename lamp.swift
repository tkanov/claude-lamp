import Cocoa

// claude-lamp — a menu-bar status light for Claude Code.
// Each Claude session's hooks write its state to ~/.claude/lamp/sessions/<id>
// (one word + the terminal's bundle id). The lamp aggregates across sessions:
//   any session needs input -> red    (pulses until that session is handled)
//   else any session is done -> green  (auto-dims per session after greenTimeout)
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
let greenTimeout  = 150.0  // auto-dim a session's green "done" after this many seconds
let graceDelay    = 2.0    // keep a single-session lamp lit this long before a frontmost terminal clears it
let idleColor   = NSColor(white: 0.42, alpha: 1.0)                             // dim idle bar
let notifyColor = NSColor(srgbRed: 0.88, green: 0.27, blue: 0.22, alpha: 1.0)  // red: input/attention needed
let doneColor   = NSColor(srgbRed: 0.00, green: 0.70, blue: 0.32, alpha: 1.0)  // green: turn done

struct Session { let word: String; let bundle: String; let mtime: TimeInterval; let path: String }

final class Lamp: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var blink: Timer?, phase: TimeInterval = 0, color = idleColor
    var currentKey: String?     // "notify" / "done" / nil — what the lamp is showing now
    var targetBundle: String?   // terminal of the session to jump to on click
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
                               mtime: d.timeIntervalSince1970, path: path))
        }
        return out
    }

    func poll() {
        let now = Date().timeIntervalSince1970
        let fm = FileManager.default

        // Per-session green auto-dim: drop "done" sessions past the timeout.
        var sessions = scanSessions()
        for s in sessions where s.word == "done" && now - s.mtime > greenTimeout {
            try? fm.removeItem(atPath: s.path)
        }
        sessions.removeAll { $0.word == "done" && now - $0.mtime > greenTimeout }

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
        targetPath = winner?.path
        guard key != currentKey else { return }   // same color — keep the pulse running
        currentKey = key
        switch key {
        case "notify": start(notifyColor)
        case "done":   start(doneColor)
        default:       stop()
        }
    }

    func start(_ c: NSColor) {
        color = c; phase = 0
        blink?.invalidate()
        blink = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            s.phase += frameInterval
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
            if let id = targetBundle {
                NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.activate()
            }
            if let p = targetPath { try? FileManager.default.removeItem(atPath: p) }  // acknowledge this signal
            // the next poll re-aggregates the remaining sessions
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)    // menu-bar only, no Dock icon
let lamp = Lamp()
app.run()

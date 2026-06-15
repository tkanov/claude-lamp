import Cocoa

// claude-lamp — a menu-bar status light for Claude Code.
// Reads one word from ~/.claude/lamp/state and shows it as a pulsing bar:
//   notify -> red    (Claude needs input/attention — blinks until acknowledged)
//   done   -> green  (turn finished — auto-dims after greenTimeout)
//   off    -> dim idle bar
// The hook also records the terminal's bundle id in ~/.claude/lamp/term; the
// lamp clears whenever that terminal is frontmost and jumps to it on click.
// All look-and-feel knobs are the constants below.

let stateFile = ("~/.claude/lamp/state" as NSString).expandingTildeInPath
let termFile  = ("~/.claude/lamp/term" as NSString).expandingTildeInPath
let blinkInterval = 0.25   // half-cycle of the pulse, seconds
let frameInterval = 1.0/30 // redraw cadence for the fade
let minAlpha = 0.05        // dimmest point of the fade (filament never fully cools)
let holdFrac = 0.5         // fraction of the cycle held at full brightness before fading
let coolTau  = 0.05        // exponential cool-down time constant, seconds (smaller = snuffs out faster)
let pollInterval  = 0.25   // state-file re-read cadence
let greenTimeout  = 150.0  // auto-stop the green "turn done" pulse after this many seconds
let graceDelay    = 2.0    // keep the lamp lit at least this long before a frontmost terminal clears it
let idleColor   = NSColor(white: 0.42, alpha: 1.0)                             // dim idle bar
let notifyColor = NSColor(srgbRed: 0.88, green: 0.27, blue: 0.22, alpha: 1.0)  // red: input/attention needed
let doneColor   = NSColor(srgbRed: 0.00, green: 0.70, blue: 0.32, alpha: 1.0)  // green: turn done

final class Lamp: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var blink: Timer?, timeoutTimer: Timer?, phase: TimeInterval = 0, color = idleColor
    var lastContent = "", lastMtime: TimeInterval = -1
    var targetBundleId: String?   // bundle id of the terminal that lit the lamp (from the hook)

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

    func poll() {
        // Clear as soon as the terminal that lit the lamp is frontmost.
        if blink != nil, phase >= graceDelay, let id = targetBundleId,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == id {
            stop()
        }
        var content = "off", mtime: TimeInterval = -1
        if let a = try? FileManager.default.attributesOfItem(atPath: stateFile),
           let d = a[.modificationDate] as? Date {
            mtime = d.timeIntervalSince1970
            content = (try? String(contentsOfFile: stateFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "off"
        }
        guard content != lastContent || mtime != lastMtime else { return }
        lastContent = content; lastMtime = mtime
        switch content {
        case "notify": start(notifyColor, autoStopAfter: nil)          // input/attention needed — blinks until acknowledged
        case "done":   start(doneColor, autoStopAfter: greenTimeout)   // turn finished — auto-dims if ignored
        default:       stop()
        }
    }

    func start(_ c: NSColor, autoStopAfter: TimeInterval?) {
        color = c; phase = 0
        targetBundleId = Lamp.terminalBundleId()   // the terminal Claude is running in, per the hook
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
        timeoutTimer?.invalidate(); timeoutTimer = nil
        if let t = autoStopAfter {
            timeoutTimer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in self?.stop() }
        }
    }

    func stop() {
        blink?.invalidate(); blink = nil
        timeoutTimer?.invalidate(); timeoutTimer = nil
        item.button?.image = Lamp.bar(idleColor)
    }

    static func terminalBundleId() -> String? {
        let id = (try? String(contentsOfFile: termFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (id?.isEmpty == false) ? id : nil
    }

    @objc func click() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let m = NSMenu()
            m.addItem(withTitle: "Quit Claude Lamp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = m
            item.button?.performClick(nil)
            item.menu = nil            // detach so left-click dismisses next time
        } else {
            if let id = targetBundleId {
                NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.activate()
            }
            stop()                     // jump to the terminal and acknowledge the light
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)    // menu-bar only, no Dock icon
let lamp = Lamp()
app.run()

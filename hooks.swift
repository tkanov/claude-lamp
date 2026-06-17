import Foundation

// Installs or removes the claude-lamp hooks in a Claude Code settings.json.
// Non-destructive: existing hooks are preserved, ours are de-duplicated on
// re-run (idempotent), and the file is backed up to <settings>.bak before any
// write. Pure Foundation so it has no jq/python dependency (a stock Mac has
// neither, and the installer already requires swiftc).
//
// Usage: claude-lamp-hooks <install|uninstall> <settings.json path> <set-lamp.sh path>

let args = CommandLine.arguments
guard args.count == 4, args[1] == "install" || args[1] == "uninstall" else {
    FileHandle.standardError.write(Data("usage: claude-lamp-hooks <install|uninstall> <settings.json> <set-lamp.sh>\n".utf8))
    exit(2)
}
let mode = args[1]
let settingsPath = args[2]
let scriptPath = args[3]

// event -> state word the hook should write. PostToolUse also clears ("off"):
// after you answer a permission prompt, the granted tool runs and PostToolUse
// fires — the earliest signal that a red session is unblocked again.
let mapping = [("Notification", "notify"), ("Stop", "done"), ("UserPromptSubmit", "off"), ("PostToolUse", "off")]
let fm = FileManager.default

let existingData = fm.contents(atPath: settingsPath)
var root: [String: Any] = [:]
if let d = existingData, !d.isEmpty {
    guard let obj = try? JSONSerialization.jsonObject(with: d), let dict = obj as? [String: Any] else {
        FileHandle.standardError.write(Data("error: \(settingsPath) is not valid JSON; aborting to avoid clobbering it\n".utf8))
        exit(1)
    }
    root = dict
}

var hooks = (root["hooks"] as? [String: Any]) ?? [:]

// An entry is "ours" if any of its commands references our set-lamp.sh path.
func isOurs(_ entry: Any) -> Bool {
    guard let e = entry as? [String: Any], let list = e["hooks"] as? [[String: Any]] else { return false }
    return list.contains { ($0["command"] as? String)?.contains(scriptPath) == true }
}

for (event, word) in mapping {
    var entries = (hooks[event] as? [Any]) ?? []
    entries.removeAll(where: isOurs)   // drop any prior copy of ours (dedupe / repair)
    if mode == "install" {
        entries.append(["hooks": [["type": "command", "command": "\(scriptPath) \(word)"]]])
    }
    if entries.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = entries }
}

if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }

if let d = existingData {
    try? d.write(to: URL(fileURLWithPath: settingsPath + ".bak"))
}

do {
    let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try out.write(to: URL(fileURLWithPath: settingsPath))
    print("\(mode == "install" ? "Merged" : "Removed") claude-lamp hooks in \(settingsPath)")
} catch {
    FileHandle.standardError.write(Data("error writing \(settingsPath): \(error)\n".utf8))
    exit(1)
}

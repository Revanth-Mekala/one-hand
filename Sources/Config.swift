import Foundation

struct ShortcutEntry: Codable, Equatable {
    var trigger: String
    var action: String
    var note: String?
}

struct AppConfig: Codable, Equatable {
    /// Modifier to hold to switch one-hand mode on/off.
    var toggleKey = "opt"
    var toggleHoldSeconds = 3.0
    /// A lone modifier released within this time counts as a tap.
    var tapMaxSeconds = 0.5
    /// Pixels per scroll step (about 60 steps per second while held).
    var scrollSpeed = 14.0
    var playSounds = true
    var startEnabled = false
    var shortcuts = AppConfig.defaultShortcuts

    static let defaultShortcuts: [ShortcutEntry] = [
        ShortcutEntry(trigger: "opt", action: "esc", note: "Tap Option → Escape"),
        ShortcutEntry(trigger: "n", action: "cmd+shift+4", note: "Screenshot"),
        ShortcutEntry(trigger: "v", action: "cmd+c", note: "Copy"),
        ShortcutEntry(trigger: "b", action: "cmd+v", note: "Paste"),
        ShortcutEntry(trigger: "shift+,", action: "cmd+shift+[", note: "Tab to the left"),
        ShortcutEntry(trigger: "shift+.", action: "cmd+shift+]", note: "Tab to the right"),
        ShortcutEntry(trigger: "space", action: "scroll:down", note: "Scroll down (hold)"),
        ShortcutEntry(trigger: "u", action: "scroll:up", note: "Scroll up (hold)"),
    ]

    enum CodingKeys: String, CodingKey {
        case toggleKey, toggleHoldSeconds, tapMaxSeconds, scrollSpeed, playSounds, startEnabled, shortcuts
    }

    init() {}

    /// Missing keys fall back to defaults so older or hand-trimmed config files still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        toggleKey = try c.decodeIfPresent(String.self, forKey: .toggleKey) ?? d.toggleKey
        toggleHoldSeconds = try c.decodeIfPresent(Double.self, forKey: .toggleHoldSeconds) ?? d.toggleHoldSeconds
        tapMaxSeconds = try c.decodeIfPresent(Double.self, forKey: .tapMaxSeconds) ?? d.tapMaxSeconds
        scrollSpeed = try c.decodeIfPresent(Double.self, forKey: .scrollSpeed) ?? d.scrollSpeed
        playSounds = try c.decodeIfPresent(Bool.self, forKey: .playSounds) ?? d.playSounds
        startEnabled = try c.decodeIfPresent(Bool.self, forKey: .startEnabled) ?? d.startEnabled
        shortcuts = try c.decodeIfPresent([ShortcutEntry].self, forKey: .shortcuts) ?? d.shortcuts
    }

    func validationErrors() -> [String] {
        var errors: [String] = []
        if case .modifierTap? = Trigger.parse(toggleKey) {} else {
            errors.append("Toggle key “\(toggleKey)” must be a single modifier (opt, cmd, ctrl or shift).")
        }
        if toggleHoldSeconds < 0.2 { errors.append("Hold-to-toggle time must be at least 0.2 seconds.") }
        if tapMaxSeconds <= 0 { errors.append("Tap time must be greater than 0.") }
        if scrollSpeed <= 0 { errors.append("Scroll speed must be greater than 0.") }

        var seen = Set<Trigger>()
        for (index, entry) in shortcuts.enumerated() {
            let row = index + 1
            guard let trigger = Trigger.parse(entry.trigger) else {
                errors.append("Row \(row): can't understand trigger “\(entry.trigger)”.")
                continue
            }
            if Action.parse(entry.action) == nil {
                errors.append("Row \(row): can't understand action “\(entry.action)”.")
            }
            if !seen.insert(trigger).inserted {
                errors.append("Row \(row): trigger “\(entry.trigger)” is used more than once.")
            }
        }
        return errors
    }
}

/// Reads and writes ~/Library/Application Support/OneHand/config.json.
final class ConfigStore {
    let url: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = support.appendingPathComponent("OneHand", isDirectory: true).appendingPathComponent("config.json")
    }

    /// Returns the saved config, writing the defaults on first run. On a read error the
    /// file is left untouched and the defaults are returned with the error message.
    func load() -> (config: AppConfig, error: String?) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let config = AppConfig()
            try? save(config)
            return (config, nil)
        }
        do {
            let data = try Data(contentsOf: url)
            return (try JSONDecoder().decode(AppConfig.self, from: data), nil)
        } catch {
            return (AppConfig(), "Couldn't read \(url.path): \(error.localizedDescription). Using defaults.")
        }
    }

    func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}

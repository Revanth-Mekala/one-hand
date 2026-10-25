import Carbon.HIToolbox
import CoreGraphics

/// A physical key plus modifiers. `keyCode == nil` means "modifiers only" (used for tap triggers).
struct KeyCombo: Hashable {
    var keyCode: CGKeyCode?
    var mods: UInt64

    /// The modifiers we care about when matching (caps lock, fn and numpad bits are ignored).
    static let modifierMask: UInt64 = CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskShift.rawValue
        | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskControl.rawValue
}

/// What a shortcut listens for.
enum Trigger: Hashable {
    case key(KeyCombo)
    /// A lone modifier pressed and released quickly, e.g. tapping Option.
    case modifierTap(UInt64)

    static func parse(_ text: String) -> Trigger? {
        guard let combo = KeyNames.parse(text) else { return nil }
        if combo.keyCode != nil { return .key(combo) }
        return combo.mods.nonzeroBitCount == 1 ? .modifierTap(combo.mods) : nil
    }
}

/// What a shortcut does.
enum Action: Equatable {
    case keystroke(KeyCombo)
    /// Direction for continuous scrolling while the trigger is held. dy > 0 scrolls up, dx > 0 scrolls left.
    case scroll(dx: Int32, dy: Int32)
    case shell(String)
    case toggleMode

    static func parse(_ text: String) -> Action? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("shell:") {
            let command = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return command.isEmpty ? nil : .shell(command)
        }
        if lower.hasPrefix("scroll:") {
            switch lower.dropFirst(7).trimmingCharacters(in: .whitespaces) {
            case "up": return .scroll(dx: 0, dy: 1)
            case "down": return .scroll(dx: 0, dy: -1)
            case "left": return .scroll(dx: 1, dy: 0)
            case "right": return .scroll(dx: -1, dy: 0)
            default: return nil
            }
        }
        if lower == "toggle" { return .toggleMode }
        guard let combo = KeyNames.parse(trimmed), combo.keyCode != nil else { return nil }
        return .keystroke(combo)
    }
}

/// Converts between text like "cmd+shift+4" and key codes (US ANSI layout).
enum KeyNames {
    private static let modifierNames: [(names: [String], flag: CGEventFlags)] = [
        (["ctrl", "control", "⌃"], .maskControl),
        (["opt", "option", "alt", "⌥"], .maskAlternate),
        (["shift", "⇧"], .maskShift),
        (["cmd", "command", "⌘"], .maskCommand),
    ]

    /// Canonical name → key code. The first name listed for a code is used when formatting.
    private static let keyTable: [(String, Int)] = [
        ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D),
        ("e", kVK_ANSI_E), ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H),
        ("i", kVK_ANSI_I), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
        ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P),
        ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
        ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
        ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
        ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
        ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7),
        ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
        (",", kVK_ANSI_Comma), (".", kVK_ANSI_Period), ("/", kVK_ANSI_Slash),
        (";", kVK_ANSI_Semicolon), ("'", kVK_ANSI_Quote), ("[", kVK_ANSI_LeftBracket),
        ("]", kVK_ANSI_RightBracket), ("\\", kVK_ANSI_Backslash), ("-", kVK_ANSI_Minus),
        ("=", kVK_ANSI_Equal), ("`", kVK_ANSI_Grave),
        ("space", kVK_Space), ("tab", kVK_Tab), ("return", kVK_Return), ("esc", kVK_Escape),
        ("delete", kVK_Delete), ("fwddelete", kVK_ForwardDelete),
        ("left", kVK_LeftArrow), ("right", kVK_RightArrow), ("up", kVK_UpArrow), ("down", kVK_DownArrow),
        ("home", kVK_Home), ("end", kVK_End), ("pageup", kVK_PageUp), ("pagedown", kVK_PageDown),
        ("f1", kVK_F1), ("f2", kVK_F2), ("f3", kVK_F3), ("f4", kVK_F4), ("f5", kVK_F5),
        ("f6", kVK_F6), ("f7", kVK_F7), ("f8", kVK_F8), ("f9", kVK_F9), ("f10", kVK_F10),
        ("f11", kVK_F11), ("f12", kVK_F12), ("f13", kVK_F13), ("f14", kVK_F14),
        ("f15", kVK_F15), ("f16", kVK_F16), ("f17", kVK_F17), ("f18", kVK_F18),
        ("f19", kVK_F19), ("f20", kVK_F20),
    ]

    private static let aliases: [String: String] = [
        "escape": "esc", "enter": "return", "backspace": "delete", "forwarddelete": "fwddelete",
        "comma": ",", "period": ".", "dot": ".", "slash": "/", "semicolon": ";", "quote": "'",
        "leftbracket": "[", "rightbracket": "]", "backslash": "\\", "minus": "-", "equals": "=",
        "grave": "`", "backtick": "`", "spacebar": "space", "pgup": "pageup", "pgdn": "pagedown",
    ]

    /// Shifted characters, so "<" can be written instead of "shift+,".
    private static let shifted: [String: String] = [
        "<": ",", ">": ".", "?": "/", ":": ";", "\"": "'", "{": "[", "}": "]", "|": "\\",
        "_": "-", "~": "`", "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6",
        "&": "7", "*": "8", "(": "9", ")": "0",
    ]

    private static let codesByName: [String: CGKeyCode] = {
        var map: [String: CGKeyCode] = [:]
        for (name, code) in keyTable { map[name] = CGKeyCode(code) }
        return map
    }()

    private static let namesByCode: [CGKeyCode: String] = {
        var map: [CGKeyCode: String] = [:]
        for (name, code) in keyTable where map[CGKeyCode(code)] == nil { map[CGKeyCode(code)] = name }
        return map
    }()

    /// Parses "shift + ,", "cmd+shift+4", "opt", "key50" (raw key code) and similar.
    static func parse(_ text: String) -> KeyCombo? {
        let parts = text.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        var mods: UInt64 = 0
        var code: CGKeyCode?
        for part in parts {
            if let entry = modifierNames.first(where: { $0.names.contains(part) }) {
                mods |= entry.flag.rawValue
                continue
            }
            guard code == nil else { return nil } // only one non-modifier key allowed
            let name = aliases[part] ?? part
            if let c = codesByName[name] {
                code = c
            } else if let base = shifted[name], let c = codesByName[base] {
                code = c
                mods |= CGEventFlags.maskShift.rawValue
            } else if name.hasPrefix("key"), let raw = UInt16(name.dropFirst(3)), raw < 128 {
                code = raw
            } else {
                return nil
            }
        }
        return KeyCombo(keyCode: code, mods: mods)
    }

    static func format(_ combo: KeyCombo) -> String {
        var parts = modifierNames.filter { combo.mods & $0.flag.rawValue != 0 }.map { $0.names[0] }
        if let code = combo.keyCode { parts.append(namesByCode[code] ?? "key\(code)") }
        return parts.joined(separator: "+")
    }

    /// The modifier flag a left/right modifier key controls, or nil for other keys.
    static func modifierFlag(forKeyCode code: CGKeyCode) -> UInt64? {
        switch Int(code) {
        case kVK_Command, kVK_RightCommand: return CGEventFlags.maskCommand.rawValue
        case kVK_Shift, kVK_RightShift: return CGEventFlags.maskShift.rawValue
        case kVK_Option, kVK_RightOption: return CGEventFlags.maskAlternate.rawValue
        case kVK_Control, kVK_RightControl: return CGEventFlags.maskControl.rawValue
        default: return nil
        }
    }
}

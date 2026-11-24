import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// A keystroke such as `ctrl+shift+4`: modifiers plus exactly one key.
///
/// Keys are virtual key codes of the US ANSI layout, i.e. physical key positions: on another layout the key in the
/// US position of the named character is pressed.
public struct KeySpec: Hashable, Sendable, CustomStringConvertible {
    public var modifiers: Modifiers
    public var keyCode: CGKeyCode
    public var keyName: String

    public init(modifiers: Modifiers, keyCode: CGKeyCode, keyName: String) {
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.keyName = keyName
    }

    public var description: String {
        modifiers.isEmpty ? keyName : "\(modifiers)+\(keyName)"
    }

    /// Parses `modifier+...+key`, case-insensitive, spaces around `+` allowed.
    public static func parse(_ text: String) throws(KeySpecError) -> KeySpec {
        let parts = text.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if parts.contains(where: \.isEmpty) {
            throw KeySpecError("\"\(text)\" has an empty part; write keys like \"ctrl+shift+4\"")
        }
        var modifiers: Modifiers = []
        var key: (code: CGKeyCode, name: String)?
        for part in parts {
            if let modifier = Modifiers.named(part) {
                if modifiers.contains(modifier) {
                    throw KeySpecError("\"\(text)\" repeats the modifier \"\(part)\"")
                }
                modifiers.insert(modifier)
            } else if let code = keyCodes[part] {
                if let key {
                    throw KeySpecError("\"\(text)\" names two keys, \"\(key.name)\" and \"\(part)\"; use one key plus modifiers")
                }
                key = (code, part)
            } else {
                throw KeySpecError("\"\(text)\": unknown key \"\(part)\"")
            }
        }
        guard let key else {
            throw KeySpecError("\"\(text)\" has no key besides modifiers")
        }
        return KeySpec(modifiers: modifiers, keyCode: key.code, keyName: key.name)
    }

    /// Key names and their US ANSI virtual key codes.
    static let keyCodes: [String: CGKeyCode] = {
        var codes: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
            "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
            "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "-": kVK_ANSI_Minus, "minus": kVK_ANSI_Minus,
            "=": kVK_ANSI_Equal, "equal": kVK_ANSI_Equal,
            "[": kVK_ANSI_LeftBracket, "leftbracket": kVK_ANSI_LeftBracket,
            "]": kVK_ANSI_RightBracket, "rightbracket": kVK_ANSI_RightBracket,
            "\\": kVK_ANSI_Backslash, "backslash": kVK_ANSI_Backslash,
            ";": kVK_ANSI_Semicolon, "semicolon": kVK_ANSI_Semicolon,
            "'": kVK_ANSI_Quote, "quote": kVK_ANSI_Quote,
            ",": kVK_ANSI_Comma, "comma": kVK_ANSI_Comma,
            ".": kVK_ANSI_Period, "period": kVK_ANSI_Period,
            "/": kVK_ANSI_Slash, "slash": kVK_ANSI_Slash,
            "`": kVK_ANSI_Grave, "grave": kVK_ANSI_Grave,
            "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "space": kVK_Space,
            "delete": kVK_Delete, "backspace": kVK_Delete, "forwarddelete": kVK_ForwardDelete,
            "escape": kVK_Escape, "esc": kVK_Escape,
            "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (index, code) in functionKeys.enumerated() {
            codes["f\(index + 1)"] = code
        }
        return codes.mapValues { CGKeyCode($0) }
    }()
}

public struct KeySpecError: Error, Equatable, CustomStringConvertible {
    public let description: String

    init(_ description: String) {
        self.description = description
    }
}

import CoreGraphics

/// The modifier keys Cue matches and posts. Caps Lock and Fn are deliberately absent: they are ignored when matching.
public struct Modifiers: OptionSet, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)

    /// Each modifier with its event flag and the names accepted in the config, canonical name first.
    static let table: [(modifier: Modifiers, flag: CGEventFlags, names: [String])] = [
        (.control, .maskControl, ["control", "ctrl"]),
        (.option, .maskAlternate, ["option", "opt", "alt"]),
        (.shift, .maskShift, ["shift"]),
        (.command, .maskCommand, ["command", "cmd"]),
    ]

    /// The modifier a config name stands for, case-insensitively.
    public static func named(_ name: String) -> Modifiers? {
        let lowered = name.lowercased()
        return table.first { $0.names.contains(lowered) }?.modifier
    }

    static var acceptedNames: String {
        table.flatMap(\.names).joined(separator: ", ")
    }

    /// The Control, Option, Shift and Command state in `flags`; every other flag, including Caps Lock and Fn, is ignored.
    public init(flags: CGEventFlags) {
        self = Self.table.reduce(into: []) { result, entry in
            if flags.contains(entry.flag) { result.insert(entry.modifier) }
        }
    }

    /// Exactly these modifiers as event flags.
    public var eventFlags: CGEventFlags {
        Self.table.reduce(into: []) { result, entry in
            if contains(entry.modifier) { result.insert(entry.flag) }
        }
    }

    public var description: String {
        let names = Self.table.filter { contains($0.modifier) }.map { $0.names[0] }
        return names.isEmpty ? "none" : names.joined(separator: "+")
    }
}

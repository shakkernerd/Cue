import Foundation

/// When a rule fires: the pointer pushed onto `edge` while exactly `modifiers` are held.
public struct Trigger: Hashable, Sendable {
    public var edge: Edge
    public var modifiers: Modifiers

    public init(edge: Edge, modifiers: Modifiers) {
        self.edge = edge
        self.modifiers = modifiers
    }
}

/// What a rule does when it fires.
public enum Action: Hashable, Sendable {
    /// Post this keystroke system-wide.
    case keys(KeySpec)
}

public struct Rule: Hashable, Sendable {
    public var trigger: Trigger
    public var action: Action

    public init(trigger: Trigger, action: Action) {
        self.trigger = trigger
        self.action = action
    }
}

/// The contents of `~/.config/cue/config.json`.
public struct Config: Equatable, Sendable {
    public var rules: [Rule]

    public init(rules: [Rule]) {
        self.rules = rules
    }

    /// Parses and validates the config JSON. Every problem names its location, such as `rules[0].trigger.edge`.
    public static func parse(_ data: Data) throws(ConfigError) -> Config {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            let detail = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
            throw ConfigError("invalid JSON: \(detail ?? error.localizedDescription)")
        }
        let root = try object(json, at: "config", keys: ["rules"], required: ["rules"])
        guard let rulesJSON = root["rules"] as? [Any] else {
            throw ConfigError("rules: expected an array of rules")
        }

        var rules: [Rule] = []
        var firstIndexByTrigger: [Trigger: Int] = [:]
        for (index, ruleJSON) in rulesJSON.enumerated() {
            let path = "rules[\(index)]"
            let rule = try parseRule(ruleJSON, at: path)
            if let first = firstIndexByTrigger[rule.trigger] {
                throw ConfigError("\(path).trigger: same edge and modifiers as rules[\(first)]")
            }
            firstIndexByTrigger[rule.trigger] = index
            rules.append(rule)
        }
        return Config(rules: rules)
    }

    private static func parseRule(_ json: Any, at path: String) throws(ConfigError) -> Rule {
        let rule = try object(json, at: path, keys: ["trigger", "action"], required: ["trigger", "action"])
        return Rule(
            trigger: try parseTrigger(rule["trigger"]!, at: "\(path).trigger"),
            action: try parseAction(rule["action"]!, at: "\(path).action")
        )
    }

    private static func parseTrigger(_ json: Any, at path: String) throws(ConfigError) -> Trigger {
        let trigger = try object(json, at: path, keys: ["edge", "modifiers"], required: ["edge", "modifiers"])
        let edgeNames = Edge.allCases.map(\.rawValue).joined(separator: ", ")
        guard let edgeName = trigger["edge"] as? String, let edge = Edge(rawValue: edgeName.lowercased()) else {
            throw ConfigError("\(path).edge: expected one of \(edgeNames)")
        }
        guard let names = trigger["modifiers"] as? [Any] else {
            throw ConfigError("\(path).modifiers: expected an array such as [\"control\"]")
        }
        var modifiers: Modifiers = []
        for (index, nameJSON) in names.enumerated() {
            let itemPath = "\(path).modifiers[\(index)]"
            guard let name = nameJSON as? String, let modifier = Modifiers.named(name) else {
                throw ConfigError("\(itemPath): expected one of \(Modifiers.acceptedNames)")
            }
            if modifiers.contains(modifier) {
                throw ConfigError("\(itemPath): \"\(name)\" repeats a modifier")
            }
            modifiers.insert(modifier)
        }
        return Trigger(edge: edge, modifiers: modifiers)
    }

    private static let actionKinds = ["keys"]

    private static func parseAction(_ json: Any, at path: String) throws(ConfigError) -> Action {
        guard let action = json as? [String: Any] else {
            throw ConfigError("\(path): expected an object such as {\"keys\": \"ctrl+shift+4\"}")
        }
        let supported = actionKinds.joined(separator: ", ")
        guard action.count == 1, let entry = action.first else {
            throw ConfigError("\(path): expected exactly one action kind (\(supported)), found \(action.count)")
        }
        let (kind, value) = (entry.key, entry.value)
        switch kind {
        case "keys":
            guard let text = value as? String else {
                throw ConfigError("\(path).keys: expected a string such as \"ctrl+shift+4\"")
            }
            do {
                return .keys(try KeySpec.parse(text))
            } catch {
                throw ConfigError("\(path).keys: \(error)")
            }
        default:
            throw ConfigError("\(path): unknown action kind \"\(kind)\"; supported: \(supported)")
        }
    }

    /// `json` as an object holding only `keys` and at least `required`.
    private static func object(
        _ json: Any, at path: String, keys: Set<String>, required: [String]
    ) throws(ConfigError) -> [String: Any] {
        guard let object = json as? [String: Any] else {
            throw ConfigError("\(path): expected an object")
        }
        if let unknown = object.keys.sorted().first(where: { !keys.contains($0) }) {
            throw ConfigError("\(path): unknown key \"\(unknown)\"")
        }
        if let missing = required.first(where: { object[$0] == nil }) {
            throw ConfigError("\(path): missing \"\(missing)\"")
        }
        return object
    }
}

public struct ConfigError: Error, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

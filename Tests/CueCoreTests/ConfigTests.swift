import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing

@testable import CueCore

@Suite struct KeySpecTests {
    @Test func parsesTheDisplayPilotShortcuts() throws {
        let usbc = try KeySpec.parse("ctrl+shift+1")
        #expect(usbc.modifiers == [.control, .shift])
        #expect(usbc.keyCode == CGKeyCode(kVK_ANSI_1))
        let hdmi = try KeySpec.parse("ctrl+shift+4")
        #expect(hdmi.keyCode == CGKeyCode(kVK_ANSI_4))
    }

    @Test func isCaseAndSpaceInsensitiveWithAliases() throws {
        let spec = try KeySpec.parse(" Cmd + Option + Shift + A ")
        #expect(spec.modifiers == [.command, .option, .shift])
        #expect(spec.keyCode == CGKeyCode(kVK_ANSI_A))
        #expect(try KeySpec.parse("control+alt+f12").modifiers == [.control, .option])
        #expect(try KeySpec.parse("control+alt+f12").keyCode == CGKeyCode(kVK_F12))
        #expect(try KeySpec.parse("opt+left").keyCode == CGKeyCode(kVK_LeftArrow))
        #expect(try KeySpec.parse("space").modifiers.isEmpty)
        #expect(try KeySpec.parse("cmd+=").keyCode == CGKeyCode(kVK_ANSI_Equal))
        #expect(try KeySpec.parse("esc").keyCode == CGKeyCode(kVK_Escape))
    }

    @Test(arguments: [
        ("", "empty part"),
        ("ctrl+", "empty part"),
        ("ctrl+shift", "no key besides modifiers"),
        ("a+b", "names two keys"),
        ("ctrl+ctrl+a", "repeats the modifier"),
        ("ctrl+hyper+a", "unknown key \"hyper\""),
        ("fn+a", "unknown key \"fn\""),
    ])
    func rejectsInvalidSpecs(text: String, message: String) {
        #expect {
            try KeySpec.parse(text)
        } throws: { error in
            (error as? KeySpecError)?.description.contains(message) == true
        }
    }

    @Test func keystrokeEventsCarryExactlyTheSpecModifiers() throws {
        let spec = try KeySpec.parse("ctrl+shift+1")
        let events = Keystroke.events(for: spec)
        #expect(events.count == 2)
        for (event, down) in zip(events, [true, false]) {
            #expect(event.type == (down ? .keyDown : .keyUp))
            #expect(event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_1))
            #expect(event.flags == [.maskControl, .maskShift])
        }
        let plain = Keystroke.events(for: try KeySpec.parse("f5"))
        #expect(plain.allSatisfy { $0.flags.isEmpty })
    }
}

@Suite struct ConfigParsingTests {
    func parse(_ json: String) throws(ConfigError) -> Config {
        try Config.parse(Data(json.utf8))
    }

    func error(_ json: String) -> String? {
        do {
            _ = try parse(json)
            return nil
        } catch {
            return error.description
        }
    }

    @Test func parsesTheDisplayPilotExample() throws {
        let config = try parse(#"""
            {
              "rules": [
                { "trigger": { "edge": "left", "modifiers": ["control"] }, "action": { "keys": "ctrl+shift+4" } },
                { "trigger": { "edge": "right", "modifiers": ["control"] }, "action": { "keys": "ctrl+shift+1" } }
              ]
            }
            """#)
        #expect(config.rules.count == 2)
        #expect(config.rules[0].trigger == Trigger(edge: .left, modifiers: .control))
        #expect(config.rules[1].action == .keys(try KeySpec.parse("ctrl+shift+1")))
    }

    @Test func emptyRulesAreValid() throws {
        #expect(try parse(ConfigFile.initialContents).rules.isEmpty)
        #expect(try parse(#"{"rules": []}"#).rules.isEmpty)
    }

    @Test func modifierNamesAreCaseInsensitiveAndCanBeEmpty() throws {
        let config = try parse(#"""
            {"rules": [
              {"trigger": {"edge": "Top", "modifiers": ["CMD", "Alt"]}, "action": {"keys": "f1"}},
              {"trigger": {"edge": "bottom", "modifiers": []}, "action": {"keys": "f2"}}
            ]}
            """#)
        #expect(config.rules[0].trigger == Trigger(edge: .top, modifiers: [.command, .option]))
        #expect(config.rules[1].trigger.modifiers.isEmpty)
    }

    @Test(arguments: [
        (#"{"rules": [}"#, "invalid JSON"),
        (#"[]"#, "config: expected an object"),
        (#"{}"#, "config: missing \"rules\""),
        (#"{"rules": {}}"#, "rules: expected an array"),
        (#"{"rules": [], "dwell": 200}"#, "config: unknown key \"dwell\""),
        (#"{"rules": [1]}"#, "rules[0]: expected an object"),
        (#"{"rules": [{"trigger": {"edge": "left", "modifiers": []}}]}"#, "rules[0]: missing \"action\""),
        (#"{"rules": [{"trigger": {"edge": "middle", "modifiers": []}, "action": {"keys": "a"}}]}"#,
         "rules[0].trigger.edge: expected one of left, right, top, bottom"),
        (#"{"rules": [{"trigger": {"edge": "left"}, "action": {"keys": "a"}}]}"#, "rules[0].trigger: missing \"modifiers\""),
        (#"{"rules": [{"trigger": {"edge": "left", "modifiers": "control"}, "action": {"keys": "a"}}]}"#,
         "rules[0].trigger.modifiers: expected an array"),
        (#"{"rules": [{"trigger": {"edge": "left", "modifiers": ["capslock"]}, "action": {"keys": "a"}}]}"#,
         "rules[0].trigger.modifiers[0]: expected one of control, ctrl"),
        (#"{"rules": [{"trigger": {"edge": "left", "modifiers": ["ctrl", "control"]}, "action": {"keys": "a"}}]}"#,
         "rules[0].trigger.modifiers[1]: \"control\" repeats a modifier"),
        (#"{"rules": [{"trigger": {"edge": "left", "modifiers": [], "corner": 1}, "action": {"keys": "a"}}]}"#,
         "rules[0].trigger: unknown key \"corner\""),
        (#"{"rules": [{"trigger": {"edge": "left", "modifiers": []}, "action": {"shell": "say hi"}}]}"#,
         "rules[0].action: unknown action kind \"shell\"; supported: keys"),
        (#"{"rules": [{"trigger": {"edge": "left", "modifiers": []}, "action": {}}]}"#,
         "rules[0].action: expected exactly one action kind"),
        (#"{"rules": [{"trigger": {"edge": "left", "modifiers": []}, "action": {"keys": "a", "shell": "x"}}]}"#,
         "rules[0].action: expected exactly one action kind"),
        (#"{"rules": [{"trigger": {"edge": "left", "modifiers": []}, "action": {"keys": 4}}]}"#,
         "rules[0].action.keys: expected a string"),
        (#"{"rules": [{"trigger": {"edge": "left", "modifiers": []}, "action": {"keys": "ctrl+shift"}}]}"#,
         "rules[0].action.keys: \"ctrl+shift\" has no key besides modifiers"),
    ])
    func rejectsInvalidConfigWithItsLocation(json: String, message: String) {
        let description = error(json)
        #expect(description?.contains(message) == true, "got: \(description ?? "no error")")
    }

    @Test func rejectsDuplicateTriggersWhateverTheModifierOrder() {
        let description = error(#"""
            {"rules": [
              {"trigger": {"edge": "left", "modifiers": ["control", "shift"]}, "action": {"keys": "a"}},
              {"trigger": {"edge": "right", "modifiers": ["control", "shift"]}, "action": {"keys": "b"}},
              {"trigger": {"edge": "left", "modifiers": ["shift", "ctrl"]}, "action": {"keys": "c"}}
            ]}
            """#)
        #expect(description == "rules[2].trigger: same edge and modifiers as rules[0]")
    }
}

@Suite struct ConfigFileTests {
    func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "cue-tests-\(UUID().uuidString)/nested/config.json", directoryHint: .notDirectory)
    }

    @Test func createsAnEmptyConfigWhenMissing() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let config = try ConfigFile.load(from: url).get()
        #expect(config.rules.isEmpty)
        #expect(try String(contentsOf: url, encoding: .utf8) == ConfigFile.initialContents)
    }

    @Test func leavesAnExistingConfigUntouched() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let broken = "{ not json"
        try Data(broken.utf8).write(to: url)
        guard case .failure(let error) = ConfigFile.load(from: url) else {
            Issue.record("expected a failure")
            return
        }
        #expect(error.description.hasPrefix("invalid JSON"))
        #expect(try String(contentsOf: url, encoding: .utf8) == broken)
    }

    @Test func aFailedLoadKeepsTheLastWorkingRules() throws {
        var state = ConfigState()
        let good = try Config.parse(Data(#"{"rules": [{"trigger": {"edge": "right", "modifiers": ["control"]}, "action": {"keys": "ctrl+shift+1"}}]}"#.utf8))
        state.apply(.success(good))
        #expect(state.rules.count == 1)
        #expect(state.error == nil)
        state.apply(.failure(ConfigError("invalid JSON: x")))
        #expect(state.rules == good.rules)
        #expect(state.error == ConfigError("invalid JSON: x"))
        state.apply(.success(Config(rules: [])))
        #expect(state.rules.isEmpty)
        #expect(state.error == nil)
    }
}

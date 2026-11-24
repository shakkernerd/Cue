import Foundation
import Testing

@testable import CueCore

/// Drives `ConfigWatcher` against real files in a temporary directory, the way editors and shells write them.
@Suite final class ConfigWatcherTests {
    /// Counts `onChange` calls; read from the test while the watcher's queue writes.
    final class Changes: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func record() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }

        /// Waits until at least `target` changes arrived, failing after `timeout` seconds.
        func wait(for target: Int, timeout: Double = 5, sourceLocation: SourceLocation = #_sourceLocation) async throws {
            let deadline = Date().addingTimeInterval(timeout)
            while count < target, Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(count >= target, "expected \(target) change(s), got \(count)", sourceLocation: sourceLocation)
        }

        /// Waits `seconds` and expects no change beyond `count`.
        func expectQuiet(at count: Int, for seconds: Double = 0.5, sourceLocation: SourceLocation = #_sourceLocation)
            async throws
        {
            try await Task.sleep(for: .seconds(seconds))
            #expect(self.count == count, sourceLocation: sourceLocation)
        }
    }

    let root: URL
    let file: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "cue-watcher-\(UUID().uuidString)")
        file = root.appending(path: "cue/config.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write("{\"rules\": []}", atomically: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ text: String, atomically: Bool, to url: URL? = nil) throws {
        try Data(text.utf8).write(to: url ?? file, options: atomically ? .atomic : [])
    }

    /// A started watcher; `stop` stops it.
    struct Watch {
        let watcher: ConfigWatcher
        let queue: DispatchQueue
        func stop() { queue.sync { watcher.stop() } }
    }

    /// The debounce leaves room for a loaded machine delivering one operation's events apart.
    func watch(_ url: URL? = nil, debounce: Double = 0.15) -> (Watch, Changes) {
        let changes = Changes()
        let queue = DispatchQueue(label: "ConfigWatcherTests")
        let watcher = ConfigWatcher(
            url: url ?? file, queue: queue, debounce: debounce, retryInterval: 0.05, onChange: { changes.record() })
        queue.sync { watcher.start() }
        return (Watch(watcher: watcher, queue: queue), changes)
    }

    @Test func reportsAWriteInPlace() async throws {
        let (watching, changes) = watch()
        defer { watching.stop() }
        try await changes.expectQuiet(at: 0)
        try write("{\"rules\": [1]}", atomically: false)
        try await changes.wait(for: 1)
    }

    /// An atomic save renames a new file over the old one; later saves change that new file.
    @Test func followsTheFileAcrossAtomicSaves() async throws {
        let (watching, changes) = watch()
        defer { watching.stop() }
        try write("{\"rules\": [1]}", atomically: true)
        try await changes.wait(for: 1)
        try await changes.expectQuiet(at: 1)
        try write("{\"rules\": [2]}", atomically: false)
        try await changes.wait(for: 2)
        try write("{\"rules\": [3]}", atomically: true)
        try await changes.wait(for: 3)
    }

    @Test func reportsDeletionAndRecreation() async throws {
        let (watching, changes) = watch()
        defer { watching.stop() }
        try FileManager.default.removeItem(at: file)
        try await changes.wait(for: 1)
        try await changes.expectQuiet(at: 1)
        try write("{\"rules\": [1]}", atomically: false)
        try await changes.wait(for: 2)
        // The recreated file is watched for writes too.
        try await changes.expectQuiet(at: 2)
        try write("{\"rules\": [2]}", atomically: false)
        try await changes.wait(for: 3)
    }

    /// `echo > file` truncates, then writes; a burst like that is one change.
    @Test func coalescesABurstIntoOneChange() async throws {
        let (watching, changes) = watch(debounce: 0.5)
        defer { watching.stop() }
        for index in 0..<5 {
            try write("{\"rules\": [\(index)]}", atomically: index.isMultiple(of: 2))
        }
        try await changes.wait(for: 1)
        try await changes.expectQuiet(at: 1, for: 0.8)
    }

    /// Another file in the directory changing every 20 ms does not hold the reload back past `10 × debounce`.
    @Test func reportsDuringSteadyActivity() async throws {
        let (watching, changes) = watch(debounce: 0.1)
        defer { watching.stop() }
        let other = file.deletingLastPathComponent().appending(path: "other.txt")
        try write("{\"rules\": [1]}", atomically: false)
        let deadline = Date().addingTimeInterval(1.6)
        var index = 0
        while Date() < deadline {
            try write("\(index)", atomically: true, to: other)
            index += 1
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(changes.count >= 1, "no change reported during 1.6 s of steady activity")
    }

    @Test func waitsForAMissingDirectory() async throws {
        let missing = root.appending(path: "later/config.json")
        let (watching, changes) = watch(missing)
        defer { watching.stop() }
        try await changes.expectQuiet(at: 0)
        try FileManager.default.createDirectory(at: missing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await changes.wait(for: 1)
        try write("{\"rules\": []}", atomically: true, to: missing)
        try await changes.wait(for: 2)
        try await changes.expectQuiet(at: 2)
        try write("{\"rules\": [1]}", atomically: false, to: missing)
        try await changes.wait(for: 3)
    }

    @Test func watchesThroughASymlinkedDirectory() async throws {
        let link = root.appending(path: "linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file.deletingLastPathComponent())
        let (watching, changes) = watch(link.appending(path: "config.json"))
        defer { watching.stop() }
        try write("{\"rules\": [1]}", atomically: true)
        try await changes.wait(for: 1)
        try await changes.expectQuiet(at: 1)
        try write("{\"rules\": [2]}", atomically: false)
        try await changes.wait(for: 2)
    }

    @Test func followsASymlinkedFileToItsTarget() async throws {
        let target = root.appending(path: "elsewhere/config.json")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write("{\"rules\": []}", atomically: false, to: target)
        let link = root.appending(path: "cue/linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let (watching, changes) = watch(link)
        defer { watching.stop() }
        try write("{\"rules\": [1]}", atomically: false, to: target)
        try await changes.wait(for: 1)
        // The target is replaced in its own directory, which is not watched; the old target's deletion is.
        try write("{\"rules\": [2]}", atomically: true, to: target)
        try await changes.wait(for: 2)
        try await changes.expectQuiet(at: 2)
        try write("{\"rules\": [3]}", atomically: false, to: target)
        try await changes.wait(for: 3)
    }

    @Test func reportsNothingAfterStop() async throws {
        let (watching, changes) = watch()
        watching.stop()
        try write("{\"rules\": [1]}", atomically: false)
        try write("{\"rules\": [2]}", atomically: true)
        try await changes.expectQuiet(at: 0)
    }
}

@Suite final class ConfigReloadTests {
    let file = FileManager.default.temporaryDirectory.appending(path: "cue-reload-\(UUID().uuidString)/config.json")

    deinit {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    @Test func readDoesNotCreateAMissingFile() throws {
        guard case .failure(let error) = ConfigFile.read(from: file) else {
            Issue.record("reading a missing file succeeded")
            return
        }
        #expect(error.description.hasPrefix("cannot read \(file.path(percentEncoded: false))"))
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    /// A deleted or broken config while Cue runs keeps the rules in force and reports the problem; fixing it clears it.
    @Test func aFailedReloadKeepsTheRulesInForce() throws {
        let rule = """
            {"rules": [{"trigger": {"edge": "right", "modifiers": ["control"]}, "action": {"keys": "ctrl+shift+1"}}]}
            """
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(rule.utf8).write(to: file)
        var state = ConfigState()
        state.apply(ConfigFile.load(from: file))
        let rules = state.rules
        #expect(rules.count == 1 && state.error == nil)

        try FileManager.default.removeItem(at: file)
        state.apply(ConfigFile.read(from: file))
        #expect(state.rules == rules)
        #expect(state.error?.description.hasPrefix("cannot read") == true)

        try Data("{\"rules\": [".utf8).write(to: file)
        state.apply(ConfigFile.read(from: file))
        #expect(state.rules == rules)
        #expect(state.error?.description.hasPrefix("invalid JSON") == true)

        try Data("{\"rules\": []}".utf8).write(to: file)
        state.apply(ConfigFile.read(from: file))
        #expect(state.rules.isEmpty && state.error == nil)
    }
}

import Foundation
import Testing

@testable import CueCore

@Suite struct ShellCommandTests {
    /// Collects `onExit` calls so a test can wait for them.
    final class Exits: @unchecked Sendable {
        private let lock = NSLock()
        private var exits: [(pid: Int32, exit: ShellCommand.Exit)] = []
        private let ended = DispatchSemaphore(value: 0)

        func record(_ pid: Int32, _ exit: ShellCommand.Exit) {
            lock.withLock { exits.append((pid, exit)) }
            ended.signal()
        }

        /// The next exit, or nil when none arrives within `timeout` seconds.
        func next(timeout: Double = 10) -> (pid: Int32, exit: ShellCommand.Exit)? {
            guard ended.wait(timeout: .now() + timeout) == .success else { return nil }
            return lock.withLock { exits.removeFirst() }
        }
    }

    func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "cue-shell-\(UUID().uuidString)", directoryHint: .notDirectory)
    }

    func contents(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .newlines)
    }

    @Test func runsTheCommandAndReportsSuccess() throws {
        let out = temporaryFile()
        defer { try? FileManager.default.removeItem(at: out) }
        let exits = Exits()
        let pid = try ShellCommand.run("date +%s > '\(out.path)'", onExit: exits.record)
        let ended = try #require(exits.next())
        #expect(ended.pid == pid)
        #expect(ended.exit == .status(0))
        #expect(ended.exit.succeeded)
        #expect(Int(try contents(out)) != nil)
    }

    @Test func runsAsALoginShellInTheHomeDirectoryWithTildeExpanded() throws {
        let out = temporaryFile()
        defer { try? FileManager.default.removeItem(at: out) }
        let exits = Exits()
        try ShellCommand.run(
            #"{ [[ -o login ]] && echo login; pwd; echo ~; }"# + " > '\(out.path)'",
            shell: URL(filePath: "/bin/zsh"), onExit: exits.record)
        #expect(exits.next()?.exit == .status(0))
        let home = (FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false) as NSString)
            .standardizingPath
        let lines = try contents(out).split(separator: "\n").map(String.init)
        #expect(lines == ["login", home, home])
    }

    @Test func usesTheLoginShellFromTheUserDatabase() throws {
        let entry = try #require(getpwuid(getuid()))
        let shell = try #require(entry.pointee.pw_shell)
        #expect(ShellCommand.loginShell.path(percentEncoded: false) == String(cString: shell))
        #expect(FileManager.default.isExecutableFile(atPath: ShellCommand.loginShell.path(percentEncoded: false)))
    }

    @Test func returnsWithoutWaitingForALongCommand() throws {
        let exits = Exits()
        let start = DispatchTime.now()
        let pid = try ShellCommand.run("exec sleep 5", onExit: exits.record)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        #expect(elapsed < 0.5, "run took \(elapsed) s")
        #expect(exits.next(timeout: 0.2) == nil)
        kill(pid, SIGTERM)
        #expect(exits.next()?.exit == .signal(SIGTERM))
    }

    @Test func reportsTheExitStatusOfAFailingCommand() throws {
        let exits = Exits()
        try ShellCommand.run("echo failing >&2; exit 3", onExit: exits.record)
        let ended = try #require(exits.next())
        #expect(ended.exit == .status(3))
        #expect(!ended.exit.succeeded)
        #expect(ended.exit.description == "exit status 3")
    }

    @Test func reapsTheProcessBeforeReportingItsExit() throws {
        let exits = Exits()
        let pids = try (0..<5).map { _ in try ShellCommand.run("true", onExit: exits.record) }
        var ended: [Int32] = []
        for _ in pids {
            ended.append(try #require(exits.next()).pid)
        }
        #expect(Set(ended) == Set(pids))
        for pid in pids {
            // A zombie still answers signal 0; a reaped process does not exist.
            #expect(kill(pid, 0) == -1 && errno == ESRCH, "pid \(pid) still exists")
        }
    }

    @Test func throwsWhenTheShellCannotStart() {
        let exits = Exits()
        #expect(throws: (any Error).self) {
            try ShellCommand.run("true", shell: URL(filePath: "/nonexistent/shell"), onExit: exits.record)
        }
        #expect(exits.next(timeout: 0.2) == nil)
    }
}

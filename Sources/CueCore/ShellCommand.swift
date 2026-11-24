import Foundation

/// Runs a rule's shell command without waiting for it.
public enum ShellCommand {
    /// How a command ended.
    public enum Exit: Equatable, Sendable, CustomStringConvertible {
        /// It exited with this status.
        case status(Int32)
        /// It was killed by this signal.
        case signal(Int32)

        public var succeeded: Bool { self == .status(0) }

        public var description: String {
            switch self {
            case .status(let status): "exit status \(status)"
            case .signal(let signal): "killed by signal \(signal)"
            }
        }
    }

    /// The user's login shell from the user database (`/bin/zsh`, macOS's default, if it names none).
    public static var loginShell: URL {
        var entry = passwd()
        var found: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 4096)
        let shell: String? = buffer.withUnsafeMutableBufferPointer { storage in
            guard getpwuid_r(getuid(), &entry, storage.baseAddress, storage.count, &found) == 0, found != nil,
                  let shell = entry.pw_shell, shell.pointee != 0
            else { return nil }
            return String(cString: shell)
        }
        return URL(filePath: shell ?? "/bin/zsh")
    }

    /// The arguments that run `command` in `shell` as a login shell: `-l -c <command>`. csh and tcsh accept `-l` only
    /// as their sole flag, so they get `-c <command>` and read `.cshrc` but not `.login`.
    public static func arguments(for shell: URL, running command: String) -> [String] {
        switch shell.lastPathComponent {
        case "csh", "tcsh": ["-c", command]
        default: ["-l", "-c", command]
        }
    }

    /// Starts `command` through `shell` as a login shell (`arguments(for:running:)`) and returns its process ID without
    /// waiting for it to end.
    ///
    /// The command runs in the home directory with Cue's environment; the login shell adds the `PATH` and variables
    /// from its login files. Standard input, output and error are `/dev/null`, so the command never waits on Cue.
    /// `onExit` runs on a background queue with the process ID once the command has ended and has been reaped.
    /// Throws when the shell cannot be started.
    @discardableResult
    public static func run(
        _ command: String, shell: URL = loginShell, onExit: @escaping @Sendable (_ pid: Int32, _ exit: Exit) -> Void
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = shell
        process.arguments = arguments(for: shell, running: command)
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // The handler holds the process until it ends; clearing it afterwards releases both.
        process.terminationHandler = { [process] _ in
            let exit: Exit = switch process.terminationReason {
            case .uncaughtSignal: .signal(process.terminationStatus)
            case .exit: .status(process.terminationStatus)
            @unknown default: .status(process.terminationStatus)
            }
            process.terminationHandler = nil
            onExit(process.processIdentifier, exit)
        }
        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw error
        }
        return process.processIdentifier
    }
}

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
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell, shell.pointee != 0 {
            return URL(filePath: String(cString: shell))
        }
        return URL(filePath: "/bin/zsh")
    }

    /// Starts `command` as `<shell> -l -c <command>` and returns its process ID without waiting for it to end.
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
        process.arguments = ["-l", "-c", command]
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

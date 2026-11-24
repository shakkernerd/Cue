import Foundation

public enum ConfigFile {
    /// `~/.config/cue/config.json`.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/cue/config.json", directoryHint: .notDirectory)
    }

    /// Written when the config file does not exist yet.
    public static let initialContents = "{\n  \"rules\": []\n}\n"

    /// Creates the config with no rules when nothing exists at `url`; an existing file is left untouched.
    public static func createIfMissing(at url: URL) throws(ConfigError) {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(initialContents.utf8).write(to: url, options: .withoutOverwriting)
        } catch {
            throw ConfigError("cannot create \(url.path(percentEncoded: false)): \(error.localizedDescription)")
        }
    }

    /// Reads and validates the config at `url`, first creating it with no rules when it does not exist.
    public static func load(from url: URL) -> Result<Config, ConfigError> {
        do {
            try createIfMissing(at: url)
        } catch {
            return .failure(error)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failure(ConfigError("cannot read \(url.path(percentEncoded: false)): \(error.localizedDescription)"))
        }
        return Result { () throws(ConfigError) in try Config.parse(data) }
    }
}

/// The rules in force and the latest config problem. A failed load keeps the last working rules.
public struct ConfigState: Equatable, Sendable {
    public private(set) var rules: [Rule] = []
    public private(set) var error: ConfigError?

    public init() {}

    public mutating func apply(_ result: Result<Config, ConfigError>) {
        switch result {
        case .success(let config):
            rules = config.rules
            error = nil
        case .failure(let failure):
            error = failure
        }
    }
}

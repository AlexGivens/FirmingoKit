import Foundation

/// Closed developer-only commands; parsing never discovers or writes a device.
struct ROMArguments {
    /// Explicit action; only the two install commands admit a device-changing request.
    enum Command: String {
        /// Validate the fixed complete image without a device.
        case preflight
        /// Inspect one explicitly selected ROM attachment without programming.
        case inspectVolume = "inspect-volume"
        /// Prepare and explicitly execute one new full-image transfer.
        case install
        /// Execute only up to the selected incomplete-transfer checkpoint.
        case pausedInstall = "paused-install"
        /// Read fresh hello and exact binary echo without programming.
        case verify
        /// Restore persisted context without reconstructing a target or execution token.
        case inspectRecord = "inspect-record"
    }
    /// Selected action, with no implicit default.
    let command: Command
    /// Exact required options, rejecting duplicates, extras and missing values.
    let values: [String: String]
    /// Rejects malformed intent before artifact acquisition or output creation.
    init(_ arguments: [String]) throws {
        guard arguments.count <= 25, let first = arguments.first, let command = Command(rawValue: first),
              arguments.count % 2 == 1 else { throw ROMFailure("Use --help for an explicit command and options.") }
        var values: [String: String] = [:]
        for index in stride(from: 1, to: arguments.count, by: 2) {
            let key = arguments[index], value = arguments[index + 1]
            guard key.hasPrefix("--"), !value.isEmpty, value.utf8.count <= 2048,
                  values.updateValue(value, forKey: key) == nil else { throw ROMFailure("Duplicate or invalid option.") }
        }
        let required: Set<String>
        switch command {
        case .preflight: required = ["--manifest", "--image", "--output"]
        case .inspectVolume: required = ["--volume", "--output"]
        case .install, .pausedInstall: required = ["--manifest", "--image", "--output", "--volume", "--confirm-board"]
        case .verify: required = ["--record", "--output", "--address", "--device-id"]
        case .inspectRecord: required = ["--record", "--output"]
        }
        guard Set(values.keys) == required else { throw ROMFailure("Missing or unsupported option for this command.") }
        if command == .install || command == .pausedInstall {
            guard values["--confirm-board"] == "nano_rp2040_connect" else { throw ROMFailure("Explicit physical Nano confirmation is required.") }
        }
        self.command = command; self.values = values
    }
    /// Returns a checked option without exposing an unchecked dictionary lookup to execution code.
    func value(_ key: String) throws -> String {
        guard let value = values[key] else { throw ROMFailure("Missing option: " + key) }; return value
    }
    /// Resolves an explicitly supplied local path without probing it.
    func url(_ key: String) throws -> URL { URL(fileURLWithPath: try value(key)) }
}

/// Bounded readable host failure; underlying SDK errors remain separately printed and journaled.
struct ROMFailure: LocalizedError {
    /// Explanation of the rejected host action or deliberate checkpoint timeout.
    let errorDescription: String?
    /// Creates a concise qualification-host error.
    init(_ text: String) { errorDescription = text }
}

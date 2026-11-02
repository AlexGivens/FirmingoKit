import Foundation

/// Immutable catalogue projection for orchestration; descriptor validation remains SDK-owned.
public struct WorkbenchCatalogue: Codable, Sendable {
    /// Digest returned by the SDK's trusted bundled loader.
    public let sha256: String
    /// Explicit choices; no first/latest descriptor is implicitly selected.
    public let builds: [Build]
    /// One SDK-validated choice shown identically in UI and automation.
    public struct Build: Codable, Sendable, Identifiable {
        /// Exact static descriptor identity.
        public let id: String
        /// Board identifier from the SDK descriptor.
        public let board: String
        /// Managed profile from the SDK descriptor.
        public let profile: String
        /// Creates a display projection without inventing a descriptor or device association.
        public init(id: String, board: String, profile: String) { self.id = id; self.board = board; self.profile = profile }
    }
    /// Captures an already validated inventory; injectable tests never qualify these as real compiler outputs.
    public init(sha256: String, builds: [Build]) { self.sha256 = sha256; self.builds = builds }
}

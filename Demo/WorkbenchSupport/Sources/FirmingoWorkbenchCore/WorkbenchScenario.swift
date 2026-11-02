import Foundation

/// Data-driven discoverable case, with availability independent of any pass claim.
public struct WorkbenchScenario: Codable, Sendable, Identifiable, Equatable {
    /// Stable automation name, unaffected by display labels.
    public let id: String
    /// Human-visible purpose in the Test Lab.
    public let title: String
    /// Feature grouping shared by UI and CLI listings.
    public let category: String
    /// Observable assertion and scope, not simulated behavior.
    public let detail: String
    /// Whether this implemented case requires an exact descriptor selection.
    public let requiresBuild: Bool
    /// An explicit migration prerequisite; nil means this runner implements the case.
    public let unavailableReason: String?
    /// Initial catalogue: real compiler cases plus clearly blocked future hardware/lifecycle migrations.
    public static let all: [Self] = [
        .init(id: "compiler.catalogue", title: "Verify bundled catalogue", category: "Compiler",
              detail: "Load SDK-verified metadata. This does not execute WASM or inspect a board.", requiresBuild: false, unavailableReason: nil),
        .init(id: "compiler.resources", title: "Verify compiler resources", category: "Compiler",
              detail: "Verify the actual bundled WASM and runtime through public SDK APIs.", requiresBuild: false, unavailableReason: nil),
        .init(id: "compiler.smoke", title: "Cold/warm compilation", category: "Compiler",
              detail: "Build two pinned sources through one compiler and compare exact capsule hashes.", requiresBuild: true, unavailableReason: nil),
        .init(id: "compiler.diagnostics", title: "Diagnostics and fresh build", category: "Compiler",
              detail: "Require a real frontend rejection, then a known fresh artifact through the same compiler.", requiresBuild: true, unavailableReason: nil),
        .init(id: "device.upload-recovery", title: "Managed upload and recovery", category: "Device",
              detail: "Existing qualification guards remain in NanoHost until this migration is verified.", requiresBuild: true,
              unavailableReason: "Not migrated. This runner has no device, staging, commit or ROM-write command."),
        .init(id: "host.lifecycle", title: "Compiler lifecycle and pressure", category: "Host",
              detail: "Actual external lifecycle actions and broader resource measurement need their own migration.", requiresBuild: true,
              unavailableReason: "Not migrated. Existing lifecycle evidence retains its exact app/source identity.")
    ]
}

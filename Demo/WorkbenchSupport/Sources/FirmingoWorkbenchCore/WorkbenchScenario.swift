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
    /// Requires a real interactive iOS/iPadOS scene adapter; launch-only CLI cannot synthesize it.
    public var requiresSceneTransitions = false
    /// Device selection is required independently of compiler resources.
    public var requiresDevice = false
    /// Shared registry: compiler, mobile scene and selected-device checks; upload/recovery stays explicitly blocked.
    public static let all: [Self] = [
        .init(id: "device.inspect", title: "Inspect selected device", category: "Device",
              detail: "SDK hello and capabilities only; no console ownership, resident association or upload.", requiresBuild: false,
              unavailableReason: nil, requiresDevice: true),
        .init(id: "device.console-binary", title: "Exact 256-byte binary console", category: "Device",
              detail: "Check selected identity and boot, acquire application channel one, send one fixed probe and compare every byte. Requires an already running compatible echo application.", requiresBuild: false,
              unavailableReason: nil, requiresDevice: true),
        .init(id: "compiler.catalogue", title: "Verify bundled catalogue", category: "Compiler",
              detail: "Load SDK-verified metadata. This does not execute WASM or inspect a board.", requiresBuild: false, unavailableReason: nil),
        .init(id: "compiler.resources", title: "Verify compiler resources", category: "Compiler",
              detail: "Verify the actual bundled WASM and runtime through public SDK APIs.", requiresBuild: false, unavailableReason: nil),
        .init(id: "compiler.smoke", title: "Cold/warm compilation", category: "Compiler",
              detail: "Build two pinned sources through one compiler and compare exact capsule hashes.", requiresBuild: true, unavailableReason: nil),
        .init(id: "compiler.diagnostics", title: "Diagnostics and fresh build", category: "Compiler",
              detail: "Require a real frontend rejection, then a known fresh artifact through the same compiler.", requiresBuild: true, unavailableReason: nil),
        .init(id: "managed.stage", title: "Compile and stage fixed FMS2 sketch", category: "Managed upload",
              detail: "Review exact resident evidence and physical D2 authorization; compile the fixed source and verify RAM only.", requiresBuild: false, unavailableReason: nil, requiresDevice: true),
        .init(id: "managed.commit", title: "Commit live stage once", category: "Managed upload",
              detail: "Separate one-shot authorization replaces the managed slot. Save intent first; query startup separately.", requiresBuild: false, unavailableReason: nil, requiresDevice: true),
        .init(id: "managed.abort", title: "Abort live RAM stage", category: "Managed recovery",
              detail: "Explicit SDK pre-commit abort; unavailable after commit or process restart.", requiresBuild: false, unavailableReason: nil, requiresDevice: true),
        .init(id: "managed.disconnect", title: "Disconnect stage without commit", category: "Managed recovery",
              detail: "Close the staged connection and retain query-only context; do not infer device outcome.", requiresBuild: false, unavailableReason: nil, requiresDevice: true),
        .init(id: "managed.reconcile", title: "Query saved managed transaction", category: "Managed recovery",
              detail: "Fresh read-only status. Never restores staging or commit; unknown and failed results remain distinct.", requiresBuild: false, unavailableReason: nil, requiresDevice: true),
        .init(id: "managed.restore", title: "Restore saved managed context", category: "Managed recovery",
              detail: "Read validated host checkpoint and current record hash only; never reconnects or restores commit permission.", requiresBuild: false, unavailableReason: nil, requiresDevice: true),
        .init(id: "managed.retire", title: "Retire known pre-commit context", category: "Managed recovery",
              detail: "Requires a saved no-commit intent and an observed boot change; preserves unknown device outcome and history.", requiresBuild: false, unavailableReason: nil, requiresDevice: true),
        .init(id: "device.upload-recovery", title: "Legacy combined upload/recovery", category: "Managed recovery",
              detail: "Use the separate explicit managed actions. ROM programming and fault injection remain specialized hosts.", requiresBuild: false,
              unavailableReason: "Select a distinct managed stage, commit, disposal or reconciliation action."),
        .init(id: "compiler.cancellation", title: "SDK busy, cancellation and fresh build", category: "Compiler",
              detail: "Observe source compilation, require typed SDK busy, cancel that request and build fresh.", requiresBuild: true, unavailableReason: nil),
        .init(id: "compiler.deadline", title: "Production deadline and fresh build", category: "Compiler",
              detail: "Use the pinned expensive input to require the real sixty-second SDK deadline; no injected timeout.", requiresBuild: true, unavailableReason: nil),
        .init(id: "compiler.stress", title: "Twenty builds and memory observations", category: "Compiler",
              detail: "Alternate twenty known builds with bounded self-process footprint samples; no leak-free or aggregate peak claim.", requiresBuild: true, unavailableReason: nil),
        .init(id: "host.lifecycle", title: "Idle background and return", category: "Host",
              detail: "Build known artifacts around actual iOS/iPadOS background/return events in the same app process.", requiresBuild: true,
              unavailableReason: nil, requiresSceneTransitions: true),
        .init(id: "host.lifecycle-active", title: "Active compiler background cancellation", category: "Host",
              detail: "Explicitly start a pinned long build, go Home while an SDK call is pending, then return and build fresh.", requiresBuild: true,
              unavailableReason: nil, requiresSceneTransitions: true),
        .init(id: "host.lifecycle-worker", title: "Calibrated worker background cancellation", category: "Host",
              detail: "Calibrate the pinned long source compile, explicitly start, go Home and require first-source cancellation plus fresh recovery.", requiresBuild: true,
              unavailableReason: nil, requiresSceneTransitions: true)
    ]
}

import Foundation

/// Optional schema-one extension for compiler lifetime, deadline, bounded stress and real scene evidence.
public struct WorkbenchExerciseEvidence: Codable, Sendable {
    /// Exact selected scenario; no synthetic scene/deadline event is inferred from this field.
    public var kind: String
    /// Whether real interactive scene observations exist; CLI never claims foreground qualification.
    public var sceneObservationScope = "Launch process only; no foreground/background claim"
    /// Actual completed SDK builds, with receipts retained in the unique exported artifacts and per-call digest.
    public var builds: [Build] = []
    /// Actual callback observations for the interrupted/deadline request only, at most eight.
    public var progress: [WorkbenchCompilerProbe.Point] = []
    /// Real aggregate app-scene observations delivered by SwiftUI; not proof of suspension.
    public var scenes: [Scene] = []
    /// At most 128 self-process footprint samples; excludes WebKit children and unsampled peaks.
    public var samples: [Sample] = []
    /// Samples omitted after the finite cap; zero does not imply continuous measurement.
    public var droppedSamples = 0
    /// Current request workload identity when a fixed worker/deadline input is selected.
    public var workloadSHA256: String?
    /// Exact workload UTF-8 byte count.
    public var workloadBytes: Int?
    /// Public runtime deadline, never a shortened injected timer.
    public var runtimeDeadlineSeconds: Int?
    /// Admission time of the request selected for interruption/timeout.
    public var startedSeconds: Double?
    /// Actual child-task settlement; fresh work must follow this observation.
    public var settledSeconds: Double?
    /// Cancellation request time, absent for an actual timeout.
    public var cancelRequestedSeconds: Double?
    /// Explicit UI start after worker calibration; absent for automatic CLI checks.
    public var manuallyStartedSeconds: Double?
    /// Explicit initiator, distinguishing paired agent commands from a developer's UI action.
    public var startOrigin: StartOrigin?
    /// No synthetic scene transition is implied by either initiator.
    public enum StartOrigin: String, Codable, Sendable {
        /// Developer tapped the Test Lab button.
        case manualUI
        /// Explicit paired-controller begin command after calibration.
        case pairedController
    }
    /// Known fresh build admission after the interrupted request settled.
    public var freshStartedSeconds: Double?
    /// Typed result only: cancelled or timedOut; a generic failure cannot substitute.
    public var outcome: String?
    /// True only after an overlapping public SDK request returned typed busy.
    public var busyObserved = false
    /// First-source compilation interval observed during the completed worker calibration.
    public var calibratedCompileSeconds: Double?
    /// One actual known completed build; the receipt digest distinguishes repeated immutable requests.
    public struct Build: Codable, Sendable {
        /// One-based completion ordinal.
        public let index: Int
        /// Fixed source choice, never a path supplied by an agent.
        public let input: String
        /// Complete capsule identity already compared with the independent vector.
        public let sha256: String
        /// Actual immutable SDK receipt identity for this call.
        public let receiptSHA256: String
        /// Actual duration including the SDK resource/host work.
        public let seconds: Double
        /// Post-build worker linear bytes, separate from host footprint.
        public let wasmLinearMemoryBytes: Int
    }
    /// Relative time and actual aggregate scene phase at delivery.
    public struct Scene: Codable, Sendable {
        /// Monotonic run-relative seconds.
        public let seconds: Double
        /// Active, inactive or background.
        public let phase: String
    }
    /// Self-process TASK_VM_INFO observation; not an aggregate app plus WebKit memory peak.
    public struct Sample: Codable, Sendable {
        /// Monotonic run-relative seconds.
        public let seconds: Double
        /// Positive phys_footprint bytes for this process only.
        public let bytes: UInt64
    }
    /// Creates an empty finite evidence record at admission.
    public init(kind: String) { self.kind = kind }
}

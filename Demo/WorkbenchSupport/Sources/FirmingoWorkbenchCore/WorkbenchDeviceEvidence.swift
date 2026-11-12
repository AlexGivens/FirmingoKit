import Foundation
import FirmingoKit

/// Bounded hardware observations, distinct from compiler receipts and installed-image attestation.
public struct WorkbenchDeviceEvidence: Codable, Sendable {
    /// Original selected endpoint/identity/probe, retained even after a failed connection.
    public var selection: WorkbenchDeviceSelection
    /// Self-reported hello, present only after a validated SDK connection.
    public var snapshot: Snapshot?
    /// Whether a connection was explicitly attempted; absence of hardware is never a pass.
    public var connectionAttempted = false
    /// Whether serial.open was acknowledged, independently of bytes or useful behavior.
    public var consoleOpened = false
    /// Set and durably published before sending any probe bytes; cancellation cannot recall them.
    public var probeAttempted = false
    /// Transport-accepted byte count, including any fixed command prefixes and nonces.
    public var sentBytes = 0
    /// Exact bounded test reply, never text-decoded or stripped of startup bytes.
    public var received = Data()
    /// Explicit close acknowledgement, separate from disconnect cleanup.
    public var consoleClosed = false
    /// Completed SDK disconnect/short-lived inspection cleanup.
    public var disconnected = false
    /// First differing byte when observed; truncation/extra data remain failures too.
    public var firstMismatchOffset: Int?
    /// Starts with no claimed hardware observation.
    public init(selection: WorkbenchDeviceSelection) { self.selection = selection }
    /// Retains at most one extra byte for a failed fixed reply and bounds accepted sends.
    func validateBounds() throws {
        if selection.stateSketch != nil {
            guard received.count <= 2 * NanoStateProbe.sampleBytes + 1, [0, 2, 4].contains(sentBytes),
                  firstMismatchOffset == nil else { throw WorkbenchFailure("Invalid state probe evidence bounds.") }
        } else {
            guard received.count <= 257, (0...257).contains(sentBytes) else {
                throw WorkbenchFailure("Invalid device evidence bounds.")
            }
        }
    }
    /// Independent terminal assertions prevent an incomplete backend observation from publishing a pass.
    public func validate(console: Bool) throws {
        try selection.validate()
        guard connectionAttempted, disconnected, let snapshot, snapshot.protocolMajor == 1,
              snapshot.deviceID == selection.deviceID, snapshot.boardID == selection.boardID,
              WorkbenchDeviceSelection.isID(snapshot.bootID), !snapshot.channels.isEmpty else {
            throw WorkbenchFailure("Missing or mismatched device inspection/cleanup evidence.")
        }
        if console {
            guard snapshot.bootID == selection.bootID, snapshot.channels.contains(where: { $0.id == 1 && $0.backend == "application" }),
                  consoleOpened, probeAttempted, consoleClosed, firstMismatchOffset == nil else {
                throw WorkbenchFailure("Console evidence does not prove the selected boot and cleanup.")
            }
            if let sketch = selection.stateSketch {
                guard sentBytes == 4, snapshot.targets.contains(where: { $0.id == 2 && $0.format == "nano-managed-v2" }) else {
                    throw WorkbenchFailure("State probe requires two fixed requests on the selected FMS2 target.")
                }
                try NanoStateProbe.validatePair(received, sketch: sketch)
            } else {
                guard sentBytes == (selection.consoleProbe == "fms2-command-2-v1" ? 257 : 256), received == Data(0...255) else {
                    throw WorkbenchFailure("Console evidence does not prove the selected exact binary echo.")
                }
            }
        } else {
            guard !consoleOpened, !probeAttempted, !consoleClosed, sentBytes == 0, received.isEmpty,
                  firstMismatchOffset == nil else { throw WorkbenchFailure("Inspection unexpectedly acquired or wrote a console.") }
        }
    }
    /// Codable projection of actual SDK-validated hello facts; neither hash nor boot attestation is invented.
    public struct Snapshot: Codable, Sendable {
        /// Protocol major returned by hello.
        public let protocolMajor: UInt32
        /// Self-reported firmware version.
        public let firmwareVersion: String
        /// Stable device identity validated against selection.
        public let deviceID: String
        /// Boot identity observed on this connection.
        public let bootID: String
        /// Advertised board identity.
        public let boardID: String
        /// Negotiated payload bound.
        public let maximumPayload: UInt32
        /// Advertised development/authentication policy.
        public let authenticationMode: String
        /// Actual channel capabilities without granting ownership.
        public let channels: [Channel]
        /// Actual upload capabilities; this runner cannot invoke them.
        public let targets: [Target]
        /// Copies only validated bounded SDK fields.
        public init(_ device: FirmingoDevice) {
            protocolMajor = device.protocolMajor; firmwareVersion = device.firmwareVersion
            deviceID = device.deviceID; bootID = device.bootID; boardID = device.boardID
            maximumPayload = device.maximumPayload; authenticationMode = device.authenticationMode
            channels = device.channels.map { .init(id: $0.id, backend: $0.backend.rawValue, controls: $0.controls,
                receiveQueueBytes: $0.receiveQueueBytes, transmitQueueBytes: $0.transmitQueueBytes, isOwned: $0.isOwned) }
            targets = device.targets.map { .init(id: $0.id, format: $0.format, maximumSize: $0.maximumSize,
                maximumChunk: $0.maximumChunk, authorization: $0.authorization) }
        }
    }
    /// Channel facts recorded before serial.open; ownership is a snapshot only.
    public struct Channel: Codable, Sendable {
        /// Advertised channel identifier.
        public let id: UInt32
        /// SDK-validated application/UART backend identifier.
        public let backend: String
        /// Advertised controls, not permission to invoke them.
        public let controls: [String]
        /// Receive queue capacity in bytes.
        public let receiveQueueBytes: UInt32
        /// Transmit queue capacity in bytes.
        public let transmitQueueBytes: UInt32
        /// Advertised ownership at hello time.
        public let isOwned: Bool
    }
    /// Upload target facts; no staging/commit interface is exposed by these scenarios.
    public struct Target: Codable, Sendable {
        /// Advertised target identifier.
        public let id: UInt32
        /// Advertised capsule format.
        public let format: String
        /// Complete artifact bound.
        public let maximumSize: UInt32
        /// Upload chunk bound.
        public let maximumChunk: UInt32
        /// Advertised authorization policy.
        public let authorization: String
    }
}

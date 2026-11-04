import Foundation
import FirmingoKit

/// Fixed FMS2 qualification through public SDK APIs; no firmware image, raw flash or ROM writer is included.
@MainActor public final class SDKWorkbenchManagedDriver: WorkbenchManagedDriver {
    /// Compiled and independently SDK-validated capsule, issued only by real compilation in this process.
    private var capsule: ManagedCapsule?
    /// Verified RAM session; never reconstructed from a persisted upload record.
    private var session: FirmingoSession?
    /// Initializes no runtime or network activity.
    public init() {}
    /// Verifies the existing source/catalogue pins and real WASM output before device access.
    public func compile(sketch: String, deviceID: String) async throws -> WorkbenchReport.Artifact {
        guard ["state-a", "state-b"].contains(sketch) else { throw WorkbenchFailure("Unknown fixed sketch.") }
        let sourceSHA = sketch == "state-a" ? "d29fd4a8d813140b89a801e244bf87cd40b4e17ba7a795a70dc64fec3084e0e3" : "9576804970569a7df57e40a071d4c26fce0907fbe3f312af81ecf146466971f0"
        let source = try resource(sketch + ".ino", maximum: 4096)
        guard WorkbenchManagedCheckpoint.digest(source) == sourceSHA, let text = String(data: source, encoding: .utf8) else { throw WorkbenchFailure("Changed fixed source.") }
        let catalogue = try await ManagedCompilerCatalogue.load(manifestJSON: resource("catalogue.json", maximum: 16384),
            expectedSHA256: "8b8f1432d40b42502acca728083e5045f09ed493014bbde1786d3fa8aeed13cd")
        let snapshot = try SketchSourceSnapshot(documentID: UUID(), revision: 1, filename: sketch + ".ino", source: text)
        let result = try await ManagedSketchCompiler().build(ManagedOfflineBuildRequest(snapshot: snapshot, catalogue: catalogue, firmwareBuildID: WorkbenchManagedSelection.buildID))
        guard result.artifact.sha256 == WorkbenchManagedCheckpoint.capsuleSHA256(sketch), result.artifact.compilerReceiptJSON != nil,
              result.artifact.firmwareBuild.firmwareImageSHA256 == WorkbenchManagedSelection.imageSHA256 else { throw WorkbenchFailure("Unexpected FMS2 build output.") }
        let association = try ManagedDeviceAssociation(deviceID: deviceID, firmwareBuildID: WorkbenchManagedSelection.buildID, evidence: .hostConfirmedExistingFirmware)
        capsule = try result.artifact.bind(to: association)
        return .init(name: sketch + ".fms", sha256: result.artifact.sha256, bytes: result.artifact.bytes,
            receiptJSON: try JSONEncoder().encode(result.artifact.receipt), wasmLinearMemoryBytes: result.linearMemoryBytes)
    }
    /// Rechecks exact hello and the separate inspection's boot before any stage call.
    public func stage(_ selection: WorkbenchDeviceSelection) async throws -> ManagedUploadRecord {
        guard let capsule, session == nil else { throw WorkbenchFailure("Compile the selected fixed source first.") }
        let connection = try await connect(selection); session = connection
        guard connection.device.bootID == selection.bootID,
              connection.device.firmwareVersion == "0.1.0-statefulupload-exp1" else {
            await disconnect(); throw WorkbenchFailure("Boot or upload-enabled resident changed; no stage was sent.")
        }
        return try await connection.stageManagedUpload(capsule)
    }
    /// Calls the SDK once; SDK uncertainty is propagated with its saved record.
    public func commit(_ record: ManagedUploadRecord) async throws -> WorkbenchManagedCheckpoint.Snapshot {
        guard let session else { throw WorkbenchFailure("No live staged SDK session.") }
        return .init(try await session.commitManagedUpload(record))
    }
    /// Calls SDK pre-commit abort only on the actual live session.
    public func abort(_ record: ManagedUploadRecord) async throws -> WorkbenchManagedCheckpoint.Snapshot {
        guard let session else { throw WorkbenchFailure("No live staged SDK session.") }
        return .init(try await session.abortManagedUpload(record))
    }
    /// Invalidates local authority before cleanup suspension; normal completion never restores it.
    public func disconnect() async {
        let old = session; session = nil; capsule = nil
        if let old { await old.disconnect() }
    }
    /// A new public SDK session queries the saved record; changed boots remain explicitly unknown.
    public func reconcile(_ selection: WorkbenchDeviceSelection, record: ManagedUploadRecord) async throws -> (WorkbenchManagedCheckpoint.Snapshot?, String?) {
        let connection = try await connect(selection)
        do {
            let result = try await connection.reconcileManagedUpload(record); await connection.disconnect()
            switch result {
            case .snapshot(let value): return (.init(value), nil)
            case .unknown(let reason):
                switch reason {
                case .deviceChanged: return (nil, "deviceChanged")
                case .bootChanged: return (nil, "bootChanged")
                case .targetUnavailable: return (nil, "targetUnavailable")
                case .recordMismatch: return (nil, "recordMismatch")
                case .recordUnavailable(let code): return (nil, "recordUnavailable:" + code)
                }
            }
        } catch { await connection.disconnect(); throw error }
    }
    /// Public SDK identity/backend validation, without discovery or console ownership.
    private func connect(_ selection: WorkbenchDeviceSelection) async throws -> FirmingoSession {
        try await FirmingoSession.connect(to: FirmingoEndpoint(address: selection.address), expectedBoard: .nanoRP2040Connect,
            expectedBackend: .application, expectedDeviceID: selection.deviceID)
    }
    /// Loads only tracked fixed metadata/source bytes, never executable firmware or an external path.
    private func resource(_ name: String, maximum: Int) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "ManagedQualification") else { throw WorkbenchFailure("Missing managed qualification metadata.") }
        let value = try Data(contentsOf: url)
        guard value.count <= maximum else { throw WorkbenchFailure("Oversized managed qualification metadata.") }; return value
    }
}

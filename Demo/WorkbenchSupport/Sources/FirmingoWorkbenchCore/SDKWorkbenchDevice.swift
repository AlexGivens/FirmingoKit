import Foundation
import FirmingoKit

/// The same bounded SDK inspection/console paths used by Test Lab and MCP; no device update/reset API exists here.
@MainActor public final class SDKWorkbenchDevice: WorkbenchDeviceBackend {
    /// Optional demo-wide lease prevents overlap with unresolved deployment state and other document actions.
    private let acquire: @MainActor (Bool) async throws -> UUID
    /// Releases exactly the acquired demo lease on every outcome.
    private let release: @MainActor (UUID) async -> Void
    /// Default standalone host has only engine ownership; the demo supplies its existing deployment journal guard.
    public init(acquire: @escaping @MainActor (Bool) async throws -> UUID = { _ in UUID() },
                release: @escaping @MainActor (UUID) async -> Void = { _ in }) {
        self.acquire = acquire; self.release = release
    }
    /// Runs exactly once. A failed/uncertain send is never retried; all acquired connections are disconnected.
    public func run(_ selection: WorkbenchDeviceSelection, console: Bool,
                    save: @escaping @MainActor (WorkbenchDeviceEvidence) throws -> Void) async throws {
        try selection.validate(); try Task.checkCancellation()
        guard let board = FirmingoBoard(rawValue: selection.boardID) else { throw WorkbenchFailure("Unsupported board selection.") }
        let lease = try await acquire(console)
        do { try await perform(selection, board: board, console: console, save: save); await release(lease) }
        catch { await release(lease); throw error }
    }
    /// Persists connection and write intent before SDK I/O and leaves partial observations visible on failure.
    private func perform(_ selection: WorkbenchDeviceSelection, board: FirmingoBoard, console: Bool,
                         save: @escaping @MainActor (WorkbenchDeviceEvidence) throws -> Void) async throws {
        let observation = WorkbenchDeviceObservation(selection: selection, save: save)
        observation.value.connectionAttempted = true; try observation.publish()
        let endpoint = try FirmingoEndpoint(address: selection.address)
        if !console {
            let device = try await FirmingoInspector.inspect(at: endpoint, expectedBoard: board, expectedDeviceID: selection.deviceID)
            observation.value.snapshot = .init(device); observation.value.disconnected = true; try Task.checkCancellation(); try observation.publish(); return
        }
        guard let boot = selection.bootID, let mode = selection.consoleProbe, WorkbenchDeviceSelection.probes.contains(mode) else {
            throw WorkbenchFailure("Inspect first, then select the exact boot and fixed binary probe.")
        }
        let connection = try await FirmingoSession.connect(to: endpoint, expectedBoard: board,
            expectedBackend: .application, expectedDeviceID: selection.deviceID)
        do {
            observation.value.snapshot = .init(connection.device); try observation.publish()
            guard connection.device.bootID == boot else { throw WorkbenchFailure("Boot changed after inspection; no console bytes were sent.") }
            if selection.stateSketch != nil {
                guard connection.device.targets.contains(where: { $0.id == 2 && $0.format == "nano-managed-v2" }) else {
                    throw WorkbenchFailure("The selected Nano does not advertise the FMS2 managed target.")
                }
            }
            try Task.checkCancellation(); try await connection.openConsole()
            observation.value.consoleOpened = true; try observation.publish()
            if let sketch = selection.stateSketch {
                let first = try await probe(Data([1, NanoStateProbe.firstNonce]), count: NanoStateProbe.sampleBytes,
                                            on: connection, observation: observation)
                _ = try NanoStateProbe.parse(first, sketch: sketch, nonce: NanoStateProbe.firstNonce)
                try await Task.sleep(for: .milliseconds(50))
                _ = try await probe(Data([1, NanoStateProbe.secondNonce]), count: NanoStateProbe.sampleBytes,
                                    on: connection, observation: observation)
                try NanoStateProbe.validatePair(observation.value.received, sketch: sketch)
            } else {
                let expected = Data(0...255)
                let outbound = mode == "fms2-command-2-v1" ? Data([2]) + expected : expected
                let received = try await probe(outbound, count: expected.count, expected: expected,
                                               on: connection, observation: observation)
                guard received == expected else {
                    throw WorkbenchFailure("Binary reply differs in length or at byte \(observation.value.firstMismatchOffset ?? min(received.count, 256)).")
                }
            }
            try Task.checkCancellation(); try await connection.closeConsole()
            observation.value.consoleClosed = true; await connection.disconnect(); observation.value.disconnected = true; try observation.publish()
        } catch {
            await connection.disconnect(); observation.value.disconnected = true
            // A persistence failure is not repaired or hidden by a successful disconnect.
            do { try observation.publish() } catch let persistence { throw persistence }
            throw error
        }
    }

    /// Saves intent before one fixed send and bounds its reply under the original five-second read deadline.
    private func probe(_ outbound: Data, count: Int, expected: Data? = nil, on connection: FirmingoSession,
                       observation: WorkbenchDeviceObservation) async throws -> Data {
        try Task.checkCancellation()
        observation.value.probeAttempted = true
        try observation.publish()
        try await connection.sendSerial(outbound)
        observation.value.sentBytes += outbound.count
        try observation.publish()
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await observation.read(from: connection, count: count, expected: expected) }
            group.addTask { try await Task.sleep(for: .seconds(5)); throw FirmingoError.timedOut }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw WorkbenchFailure("Missing binary reply.") }
            return first
        }
    }
}

/// Main-actor progress owner retains partial bytes even when the read deadline or cancellation wins.
@MainActor private final class WorkbenchDeviceObservation {
    /// Latest bounded actual observations; never restored as device authority.
    var value: WorkbenchDeviceEvidence
    /// Durable engine gate invoked before later side effects.
    let save: @MainActor (WorkbenchDeviceEvidence) throws -> Void
    /// Captures one selected run and its journal boundary.
    init(selection: WorkbenchDeviceSelection, save: @escaping @MainActor (WorkbenchDeviceEvidence) throws -> Void) {
        value = .init(selection: selection); self.save = save
    }
    /// One SDK pull consumer retains bounded bytes; publication is capped at roughly eight checkpoints.
    func read(from connection: FirmingoSession, count: Int, expected: Data?) async throws -> Data {
        let prior = value.received
        var data = Data()
        for try await chunk in connection.serialBytes {
            let previousCount = data.count
            let excessive = chunk.count > count - data.count
            data.append(contentsOf: chunk.prefix(count + 1 - data.count))
            value.received = prior + data
            if let expected {
                value.firstMismatchOffset = zip(data, expected).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset
            }
            if previousCount == 0 || data.count / 32 > previousCount / 32 || data.count >= count { try publish() }
            if excessive { throw WorkbenchFailure("Binary reply exceeds the fixed probe bound.") }
            if data.count == count { return data }
        }
        try publish()
        return data
    }
    /// A failed gate propagates; it cannot become a successful observation.
    func publish() throws { try save(value) }
}

import Foundation

/// Inspects one explicitly selected endpoint with a fresh, short-lived FMGO connection.
/// It sends hello once, acquires no channel, performs no writes to firmware, and always closes.
public enum FirmingoInspector {
    /// Opens TCP, validates hello against the host selection, and closes before returning its snapshot.
    /// The absolute five-second SDK deadline includes initial path/permission waiting and hello.
    /// Waiting uses the same connection and sends no hello before ready. Cancellation closes I/O
    /// and throws `CancellationError`. Identity is unauthenticated development identity, not attestation.
    /// - Parameters:
    ///   - endpoint: Explicit numeric address and port; no discovery or reconnect occurs.
    ///   - expectedBoard: Exact board chosen by the host.
    ///   - expectedDeviceID: Optional previously selected device ID, matched exactly when supplied.
    /// - Returns: Advertised identity and capabilities, without serial ownership.
    @concurrent
    public static func inspect(at endpoint: FirmingoEndpoint, expectedBoard: FirmingoBoard,
                               expectedDeviceID: String? = nil) async throws -> FirmingoDevice {
        let transport = try TCPInspectionTransport(endpoint: endpoint)
        return try await inspect(transport: transport, expectedBoard: expectedBoard,
                                 expectedDeviceID: expectedDeviceID) {
            try await Task.sleep(for: .seconds(5))
        }
    }

    /// Injects transport and absolute-deadline wait for deterministic tests of cleanup and correlation.
    static func inspect(transport: any InspectionTransport, expectedBoard: FirmingoBoard,
                        expectedDeviceID: String? = nil,
                        deadline: @escaping @Sendable () async throws -> Void) async throws -> FirmingoDevice {
        do {
            let result = try await FMGOHandshake.timed(transport: transport, expectedBoard: expectedBoard,
                                                       expectedDeviceID: expectedDeviceID, deadline: deadline)
            await transport.close()
            try Task.checkCancellation()
            return result.device
        } catch {
            await transport.close()
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

}

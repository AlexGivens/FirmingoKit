import Foundation

/// Shared one-shot hello exchange, preserving coalesced bytes for a persistent session.
enum FMGOHandshake {
    /// Validated hello plus unconsumed bytes already read from the transport.
    struct Result: Sendable {
        /// Validated identity and capabilities.
        let device: FirmingoDevice
        /// Following bytes in the same TCP read, retained without reinterpretation.
        let tail: Data
    }

    /// Bounds connection establishment and hello under one absolute SDK deadline.
    /// Successful callers own the still-open transport; failures and cancellation close it.
    static func timed(transport: any InspectionTransport, expectedBoard: FirmingoBoard,
                      expectedDeviceID: String?,
                      deadline: @escaping @Sendable () async throws -> Void) async throws -> Result {
        do {
            let result = try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: Result.self) { group in
                    group.addTask {
                        do {
                            return try await perform(transport: transport, expectedBoard: expectedBoard,
                                                     expectedDeviceID: expectedDeviceID)
                        } catch {
                            await transport.close()
                            throw error
                        }
                    }
                    group.addTask {
                        try await deadline()
                        try Task.checkCancellation()
                        throw FirmingoError.timedOut
                    }
                    defer { group.cancelAll() }
                    do {
                        guard let result = try await group.next() else { throw FirmingoError.disconnected }
                        return result
                    } catch {
                        await transport.close()
                        throw error
                    }
                }
            } onCancel: {
                Task { await transport.close() }
            }
            try Task.checkCancellation()
            return result
        } catch {
            await transport.close()
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    /// Opens once, sends one exact hello, and validates the first response frame.
    static func perform(transport: any InspectionTransport, expectedBoard: FirmingoBoard,
                        expectedDeviceID: String?) async throws -> Result {
        try Task.checkCancellation()
        try await transport.open()
        try await transport.sendAll(FMGOFrame(kind: .request, requestID: 1,
                                             payload: Data(#"{"op":"hello"}"#.utf8)).encoded())
        var decoder = FMGOFrameDecoder()
        while let input = try await transport.receive() {
            try Task.checkCancellation()
            guard !input.isEmpty, input.count <= FMGOFrame.headerSize + FMGOFrame.maximumPayload else {
                throw FirmingoError.protocolViolation("invalid transport read size")
            }
            var remaining = input
            while !remaining.isEmpty {
                let consumed = try decoder.consume(remaining)
                remaining = remaining.dropFirst(consumed)
                if let frame = decoder.takeFrame() {
                    let device = try FirmingoDevice.hello(from: frame, requestID: 1,
                                                          expectedBoard: expectedBoard,
                                                          expectedDeviceID: expectedDeviceID)
                    return Result(device: device, tail: remaining)
                }
            }
        }
        throw FirmingoError.disconnected
    }
}

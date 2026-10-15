import Foundation

/// One actor-isolated FMGO connection with a single ordered reader and explicit channel ownership.
/// Supports channel-one serial bytes and the reviewed experimental Nano managed-upload contract.
/// Complete firmware installation, device reset, and arbitrary firmware commands remain unavailable.
public actor FirmingoSession {
    /// Identity and capabilities validated by the one hello on this connection.
    public nonisolated let device: FirmingoDevice
    /// The single-use transport owned until disconnection.
    private let transport: any InspectionTransport
    /// Injectable wait primitive used by SDK deadlines; tests trigger it without sleeps.
    private let deadlineSleep: @Sendable (Duration) async throws -> Void
    /// Frame assembler retained across arbitrarily split and coalesced reads.
    private var decoder = FMGOFrameDecoder()
    /// Bytes coalesced after hello, consumed before the next transport read.
    private var initialTail: Data
    /// Exactly one task owns all transport reads and frame dispatch.
    private var reader: Task<Void, Never>?
    /// When true, serial.open was acknowledged by this session.
    private var consoleOpen = false
    /// Distinguishes a normal closed console from a console that was never acquired.
    private var everOpened = false
    /// Allows device serial frames to precede the serial.open response.
    private var openingConsole = false
    /// An explicit close discards queued/incoming bytes while awaiting its reply.
    private var closingConsole = false
    /// Sticky terminal state, including cancellation and unexpected EOF.
    private var terminalError: (any Error)?
    /// Monotonic nonzero request ID; never reused on one connection.
    private var nextRequestID: UInt32 = 2
    /// The only outstanding control request ID.
    private var pendingID: UInt32?
    /// Reply that arrived while the corresponding frame write was still in progress.
    private var earlyReply: Result<WireJSON.Value, any Error>?
    /// Caller waiting for the current reply after its write finished.
    private var pendingReply: CheckedContinuation<WireJSON.Value, any Error>?
    /// Absolute five-second deadline for the outstanding SDK control request.
    private var requestTimer: Task<Void, Never>?
    /// Prevents interleaving frames from concurrent caller writes.
    private var sending = false
    /// Exact byte chunks buffered for the one pull consumer.
    private var serialQueue: [Data] = []
    /// Sum of queued bytes, bounded by 4096.
    private var queuedBytes = 0
    /// One consumer waiting for serial data.
    private var serialWaiter: CheckedContinuation<Data?, any Error>?
    /// Reader blocked until the host drains enough queued data.
    private var roomWaiter: CheckedContinuation<Void, any Error>?
    /// Bounded wait while the host applies backpressure.
    private var roomTimer: Task<Void, Never>?
    /// Absolute assembly deadline measured from the first byte of an incomplete frame.
    private var frameDeadline: ContinuousClock.Instant?
    /// Firmware-inspired idle deadline, reset only on actual transport progress.
    private var idleDeadline = ContinuousClock.now.advanced(by: .seconds(30))
    /// Reserves this actor against console acquisition and overlapping upload operations.
    private var managedOperation = false
    /// The only staged transaction issued by this session; restored records cannot authorize commit.
    private var managedRecord: ManagedUploadRecord?
    /// True only after every chunk and finish were acknowledged for this session's record.
    private var managedVerified = false
    /// Set before the first commit write; never cleared or retried on this connection.
    private var managedCommitAttempted = false

    /// One pull-based serial source for this connection. Create one consumer after `openConsole()`.
    public nonisolated var serialBytes: SerialBytes { SerialBytes(session: self) }

    /// Constructs an unstarted session from a validated hello without exposing the transport.
    private init(transport: any InspectionTransport, handshake: FMGOHandshake.Result,
                 deadlineSleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.transport = transport
        self.deadlineSleep = deadlineSleep
        device = handshake.device
        initialTail = handshake.tail
    }

    /// Opens a selected numeric endpoint, sends hello once, and checks the exact board, optional device ID,
    /// and expected application/UART backend before making channel operations available.
    /// A five-second deadline covers initial path/permission waiting, TCP establishment and hello.
    /// Waiting before ready retains the same connection; no reconnect or replay occurs.
    @concurrent
    public static func connect(to endpoint: FirmingoEndpoint, expectedBoard: FirmingoBoard,
                               expectedBackend: FirmingoDevice.Backend,
                               expectedDeviceID: String? = nil) async throws -> FirmingoSession {
        let transport = try TCPInspectionTransport(endpoint: endpoint)
        return try await connect(transport: transport, expectedBoard: expectedBoard,
                                 expectedBackend: expectedBackend, expectedDeviceID: expectedDeviceID) {
            try await Task.sleep(for: .seconds(5))
        } deadlineSleep: { try await Task.sleep(for: $0) }
    }

    /// Injects a transport and deadline for deterministic host-side session tests.
    static func connect(transport: any InspectionTransport, expectedBoard: FirmingoBoard,
                        expectedBackend: FirmingoDevice.Backend, expectedDeviceID: String? = nil,
                        deadline: @escaping @Sendable () async throws -> Void,
                        deadlineSleep: @escaping @Sendable (Duration) async throws -> Void = {
                            try await Task.sleep(for: $0)
                        }) async throws -> FirmingoSession {
        let handshake = try await FMGOHandshake.timed(transport: transport, expectedBoard: expectedBoard,
                                                      expectedDeviceID: expectedDeviceID, deadline: deadline)
        guard handshake.device.channels[0].backend == expectedBackend else {
            await transport.close()
            throw FirmingoError.identityMismatch
        }
        let session = FirmingoSession(transport: transport, handshake: handshake,
                                     deadlineSleep: deadlineSleep)
        await session.startReader()
        return session
    }

    /// Starts the one ordered reader only after hello identity/capabilities are validated.
    private func startReader() {
        reader = Task { [weak self] in await self?.readLoop() }
    }

    /// Acquires channel one. Application profiles use absent configuration; UART retains its current
    /// advertised settings. A competing owner is reported as the firmware's `busy` rejection.
    public func openConsole() async throws {
        try requireActive()
        guard !managedOperation, managedRecord == nil else { throw FirmingoError.busy }
        guard !consoleOpen, !openingConsole, !closingConsole else { throw FirmingoError.invalidState }
        openingConsole = true
        defer { openingConsole = false }
        do {
            let result = try await request(#"{"op":"serial.open","channel_id":1}"#)
            _ = try result.object()
            consoleOpen = true
            everOpened = true
        } catch {
            // Serial preceding a rejected open is a protocol contradiction; never expose it later.
            if !serialQueue.isEmpty { await terminate(FirmingoError.protocolViolation("serial preceded rejected open")) }
            throw error
        }
    }

    /// Returns a queue/counter snapshot. It is not a flush barrier or execution acknowledgement.
    public func serialStatus() async throws -> SerialStatus {
        try requireConsole()
        guard !managedOperation else { throw FirmingoError.busy }
        let result = try await request(#"{"op":"serial.status","channel_id":1}"#)
        do {
            let channel = try result.required("channel_id").uint32()
            let received = try result.required("backend_rx_bytes").uint64()
            let transmitted = try result.required("backend_tx_bytes").uint64()
            let toBackend = try result.required("pending_to_backend").uint32()
            let toPeer = try result.required("pending_to_peer").uint32()
            guard channel == 1, toBackend <= 256, toPeer <= 256 else { throw WireJSON.invalid }
            return SerialStatus(backendReceivedBytes: received, backendTransmittedBytes: transmitted,
                                pendingToBackend: toBackend, pendingToPeer: toPeer)
        } catch {
            await terminate(error)
            throw error
        }
    }

    /// Writes exact bytes as sequential frames of at most 256 data bytes. Completion means that the
    /// local transport accepted the frames, not that the sketch consumed them. Empty input sends nothing.
    /// UART with fewer than eight data bits rejects unrepresentable input bytes before any write.
    public func sendSerial(_ bytes: Data) async throws {
        try requireConsole()
        guard !managedOperation else { throw FirmingoError.busy }
        guard pendingID == nil, !sending else { throw FirmingoError.busy }
        if let bits = device.channels[0].uart?.dataBits, bits < 8 {
            let maximum = UInt8((1 << bits) - 1)
            guard bytes.allSatisfy({ $0 <= maximum }) else {
                throw FirmingoError.protocolViolation("byte exceeds configured UART data bits")
            }
        }
        guard !bytes.isEmpty else { return }
        sending = true
        defer { sending = false }
        var attempted = false
        do {
            var remaining = bytes
            while !remaining.isEmpty {
                try Task.checkCancellation()
                try requireConsole()
                let chunk = Data(remaining.prefix(256))
                var payload = Data([0, 0, 0, 1])
                payload.append(chunk)
                attempted = true
                try await transport.sendAll(FMGOFrame(kind: .serial, requestID: 0,
                                                      payload: payload).encoded(limit: Int(device.maximumPayload)))
                idleDeadline = ContinuousClock.now.advanced(by: .seconds(30))
                remaining = remaining.dropFirst(chunk.count)
            }
        } catch {
            let reported: any Error = attempted
                ? FirmingoError.uncertainOutcome(operation: "serial write", underlying: error)
                : error
            await terminate(reported)
            if attempted { throw reported }
            if Task.isCancelled { throw CancellationError() }
            throw reported
        }
    }

    /// Relinquishes channel ownership explicitly and discards queued, undelivered serial bytes.
    /// Bytes already accepted by the transport cannot be recalled. A failed close terminates this session.
    public func closeConsole() async throws {
        try requireConsole()
        guard pendingID == nil, !sending, !closingConsole else { throw FirmingoError.busy }
        closingConsole = true
        discardSerialQueue()
        do {
            let result = try await request(#"{"op":"serial.close","channel_id":1}"#)
            _ = try result.object()
            consoleOpen = false
            closingConsole = false
            serialWaiter?.resume(returning: nil)
            serialWaiter = nil
        } catch {
            await terminate(error)
            throw error
        }
    }

    /// Closes TCP immediately. Firmware disconnect cleanup releases channel ownership and queues;
    /// no commands, serial bytes, or uncertain application writes are replayed.
    public func disconnect() async { await terminate(nil) }

    /// Installer-only shutdown rejects pending/staged device work instead of hiding its outcome.
    /// Reserving managedOperation blocks new sends/acquisition across the close suspension point.
    func closeForFirmwareProgramming() async throws {
        guard !managedOperation, managedRecord == nil, !managedCommitAttempted,
              pendingID == nil, !sending, !openingConsole, !closingConsole else { throw FirmingoError.busy }
        managedOperation = true
        defer { managedOperation = false }
        if terminalError == nil, consoleOpen { try await closeConsole() }
        await terminate(nil)
    }

    /// Validates target/selected resident identity, closes this session's console if open, and stages
    /// all capsule bytes with exact-offset acknowledgements before requesting RAM verification.
    /// No commit or flash write occurs. Cancellation/failure disconnects and disposes the RAM stage;
    /// no chunk is retried. D2/GPIO25–GND physical authorization is enforced by the firmware at begin.
    /// Progress is delivered synchronously on SDK isolation at most once per acknowledged chunk;
    /// callbacks must return promptly and dispatch UI updates to the main actor.
    /// Save the returned record before an explicit `commitManagedUpload` call.
    public func stageManagedUpload(_ capsule: ManagedCapsule,
                                   progress: @Sendable (ManagedUploadProgress) -> Void = { _ in }) async throws -> ManagedUploadRecord {
        try requireActive()
        guard !managedOperation, managedRecord == nil, pendingID == nil, !sending,
              !openingConsole, !closingConsole else { throw FirmingoError.busy }
        let target = try NanoManagedContract.target(in: device, profile: capsule.resident.profile)
        guard device.deviceID == capsule.resident.deviceID else { throw FirmingoError.identityMismatch }
        guard capsule.bytes.count <= target.maximumSize else {
            throw ManagedUploadError.invalidArtifact("The capsule exceeds the advertised upload size")
        }
        managedOperation = true
        defer { managedOperation = false }
        do {
            try Task.checkCancellation()
            if consoleOpen { try await closeConsole() }
            let begin = #"{"op":"flash.begin","target_id":\#(target.id),"board_id":"nano_rp2040_connect","format":"\#(target.format)","size":\#(capsule.bytes.count),"sha256":"\#(capsule.sha256)"}"#
            let accepted = try ManagedUploadSnapshot.parse(await request(begin))
            let record = try ManagedUploadRecord(device: device, uploadID: accepted.uploadID, capsule: capsule)
            try checkStagedSnapshot(accepted, record: record, state: .accepted, received: 0)
            managedRecord = record
            progress(.accepted(record))
            let chunkSize = min(Int(target.maximumChunk), Int(device.maximumPayload) - 8)
            var offset = 0
            while offset < capsule.bytes.count {
                try Task.checkCancellation()
                let chunk = Data(capsule.bytes.dropFirst(offset).prefix(chunkSize))
                var payload = Self.uploadPrefix(id: record.uploadID, offset: UInt32(offset))
                payload.append(chunk)
                let snapshot = try ManagedUploadSnapshot.parse(await request(kind: .upload, payload: payload))
                try checkStagedSnapshot(snapshot, record: record, state: .accepted,
                                        received: UInt32(offset + chunk.count))
                offset += chunk.count
                progress(.transferred(record, received: UInt32(offset)))
            }
            let verified = try ManagedUploadSnapshot.parse(await request(uploadCommand("flash.finish", record: record)))
            try checkStagedSnapshot(verified, record: record, state: .verified, received: record.size)
            managedVerified = true
            progress(.verified(record))
            return record
        } catch {
            await terminate(error)
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    /// Explicitly requests installation once for this connection's verified record, then disconnects.
    /// Persist the record first. A committing result establishes only queue acceptance; query status
    /// on a fresh matching connection to observe installation/startup. D2–GND must remain authorized.
    /// Any missing/rejected/malformed reply or cancellation after the attempt throws uncertainCommit
    /// with the record/cause. That operation cannot be committed again, aborted, or replayed by the SDK.
    public func commitManagedUpload(_ record: ManagedUploadRecord) async throws -> ManagedUploadSnapshot {
        try requireActive()
        guard !managedOperation, pendingID == nil, !sending else { throw FirmingoError.busy }
        guard managedRecord == record, managedVerified, !managedCommitAttempted else {
            throw FirmingoError.invalidState
        }
        try Task.checkCancellation()
        managedCommitAttempted = true
        managedOperation = true
        managedVerified = false
        defer { managedOperation = false }
        do {
            let snapshot = try ManagedUploadSnapshot.parse(await request(uploadCommand("flash.commit", record: record)))
            guard snapshot.matches(record),
                  (snapshot.state == .committing && !snapshot.slotTouched) || snapshot.state == .failed else {
                throw WireJSON.invalid
            }
            await terminate(nil)
            return snapshot
        } catch {
            let uncertainty = ManagedUploadError.uncertainCommit(record: record, underlying: error)
            await terminate(uncertainty)
            // Reader/request cancellation can have closed transport first. Retain the public commit
            // uncertainty as the terminal cause rather than later presenting it as a safe cancellation.
            terminalError = uncertainty
            throw uncertainty
        }
    }

    /// Explicitly disposes this connection's verified pre-commit RAM stage without writing flash.
    /// Aborting after a commit attempt is unavailable; cancellation/failure closes this connection.
    public func abortManagedUpload(_ record: ManagedUploadRecord) async throws -> ManagedUploadSnapshot {
        try requireActive()
        guard !managedOperation, pendingID == nil, !sending else { throw FirmingoError.busy }
        guard managedRecord == record, managedVerified, !managedCommitAttempted else {
            throw FirmingoError.invalidState
        }
        managedOperation = true
        defer { managedOperation = false }
        do {
            let snapshot = try ManagedUploadSnapshot.parse(await request(uploadCommand("flash.abort", record: record)))
            guard snapshot.matches(record), snapshot.state == .aborted, !snapshot.slotTouched,
                  snapshot.errorCode == "none" else { throw WireJSON.invalid }
            managedRecord = nil
            managedVerified = false
            return snapshot
        } catch {
            await terminate(error)
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    /// Queries one saved transaction from a newly connected, hello-validated session with no console.
    /// Checks device/boot/target before sending status and ID/size/hash before returning a snapshot.
    /// Changed boots/devices, superseding records, and incompatible targets return unknown outcomes.
    /// Failed states inside successful envelopes remain failed snapshots with their firmware error.
    /// No polling, reconnection, chunk retry, or commit is performed as a side effect of this query.
    public func reconcileManagedUpload(_ record: ManagedUploadRecord) async throws -> ManagedUploadReconciliation {
        try requireActive()
        guard !managedOperation, managedRecord == nil, !consoleOpen, !openingConsole,
              !closingConsole, pendingID == nil, !sending else { throw FirmingoError.invalidState }
        guard device.deviceID == record.deviceID, device.boardID == record.boardID else { return .unknown(.deviceChanged) }
        guard device.bootID == record.bootID else { return .unknown(.bootChanged) }
        do {
            guard let profile = ManagedSketchBuildRequest.Profile(rawValue: record.format), profile.targetID == record.targetID else { return .unknown(.targetUnavailable) }
            _ = try NanoManagedContract.target(in: device, profile: profile)
        }
        catch ManagedUploadError.unsupportedTarget { return .unknown(.targetUnavailable) }
        managedOperation = true
        defer { managedOperation = false }
        do {
            let snapshot = try ManagedUploadSnapshot.parse(await request(uploadCommand("flash.status", record: record)))
            guard snapshot.matches(record) else { return .unknown(.recordMismatch) }
            return .snapshot(snapshot)
        } catch FirmingoError.deviceRejected(let code, _) where ["wrong_target", "unsupported", "invalid_state"].contains(code) {
            return .unknown(.recordUnavailable(code: code))
        } catch {
            await terminate(error)
            throw error
        }
    }

    /// Builds the selected contract's exact JSON schema from validated constants/nonzero record IDs.
    private func uploadCommand(_ operation: String, record: ManagedUploadRecord) -> String {
        #"{"op":"\#(operation)","target_id":\#(record.targetID),"upload_id":\#(record.uploadID)}"#
    }
    /// Rejects failed, mismatched, or out-of-order acknowledgements before sending another chunk/finish.
    private func checkStagedSnapshot(_ snapshot: ManagedUploadSnapshot, record: ManagedUploadRecord,
                                     state: ManagedUploadSnapshot.State, received: UInt32) throws {
        guard snapshot.matches(record) else { throw WireJSON.invalid }
        if snapshot.state == .failed || snapshot.state == .aborted { throw ManagedUploadError.transactionFailed(snapshot) }
        guard snapshot.state == state, snapshot.received == received, !snapshot.slotTouched else { throw WireJSON.invalid }
    }
    /// Constructs the eight-byte big-endian upload ID/relative offset prefix without alignment assumptions.
    private static func uploadPrefix(id: UInt32, offset: UInt32) -> Data {
        var bytes = Data()
        for value in [id, offset] {
            for shift in stride(from: 24, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: value >> shift)) }
        }
        return bytes
    }

    /// Retrieves one exact serial data chunk for `SerialBytes`. One concurrent consumer is permitted.
    func receiveSerial() async throws -> Data? {
        try Task.checkCancellation()
        if let terminalError { throw terminalError }
        guard everOpened else { throw FirmingoError.invalidState }
        guard consoleOpen, !closingConsole else { return nil }
        guard serialWaiter == nil else { throw FirmingoError.busy }
        if !serialQueue.isEmpty {
            let bytes = serialQueue.removeFirst()
            queuedBytes -= bytes.count
            let room = roomWaiter
            roomWaiter = nil
            roomTimer?.cancel()
            roomTimer = nil
            room?.resume()
            return bytes
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { serialWaiter = $0 }
        } onCancel: {
            Task { await self.terminate(CancellationError()) }
        }
    }

    /// Rejects a closed connection without risking transport I/O.
    private func requireActive() throws {
        if let terminalError { throw terminalError }
    }

    /// Requires acknowledged ownership, with no close in progress.
    private func requireConsole() throws {
        try requireActive()
        guard consoleOpen, !closingConsole else { throw FirmingoError.invalidState }
    }

    /// Sends a single request and waits for its correlated response, bounded by five seconds.
    /// Actor reentrancy is guarded by pendingID and sending. Cancellation closes this session.
    private func request(_ json: String) async throws -> WireJSON.Value {
        try await request(kind: .request, payload: Data(json.utf8))
    }

    /// Applies identical ordered request correlation/deadlines to control JSON and binary upload chunks.
    private func request(kind: FMGOFrame.Kind, payload: Data) async throws -> WireJSON.Value {
        try requireActive()
        guard pendingID == nil, !sending, nextRequestID != 0 else { throw FirmingoError.busy }
        let id = nextRequestID
        nextRequestID = id == UInt32.max ? 0 : id + 1
        let frame = try FMGOFrame(kind: kind, requestID: id,
                                  payload: payload).encoded(limit: Int(device.maximumPayload))
        pendingID = id
        let sleeper = deadlineSleep
        requestTimer = Task { [weak self] in
            do {
                try await sleeper(.seconds(5))
                await self?.expireRequest(id)
            } catch is CancellationError {
                // The reply completed before the deadline.
            } catch {
                await self?.terminate(error)
            }
        }
        return try await withTaskCancellationHandler {
            do {
                sending = true
                defer { sending = false }
                try await transport.sendAll(frame)
                idleDeadline = ContinuousClock.now.advanced(by: .seconds(30))
                try requireActive()
                if let earlyReply {
                    clearPending()
                    return try earlyReply.get()
                }
                return try await withCheckedThrowingContinuation { pendingReply = $0 }
            } catch {
                if pendingID != nil { await terminate(error) }
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
        } onCancel: {
            Task { await self.terminate(CancellationError()) }
        }
    }

    /// Clears one completed request, including its deadline timer.
    private func clearPending() {
        pendingID = nil
        earlyReply = nil
        pendingReply = nil
        requestTimer?.cancel()
        requestTimer = nil
    }

    /// Fails only the still-outstanding request ID and releases all I/O.
    private func expireRequest(_ id: UInt32) async {
        guard pendingID == id else { return }
        await terminate(FirmingoError.timedOut)
    }

    /// Reads one TCP fragment with the earlier of the frame and idle deadlines.
    private func timedReceive() async throws -> Data {
        let expiry = min(frameDeadline ?? idleDeadline, idleDeadline)
        let remaining = ContinuousClock.now.duration(to: expiry)
        guard remaining > .zero else { throw FirmingoError.timedOut }
        let sleeper = deadlineSleep
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { [transport] in
                guard let data = try await transport.receive() else { throw FirmingoError.disconnected }
                return data
            }
            group.addTask {
                try await sleeper(remaining)
                try Task.checkCancellation()
                throw FirmingoError.timedOut
            }
            defer { group.cancelAll() }
            do {
                guard let data = try await group.next() else { throw FirmingoError.disconnected }
                return data
            } catch {
                await transport.close()
                throw error
            }
        }
    }

    /// Processes retained hello tail first, then one bounded read at a time until termination.
    private func readLoop() async {
        var input = initialTail
        initialTail = Data()
        do {
            while true {
                try requireActive()
                if input.isEmpty {
                    input = try await timedReceive()
                    guard !input.isEmpty, input.count <= FMGOFrame.headerSize + FMGOFrame.maximumPayload else {
                        throw FirmingoError.protocolViolation("invalid transport read size")
                    }
                    idleDeadline = ContinuousClock.now.advanced(by: .seconds(30))
                }
                if decoder.bufferedByteCount == 0 { frameDeadline = ContinuousClock.now.advanced(by: .seconds(5)) }
                let consumed = try decoder.consume(input)
                input = input.dropFirst(consumed)
                if let frame = decoder.takeFrame() {
                    frameDeadline = nil
                    try await dispatch(frame)
                }
            }
        } catch {
            await terminate(error)
        }
    }

    /// Correlates control replies while routing interleaved serial bytes independently.
    private func dispatch(_ frame: FMGOFrame) async throws {
        switch frame.kind {
        case .response:
            guard let pendingID, frame.requestID == pendingID else {
                throw FirmingoError.protocolViolation("unexpected response ID")
            }
            let envelope = try WireJSON.parse(frame.payload)
            let ok = try envelope.required("ok").bool()
            let outcome: Result<WireJSON.Value, any Error>
            if ok {
                let result = try envelope.required("result")
                _ = try result.object()
                outcome = .success(result)
            } else {
                let error = try envelope.required("error")
                let code = try error.required("code").string()
                let message = try error.required("message").string()
                guard !code.isEmpty else { throw WireJSON.invalid }
                outcome = .failure(FirmingoError.deviceRejected(code: code, message: message))
            }
            if let waiter = pendingReply {
                clearPending()
                waiter.resume(with: outcome)
            } else {
                earlyReply = outcome
            }
        case .serial:
            guard consoleOpen || openingConsole, (5...260).contains(frame.payload.count),
                  frame.payload.prefix(4).elementsEqual([0, 0, 0, 1]) else {
                throw FirmingoError.protocolViolation("serial without channel-one ownership")
            }
            if closingConsole { return }
            let bytes = Data(frame.payload.dropFirst(4))
            if let waiter = serialWaiter {
                serialWaiter = nil
                waiter.resume(returning: bytes)
            } else {
                while queuedBytes + bytes.count > 4096 {
                    try await waitForRoom()
                    try requireActive()
                    if closingConsole { return }
                }
                serialQueue.append(bytes)
                queuedBytes += bytes.count
            }
        case .event, .request, .upload:
            throw FirmingoError.protocolViolation("unexpected device frame type")
        }
    }

    /// Suspends the sole reader at a fixed 4096-byte queue ceiling, with a 30-second SDK bound.
    private func waitForRoom() async throws {
        guard roomWaiter == nil else { throw FirmingoError.protocolViolation("multiple blocked readers") }
        let sleeper = deadlineSleep
        roomTimer = Task { [weak self] in
            do {
                try await sleeper(.seconds(30))
                await self?.expireRoom()
            } catch is CancellationError {
                // Consumer made room or the connection closed.
            } catch {
                await self?.terminate(error)
            }
        }
        try await withCheckedThrowingContinuation { roomWaiter = $0 }
    }

    /// Terminates a stalled consumer rather than retaining a reader indefinitely.
    private func expireRoom() async {
        guard roomWaiter != nil else { return }
        await terminate(FirmingoError.timedOut)
    }

    /// Discards only buffered SDK bytes when the host explicitly closes the console.
    private func discardSerialQueue() {
        serialQueue.removeAll(keepingCapacity: true)
        queuedBytes = 0
        roomTimer?.cancel()
        roomTimer = nil
        let waiter = roomWaiter
        roomWaiter = nil
        waiter?.resume()
    }

    /// Resolves every pending operation once and closes the transport. Error termination discards all
    /// queued bytes; a caller never receives an apparent successful replay on a new connection.
    private func terminate(_ error: (any Error)?) async {
        guard terminalError == nil else { return }
        let failure = error ?? FirmingoError.disconnected
        terminalError = failure
        reader?.cancel()
        reader = nil
        requestTimer?.cancel()
        requestTimer = nil
        roomTimer?.cancel()
        roomTimer = nil
        let response = pendingReply
        let serial = serialWaiter
        let room = roomWaiter
        pendingID = nil
        pendingReply = nil
        earlyReply = nil
        serialWaiter = nil
        roomWaiter = nil
        serialQueue.removeAll()
        queuedBytes = 0
        consoleOpen = false
        openingConsole = false
        closingConsole = false
        if let response { response.resume(throwing: failure) }
        if let serial {
            if error == nil { serial.resume(returning: nil) }
            else { serial.resume(throwing: failure) }
        }
        room?.resume(throwing: failure)
        await transport.close()
    }
}

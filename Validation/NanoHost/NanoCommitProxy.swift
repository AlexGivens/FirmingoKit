import Foundation
import Network

/// Explicit one-client loopback fault injector; forwards real frames and suppresses one validated commit reply.
actor NanoCommitProxy {
    /// Actor-owned bounded Network.framework socket, independent of the SDK transport implementation.
    private actor Socket {
        /// One physical or loopback TCP connection.
        private let connection: NWConnection
        /// Serial callback context; callbacks return mutable work to this actor.
        private let queue = DispatchQueue(label: "NanoRecovery.socket")
        /// Sticky single-use lifetime.
        private var closed = false
        /// Whether the single permitted open has started.
        private var started = false
        /// Pending readiness continuation.
        private var opening: CheckedContinuation<Void, any Error>?
        /// Pending bounded read continuation.
        private var reading: CheckedContinuation<Data, any Error>?
        /// Pending complete write continuation.
        private var writing: CheckedContinuation<Void, any Error>?
        /// Takes ownership without initiating I/O.
        init(_ connection: NWConnection) { self.connection = connection }
        /// Opens once; caller owns the five-second setup deadline.
        func open() async throws {
            guard !closed, !started else { throw NanoGate.Rejected() }; started = true
            try await withCheckedThrowingContinuation { continuation in
                opening = continuation
                connection.stateUpdateHandler = { [weak self] state in Task { await self?.changed(state) } }
                connection.start(queue: queue)
            }
        }
        /// Resolves initial waiting on this connection; established waiting is terminal.
        private func changed(_ state: NWConnection.State) {
            guard !closed else { return }
            switch state {
            case .ready: let c = opening; opening = nil; c?.resume()
            case .failed, .cancelled: close()
            case .waiting: if opening == nil { close() }
            default: break
            }
        }
        /// Receives exactly a caller-bounded prefix; no coalesced tail or queue grows without a bound.
        func read(_ count: Int) async throws -> Data {
            guard (1...4096).contains(count) else { throw NanoGate.Rejected() }
            var result = Data()
            while result.count < count {
                guard started, !closed, opening == nil, reading == nil else { throw NanoGate.Rejected() }
                let remaining = count - result.count
                let part: Data = try await withCheckedThrowingContinuation { continuation in
                    reading = continuation
                    connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] data, _, done, error in
                        Task { await self?.received(data, done: done, error: error) }
                    }
                }
                result.append(part)
            }
            return result
        }
        /// Delivers final bytes before EOF; every continuation settles once.
        private func received(_ data: Data?, done: Bool, error: NWError?) {
            guard !closed else { return }
            if error != nil { close(); return }
            let c = reading; reading = nil
            if let data, !data.isEmpty { c?.resume(returning: data) }
            else { c?.resume(throwing: NanoGate.Rejected()) }
            if done { close() }
        }
        /// One complete bounded frame at a time provides backpressure through Network.framework.
        func write(_ bytes: Data) async throws {
            guard started, !closed, opening == nil, writing == nil, bytes.count <= 4112 else { throw NanoGate.Rejected() }
            try await withCheckedThrowingContinuation { continuation in
                writing = continuation
                connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
                    Task { await self?.sent(error) }
                })
            }
        }
        /// Completes a single send or releases every pending operation on failure.
        private func sent(_ error: NWError?) {
            guard !closed else { return }
            if error != nil { close(); return }
            let c = writing; writing = nil; c?.resume()
        }
        /// Idempotent shutdown resolves pending I/O even when callbacks arrive late.
        func close() {
            guard !closed else { return }; closed = true; connection.cancel()
            let o = opening, r = reading, w = writing
            opening = nil; reading = nil; writing = nil
            o?.resume(throwing: NanoGate.Rejected()); r?.resume(throwing: NanoGate.Rejected()); w?.resume(throwing: NanoGate.Rejected())
        }
    }
    /// Numeric board endpoint selected by the host; never inferred from discovery.
    private let address: String
    /// Explicit upstream port; hardware uses 7420, isolated local relay tests use their own ephemeral listener.
    private let port: UInt16
    /// One listener bound only to IPv4 loopback.
    private var listener: NWListener?
    /// Initial listener readiness continuation.
    private var opening: CheckedContinuation<UInt16, any Error>?
    /// Sole accepted SDK connection.
    private var downstream: Socket?
    /// Sole connection to the selected Nano.
    private var upstream: Socket?
    /// Owned opening/forwarding tasks, canceled on terminal closure.
    private var tasks: [Task<Void, Never>] = []
    /// Fault gate is armed only after actual SDK staging returns its record.
    private var gate: NanoReplyLossGate?
    /// Observed completion of the one upstream commit send.
    private var commitSendCompleted = false
    /// Sticky closure state; no reconnection is possible.
    private var closed = false
    /// Terminal diagnostics, bounded and never an installation-success claim.
    private var failure = ""

    /// Configuration alone never creates a socket.
    init(address: String, port: UInt16 = 7420) { self.address = address; self.port = port }
    /// Starts an explicit loopback listener; the SDK still performs its own real hello/identity checks.
    func start() async throws -> UInt16 {
        guard listener == nil, !closed else { throw NanoGate.Rejected() }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let value = try NWListener(using: parameters)
        listener = value
        return try await withCheckedThrowingContinuation { continuation in
            opening = continuation
            value.stateUpdateHandler = { [weak self] state in Task { await self?.changed(state) } }
            value.newConnectionHandler = { [weak self] connection in Task { await self?.accept(connection) } }
            value.start(queue: DispatchQueue(label: "NanoRecovery.listener"))
        }
    }
    /// Publishes the selected ephemeral port, or settles readiness on failure.
    private func changed(_ state: NWListener.State) async {
        guard !closed else { return }
        switch state {
        case .ready:
            let c = opening; opening = nil
            if let port = listener?.port { c?.resume(returning: port.rawValue) }
            else { c?.resume(throwing: NanoGate.Rejected()); await stop() }
        case .failed, .cancelled: await stop()
        default: break
        }
    }
    /// Admits one client and opens the one upstream socket with a finite setup deadline.
    private func accept(_ connection: NWConnection) {
        guard !closed, downstream == nil else { connection.cancel(); return }
        let client = Socket(connection)
        guard let selectedPort = NWEndpoint.Port(rawValue: port) else { connection.cancel(); return }
        let device = Socket(NWConnection(host: NWEndpoint.Host(address), port: selectedPort, using: .tcp))
        downstream = client; upstream = device
        tasks.append(Task { [weak self] in
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await client.open(); try await device.open() }
                    group.addTask { try await Task.sleep(for: .seconds(5)); await client.close(); await device.close(); throw NanoGate.Rejected() }
                    defer { group.cancelAll() }; _ = try await group.next()
                }
                await self?.started(client, device)
            } catch { await self?.failed(error) }
        })
    }
    /// Starts one task per direction only after both sockets are actually ready.
    private func started(_ client: Socket, _ device: Socket) {
        guard !closed else { return }
        tasks.append(Task { [weak self] in await self?.forward(client, to: device, fromClient: true) })
        tasks.append(Task { [weak self] in await self?.forward(device, to: client, fromClient: false) })
    }
    /// Arms exactly the verified target-2 transaction; this does not send commit.
    func arm(uploadID: UInt32, size: UInt32, sha256: String) throws {
        guard !closed, gate == nil, uploadID > 0, (260...4096).contains(size), sha256.count == 64 else { throw NanoGate.Rejected() }
        gate = NanoReplyLossGate(uploadID: uploadID, size: size, sha256: sha256)
    }
    /// Reads/forwards whole bounded frames with no replay; closes both ends after consuming the selected real reply.
    private func forward(_ source: Socket, to destination: Socket, fromClient: Bool) async {
        do {
            while !closed {
                var frame = try await source.read(16)
                let header = try NanoReplyLossGate.header(frame, complete: false)
                if header.size > 0 { frame.append(try await source.read(header.size)) }
                var commit = false
                if fromClient, try NanoReplyLossGate.operation(frame) == "flash.commit" {
                    guard var selected = gate else { throw NanoGate.Rejected() }
                    try selected.observeCommit(frame); gate = selected; commit = true
                } else if !fromClient, var selected = gate {
                    let deliver = try selected.shouldForward(frame); gate = selected
                    if !deliver { await stop(); return }
                }
                try await destination.write(frame)
                if commit { commitSendCompleted = true }
            }
        } catch { await failed(error) }
    }
    /// Records an unexpected terminal failure without turning it into a successful injected loss.
    private func failed(_ error: any Error) async {
        if !closed { failure = String(error.localizedDescription.prefix(512)) }
        await stop()
    }
    /// Captures real observed bytes and send completion; callers must require every field before accepting the check.
    func evidence() -> [String: String] {
        ["commitRequestsObserved": gate?.commitRequestID == nil ? "0" : "1", "commitSendCompleted": String(commitSendCompleted),
         "withheldResponse": gate?.withheldResponse?.base64EncodedString() ?? "", "failure": failure]
    }
    /// Closes only this test proxy's sockets/tasks and settles pending listener setup.
    func stop() async {
        guard !closed else { return }; closed = true
        listener?.cancel(); let c = opening; opening = nil; c?.resume(throwing: NanoGate.Rejected())
        for task in tasks { task.cancel() }; tasks.removeAll()
        if let downstream { await downstream.close() }
        if let upstream { await upstream.close() }
    }
}

import Foundation
@testable import FirmingoKit

/// Scripted byte-stream peer with partial writes, interleaved frames, and explicit EOF.
actor SessionTestTransport: InspectionTransport {
    /// The pinned independent hello response frame.
    private let hello: Data
    /// Maximum accepted prefix per host write; one tests partial-write retention.
    private let writeLimit: Int
    /// Payloads returned for successive control requests by operation name.
    private var responses: [String: [Data]]
    /// Frames emitted immediately before the next open response.
    private var openPrelude: [Data]
    /// Whether prelude and reply share a single transport read.
    private let coalesceOpen: Bool
    /// Fail a write once this many accepted calls have occurred, if configured.
    private var failAfterWrites: Int?
    /// Incoming client frame assembler, independent of write boundaries.
    private var decoder = FMGOFrameDecoder()
    /// Device-to-host chunks awaiting a receive.
    private var incoming: [Data] = []
    /// One suspended receive, resolved by inject or close.
    private var pendingRead: CheckedContinuation<Data?, any Error>?
    /// One waiting assertion for a specified delivered read count.
    private var deliveredWaiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?
    /// One waiting assertion for a specified sent frame count.
    private var sentWaiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?
    /// Complete host frames received in order.
    private(set) var sentFrames: [FMGOFrame] = []
    /// Raw accepted prefixes proving partial writes were retained.
    private(set) var writeChunks: [Data] = []
    /// Number of chunks delivered to the host reader.
    private(set) var deliveredReads = 0
    /// Number of transport opens; stays one per session.
    private(set) var opens = 0
    /// Whether SDK cleanup closed the peer.
    private(set) var closed = false
    /// Signals terminal cleanup without polling or timing-sensitive sleeps.
    let closedLatch = TestLatch()

    /// Configures deterministic request responses and optional serial-before-open bytes.
    init(hello: Data, writeLimit: Int = 4112, responses: [String: [Data]] = [:],
         openPrelude: [Data] = [], coalesceOpen: Bool = false) {
        self.hello = hello
        self.writeLimit = writeLimit
        self.responses = responses
        self.openPrelude = openPrelude
        self.coalesceOpen = coalesceOpen
    }

    /// Opens once without sockets or timing.
    func open() throws {
        guard !closed, opens == 0 else { throw FirmingoError.disconnected }
        opens += 1
    }

    /// Accepts a short prefix and processes any completed host frame.
    func send(_ bytes: Data) throws -> Int {
        guard !closed, opens == 1 else { throw FirmingoError.disconnected }
        if let failAfterWrites, writeChunks.count >= failAfterWrites { throw FirmingoError.disconnected }
        let accepted = Data(bytes.prefix(writeLimit))
        writeChunks.append(accepted)
        var tail = accepted
        while !tail.isEmpty {
            tail = tail.dropFirst(try decoder.consume(tail))
            if let frame = decoder.takeFrame() {
                sentFrames.append(frame)
                notifySent()
                try respond(to: frame)
            }
        }
        return accepted.count
    }

    /// Makes a later partial write fail after a deterministic number of accepted calls.
    func failAfter(additionalWrites: Int) { failAfterWrites = writeChunks.count + additionalWrites }

    /// Supplies the next scripted chunk or suspends until the SDK closes.
    func receive() async throws -> Data? {
        guard !closed else { throw FirmingoError.disconnected }
        if !incoming.isEmpty {
            let bytes = incoming.removeFirst()
            deliveredReads += 1
            notifyDelivered()
            return bytes
        }
        return try await withCheckedThrowingContinuation { pendingRead = $0 }
    }

    /// Makes scripted peer bytes available without waiting for a real network.
    func inject(_ bytes: Data) {
        guard !closed else { return }
        if let pendingRead {
            self.pendingRead = nil
            deliveredReads += 1
            notifyDelivered()
            pendingRead.resume(returning: bytes)
        } else {
            incoming.append(bytes)
        }
    }

    /// Resolves pending reads promptly and keeps frame observations for assertions.
    func close() {
        guard !closed else { return }
        closed = true
        Task { await closedLatch.signal() }
        let reader = pendingRead
        pendingRead = nil
        reader?.resume(throwing: FirmingoError.disconnected)
    }

    /// Waits for at least the specified number of complete host frames.
    func waitForSent(_ count: Int) async {
        if sentFrames.count >= count { return }
        await withCheckedContinuation { sentWaiter = (count, $0) }
    }

    /// Waits for at least the specified number of chunks consumed by the SDK reader.
    func waitForDelivered(_ count: Int) async {
        if deliveredReads >= count { return }
        await withCheckedContinuation { deliveredWaiter = (count, $0) }
    }

    /// Unblocks an assertion after a complete host frame arrives.
    private func notifySent() {
        if let sentWaiter, sentFrames.count >= sentWaiter.count {
            self.sentWaiter = nil
            sentWaiter.continuation.resume()
        }
    }

    /// Unblocks an assertion after the SDK's reader consumes a chunk.
    private func notifyDelivered() {
        if let deliveredWaiter, deliveredReads >= deliveredWaiter.count {
            self.deliveredWaiter = nil
            deliveredWaiter.continuation.resume()
        }
    }

    /// Routes a complete request through the fixed scripted firmware response.
    private func respond(to frame: FMGOFrame) throws {
        if frame.kind == .upload {
            guard var replies = responses["upload.chunk"], !replies.isEmpty else { return }
            let payload = replies.removeFirst()
            responses["upload.chunk"] = replies
            inject(try FMGOFrame(kind: .response, requestID: frame.requestID, payload: payload).encoded())
            return
        }
        guard frame.kind == .request else { return }
        let document = try WireJSON.parse(frame.payload)
        let operation = try document.required("op").string()
        if operation == "hello" { inject(hello); return }
        if operation == "serial.open", !openPrelude.isEmpty {
            let prelude = openPrelude
            openPrelude = []
            if coalesceOpen, var replies = responses[operation], !replies.isEmpty {
                let payload = replies.removeFirst()
                responses[operation] = replies
                let reply = try FMGOFrame(kind: .response, requestID: frame.requestID, payload: payload).encoded()
                inject(prelude.reduce(into: Data()) { $0.append($1) } + reply)
                return
            }
            for bytes in prelude { inject(bytes) }
        }
        guard var replies = responses[operation], !replies.isEmpty else { return }
        let payload = replies.removeFirst()
        responses[operation] = replies
        inject(try FMGOFrame(kind: .response, requestID: frame.requestID, payload: payload).encoded())
    }
}

import Foundation
import Testing
@testable import FirmingoKit

/// Managed staging, one-shot commit, and read-only reconciliation over fake transports only.
struct ManagedUploadTests {
    /// Staging matches independent begin/chunk/finish vectors; it never sends commit implicitly.
    @Test func goldenStagingAndAbort() async throws {
        var replies = try ManagedUploadFixtures.stagingResponses()
        replies["flash.abort"] = [try ManagedUploadFixtures.response("aborted")]
        let peer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(), writeLimit: 3, responses: replies)
        let session = try await ManagedUploadFixtures.connect(peer)
        let record = try await session.stageManagedUpload(ManagedUploadFixtures.capsule())
        #expect(record.uploadID == 1)
        #expect(record.sha256 == ManagedUploadFixtures.capsuleDigest)
        #expect(record.bootID == "0123456789abcdef")
        let sent = await peer.sentFrames
        #expect(sent.map(\.requestID) == [1, 2, 3, 4])
        for (index, name) in [(1, "begin-request"), (2, "chunk"), (3, "finish-request")] {
            let frame = sent[index]
            let recorrelation = try FMGOFrame(kind: frame.kind, requestID: 9, payload: frame.payload).encoded()
            #expect(try recorrelation == ProtocolFixtures.bytes("managed-upload/\(name)"))
        }
        #expect(await peer.writeChunks.allSatisfy { $0.count <= 3 })
        await #expect(throws: FirmingoError.self) { try await session.openConsole() }
        let aborted = try await session.abortManagedUpload(record)
        #expect(aborted.state == .aborted)
        #expect(aborted.errorCode == "none")
        #expect(!aborted.slotTouched)
        await session.disconnect()
    }
    /// A currently owned console is explicitly closed before begin, disposing its serial queue.
    @Test func closesConsoleBeforeBegin() async throws {
        var replies = try ManagedUploadFixtures.stagingResponses()
        replies["serial.open"] = [Data(#"{"ok":true,"result":{}}"#.utf8)]
        replies["serial.close"] = [Data(#"{"ok":true,"result":{}}"#.utf8)]
        let peer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(), responses: replies)
        let session = try await ManagedUploadFixtures.connect(peer)
        try await session.openConsole()
        let record = try await session.stageManagedUpload(ManagedUploadFixtures.capsule())
        let operations = try await peer.sentFrames.filter { $0.kind == .request }.map {
            try WireJSON.parse($0.payload).required("op").string()
        }
        #expect(operations == ["hello", "serial.open", "serial.close", "flash.begin", "flash.finish"])
        var serial = session.serialBytes.makeAsyncIterator()
        #expect(try await serial.next() == nil)
        #expect(record.size == 264)
        await session.disconnect()
    }
    /// Release firmware with no targets and the wrong physical device cannot reach flash.begin.
    @Test func rejectsUnsupportedAndWrongDeviceBeforeWrite() async throws {
        for hello in [try FMGOFrame(kind: .response, requestID: 1,
                                   payload: ProtocolFixtures.frame("hello-response").payload).encoded(),
                      try ManagedUploadFixtures.hello(mutate: { $0["device_id"] = "1111111111111111" })] {
            let peer = SessionTestTransport(hello: hello)
            let session = try await ManagedUploadFixtures.connect(peer)
            await #expect(throws: (any Error).self) { try await session.stageManagedUpload(ManagedUploadFixtures.capsule()) }
            #expect(await peer.sentFrames.count == 1)
            #expect(!(await peer.closed))
            await session.disconnect()
        }
    }
    /// Authorization/ownership/target rejection remains a device error and sends no chunk/finish/commit.
    @Test(arguments: ["unauthorized", "busy", "wrong_target"])
    func beginRejection(code: String) async throws {
        let response = code == "unauthorized" ? try ManagedUploadFixtures.response("unauthorized") :
            Data(#"{"ok":false,"error":{"code":"\#(code)","message":"\#(code)"}}"#.utf8)
        let peer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(),
                                        responses: ["flash.begin": [response]])
        let session = try await ManagedUploadFixtures.connect(peer)
        do {
            _ = try await session.stageManagedUpload(ManagedUploadFixtures.capsule())
            Issue.record("Expected physical authorization rejection")
        } catch FirmingoError.deviceRejected(let rejected, _) { #expect(rejected == code) }
        #expect(await peer.sentFrames.count == 2)
        #expect(await peer.closed)
    }
    /// Wrong offsets/transaction identity/hash/size are terminal and never advance to finish.
    @Test(arguments: ["received", "upload_id", "sha256", "size", "slot_touched"])
    func mismatchedChunkAcknowledgement(field: String) async throws {
        var replies = try ManagedUploadFixtures.stagingResponses()
        replies["upload.chunk"] = [try ManagedUploadFixtures.mutatedResponse("chunk") {
            switch field {
            case "sha256": $0[field] = String(repeating: "0", count: 64)
            case "slot_touched": $0[field] = true
            default: $0[field] = field == "received" ? 0 : 999
            }
        }]
        let peer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(), responses: replies)
        let session = try await ManagedUploadFixtures.connect(peer)
        await #expect(throws: FirmingoError.self) { try await session.stageManagedUpload(ManagedUploadFixtures.capsule()) }
        #expect(await peer.sentFrames.count == 3)
        #expect(await peer.closed)
    }
    /// A successful envelope containing failed is surfaced with its machine error and touched-slot flag.
    @Test(arguments: ["flash.begin", "upload.chunk", "flash.finish"])
    func failedTransactionIsNotStageSuccess(operation: String) async throws {
        var replies = try ManagedUploadFixtures.stagingResponses()
        replies[operation] = [try ManagedUploadFixtures.response("install-failed")]
        let peer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(), responses: replies)
        let session = try await ManagedUploadFixtures.connect(peer)
        do {
            _ = try await session.stageManagedUpload(ManagedUploadFixtures.capsule())
            Issue.record("Expected transaction failure")
        } catch ManagedUploadError.transactionFailed(let snapshot) {
            #expect(snapshot.state == .failed)
            #expect(snapshot.errorCode == "install_failed")
            #expect(snapshot.slotTouched)
        }
        let expectedCount = operation == "flash.begin" ? 2 : operation == "upload.chunk" ? 3 : 4
        #expect(await peer.sentFrames.count == expectedCount)
        #expect(await peer.closed)
    }
    /// The upload reservation prevents new ownership/staging while a chunk reply is pending.
    @Test func cancellationAndOperationReservation() async throws {
        let peer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(),
                                        responses: ["flash.begin": [try ManagedUploadFixtures.response("accepted")]])
        let session = try await ManagedUploadFixtures.connect(peer)
        let stage = Task { try await session.stageManagedUpload(ManagedUploadFixtures.capsule()) }
        await peer.waitForSent(3)
        await #expect(throws: FirmingoError.self) { try await session.openConsole() }
        await #expect(throws: FirmingoError.self) { try await session.stageManagedUpload(ManagedUploadFixtures.capsule()) }
        stage.cancel()
        await #expect(throws: CancellationError.self) { try await stage.value }
        #expect(await peer.sentFrames.count == 3)
        #expect(await peer.closed)
    }
    /// A lost chunk acknowledgement times out without implicit retry or commit; its record is retained by progress.
    @Test func lostChunkReply() async throws {
        let expiry = TestLatch()
        let (records, continuation) = AsyncStream<ManagedUploadRecord>.makeStream(bufferingPolicy: .bufferingNewest(1))
        defer { continuation.finish() }
        let peer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(),
                                        responses: ["flash.begin": [try ManagedUploadFixtures.response("accepted")]])
        let session = try await ManagedUploadFixtures.connect(peer, sleep: { duration in
            if duration <= .seconds(5) { try await expiry.wait() }
            else { try await TestLatch().wait() }
        })
        let stage = Task {
            try await session.stageManagedUpload(ManagedUploadFixtures.capsule()) { progress in
                if case .accepted(let record) = progress { continuation.yield(record) }
            }
        }
        var iterator = records.makeAsyncIterator()
        let record = try #require(await iterator.next())
        await peer.waitForSent(3)
        await expiry.signal()
        await #expect(throws: FirmingoError.self) { try await stage.value }
        #expect(await peer.sentFrames.count == 3)
        let freshPeer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(),
                                             responses: ["flash.status": [try ManagedUploadFixtures.response("disconnected")]])
        let fresh = try await ManagedUploadFixtures.connect(freshPeer)
        let outcome = try await fresh.reconcileManagedUpload(record)
        guard case .snapshot(let snapshot) = outcome else { Issue.record("Expected retained aborted stage"); return }
        #expect(snapshot.state == .aborted)
        #expect(snapshot.errorCode == "disconnected")
        #expect(!snapshot.slotTouched)
        await fresh.disconnect()
    }
    /// Commit acknowledgement establishes queue acceptance only and permanently ends the original connection.
    @Test func commitAcceptedOnce() async throws {
        var replies = try ManagedUploadFixtures.stagingResponses()
        replies["flash.commit"] = [try ManagedUploadFixtures.response("committing")]
        let peer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(), responses: replies)
        let session = try await ManagedUploadFixtures.connect(peer)
        let record = try await session.stageManagedUpload(ManagedUploadFixtures.capsule())
        let snapshot = try await session.commitManagedUpload(record)
        #expect(snapshot.state == .committing)
        #expect(!snapshot.slotTouched)
        #expect(await peer.closed)
        await #expect(throws: FirmingoError.self) { try await session.commitManagedUpload(record) }
        let commits = try await peer.sentFrames.filter {
            guard $0.kind == .request else { return false }
            return try WireJSON.parse($0.payload).required("op").string() == "flash.commit"
        }
        #expect(commits.count == 1)
        #expect(try FMGOFrame(kind: .request, requestID: 9, payload: commits[0].payload).encoded() ==
                ProtocolFixtures.bytes("managed-upload/commit-request"))
    }
    /// Lost or cancelled commit replies preserve the record/cause; a new status query sends zero commits.
    @Test(arguments: [false, true]) func lostCommitReply(cancel: Bool) async throws {
        let (session, peer, record) = try await ManagedUploadFixtures.staged()
        let commit = Task { try await session.commitManagedUpload(record) }
        await peer.waitForSent(5)
        if cancel { commit.cancel() } else { await peer.close() }
        do {
            _ = try await commit.value
            Issue.record("Expected unknown commit outcome")
        } catch ManagedUploadError.uncertainCommit(let saved, let cause) {
            #expect(saved == record)
            if cancel { #expect(cause is CancellationError) }
        }
        await #expect(throws: ManagedUploadError.self) { try await session.commitManagedUpload(record) }
        let freshPeer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(),
                                             responses: ["flash.status": [try ManagedUploadFixtures.response("boot-confirmed")]])
        let fresh = try await ManagedUploadFixtures.connect(freshPeer)
        guard case .snapshot(let result) = try await fresh.reconcileManagedUpload(record) else {
            Issue.record("Expected confirmed matching record"); return
        }
        #expect(result.state == .bootConfirmed)
        #expect(result.slotTouched)
        let operations = try await freshPeer.sentFrames.map { try WireJSON.parse($0.payload).required("op").string() }
        #expect(operations == ["hello", "flash.status"])
        #expect(await peer.sentFrames.count == 5)
        await fresh.disconnect()
    }
    /// Readback, startup confirmation, installation failure, and pre-commit abort remain distinct results.
    @Test(arguments: ["installed", "boot-confirmed", "install-failed", "aborted"])
    func reconcilesIndependentStates(name: String) async throws {
        let (original, _, record) = try await ManagedUploadFixtures.staged()
        await original.disconnect()
        let peer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(),
                                        responses: ["flash.status": [try ManagedUploadFixtures.response(name)]])
        let fresh = try await ManagedUploadFixtures.connect(peer)
        guard case .snapshot(let snapshot) = try await fresh.reconcileManagedUpload(record) else {
            Issue.record("Expected matching snapshot"); return
        }
        let expected: ManagedUploadSnapshot.State = switch name {
        case "installed": .installed
        case "boot-confirmed": .bootConfirmed
        case "install-failed": .failed
        default: .aborted
        }
        #expect(snapshot.state == expected)
        #expect(snapshot.errorCode == (name == "install-failed" ? "install_failed" : "none"))
        await fresh.disconnect()
    }
    /// Changed device/boot or missing targets returns unknown before issuing any status request.
    @Test(arguments: ["device_id", "boot_id", "targets"])
    func changedConnectionIdentity(field: String) async throws {
        let (original, _, record) = try await ManagedUploadFixtures.staged()
        await original.disconnect()
        let hello = try ManagedUploadFixtures.hello { $0[field] = field == "targets" ? [] : "1111111111111111" }
        let peer = SessionTestTransport(hello: hello)
        let fresh = try await ManagedUploadFixtures.connect(peer)
        let result = try await fresh.reconcileManagedUpload(record)
        let reason: ManagedUploadReconciliation.Reason = switch field {
        case "device_id": .deviceChanged
        case "boot_id": .bootChanged
        default: .targetUnavailable
        }
        #expect(result == .unknown(reason))
        #expect(await peer.sentFrames.count == 1)
        await fresh.disconnect()
    }
    /// A status record with the wrong ID/hash/size or a superseded record is unknown, never success.
    @Test(arguments: ["upload_id", "sha256", "size", "superseded"])
    func mismatchedReconciliation(field: String) async throws {
        let (original, _, record) = try await ManagedUploadFixtures.staged()
        await original.disconnect()
        let response: Data
        if field == "superseded" {
            response = Data(#"{"ok":false,"error":{"code":"wrong_target","message":"wrong_target"}}"#.utf8)
        } else {
            response = try ManagedUploadFixtures.mutatedResponse("installed") {
                if field == "sha256" { $0[field] = String(repeating: "0", count: 64) }
                else if field == "size" { $0[field] = 265; $0["received"] = 265 }
                else { $0[field] = 2 }
            }
        }
        let peer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(), responses: ["flash.status": [response]])
        let fresh = try await ManagedUploadFixtures.connect(peer)
        let reason: ManagedUploadReconciliation.Reason = field == "superseded" ? .recordUnavailable(code: "wrong_target") : .recordMismatch
        #expect(try await fresh.reconcileManagedUpload(record) == .unknown(reason))
        #expect(await peer.sentFrames.count == 2)
        await fresh.disconnect()
    }
    /// Persisted records validate on restoration and cannot authorize commit on a fresh connection.
    @Test func savedRecordCannotReplayCommit() async throws {
        let (original, _, record) = try await ManagedUploadFixtures.staged()
        let bytes = try JSONEncoder().encode(record)
        let restored = try JSONDecoder().decode(ManagedUploadRecord.self, from: bytes)
        #expect(restored == record)
        for (field, value) in [("version", 2), ("uploadID", 0), ("size", 0)] {
            var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            json[field] = value
            #expect(throws: ManagedUploadError.self) {
                try JSONDecoder().decode(ManagedUploadRecord.self, from: JSONSerialization.data(withJSONObject: json))
            }
        }
        await original.disconnect()
        let peer = SessionTestTransport(hello: try ManagedUploadFixtures.hello())
        let fresh = try await ManagedUploadFixtures.connect(peer)
        await #expect(throws: FirmingoError.self) { try await fresh.commitManagedUpload(restored) }
        #expect(await peer.sentFrames.count == 1)
        await fresh.disconnect()
    }
    /// Minimum/maximum capsules use bounded chunks, exact capsule-relative offsets, and request counts.
    @Test(arguments: [257, 4096]) func capsuleAndChunkBoundaries(size: Int) async throws {
        let bytes = try ManagedUploadFixtures.boundaryBytes(size: size)
        let capsule = try ManagedCapsule(bytes: bytes, reportJSON: ManagedUploadFixtures.reportJSON(ManagedUploadFixtures.report(bytes: bytes)),
                                         resident: ManagedUploadFixtures.resident())
        let acknowledgedOffsets = stride(from: 0, to: size, by: 1024).map { min($0 + 1024, size) }
        let replies: [String: [Data]] = [
            "flash.begin": [try ManagedUploadFixtures.boundaryResponse(bytes: bytes, received: 0, state: "accepted")],
            "upload.chunk": try acknowledgedOffsets.map { try ManagedUploadFixtures.boundaryResponse(bytes: bytes, received: $0, state: "accepted") },
            "flash.finish": [try ManagedUploadFixtures.boundaryResponse(bytes: bytes, received: size, state: "verified")]]
        let peer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(), responses: replies)
        let session = try await ManagedUploadFixtures.connect(peer)
        let record = try await session.stageManagedUpload(capsule)
        let chunks = await peer.sentFrames.filter { $0.kind == .upload }
        #expect(chunks.count == acknowledgedOffsets.count)
        for (index, chunk) in chunks.enumerated() {
            #expect(chunk.payload.count == min(1024, size - index * 1024) + 8)
            #expect(FMGOFrame.uint32(Array(chunk.payload), at: 4) == UInt32(index * 1024))
            #expect(Data(chunk.payload.dropFirst(8)) == Data(bytes.dropFirst(index * 1024).prefix(1024)))
        }
        #expect(record.size == UInt32(size))
        #expect(await peer.sentFrames.count == chunks.count + 3)
        await session.disconnect()
    }

    /// A malformed or explicitly rejected commit reply retains the saved record and never retries.
    @Test(arguments: ["malformed", "rejected"])
    func unsafeCommitReplies(kind: String) async throws {
        var replies = try ManagedUploadFixtures.stagingResponses()
        replies["flash.commit"] = [kind == "malformed" ? Data(#"{"ok":true,"result":{}}"#.utf8)
            : try ManagedUploadFixtures.response("unauthorized")]
        let peer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(), responses: replies)
        let session = try await ManagedUploadFixtures.connect(peer)
        let record = try await session.stageManagedUpload(ManagedUploadFixtures.capsule())
        do {
            _ = try await session.commitManagedUpload(record)
            Issue.record("Expected uncertain commit")
        } catch ManagedUploadError.uncertainCommit(let saved, let cause) {
            #expect(saved == record)
            if kind == "rejected" {
                guard case FirmingoError.deviceRejected(let code, _) = cause else {
                    Issue.record("Expected retained device rejection"); return
                }
                #expect(code == "unauthorized")
            }
        }
        await #expect(throws: ManagedUploadError.self) { try await session.commitManagedUpload(record) }
        #expect(await peer.sentFrames.count == 5)
        #expect(await peer.closed)
    }

    /// A controlled commit deadline is unknown installation outcome, not a safe automatic retry.
    @Test func commitDeadlineIsUncertain() async throws {
        let expiry = TestLatch()
        let peer = SessionTestTransport(hello: try ManagedUploadFixtures.hello(),
                                        responses: try ManagedUploadFixtures.stagingResponses())
        let session = try await ManagedUploadFixtures.connect(peer, sleep: { duration in
            if duration <= .seconds(5) { try await expiry.wait() }
            else { try await TestLatch().wait() }
        })
        let record = try await session.stageManagedUpload(ManagedUploadFixtures.capsule())
        let commit = Task { try await session.commitManagedUpload(record) }
        await peer.waitForSent(5)
        await expiry.signal()
        do {
            _ = try await commit.value
            Issue.record("Expected uncertain commit timeout")
        } catch ManagedUploadError.uncertainCommit(let saved, let cause) {
            #expect(saved == record)
            guard case FirmingoError.timedOut = cause else {
                Issue.record("Expected original SDK deadline cause"); return
            }
        }
        #expect(await peer.sentFrames.count == 5)
        #expect(await peer.closed)
    }
}

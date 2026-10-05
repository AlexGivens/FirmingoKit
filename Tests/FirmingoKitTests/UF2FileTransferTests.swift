import Foundation
import Testing
@testable import FirmingoKit

/// Tests the actual native transfer loop with an in-memory partial writer, never a ROM volume.
struct UF2FileTransferTests {
    /// Controlled writer retaining accepted prefixes, ordered progress, and synchronization observations.
    private actor Sink {
        /// Exact accepted data for independent input comparison.
        var accepted = Data()
        /// Requested chunk sizes, bounded even when writes accept short prefixes.
        var sizes: [Int] = []
        /// Awaited ordered progress counts.
        var counts: [Int] = []
        /// Whether completion reached synchronization.
        var synchronized = false
        /// Accepts at most 513 bytes to exercise non-block-aligned host write boundaries.
        func write(_ chunk: Data) -> Int {
            sizes.append(chunk.count)
            let count = min(513, chunk.count)
            accepted.append(chunk.prefix(count))
            return count
        }
        /// Records progress after the previous accepted prefix.
        func progress(_ count: Int) { counts.append(count) }
        /// Marks final host synchronization; this is not board verification.
        func synchronize() { synchronized = true }
    }
    /// Partial writes retain their exact suffix; requests stay bounded and synchronize follows all bytes.
    @Test func partialPrefixesAndBounds() async throws {
        let input = Data((0..<140_000).map { UInt8(truncatingIfNeeded: $0) })
        let sink = Sink()
        try await UF2FileTransfer.transfer(input, write: { await sink.write($0) },
                                          synchronize: { await sink.synchronize() }, progress: { await sink.progress($0) })
        #expect(await sink.accepted == input)
        #expect(await sink.sizes.first == 65536)
        #expect(await sink.sizes.allSatisfy { $0 > 0 && $0 <= 65536 })
        #expect(await sink.counts.first == 513)
        #expect(await sink.counts.last == input.count)
        #expect(await sink.synchronized)
    }
    /// Invalid native write counts fail immediately, without progress or synchronization.
    @Test(arguments: [0, -1, 3]) func invalidCounts(_ count: Int) async throws {
        let sink = Sink()
        await #expect(throws: FirmwareInstallationError.self) {
            try await UF2FileTransfer.transfer(Data([0, 255]), write: { _ in count },
                                              synchronize: { await sink.synchronize() }, progress: { await sink.progress($0) })
        }
        #expect(await sink.counts.isEmpty)
        #expect(!(await sink.synchronized))
    }
}

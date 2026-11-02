import Foundation
import FirmingoKit

/// Bounded synchronous progress capture across SDK/WebKit isolation. The lock protects every mutable field;
/// snapshots are value copies, callbacks cannot access engine/UI state, and one probe belongs to one SDK call.
public final class WorkbenchCompilerProbe: @unchecked Sendable {
    /// Exclusive access to the callback buffer and overflow bit.
    private let lock = NSLock()
    /// At most eight public SDK observations, in callback order.
    private var values: [Point] = []
    /// Additional callbacks invalidate evidence rather than being silently lost.
    private var overflow = false
    /// Single bounded signal for the first actual source-compilation callback; exactly one consumer per request.
    private let signal: AsyncStream<Void>
    /// Finishes on first compilation or explicit call settlement; no unbounded notification queue.
    private let continuation: AsyncStream<Void>.Continuation
    /// One public SDK notification and its actual monotonic callback time.
    public struct Point: Codable, Sendable {
        /// Public phase; not an instruction-pointer measurement.
        public let phase: String
        /// Absolute system uptime, converted to run-relative time on export.
        public let seconds: Double
    }
    /// Allocates no compiler or background task.
    public init() {
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
        signal = pair.stream; continuation = pair.continuation
    }
    /// Called synchronously from the public SDK observer; never performs I/O or dispatches UI work.
    public func record(_ phase: ManagedCompilationPhase) {
        lock.lock()
        guard values.count < 8 else { overflow = true; lock.unlock(); continuation.finish(); return }
        let first = phase == .compiling && !values.contains { $0.phase == "compiling" }
        values.append(.init(phase: phase.rawValue, seconds: ProcessInfo.processInfo.systemUptime))
        lock.unlock()
        if first { continuation.yield(()); continuation.finish() }
    }
    /// Awaits actual first-source progress without a polling interval that could miss a short compile.
    func waitForSourceCompilation() async throws {
        for await _ in signal { try Task.checkCancellation(); return }
        throw CancellationError()
    }
    /// Called on every SDK settlement so an absent callback cannot leave an observer task pending.
    func finish() { continuation.finish() }
    /// Captures a consistent copy; an overflow makes this request unqualifiable.
    public func snapshot() throws -> [Point] {
        lock.lock(); defer { lock.unlock() }
        guard !overflow else { throw WorkbenchFailure("Compiler progress exceeded its public bound.") }
        return values
    }
}

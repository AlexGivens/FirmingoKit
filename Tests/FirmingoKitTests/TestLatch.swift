import Foundation

/// Cancellation-aware latch avoids sleeps and timing assumptions in concurrency tests.
actor TestLatch {
    /// Sticky signal supports either waiter/signal ordering.
    private var signalled = false
    /// Independently owned waiters, removed on cancellation.
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    /// Waits until signalled, promptly terminating on cancellation.
    func wait() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if signalled { return }
            try await withCheckedThrowingContinuation { waiters[id] = $0 }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }
    /// Resolves all current and future waiters.
    func signal() {
        signalled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending.values { waiter.resume() }
    }
    /// Resolves a cancelled waiter exactly once.
    private func cancel(_ id: UUID) { waiters.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
}

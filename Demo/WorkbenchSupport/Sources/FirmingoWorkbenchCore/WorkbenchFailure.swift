import Foundation

/// Concise host orchestration failure; SDK failures keep their original classification in reports.
public struct WorkbenchFailure: LocalizedError, Sendable {
    /// Readable rejection or violated scenario assertion.
    public let errorDescription: String?
    /// Creates an explicit failure without falling back or retrying.
    public init(_ message: String) { errorDescription = message }
}

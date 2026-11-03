/// App-owned foreground test policy; changes no compiler deadline, scene event or background permission.
public struct WorkbenchIdleTimerPolicy {
    /// Original host setting captured once per active test interval, including an already-disabled timer.
    private var previousValue: Bool?
    /// Starts without claiming ownership of the host idle timer.
    public init() {}
    /// Returns the host setting for the real foreground/run state and restores the captured setting on release.
    public mutating func update(isForeground: Bool, isRunning: Bool, currentValue: Bool) -> Bool {
        if isForeground && isRunning {
            if previousValue == nil { previousValue = currentValue }
            return true
        }
        guard let previousValue else { return currentValue }
        self.previousValue = nil
        return previousValue
    }
}

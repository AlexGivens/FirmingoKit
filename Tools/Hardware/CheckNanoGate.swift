import Foundation

/// Executes the production qualification policy without an SDK transport, compiler asset or device.
@main struct CheckNanoGate {
    /// Requires the exact policy rejection, never accepting another error or successful transition.
    static func rejected(_ action: () throws -> Void) throws {
        do { try action() } catch is NanoGate.Rejected { return }
        throw NSError(domain: "NanoGateChecks", code: 1)
    }

    /// Checks stale setup, missing evidence, one-shot intent, restored records and explicit terminal advancement.
    static func main() throws {
        var gate = NanoGate()
        try rejected { try gate.requestCommit() }
        try gate.prepared()
        try rejected { try gate.associate(address: "192.168.77.1", deviceID: "actual", imageSHA: NanoGate.imageSHA, note: "reviewed evidence") }
        try gate.inspected(address: "192.168.77.1", deviceID: "actual", bootID: "boot-one")
        try rejected { try gate.associate(address: "192.168.77.2", deviceID: "actual", imageSHA: NanoGate.imageSHA, note: "reviewed evidence") }
        try rejected { try gate.associate(address: "192.168.77.1", deviceID: "another", imageSHA: NanoGate.imageSHA, note: "reviewed evidence") }
        try rejected { try gate.associate(address: "192.168.77.1", deviceID: "actual", imageSHA: String(repeating: "0", count: 64), note: "reviewed evidence") }
        try rejected { try gate.associate(address: "192.168.77.1", deviceID: "actual", imageSHA: NanoGate.imageSHA, note: "") }
        try gate.associate(address: "192.168.77.1", deviceID: "actual", imageSHA: NanoGate.imageSHA, note: "reviewed evidence")
        try rejected { try gate.requireStage(address: "192.168.77.1", deviceID: "actual", bootID: "boot-two") }
        try rejected { try gate.requireStage(address: "192.168.77.2", deviceID: "actual", bootID: "boot-one") }
        try rejected { try gate.requireStage(address: "192.168.77.1", deviceID: "another", bootID: "boot-one") }
        try gate.requireStage(address: "192.168.77.1", deviceID: "actual", bootID: "boot-one")
        try gate.staged(); try gate.requestCommit()
        try rejected { try gate.requestCommit() }; try rejected { try gate.staged() }; try rejected { try gate.next() }
        try gate.confirmed(); try gate.next()
        guard gate.state == .prepared, gate.deviceID.isEmpty else { throw NSError(domain: "NanoGateChecks", code: 2) }
        gate.restore()
        try rejected { try gate.requestCommit() }; try rejected { try gate.next() }
        try gate.aborted(); try gate.next()
        try gate.inspected(address: "192.168.77.1", deviceID: "actual", bootID: "boot-two")
        try gate.associate(address: "192.168.77.1", deviceID: "actual", imageSHA: NanoGate.imageSHA, note: "new reviewed evidence")
        try gate.inspected(address: "192.168.77.1", deviceID: "actual", bootID: "boot-three")
        try rejected { try gate.requireStage(address: "192.168.77.1", deviceID: "actual", bootID: "boot-three") }
        var stateful = NanoGate(imageSHA: "1ef766226ce6a2c51c668562cd51a71ed0bfbe1634b76b54d704c7e710ca1b2f")
        try stateful.prepared(); try stateful.inspected(address: "192.168.77.1", deviceID: "actual", bootID: "boot-one")
        try rejected { try stateful.associate(address: "192.168.77.1", deviceID: "actual", imageSHA: NanoGate.imageSHA, note: "legacy evidence") }
        try stateful.associate(address: "192.168.77.1", deviceID: "actual", imageSHA: "1ef766226ce6a2c51c668562cd51a71ed0bfbe1634b76b54d704c7e710ca1b2f", note: "new reviewed evidence")
        try stateful.requireStage(address: "192.168.77.1", deviceID: "actual", bootID: "boot-one")
        print("Nano production gate checks passed: stale endpoint/device/boot, evidence, one-shot commit, restoration and explicit terminal advancement; no device access")
    }
}

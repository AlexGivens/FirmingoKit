import Foundation

/// Explicit local-only relay check executable; never accepts a physical address or board artifact.
@main struct CheckNanoProxyLoopback {
    /// Starts a loopback proxy for an independently authored Python fake peer and records its real observed bytes.
    static func main() async throws {
        let args = ProcessInfo.processInfo.arguments
        guard args.count == 4, args[1] == "--loopback-upstream-port", let port = UInt16(args[2]), port > 0 else { throw NanoGate.Rejected() }
        let directory = URL(fileURLWithPath: args[3], isDirectory: true)
        let proxy = NanoCommitProxy(address: "127.0.0.1", port: port)
        do {
            let listening = try await proxy.start()
            try await proxy.arm(uploadID: 1, size: 548, sha256: String(repeating: "0", count: 64))
            try Data(String(listening).utf8).write(to: directory.appendingPathComponent("port.txt"), options: .withoutOverwriting)
            for _ in 0..<1000 {
                let evidence = await proxy.evidence()
                if evidence["withheldResponse"]?.isEmpty == false {
                    try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]).write(to: directory.appendingPathComponent("evidence.json"), options: .withoutOverwriting)
                    await proxy.stop(); return
                }
                if evidence["failure"]?.isEmpty == false { throw NanoGate.Rejected() }
                try await Task.sleep(for: .milliseconds(10))
            }
            throw NanoGate.Rejected()
        } catch { await proxy.stop(); throw error }
    }
}

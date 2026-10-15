import Foundation
import CryptoKit

/// Immutable test-candidate selection. FMS2 uses a distinct app identity and explicit imported catalogue.
enum NanoCandidate {
    #if FMS2_QUALIFICATION
    /// Selects the separate FMS2 host without migrating the existing ABI-one app or catalogue.
    static let stateful = true
    /// Exact firmware-derived descriptor; the compiler owns its recipe identity.
    static let buildID = "dacbf259b96de0e050514764253403f3ef1ef51d0f9efaf1f43a10d8654c0e18"
    /// Resident-only UF2, separate from a ROM composite's digest.
    static let imageSHA = "1ef766226ce6a2c51c668562cd51a71ed0bfbe1634b76b54d704c7e710ca1b2f"
    /// Independently selected imported catalogue packaged only in this test host.
    static let catalogueSHA = "8b8f1432d40b42502acca728083e5045f09ed493014bbde1786d3fa8aeed13cd"
    /// Exact upload-enabled resident label, never installed-image attestation.
    static let version = "0.1.0-statefulupload-exp1"
    /// Explicit FMGO target and capsule format.
    static let targetID: UInt32 = 2
    /// Versioned managed image format.
    static let format = "nano-managed-v2"
    /// Known sketch identities and hashes, derived through actual WASM compilation and independent firmware checks.
    static let pins = [
        ("state-a", "State A: seed 7 / D13 low", "d29fd4a8d813140b89a801e244bf87cd40b4e17ba7a795a70dc64fec3084e0e3", "537ce260fc33d4b23b2f8829aee6a9b12653236db6baad4c317040dbf087fd89"),
        ("state-b", "State B: seed 23 / D13 high", "9576804970569a7df57e40a071d4c26fce0907fbe3f312af81ecf146466971f0", "505c723804addf218e9018375c1f63fd036c2e0bf19d0173ae189b04418aa9b0")]
    #else
    /// Preserves the legacy Nano qualification workflow.
    static let stateful = false
    /// Legacy descriptor identity.
    static let buildID = NanoGate.buildID
    /// Legacy resident-only image.
    static let imageSHA = NanoGate.imageSHA
    /// Legacy catalogue retained by the current reviewed consumer package.
    static let catalogueSHA = "e341bfc0385fea9b2b026dc624daa26cdeac33286f4bb07243b37c1c31837d0e"
    /// Legacy resident label.
    static let version = "0.1.0-m9exp1"
    /// Legacy upload target.
    static let targetID: UInt32 = 1
    /// Legacy image format.
    static let format = "nano-managed-v1"
    /// Legacy source/artifact identities; source is supplied inline below.
    static let pins = [("gpio", "GPIO6 high / delay", "", "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d"),
        ("console", "Binary console echo", "", "b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0")]
    #endif
    /// Current independently reviewed service/source package; stateful catalogue selection remains separate.
    static let consumerSHA = "1bbc0cc19d80490914799fbec5cb4bbc0a942a73fd3bbf6e09fff2c3856e660a"

    /// Returns only fixed bounded source bytes and verifies the FMS2 source resources before compilation.
    static func source(_ name: String) throws -> String {
        if stateful {
            guard let pin = pins.first(where: { $0.0 == name }), let url = Bundle.main.url(forResource: name, withExtension: "ino") else { throw NanoGate.Rejected() }
            let bytes = try Data(contentsOf: url)
            guard bytes.count < 4096, SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == pin.2,
                  let source = String(data: bytes, encoding: .utf8) else { throw NanoGate.Rejected() }
            return source
        }
        if name == "gpio" { return "void setup() { pinMode(6, 1); }\nvoid loop() { digitalWrite(6, 1); delay(10); }\n" }
        if name == "console" { return "void setup() { Serial.println(\"ready\"); }\nvoid loop() { int c = Serial.read(); if (c >= 0) Serial.write(uint8_t(c)); }\n" }
        throw NanoGate.Rejected()
    }
}

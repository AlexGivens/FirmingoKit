import Foundation

/// Bounded fixed source choices migrated from the legacy compiler qualification host.
public enum WorkbenchCompilerInput: String, Sendable {
    /// Board-correct pin/delay proof, never deployed by this runner.
    case gpio
    /// Distinct binary-console compiler path, never deployed by this runner.
    case console
    /// Deliberate frontend error; an unexpected successful build must fail the scenario.
    case invalid
    /// Pinned long source compilation, returning the known GPIO artifact.
    case worker
    /// Pinned expensive frontend input expected to hit the unchanged SDK deadline.
    case deadline
    /// Exact independently qualified legacy descriptor; no physical-device identity.
    public static let buildID = "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f"
    /// Fixed bounded source; broader source bundles remain a separate compiler feature.
    var source: String {
        get throws {
            switch self {
            case .gpio: "void setup() { pinMode(6, 1); }\nvoid loop() { digitalWrite(6, 1); delay(10); }\n"
            case .console: "void setup() { Serial.println(\"ready\"); }\nvoid loop() { int c = Serial.read(); if (c >= 0) Serial.write(uint8_t(c)); }\n"
            case .worker: try WorkbenchWorkload.source(deadline: false)
            case .deadline: try WorkbenchWorkload.source(deadline: true)
            case .invalid: "void setup() { missingFunction(); }\nvoid loop() {}\n"
            }
        }
    }
    /// Independent artifact vectors retained from the signed legacy compiler-host evidence.
    var expectedSHA256: String? {
        switch self {
            case .gpio, .worker: "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d"
        case .console: "b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0"
        case .invalid, .deadline: nil
        }
    }
}

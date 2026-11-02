import Foundation
import CryptoKit

/// Reproduces the legacy qualification-only fixture exactly, without a second bundled 227 KiB copy.
/// Hashes are pinned to Validation/CompilerHost and its physical deadline/worker evidence.
enum WorkbenchWorkload {
    /// Original independently pinned source hash.
    static let workerSHA256 = "9a17105b5d17f732435ab81c6bf1083386e5cb5ae8b36569259bac8cf479ec3f"
    /// Derived sixteen-repetition deadline source hash.
    static let deadlineSHA256 = "bde5df426deb79fd8277abfd5b406cf1288b28b307646b62bc5ee1028cce26eb"
    /// Generates fixed test input only; neither recipe nor compiler settings are modified.
    static func source(deadline: Bool) throws -> String {
        let original = """
        constexpr unsigned qualification_mix(unsigned x) {
          for (unsigned i = 0; i < 1024; ++i) x = (x * 1664525u + 1013904223u) ^ (x >> 13);
          return x;
        }
        """
        let replacement = """
        constexpr unsigned qualification_mix(unsigned seed) {
          unsigned result = 0;
          for (unsigned repetition = 0; repetition < 16; ++repetition) {
            unsigned x = seed;
            for (unsigned i = 0; i < 1024; ++i) x = (x * 1664525u + 1013904223u) ^ (x >> 13);
            result = x;
          }
          return result;
        }
        """
        var text = "// Qualification-only compile-time workload; never deployed.\n" + (deadline ? replacement : original) + "\n"
        for seed in UInt32(0)..<4096 {
            var x = seed
            for _ in 0..<1024 { x = (x &* 1664525 &+ 1013904223) ^ (x >> 13) }
            text += "static_assert(qualification_mix(\(seed)u) == \(x)u);\n"
        }
        text += "void setup() { pinMode(6, 1); }\nvoid loop() { digitalWrite(6, 1); delay(10); }\n"
        let data = Data(text.utf8)
        guard data.count == (deadline ? 227646 : 227505), digest(data) == (deadline ? deadlineSHA256 : workerSHA256) else {
            throw WorkbenchFailure("Qualification workload differs from the pinned legacy input.")
        }
        return text
    }
    /// Identifies bounded evidence/receipts without adding a compiler implementation.
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

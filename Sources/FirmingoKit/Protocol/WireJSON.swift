import Foundation

/// Bounded JSON parsing with exact decoded-key uniqueness and preserved number spelling.
/// Response bounds are SDK limits; the firmware's stricter request limits are not applied to replies.
struct WireJSON {
    /// Schema values. Object keys use UTF-8 bytes so Unicode normalization cannot merge distinct keys.
    indirect enum Value: Sendable {
        /// An object with unique decoded UTF-8 keys.
        case object([Data: Value])
        /// An ordered array.
        case array([Value])
        /// Validated Unicode text without embedded NUL.
        case string(String)
        /// A syntactically valid JSON number with its original spelling.
        case number(String)
        /// A JSON boolean.
        case boolean(Bool)
        /// JSON null.
        case null

        /// Finds an ASCII schema field without normalizing object keys.
        subscript(_ key: String) -> Value? {
            guard case .object(let fields) = self else { return nil }
            return fields[Data(key.utf8)]
        }
        /// Extracts a required object.
        func object() throws -> [Data: Value] {
            guard case .object(let value) = self else { throw WireJSON.invalid }
            return value
        }
        /// Extracts a required array.
        func array() throws -> [Value] {
            guard case .array(let value) = self else { throw WireJSON.invalid }
            return value
        }
        /// Extracts required text.
        func string() throws -> String {
            guard case .string(let value) = self else { throw WireJSON.invalid }
            return value
        }
        /// Extracts a required unsigned decimal u32, rejecting signs, decimals, and exponents.
        func uint32() throws -> UInt32 {
            guard case .number(let text) = self, text.utf8.allSatisfy({ (48...57).contains($0) }),
                  let value = UInt32(text) else { throw WireJSON.invalid }
            return value
        }
        /// Extracts a required unsigned decimal u64 without coercing other JSON number forms.
        func uint64() throws -> UInt64 {
            guard case .number(let text) = self, text.utf8.allSatisfy({ (48...57).contains($0) }),
                  let value = UInt64(text) else { throw WireJSON.invalid }
            return value
        }
        /// Extracts a required boolean without coercing numbers.
        func bool() throws -> Bool {
            guard case .boolean(let value) = self else { throw WireJSON.invalid }
            return value
        }
        /// Retrieves a required field; unknown fields are intentionally ignored by schema consumers.
        func required(_ key: String) throws -> Value {
            guard let value = self[key] else { throw WireJSON.invalid }
            return value
        }
    }

    /// A shared short schema/parser failure.
    static var invalid: FirmingoError { .protocolViolation("malformed JSON or invalid response schema") }
    /// Byte storage bounded by the validated frame length.
    private let bytes: [UInt8]
    /// Next unread byte.
    private var position = 0
    /// Bounds total parser work independently of nesting.
    private var tokens = 0
    /// Consumer-selected work bound; FMGO responses retain their original 512-token limit.
    private let maximumTokens: Int

    /// Validates an entire bounded UTF-8 JSON object, without BOM or trailing content.
    static func parse(_ data: Data, maximumBytes: Int = FMGOFrame.maximumPayload,
                      maximumTokens: Int = 512) throws -> Value {
        guard data.count <= maximumBytes, maximumTokens > 0 else { throw invalid }
        var parser = WireJSON(bytes: Array(data), maximumTokens: maximumTokens)
        let value = try parser.value(depth: 0)
        parser.whitespace()
        guard parser.position == parser.bytes.count else { throw invalid }
        _ = try value.object()
        return value
    }

    /// Reads one bounded value with a maximum of 16 nested containers and the selected token limit.
    private mutating func value(depth: Int) throws -> Value {
        whitespace()
        tokens += 1
        guard tokens <= maximumTokens, position < bytes.count else { throw Self.invalid }
        let byte = bytes[position]
        switch byte {
        case 123, 91:
            guard depth < 16 else { throw Self.invalid }
            position += 1
            whitespace()
            let isObject = byte == 123
            let closing: UInt8 = isObject ? 125 : 93
            var fields: [Data: Value] = [:]
            var values: [Value] = []
            if consume(closing) { return isObject ? .object(fields) : .array(values) }
            while true {
                if isObject {
                    tokens += 1
                    guard tokens <= maximumTokens else { throw Self.invalid }
                    let key = Data(try text().utf8)
                    whitespace()
                    guard consume(58), fields[key] == nil else { throw Self.invalid }
                    fields[key] = try value(depth: depth + 1)
                } else {
                    values.append(try value(depth: depth + 1))
                }
                whitespace()
                if consume(closing) { break }
                guard consume(44) else { throw Self.invalid }
                whitespace()
            }
            return isObject ? .object(fields) : .array(values)
        case 34: return .string(try text())
        case 116: try literal("true"); return .boolean(true)
        case 102: try literal("false"); return .boolean(false)
        case 110: try literal("null"); return .null
        default:
            let start = position
            _ = consume(45)
            guard position < bytes.count else { throw Self.invalid }
            if consume(48) {
                // Leading zero cannot be followed by another digit.
                guard position == bytes.count || !(48...57).contains(bytes[position]) else { throw Self.invalid }
            } else {
                guard (49...57).contains(bytes[position]) else { throw Self.invalid }
                digits()
            }
            if consume(46) { try requiredDigits() }
            if consume(101) || consume(69) {
                if !consume(43) { _ = consume(45) }
                try requiredDigits()
            }
            return .number(String(decoding: bytes[start..<position], as: UTF8.self))
        }
    }

    /// Scans a string, then delegates Unicode/escape validation to Foundation's strict string decoder.
    private mutating func text() throws -> String {
        let start = position
        guard consume(34) else { throw Self.invalid }
        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            if byte == 34 {
                do {
                    let value = try JSONDecoder().decode(String.self, from: Data(bytes[start..<position]))
                    guard !value.utf8.contains(0) else { throw Self.invalid }
                    return value
                } catch { throw Self.invalid }
            }
            if byte == 92 {
                guard position < bytes.count else { throw Self.invalid }
                position += 1
            }
        }
        throw Self.invalid
    }

    /// Consumes a literal exactly, leaving delimiter validation to its containing value.
    private mutating func literal(_ text: String) throws {
        let literal = Array(text.utf8)
        guard bytes.dropFirst(position).starts(with: literal) else { throw Self.invalid }
        position += literal.count
    }
    /// Consumes one expected byte without advancing on a mismatch.
    private mutating func consume(_ byte: UInt8) -> Bool {
        guard position < bytes.count, bytes[position] == byte else { return false }
        position += 1
        return true
    }
    /// Consumes ASCII decimal digits.
    private mutating func digits() {
        while position < bytes.count, (48...57).contains(bytes[position]) { position += 1 }
    }
    /// Requires at least one decimal digit for a fraction or exponent.
    private mutating func requiredDigits() throws {
        let start = position
        digits()
        guard position > start else { throw Self.invalid }
    }
    /// Skips only the four JSON whitespace bytes.
    private mutating func whitespace() {
        while position < bytes.count, [9, 10, 13, 32].contains(bytes[position]) { position += 1 }
    }
}

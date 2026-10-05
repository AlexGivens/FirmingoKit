import Foundation
import Testing
@testable import FirmingoKit

/// Schema, identity, and capability validation beyond synthesized Codable decoding.
struct FirmingoHelloTests {
    /// Empty release targets and the experimental target both decode from independent firmware vectors.
    @Test func capabilities() throws {
        let base = try FirmingoDevice.hello(from: ProtocolFixtures.frame("hello-response"), requestID: 1,
                                            expectedBoard: .nanoRP2040Connect, expectedDeviceID: nil)
        #expect(base.deviceID == "a1b2c3d4e5f60718")
        #expect(base.bootID == "0123456789abcdef")
        #expect(base.targets.isEmpty)
        #expect(base.channels[0].backend == .application)
        #expect(base.channels[0].uart == nil)
        #expect(!base.channels[0].isOwned)
        let managed = try FirmingoDevice.hello(from: ProtocolFixtures.frame("managed-upload/hello-response"), requestID: 9,
                                               expectedBoard: .nanoRP2040Connect, expectedDeviceID: base.deviceID)
        #expect(managed.targets.count == 1)
        #expect(managed.targets[0].format == "nano-managed-v1")
        #expect(managed.targets[0].maximumSize == 4096)
        #expect(managed.targets[0].maximumChunk == 1024)
        #expect(managed.targets[0].authorization == "physical-d2-gnd")
    }

    /// Success envelopes need every required field, correct lexical integer forms, and valid identities.
    @Test func invalidSchemas() throws {
        let original = try ProtocolFixtures.frame("hello-response")
        let json = try #require(String(data: original.payload, encoding: .utf8))
        let changes = [
            ("\"protocol_major\":1", "\"protocol_major\":true"),
            ("\"protocol_major\":1", "\"protocol_major\":1.0"),
            ("\"protocol_major\":1", "\"protocol_major\":1e0"),
            ("\"protocol_major\":1", "\"protocol_major\":-1"),
            ("\"protocol_major\":1", "\"protocol_major\":4294967296"),
            ("\"protocol_major\":1", "\"protocol_major\":2"),
            ("\"max_payload\":4096", "\"max_payload\":4097"),
            ("\"rx_queue\":256", "\"rx_queue\":0"),
            ("\"owned\":false", "\"owned\":0"),
            ("\"targets\":[]", "\"targets\":null"),
            ("\"targets\":[]", "\"other\":[]"),
            ("\"channels\":[", "\"channels\":[null,"),
            ("application", "unknown"),
            ("a1b2c3d4e5f60718", "A1b2c3d4e5f60718"),
            ("0123456789abcdef", "0123456789abcde"),
            ("session-dev-v1", "invalid version"),
            ("open-development", "authenticated")
        ]
        for (before, after) in changes {
            let payload = Data(json.replacingOccurrences(of: before, with: after).utf8)
            #expect(throws: FirmingoError.self) {
                try FirmingoDevice.hello(from: FMGOFrame(kind: .response, requestID: 1, payload: payload), requestID: 1,
                                         expectedBoard: .nanoRP2040Connect, expectedDeviceID: nil)
            }
        }
        #expect(throws: FirmingoError.self) {
            try FirmingoDevice.hello(from: original, requestID: 2, expectedBoard: .nanoRP2040Connect, expectedDeviceID: nil)
        }
        #expect(throws: FirmingoError.self) {
            try FirmingoDevice.hello(from: original, requestID: 1, expectedBoard: .raspberryPiPico, expectedDeviceID: nil)
        }
        #expect(throws: FirmingoError.self) {
            try FirmingoDevice.hello(from: original, requestID: 1, expectedBoard: .nanoRP2040Connect, expectedDeviceID: "different")
        }
    }

    /// Device error codes survive decoding, rather than being mistaken for successful inspection.
    @Test func errorEnvelope() throws {
        do {
            _ = try FirmingoDevice.hello(from: ProtocolFixtures.frame("reset-unsupported"), requestID: 3,
                                         expectedBoard: .nanoRP2040Connect, expectedDeviceID: nil)
            Issue.record("Expected device rejection")
        } catch FirmingoError.deviceRejected(let code, let message) {
            #expect(code == "unsupported")
            #expect(message == "unsupported")
        }
    }

    /// Duplicate escaped/nested keys, invalid Unicode, BOM, trailing content, and resource excesses fail.
    @Test func strictJSON() throws {
        let bad = [
            #"{"ok":true,"\u006fk":false}"#, #"{"x":{"a":1,"\u0061":2}}"#,
            #"{"x":"\u0000"}"#, #"{"x":"\ud800"}"#, #"{"x":"\udc00"}"#,
            #"{"x":01}"#, #"{"x":1.}"#, #"{"x":1e}"#, #"{"x":+1}"#,
            #"{"x":true,}"#, "{} trailing", "{}\0", "\u{feff}{}", "[]",
            "{\"x\":" + String(repeating: "[", count: 16) + "0" + String(repeating: "]", count: 16) + "}",
            "{\"x\":[" + Array(repeating: "0", count: 512).joined(separator: ",") + "]}"
        ]
        for text in bad { #expect(throws: FirmingoError.self) { try WireJSON.parse(Data(text.utf8)) } }
        #expect(throws: FirmingoError.self) { try WireJSON.parse(Data([123, 34, 120, 34, 58, 34, 255, 34, 125])) }
        let valid = try WireJSON.parse(Data(#"{"x":"\ud83d\ude00","u":4294967295,"é":1,"e\u0301":2}"#.utf8))
        #expect(try valid.required("x").string() == "😀")
        #expect(try valid.required("u").uint32() == UInt32.max)
        #expect(try valid.object().count == 4)
    }

    /// UART configuration is interpreted separately from application capabilities using the pinned schema.
    @Test func uartCapabilities() throws {
        let original = try ProtocolFixtures.frame("hello-response")
        let json = try #require(String(data: original.payload, encoding: .utf8))
        let uart = json.replacingOccurrences(of: "\"backend\":\"application\"", with: "\"backend\":\"uart\"")
            .replacingOccurrences(of: "\"owned\":false", with: #""owned":false,"config":{"baud":115200,"actual_baud":115207,"data_bits":8,"parity":"none","stop_bits":1,"flow_control":"none"},"configurable":["baud","data_bits","parity","stop_bits"],"baud_min":300,"baud_max":2000000"#)
        let frame = FMGOFrame(kind: .response, requestID: 1, payload: Data(uart.utf8))
        let device = try FirmingoDevice.hello(from: frame, requestID: 1, expectedBoard: .nanoRP2040Connect, expectedDeviceID: nil)
        #expect(device.channels[0].backend == .uart)
        #expect(device.channels[0].uart?.baud == 115200)
        #expect(device.channels[0].uart?.actualBaud == 115207)
        for (before, after) in [("115200", "299"), ("\"data_bits\":8", "\"data_bits\":9"),
                                ("\"stop_bits\":1", "\"stop_bits\":3"), ("\"flow_control\":\"none\"", "\"flow_control\":\"cts\""),
                                ("\"actual_baud\":115207", "\"actual_baud\":0"), ("\"baud_min\":300", "\"baud_min\":0")] {
            #expect(throws: FirmingoError.self) {
                try FirmingoDevice.hello(from: FMGOFrame(kind: .response, requestID: 1,
                                                       payload: Data(uart.replacingOccurrences(of: before, with: after).utf8)),
                                         requestID: 1, expectedBoard: .nanoRP2040Connect, expectedDeviceID: nil)
            }
        }
    }

    /// Unknown additive result fields are accepted, but malformed or duplicate targets never become capabilities.
    @Test func additiveFieldsAndInvalidTargets() throws {
        let original = try ProtocolFixtures.frame("managed-upload/hello-response")
        let json = try #require(String(data: original.payload, encoding: .utf8))
        let future = json.replacingOccurrences(of: "\"protocol_major\":1", with: "\"protocol_major\":1,\"future\":{\"value\":true}")
        _ = try FirmingoDevice.hello(from: FMGOFrame(kind: .response, requestID: 9, payload: Data(future.utf8)),
                                     requestID: 9, expectedBoard: .nanoRP2040Connect, expectedDeviceID: nil)
        for (before, after) in [("\"id\":1,\"format\"", "\"id\":0,\"format\""),
                                ("\"max_chunk\":1024", "\"max_chunk\":0"),
                                ("\"max_chunk\":1024", "\"max_chunk\":4097"),
                                ("\"max_size\":4096", "\"max_size\":false"),
                                ("nano-managed-v1", ""), ("physical-d2-gnd", "physical authorization")] {
            #expect(throws: FirmingoError.self) {
                try FirmingoDevice.hello(from: FMGOFrame(kind: .response, requestID: 9,
                                                       payload: Data(json.replacingOccurrences(of: before, with: after).utf8)),
                                         requestID: 9, expectedBoard: .nanoRP2040Connect, expectedDeviceID: nil)
            }
        }
    }
}

import Foundation

extension FirmingoDevice {
    /// Validates a correlated hello response and required capability fields against protocol one.
    /// Unknown result fields are ignored, while known fields retain strict types and bounds.
    static func hello(from frame: FMGOFrame, requestID: UInt32,
                      expectedBoard: FirmingoBoard, expectedDeviceID: String?) throws -> Self {
        guard frame.kind == .response, frame.requestID == requestID else {
            throw FirmingoError.protocolViolation("unexpected hello response type or request ID")
        }
        let envelope = try WireJSON.parse(frame.payload)
        if try !envelope.required("ok").bool() {
            let error = try envelope.required("error")
            _ = try error.object()
            let code = try error.required("code").string()
            let message = try error.required("message").string()
            guard !code.isEmpty else { throw WireJSON.invalid }
            throw FirmingoError.deviceRejected(code: code, message: message)
        }
        let result = try envelope.required("result")
        _ = try result.object()
        let major = try result.required("protocol_major").uint32()
        let version = try name(result.required("firmware_version"))
        let board = try name(result.required("board_id"))
        let device = try identity(result.required("device_id"))
        let boot = try identity(result.required("boot_id"))
        let maximum = try result.required("max_payload").uint32()
        let auth = try result.required("auth_mode").string()
        guard major == 1, maximum == FMGOFrame.maximumPayload, auth == "open-development" else {
            throw FirmingoError.protocolViolation("unsupported hello protocol, limit, or authentication mode")
        }
        guard board == expectedBoard.rawValue, expectedDeviceID == nil || expectedDeviceID == device else {
            throw FirmingoError.identityMismatch
        }
        let channels = try result.required("channels").array().map(channel)
        guard channels.count == 1, channels[0].id == 1 else { throw WireJSON.invalid }
        let targets = try result.required("targets").array().map(target)
        guard Set(targets.map(\.id)).count == targets.count else { throw WireJSON.invalid }
        return Self(protocolMajor: major, firmwareVersion: version, deviceID: device, bootID: boot,
                    boardID: board, maximumPayload: maximum, authenticationMode: auth,
                    channels: channels, targets: targets)
    }

    /// Checks the contract's 16 lowercase-hex device/boot identities.
    private static func identity(_ value: WireJSON.Value) throws -> String {
        let text = try value.string()
        guard text.utf8.count == 16, text.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw WireJSON.invalid
        }
        return text
    }

    /// Checks a nonempty ASCII contract name, at most 32 bytes.
    private static func name(_ value: WireJSON.Value) throws -> String {
        let text = try value.string()
        guard (1...32).contains(text.utf8.count), text.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0)
        }) else { throw WireJSON.invalid }
        return text
    }

    /// Validates one channel without granting it to the host.
    private static func channel(_ value: WireJSON.Value) throws -> Channel {
        _ = try value.object()
        let id = try value.required("id").uint32()
        guard let backend = Backend(rawValue: try value.required("backend").string()) else { throw WireJSON.invalid }
        let controls = try value.required("controls").array().map { try $0.string() }
        let rx = try value.required("rx_queue").uint32()
        let tx = try value.required("tx_queue").uint32()
        let owned = try value.required("owned").bool()
        guard id == 1, controls.isEmpty, rx == 256, tx == 256 else { throw WireJSON.invalid }
        let uart: UART?
        switch backend {
        case .application:
            guard value["config"] == nil, value["configurable"] == nil,
                  value["baud_min"] == nil, value["baud_max"] == nil else { throw WireJSON.invalid }
            uart = nil
        case .uart:
            uart = try uartConfiguration(value)
        }
        return Channel(id: id, backend: backend, controls: controls, receiveQueueBytes: rx,
                       transmitQueueBytes: tx, isOwned: owned, uart: uart)
    }

    /// Validates the pinned UART bounds and complete configuration, including absence of flow control.
    private static func uartConfiguration(_ value: WireJSON.Value) throws -> UART {
        let minimum = try value.required("baud_min").uint32()
        let maximum = try value.required("baud_max").uint32()
        let configurable = try value.required("configurable").array().map { try $0.string() }
        let config = try value.required("config")
        _ = try config.object()
        let baud = try config.required("baud").uint32()
        let actual = try config.required("actual_baud").uint32()
        let bits = try config.required("data_bits").uint32()
        let parity = try config.required("parity").string()
        let stops = try config.required("stop_bits").uint32()
        let flow = try config.required("flow_control").string()
        guard minimum == 300, maximum == 2_000_000, (minimum...maximum).contains(baud), actual > 0,
              (5...8).contains(bits), ["none", "even", "odd"].contains(parity), (1...2).contains(stops),
              flow == "none", configurable.count == 4,
              Set(configurable) == Set(["baud", "data_bits", "parity", "stop_bits"]) else { throw WireJSON.invalid }
        return UART(baud: baud, actualBaud: actual, dataBits: bits, parity: parity, stopBits: stops,
                    configurable: configurable, minimumBaud: minimum, maximumBaud: maximum)
    }

    /// Parses positive target limits without promoting an advertised format to SDK upload support.
    private static func target(_ value: WireJSON.Value) throws -> UploadTarget {
        _ = try value.object()
        let id = try value.required("id").uint32()
        let format = try name(value.required("format"))
        let size = try value.required("max_size").uint32()
        let chunk = try value.required("max_chunk").uint32()
        let authorization = try name(value.required("authorization"))
        guard id > 0, size > 0, chunk > 0, chunk <= size else { throw WireJSON.invalid }
        return UploadTarget(id: id, format: format, maximumSize: size, maximumChunk: chunk, authorization: authorization)
    }
}

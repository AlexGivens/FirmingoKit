import Foundation

extension ManagedResidentBinding {
    /// Imports a bounded explicit host build/install record; exact schema/types and binding ranges are validated.
    /// This does not authenticate the record or installed image. The host must obtain it from a trusted build
    /// and associate that exact resident/image with the selected physical device; hello is insufficient.
    public init(recordJSON: Data) throws {
        let value = try WireJSON.parse(recordJSON, maximumBytes: 2048)
        var names = ["schema", "board", "profile", "deviceID", "residentELFSHA256", "firmwareImageSHA256", "apiAddress"]
        let stateful = try value.required("schema").uint32() == 2
        if stateful { names += ["stateAddress", "stateCapacityBytes", "compilerContractSHA256"] }
        guard Set(try value.object().keys) == Set(names.map { Data($0.utf8) }),
              try value.required("schema").uint32() == (stateful ? 2 : 1),
              try value.required("board").string() == "nano_rp2040_connect",
              try value.required("profile").string() == (stateful ? "nano-managed-v2" : "nano-managed-v1") else { throw ManagedUploadError.invalidArtifact("Incompatible resident record") }
        var state: ManagedResidentState?
        if stateful {
            guard try value.required("compilerContractSHA256").string() == ManagedResidentState.compilerContractSHA256 else { throw ManagedUploadError.invalidArtifact("Unsupported stateful contract") }
            state = try ManagedResidentState(address: value.required("stateAddress").uint32(), capacityBytes: value.required("stateCapacityBytes").uint32())
        }
        try self.init(deviceID: value.required("deviceID").string(), residentELFSHA256: value.required("residentELFSHA256").string(),
                      firmwareImageSHA256: value.required("firmwareImageSHA256").string(), apiAddress: value.required("apiAddress").uint32(), state: state)
    }
}

extension ManagedResidentBinding {
    /// Adapts a reviewed association and exact immutable descriptor to the existing compiler/upload APIs.
    /// Mismatched/removed descriptor IDs cannot be silently substituted. This does not connect, verify the
    /// evidence, attest installed bytes or authorize staging; fresh session/target checks remain required.
    public init(association: ManagedDeviceAssociation, firmwareBuild: ManagedFirmwareBuildDescriptor) throws {
        guard association.firmwareBuildID == firmwareBuild.id else { throw ManagedCatalogueError.associationMismatch }
        try self.init(deviceID: association.deviceID, residentELFSHA256: firmwareBuild.residentELFSHA256,
                      firmwareImageSHA256: firmwareBuild.firmwareImageSHA256, apiAddress: firmwareBuild.apiAddress, state: firmwareBuild.state)
    }
}

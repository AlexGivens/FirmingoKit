/// Process-wide exclusion for the same backend attachment across separate installer actors.
actor FirmwareProgrammingLease {
    /// SDK-owned lease table, independent of application UI state.
    static let shared = FirmwareProgrammingLease()
    /// Current operations; no waiting queue or implicit deferred write exists.
    private var attachments: Set<String> = []
    /// Rejects overlapping device-changing operations rather than scheduling them later.
    func acquire(_ key: String) throws {
        guard attachments.insert(key).inserted else { throw FirmwareInstallationError.busy }
    }
    /// Releases a held attachment on every success/failure path.
    func release(_ key: String) { attachments.remove(key) }
}

/// Actual offline compiler phases; none implies a device connection or successful execution.
public enum ManagedCompilationPhase: String, Sendable {
    /// Checking bundled runtime and explicitly supplied service identities.
    case verifying
    /// Validating and source-mapping the immutable document revision.
    case preparing
    /// Compiling source and entry wrappers in the isolated worker.
    case compiling
    /// Linking against the selected exact resident API address.
    case linking
    /// Validating the ARM ELF and creating its selected capsule/receipt.
    case packaging
}

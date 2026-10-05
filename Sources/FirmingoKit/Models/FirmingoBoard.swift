/// Board identifiers selected explicitly by a host. A shared RP2040 chip does not imply compatibility.
public enum FirmingoBoard: String, CaseIterable, Sendable, Identifiable {
    /// Arduino Nano RP2040 Connect, distinct from ArduinoKit's identifier scheme.
    case nanoRP2040Connect = "nano_rp2040_connect"
    /// Original Raspberry Pi Pico with its own firmware image and flash layout.
    case raspberryPiPico = "raspberry_pi_pico"
    /// Stable firmware board identifier.
    public var id: String { rawValue }
    /// A display label for host board selection.
    public var displayName: String {
        switch self {
        case .nanoRP2040Connect: "Arduino Nano RP2040 Connect"
        case .raspberryPiPico: "Raspberry Pi Pico"
        }
    }
}

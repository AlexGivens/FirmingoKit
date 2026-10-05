import Network

/// An explicitly selected numeric TCP endpoint; it is not device identity or service discovery.
public struct FirmingoEndpoint: Equatable, Sendable {
    /// Validated numeric IPv4 or IPv6 address. Hostnames and zone identifiers are not accepted.
    public let address: String
    /// Nonzero TCP port. Firmware reference profiles use provisional port 7420.
    public let port: UInt16

    /// Validates a numeric address and nonzero port without opening a connection.
    public init(address: String, port: UInt16 = 7420) throws {
        guard port != 0, IPv4Address(address) != nil || IPv6Address(address) != nil else {
            throw FirmingoError.invalidEndpoint
        }
        self.address = address
        self.port = port
    }
}

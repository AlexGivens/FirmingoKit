import Foundation

/// A validated firmware transaction snapshot, separate from success of its response envelope.
/// Even bootConfirmed proves only that setup and one loop returned; useful behavior needs host checks.
public struct ManagedUploadSnapshot: Equatable, Sendable {
    /// Firmware state names for the reviewed experimental transaction.
    public enum State: String, Sendable {
        /// RAM stage acquired; no flash write.
        case accepted
        /// Digests/header verified in RAM; no flash write.
        case verified
        /// Installation queued/in progress; cannot be cancelled through upload abort.
        case committing
        /// Flash readback passed; managed sketch startup remains unconfirmed.
        case installed
        /// Managed setup and first loop returned, without a whole-board reboot.
        case bootConfirmed = "boot_confirmed"
        /// Pre-commit staging discarded; no slot write.
        case aborted
        /// Transaction failed; inspect errorCode and the conservative slotTouched flag.
        case failed
    }
    /// Nonzero transaction identifier, meaningful only with a matching saved device/boot record.
    public let uploadID: UInt32
    /// Transaction outcome at sampling time, not necessarily terminal.
    public let state: State
    /// Total expected capsule bytes.
    public let size: UInt32
    /// Bytes accepted into the RAM stage, bounded by size.
    public let received: UInt32
    /// Whole capsule SHA-256, matching the selected transaction.
    public let sha256: String
    /// True after an erase attempt, including possible partial-sector failure.
    public let slotTouched: Bool
    /// Firmware machine code, including none, disconnected, park_timeout, or install_failed.
    public let errorCode: String

    /// Parses strict scalar types, bounds, and state invariants from an upload result object.
    static func parse(_ value: WireJSON.Value) throws -> Self {
        let id = try value.required("upload_id").uint32()
        let size = try value.required("size").uint32()
        let received = try value.required("received").uint32()
        let digest = try value.required("sha256").string()
        let touched = try value.required("slot_touched").bool()
        let error = try value.required("error").string()
        guard let state = State(rawValue: try value.required("state").string()), id > 0,
              (257...4096).contains(size), received <= size,
              NanoManagedContract.isHex(digest, bytes: 32), (1...32).contains(error.utf8.count),
              error.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }) else {
            throw WireJSON.invalid
        }
        switch state {
        case .accepted: guard !touched, error == "none" else { throw WireJSON.invalid }
        case .verified: guard received == size, !touched, error == "none" else { throw WireJSON.invalid }
        case .committing: guard received == size, error == "none" else { throw WireJSON.invalid }
        case .installed, .bootConfirmed:
            guard received == size, touched, error == "none" else { throw WireJSON.invalid }
        case .aborted: guard !touched else { throw WireJSON.invalid }
        case .failed: guard error != "none" else { throw WireJSON.invalid }
        }
        return Self(uploadID: id, state: state, size: size, received: received,
                    sha256: digest, slotTouched: touched, errorCode: error)
    }
    /// Requires ID, whole-capsule length, and digest equality before using a retained snapshot.
    func matches(_ record: ManagedUploadRecord) -> Bool {
        uploadID == record.uploadID && size == record.size && sha256 == record.sha256
    }
}

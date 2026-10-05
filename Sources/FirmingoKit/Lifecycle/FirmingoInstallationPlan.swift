import Foundation

/// Reviewable artifact preflight and physical guidance independent of a working FMGO connection.
/// A plan alone neither selects a physical target nor authorizes programming. Experimental macOS
/// execution additionally requires a backend observation, a prepared token, and explicit execution.
public struct FirmingoInstallationPlan: Sendable {
    /// Exact immutable image and acquisition provenance being reviewed.
    public let image: FirmingoFirmwareImage
    /// Host-selected board matched to the image; this selection is not physical-device evidence.
    public let board: FirmingoBoard
    /// Host execution environment used to present direct or guided transfer prerequisites.
    public let hostPlatform: HostPlatform
    /// Ordered user/host actions; none of these actions is automatically performed.
    public let steps: [Step]
    /// What replacing complete firmware means for existing user data and auxiliary devices.
    public let dataEffect: String
    /// Supported next physical procedure after an interrupted transfer, requiring a new decision.
    public let recoveryInstructions: String
    /// Limits to verification, including the absence of exact installed-image attestation.
    public let verificationLimitations: String

    /// Environments with different USB/filesystem capabilities; runtime qualification remains open.
    public enum HostPlatform: Sendable {
        /// Experimental SDK ROM transfer or an external user-directed UF2 transfer is available.
        case macOS
        /// An external computer is required by the current guided route.
        case iOS
    }
    /// Inspectable action whose identifier allows a host to supply appropriate native presentation.
    public struct Step: Sendable, Identifiable {
        /// Stable action category in the ordered procedure.
        public let id: Action
        /// Concise board/platform-specific guidance for this action.
        public let instruction: String
    }
    /// Physical and host actions, kept separate from the execution state machine.
    public enum Action: String, Sendable {
        /// Confirm the selected physical board and trustworthy release.
        case review
        /// Release active communication and resolve pending device-changing operations.
        case closeSessions
        /// Use a supported computer when direct host access is unavailable.
        case useComputer
        /// Enter the board-specific ROM programming mode.
        case enterROM
        /// Explicitly select the bootloader volume associated with the physical board.
        case selectTarget
        /// User-directed transfer of exactly the validated complete Firmingo image.
        case transfer
        /// Reconnect and check identity/backend/capabilities without treating hello as attestation.
        case verify
    }

    /// Always false for an artifact-only plan. Use an installer-prepared target token to request
    /// experimental macOS execution; this property does not describe backend availability.
    public var canExecuteWithSDK: Bool { false }
    /// Target selection is still needed; a board enum, family ID, or volume label is insufficient.
    public var requiresPhysicalTargetSelection: Bool { true }

    /// Produces an artifact-bound plan without discovery, a connection, or any side effect.
    /// Throws ``FirmwareLifecycleError/boardMismatch`` before producing guidance for a wrong board.
    /// This plan can guide first installation or a separately requested complete Firmingo reinstall;
    /// it does not establish update compatibility, preservation, rollback, or resumable flashing.
    public init(image: FirmingoFirmwareImage, selectedBoard: FirmingoBoard, hostPlatform: HostPlatform) throws {
        guard image.entry.board == selectedBoard else {
            throw FirmwareLifecycleError.boardMismatch
        }
        self.image = image
        board = selectedBoard
        self.hostPlatform = hostPlatform
        let entry = Self.romInstruction(for: selectedBoard)
        var steps = [
            Step(id: .review, instruction: "Confirm the physical \(selectedBoard.displayName) and review Firmingo \(image.entry.firmwareVersion) \(image.entry.profile.rawValue), its trusted source, and its compile-tested evidence level."),
            Step(id: .closeSessions, instruction: "Close active Firmingo sessions and finish or reconcile pending device-changing operations before entering programming mode.")
        ]
        if hostPlatform == .iOS {
            steps.append(Step(id: .useComputer, instruction: "Use a Mac or another computer for the manual UF2 transfer; direct USB programming on iOS/iPadOS is not implemented or qualified by this SDK."))
        }
        steps.append(contentsOf: [
            Step(id: .enterROM, instruction: entry),
            Step(id: .selectTarget, instruction: "Explicitly select the newly mounted ROM volume belonging to that physical board. RPI-RP2 and an RP2040 family ID do not identify the board model or intended device; resolve multiple devices before proceeding."),
            Step(id: .transfer, instruction: hostPlatform == .macOS
                 ? "Confirm the selected physical board and request a separately prepared SDK installation, or explicitly copy the validated UF2 using the computer. Keep power connected; transfer completion or volume disappearance leaves installation unverified."
                 : "After a new explicit user decision, copy exactly the validated Firmingo UF2 from a computer to the selected ROM volume. Keep power connected; transfer completion or volume disappearance leaves installation unverified."),
            Step(id: .verify, instruction: "Reconnect to the explicitly selected numeric Firmingo endpoint and validate hello board, expected \(image.entry.profile.rawValue) backend, protocol, and capabilities. Confirm useful behavior separately; hello does not prove the selected image digest.")
        ])
        self.steps = steps
        dataEffect = "The transfer replaces existing RP2040 firmware in the image's affected flash sectors. Existing sketches, settings, and filesystem data have no preservation, backup, or rollback guarantee; the pinned recipe has no filesystem and excludes the final 4 KiB EEPROM reservation from writes. Nano NINA radio firmware is outside this operation."
        recoveryInstructions = "If a transfer is interrupted, keep the image and manifest provenance and report the outcome as unknown. \(entry) Select the physical target again and request a new full Firmingo reinstall; never resume at a byte offset or automatically repeat the write."
        verificationLimitations = "The release and experimental SDK programming backend have no SDK hardware qualification. A matching fresh hello checks self-reported board/profile/version/capabilities; file-copy completion, a reboot, and a firmware version string cannot attest exact installed image bytes."
    }

    /// Manufacturer-based physical entry that does not depend on installed firmware or FMGO reset.
    static func romInstruction(for board: FirmingoBoard) -> String {
        switch board {
        case .nanoRP2040Connect:
            "Connect the Nano over USB, place a jumper between REC and GND, then press reset. Once the ROM mass-storage volume appears, remove the jumper; this is separate from managed-upload D2–GND authorization."
        case .raspberryPiPico:
            "Hold BOOTSEL on the original Raspberry Pi Pico while connecting USB to the computer. Release BOOTSEL once the ROM mass-storage volume appears."
        }
    }
}

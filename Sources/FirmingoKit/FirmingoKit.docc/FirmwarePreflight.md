# Prepare a complete Firmingo image

Validate trusted local release files and review physical installation steps without connecting a board.

## Acquire and validate selected files

The host selects a trusted unsigned schema-one Firmingo `0.1.0` beta manifest
and its exact board/profile UF2. The SDK bounds local reads, checks metadata and
SHA-256, and validates the explicit RP2040 flash layout. This local operation
runs on a concurrent executor, holds security-scoped access during each read,
and checks cancellation between reads. File and validation errors propagate.

```swift
import Foundation
import FirmingoKit

func reviewFirmware(manifestURL: URL, imageURL: URL) async throws -> FirmingoInstallationPlan {
    let image = try await FirmingoFirmwareImage.load(
        trustedManifestURL: manifestURL,
        imageURL: imageURL,
        board: .nanoRP2040Connect,
        profile: .application
    )
    #if os(macOS)
    let platform = FirmingoInstallationPlan.HostPlatform.macOS
    #else
    let platform = FirmingoInstallationPlan.HostPlatform.iOS
    #endif
    return try FirmingoInstallationPlan(
        image: image,
        selectedBoard: .nanoRP2040Connect,
        hostPlatform: platform
    )
}
```

Hosts with their own acquisition policy can instead supply immutable bytes to
``FirmingoReleaseManifest/init(data:trustedSource:)`` and
``FirmingoFirmwareImage/init(bytes:manifest:board:profile:)``. Establish publisher
trust before parsing; a source URL or matching checksum is not authentication.
No firmware is bundled and no remote URL, archive, or fallback image is fetched.

## Present the plan and its limits

Display the selected board/profile/version, source and manifest/image/build-report
digests, affected flash sectors, ``FirmingoInstallationPlan/dataEffect``, ordered
``FirmingoInstallationPlan/steps``, recovery guidance, and verification limits.
Existing sketches/settings/filesystems have no preservation/rollback guarantee.
Nano NINA firmware is outside the operation. A complete UF2 remains separate from
a ``ManagedCapsule`` and cannot be passed to managed upload.

This plan prepares artifact preflight only. Physical board/bootloader
selection is still required, and ``FirmingoInstallationPlan/canExecuteWithSDK``
is false for the artifact-only plan. <doc:FirmwareProgramming> describes the separate
experimental macOS backend, target-bound preparation, explicit execution, durable
record callback and fresh-hello verification. iOS/iPadOS uses an external computer
route. Instructions and successful builds are not hardware qualification.

Interrupted transfer has an unknown outcome. Preserve selected artifact provenance,
use the board-specific ROM procedure, and require a new explicit decision for a
complete Firmingo reinstall. Never resume or automatically repeat a flash.
Transfer completion, volume disappearance, and hello do not attest exact image
identity. Hardware installation/update/recovery qualification remains open.

# Select firmware-build metadata

Keep an exact experimental resident build separate from its physical-device association.

## Current boundary

``ManagedCompilerCatalogue`` verifies host-supplied catalogue bytes and exposes
explicit firmware-build choices. ``ManagedFirmwareBuildDescriptor`` contains no
device ID. ``ManagedDeviceAssociation`` persists the host's reviewed association
between a real device and an exact descriptor identity. None of these operations
connects, compiles, flashes or authorizes an upload.

The package does not yet ship a production catalogue or compiler service or
automatically load a service. <doc:OfflineManagedCompilation> provides experimental
device-independent requests, artifacts and receipts using an explicit service.
The existing compiler still accepts ``ManagedResidentBinding``; its additive
association adapter preserves that API.
Nano descriptors remain experimental; Pico managed recipes are unavailable.

## Load and select explicitly

The expected catalogue SHA-256 must come from independently trusted build/package
provenance. Computing it from the same untrusted file establishes no publisher
authentication. Catalogue parsing is bounded and runs off main-actor execution;
cancellation throws `CancellationError`. Invalid bytes, schema or identities fail
with ``ManagedCatalogueError``. Missing selections never fall back to another build.

```swift
import Foundation
import FirmingoKit

func restoreSelectedBinding(manifestJSON: Data, trustedManifestSHA256: String,
                            savedAssociationJSON: Data) async throws
                            -> ManagedResidentBinding {
    let catalogue = try await ManagedCompilerCatalogue.load(
        manifestJSON: manifestJSON, expectedSHA256: trustedManifestSHA256)
    let association = try ManagedDeviceAssociation(recordJSON: savedAssociationJSON)
    let firmwareBuild = try catalogue.build(id: association.firmwareBuildID)
    return try ManagedResidentBinding(association: association,
                                      firmwareBuild: firmwareBuild)
}
```

Use ``ManagedCompilerCatalogue/builds(for:profile:)`` to present explicit choices.
``ManagedCompilerCatalogue/unavailableReason(for:)`` reports absent metadata,
not compiler-service availability or hardware qualification. Review actual
provenance and installed-image association before using the restored binding.
Hello cannot attest the exact resident ELF or image bytes. Run still needs fresh
device identity, backend, advertised target, physical authorization and upload
checks described in <doc:ManagedUploads>.

## Closed schema-one records

A catalogue has exactly `schema: 1` and `firmwareBuilds: [...]`. It permits at
most 32 descriptors, 128 KiB and 8192 JSON tokens. Empty catalogues expose no
builds. Duplicate IDs and conflicting metadata for one complete-image hash fail.
Standalone descriptor parsing is limited to 4096 bytes; unknown/missing fields,
duplicate keys and incorrect JSON types fail.

| Descriptor field | Accepted value or purpose |
| --- | --- |
| `schema` | Integer `1` |
| `board` | `nano_rp2040_connect` |
| `profile` | `nano-managed-v1` |
| `backend` | `application` |
| `firmwareVersion` | Nonempty ASCII label, at most 64 bytes, using letters, digits, `.`, `_`, `-` |
| `firmwareCommit` | Full lowercase 40-character source commit |
| `residentELFSHA256`, `firmwareImageSHA256`, `buildReportSHA256` | Exact lowercase 64-character digests declared by trusted build evidence |
| `apiAddress` | Integer, four-byte aligned, in `0x10000000..<0x10200000`, extracted from the exact resident ELF |
| `residentABI`, `targetID` | Integer `1` |
| `maximumCapsuleBytes` | Integer `4096` |
| `recipeIdentifier` | `nano-stateless-clang-22.1.8-v1-experimental` |
| `recipeSHA256` | `b7869f6fc863e1905deb6974408c6e7dc63943a1fb3e342a357fdf757b1e23d9` |
| `qualification` | `experimental` |

The descriptor ID hashes all these fields as sorted, compact UTF-8 JSON with
unescaped slashes. Input whitespace and key ordering do not change that ID; the
catalogue's manifest hash still covers exact input bytes. Declared digests and
addresses do not independently verify an ELF, report, publisher or executable ABI.

Association records have exactly `version: 1`, `deviceID`, `firmwareBuildID` and
`evidence`, plus `installationOperationID` only when required. Device IDs use 16
lowercase hexadecimal characters; descriptor IDs use 64. Existing-device evidence
is `hostConfirmedExistingFirmware` and prohibits an operation UUID. Installation
evidence is `reviewedInstallationRecord` and requires the canonical UUID spelling
returned by Foundation's `UUID.uuidString`. Optional fields are omitted, not null.
``ManagedDeviceAssociation/encodeRecord()`` writes deterministic records; restoration
rejects inputs over 2048 bytes and invalid/unknown fields or evidence.

The evidence label is a host assertion, not independent proof or a resume token.
Keep upload journals separate, retain exact IDs across updates, and require a new
review when installed firmware or trusted catalogue metadata changes.

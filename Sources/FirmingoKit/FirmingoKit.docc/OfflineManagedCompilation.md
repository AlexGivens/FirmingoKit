# Compile for a firmware build without a device

Build an exact source revision against verified catalogue metadata, then bind its artifact explicitly for deployment.

## Build offline

``ManagedOfflineBuildRequest`` resolves an explicit firmware-build ID from a
``ManagedCompilerCatalogue`` and captures its exact byte hash. It contains no
physical-device identity. The compiler overload returns
``ManagedOfflineCompilationResult`` with device-independent FMS1 bytes and a
receipt covering source, catalogue, descriptor, recipe and toolchain identities.
The selected descriptor supplies the exact resident API address and ELF/image
requirements; a board name or version string cannot substitute for this metadata.

```swift
import Foundation
import FirmingoKit

func compileOffline(serviceURL: URL, manifestJSON: Data, trustedManifestSHA256: String,
                    firmwareBuildID: String, snapshot: SketchSourceSnapshot) async throws
                    -> ManagedOfflineCompilationResult {
    let catalogue = try await ManagedCompilerCatalogue.load(
        manifestJSON: manifestJSON, expectedSHA256: trustedManifestSHA256)
    let request = try ManagedOfflineBuildRequest(snapshot: snapshot, catalogue: catalogue,
                                                firmwareBuildID: firmwareBuildID)
    let compiler = ManagedSketchCompiler(serviceURL: serviceURL)
    return try await compiler.build(request) { phase in
        print(phase.rawValue)
    }
}
```

The current service remains an explicitly selected, verified development binary
pending redistribution/provenance review. No production firmware catalogue or
default service loader is shipped. The trusted manifest hash must come from an
independent reviewed source. Metadata verification does not authenticate its
publisher, verify a referenced resident build report or attest installed bytes.
See <doc:ManagedCatalogue> for schemas and trust limits.

The legacy compiler overload and its existing receipt format remain compatible.
Both overloads use one actor reservation, the same bounded WebKit/WASI worker,
60-second runtime deadline, finite progress, source diagnostics and cancellation
cleanup. Concurrent mixed calls fail with ``ManagedCompilerError/busy``. Every
build starts fresh; no cache, stale-result reuse or native/remote fallback exists.
Only the experimental stateless Nano profile is accepted. Pico, arbitrary libraries,
global mutable storage and constructors remain unsupported. Declared platform
minimums and successful simulator builds do not qualify physical iPad execution.

## Bind only after reviewing current source and device evidence

An offline artifact is not a ``ManagedCapsule`` accepted by the upload API.
``ManagedOfflineSketchArtifact/bind(to:)`` requires a matching exact descriptor
association and revalidates its capsule/report against the resulting real device
binding. It does not connect, stage, commit, authenticate evidence or authorize a
write. Different real devices associated with the same exact resident build can
use the same capsule bytes; receipts remain independent of those device IDs.

```swift
func capsuleForCurrentSelection(_ result: ManagedOfflineCompilationResult,
                                current: ManagedOfflineBuildRequest,
                                savedAssociationJSON: Data) async throws -> ManagedCapsule {
    let prepared = try await ManagedSketchPreprocessor.prepare(current)
    let receipt = result.artifact.receipt
    guard receipt.documentID == current.snapshot.documentID,
          receipt.sourceRevision == current.snapshot.revision,
          receipt.sourceFilename == current.snapshot.filename,
          receipt.sourceSHA256 == prepared.sourceSHA256,
          receipt.translationUnitSHA256 == prepared.translationUnitSHA256,
          receipt.catalogueSHA256 == current.catalogueSHA256,
          receipt.firmwareBuildID == current.firmwareBuild.id else {
        throw SketchBuildError.invalidInput("Build no longer matches the current source or target")
    }
    let association = try ManagedDeviceAssociation(recordJSON: savedAssociationJSON)
    return try result.artifact.bind(to: association)
}
```

The host must review the association evidence and installed-firmware uncertainty
before using this helper, and invalidate results on source/selection changes.
For Run, capture and compile the current snapshot again, then connect with expected
board/backend/device ID and validate freshly advertised upload capabilities.
Follow <doc:ManagedUploads> for physical authorization, durable transaction records,
one explicit commit and uncertain-outcome reconciliation. Binding performs none of
these operations; it never silently replaces resident firmware or selects latest.

## Preparation, packaging and receipt identity

``ManagedSketchPreprocessor`` also accepts the offline request and returns
``PreparedManagedOfflineSketch`` using the same bounded normalization, include
restrictions and source mapping as the legacy path.
``ManagedELFConverter`` accepts that preparation and declared
``ManagedELFProvenance`` for independently linked outputs. It requires the exact
descriptor recipe identifier/hash and shares strict stateless ELF/FMS1/report
validation with legacy packaging. Declared provenance does not prove a compiler
ran or that output was built from the supplied source.

The offline receipt has its own schema-one type, separate from legacy device-bound
receipts. `buildInputSHA256` covers `version`, document UUID (Foundation canonical
spelling), source revision/filename/hash, translation-unit hash, catalogue hash,
firmware-build ID, board/profile and all provenance fields using sorted compact
UTF-8 JSON with unescaped slashes. It excludes output digests. `linkedELFSHA256`
and `capsuleSHA256` identify outputs separately. A source revision or catalogue
byte change alters input identity even if the capsule bytes are unchanged.

Current macOS real-runtime tests establish offline compilation and structural
packaging only. Synthetic development descriptors and parser fixtures are never
deployment evidence. Signed sandbox, minimum-OS execution, physical iPad,
resident ABI execution, startup and useful sketch behavior remain unqualified.

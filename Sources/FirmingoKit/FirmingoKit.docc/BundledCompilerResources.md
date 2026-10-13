# Load SDK compiler resources

Discover verified metadata and compiler resources without an external toolchain.

## Current availability

``ManagedCompilerCatalogue/loadBundled()`` loads the SDK-owned inventory and its
eight bounded runtime/source/license/catalogue roles off UI execution. The current
catalogue is intentionally empty: trusted production firmware-build descriptors
have not been staged. No board or latest build is selected automatically. A
successful catalogue load is separate from compiler availability.

``ManagedSketchCompiler/init()`` selects the same SDK-owned resource set without
file selection. Construction performs no I/O; each build verifies the inventory
and exact assets before source preparation or WebKit execution. The current
inventory marks compiler-service distribution review as pending, so a default
build throws ``ManagedCompilerResourceError/serviceApprovalPending``. No WASM
service or synthetic firmware descriptor is bundled to bypass that gate.

```swift
import FirmingoKit

let catalogue = try await ManagedCompilerCatalogue.loadBundled()
let choices = catalogue.builds(for: .nanoRP2040Connect)
let compiler = ManagedSketchCompiler()

do {
    try await compiler.verifyResources()
} catch let error as ManagedCompilerResourceError {
    print(error.errorDescription ?? "Compiler resource verification failed.")
}

if choices.isEmpty {
    print(catalogue.unavailableReason(for: .nanoRP2040Connect) ?? "No firmware build available.")
}
```

After approved resources and trusted descriptors are packaged, a host explicitly
selects an exact SDK-listed descriptor, creates ``ManagedOfflineBuildRequest`` and
calls the default compiler. Build remains offline and does not create a physical
device association or authorize upload. That successful bundled compilation flow
is not delivered by the current empty catalogue and pending service.

## Integrity and review boundaries

``ManagedSketchCompiler/verifyResources()`` lets a host check the selected compiler
assets without a sketch, WebKit startup or board connection. It uses the same busy
reservation as Build, propagates cancellation and never caches resource bytes.
Success confirms asset integrity only; actual builds verify again and can fail if
resources have changed. Pending SDK review remains a structured error. An explicit
development compiler verifies only its selected service and the packaged runtime.

The version-one inventory is independently pinned in SDK code. It binds the
stateless Nano recipe, service ABI two, exact service byte count/SHA-256, source
contract and experimental/unqualified status, plus runtime manifest, host page,
WASI licenses and catalogue digests. Closed keys, scalar types, duplicate keys,
file roles, byte limits and recipe identities are checked before paths are built.
Fixed local leaves and nonsymlink regular files are required; there is no remote
fetch, sibling lookup, environment override or automatic fallback.

Every load verifies exact bytes. Verified page and service data are passed into
the isolated worker, avoiding a later WebKit disk read of those assets. Pending
service review fails before service-file access, even if a file was copied into
the bundle. Editing approval metadata without changing the SDK's independent
anchor fails inventory integrity. An anchored review declaration is an SDK release
decision, not publisher authentication or device attestation.

``ManagedCompilerResourceError`` separates missing bundles, incompatible/integrity
failures, invalid fixed files and pending service review. Other filesystem errors
retain their underlying causes; cancellation remains `CancellationError`.

## Development compatibility

``ManagedSketchCompiler/init(serviceURL:)`` retains the explicit verified local
service workflow with the existing recipe/toolchain identities and error behavior.
``ManagedCompilerCatalogue/load(manifestJSON:expectedSHA256:)`` retains independently
anchored development imports. Neither public API accepts an override for the
bundled inventory's review decision. The demo starts with SDK resource loading
and exposes these explicit paths as optional development resource sources.

Resource loading, package builds, test-only runtime parity and unsigned archive
checks do not qualify signed sandbox, physical iPad, minimum OS, resident ABI calls
or deployment. Pico managed Build/Run remains unavailable. Firmware installation
and interruption recovery are separate explicit workflows.

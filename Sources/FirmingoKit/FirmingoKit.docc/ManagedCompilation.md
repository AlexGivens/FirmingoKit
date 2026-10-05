# Compile a managed sketch locally

Build one immutable Nano source revision without connecting to a microcontroller.

## Experimental support

``ManagedSketchCompiler`` uses an internal nonpersistent WebKit page and fresh
WASI worker. It compiles/links the constrained Nano `nano-managed-v1` stateless
recipe, validates ARM ELF and packages FMS1/report/receipts. The public API exposes
no web view. Pico, arbitrary Arduino libraries, mutable global storage, runtime
constructors and operations requiring unprovided compiler-runtime helpers remain
unsupported. Setup and loop must return; compilation cannot prove that behavior.

The exact reviewed memory-bounded service is explicitly supplied by the host
until service licensing/provenance review permits bundling. Independent runtime,
worker/facade/recipe and licensed WASI shim resources are packaged and hash-verified.
There is no sibling checkout, Node runtime, native compiler, shell or remote
fallback in a host app. Keep security-scoped access to the selected service for
the whole build if the app sandbox requires it.

Real current-macOS WebKit tests establish offline compile/link/structural packaging
only. Signed sandbox, minimum OS, physical iOS/iPadOS, resident ABI calls and
hardware behavior remain unqualified. Development outputs use synthetic binding
metadata and must never be uploaded.

## Build a snapshot

The host obtains exact resident ELF/image hashes and the API-table symbol from a
trusted build/install record associated with the selected physical device. Hello
cannot establish that association. ``ManagedResidentBinding/init(recordJSON:)``
checks bounded record syntax; it does not authenticate its provenance or installed
bytes. Never substitute a sample address or fabricated digest for a real deployment.

Alternatively, <doc:ManagedCatalogue> explains the additive firmware-build
descriptor and device-association adapter. Catalogue metadata is independent of
a physical device. The legacy example below uses a binding; see
<doc:OfflineManagedCompilation> for requests and receipts without a device ID.

```swift
import Foundation
import FirmingoKit

func buildDocument(serviceURL: URL, residentRecord: Data, documentID: UUID,
                   revision: UInt64, filename: String, source: String) async throws
                   -> ManagedCompilationResult {
    let resident = try ManagedResidentBinding(recordJSON: residentRecord)
    let snapshot = try SketchSourceSnapshot(documentID: documentID, revision: revision,
                                            filename: filename, source: source)
    let request = try ManagedSketchBuildRequest(snapshot: snapshot,
        board: .nanoRP2040Connect, profile: .nanoManagedV1, resident: resident)
    let compiler = ManagedSketchCompiler(serviceURL: serviceURL)
    return try await compiler.build(request) { phase in
        print(phase.rawValue)
    }
}
```

Source is a single bounded `.ino` with a narrow Arduino facade. See
<doc:ManagedBuildPreparation> for preprocessing, source mapping, prototypes and
unsupported directives. Compilation produces real structured diagnostics, including
frontend errors even when the service's integer exit status is zero. Handle
``ManagedCompilerError/compilationFailed(_:)`` and
``SketchBuildError/unsupportedSource(_:)`` to display their associated records.
Do not read another editor revision while a build is running.

Progress is a finite synchronous observer, with at most eight notifications;
callbacks must return promptly and dispatch UI state onto the main actor. Each
compiler actor admits one active build; overlapping calls fail with
``ManagedCompilerError/busy``. Runtime work has a 60-second deadline. Cancellation,
worker/navigation/bridge failure or WebKit process termination discards its context.
Every subsequent build starts fresh; no mutable runtime cache or stale-artifact
reuse exists. Linear-memory observations do not measure peak process memory.

## Deploy through the separate upload API

Before deploying, compare the receipt's document UUID, revision, original source,
board/profile and resident metadata with the current selection. An edit or changed
target invalidates the build. A new Run should capture and compile the current
snapshot again. Compilation itself never acquires a console, stages a transaction,
commits, flashes or resets a board.

Connect with expected board/backend/device ID and use <doc:ManagedUploads> to
stage the capsule. Persist its transaction record before the one explicit commit
attempt. Distinguish RAM verification, commit acceptance, installation and startup
confirmation; useful behavior needs a hardware check. Unknown commit outcomes
require a new explicit status action, never a repeated commit or automatic upload.
Open the console only when appropriate, with a fresh expected-device validation.

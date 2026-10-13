# Preparing source and packaging a managed ELF

Prepare an offline source revision and package independently linked Nano code without accessing a board.

## Scope

``ManagedSketchPreprocessor`` prepares C++ input through the verified shared compiler package
in a private WebKit worker. No WASM service, service approval or visible view is
required. Missing/corrupt resources and host/cancellation failures throw explicitly.
First-line diagnostic byte columns include any original UTF-8 BOM. ``ManagedELFConverter`` validates
an independently linked ELF and produces an experimental FMS1 capsule. Neither
compiles source. The separate experimental ``ManagedSketchCompiler`` compiles prepared source through an internal WebKit worker; see <doc:ManagedCompilation>.
Packaging proves structure and digests, with no source-to-code or hardware attestation.

## Capture immutable inputs

Create a ``SketchSourceSnapshot`` before asynchronous work. Supply the Nano board,
explicit managed profile, and exact host-known ``ManagedResidentBinding``; hello
does not establish an ELF identity or API address. Pico has no managed target.

```swift
import Foundation
import FirmingoKit

/// Captures and prepares one offline source revision with exact host-known resident metadata.
func prepareSource(
    source: String, documentID: UUID, revision: UInt64,
    resident: ManagedResidentBinding
) async throws -> PreparedManagedSketch {
    let snapshot = try SketchSourceSnapshot(
        documentID: documentID, revision: revision,
        filename: "Blink.ino", source: source
    )
    let request = try ManagedSketchBuildRequest(
        snapshot: snapshot, board: .nanoRP2040Connect,
        profile: .nanoManagedV1, resident: resident
    )
    return try await ManagedSketchPreprocessor.prepare(request)
}
```

The single source file is at most 256 KiB, nonempty and NUL-free. Portable ASCII
leaf filenames are limited to 96 bytes. Compiler input normalizes line endings
and an initial BOM, then adds Arduino.h and an original-filename `#line`.
Only literal Arduino.h includes are accepted. Other directives, libraries,
multi-file sketches, arbitrary flags and escaped physical newlines are unavailable.
Helpers need explicit forward declarations; prototypes are not invented.

Unsupported preprocessing returns ``SketchBuildError/unsupportedSource(_:)`` with
at most 64 ``SketchDiagnostic`` values, using original one-based lines and UTF-8
byte columns. ``PreparedManagedSketch/sourceLine(forGeneratedLine:)`` maps physical
generated lines when needed; diagnostics honoring `#line` already use original
positions. Source preparation is not syntax/type checking or proof of statelessness.

## Package independently linked code

An independent trusted builder must consume the prepared translation unit, fixed
Nano recipe and exact resident API/ABI metadata. The pinned firmware facade exposes
a constrained Arduino subset; full cores/libraries, globals/initializers and
USB/NINA are unavailable. Setup/loop must return. ELF headers cannot establish
those executable properties.

```swift
/// Packages an independently built ELF whose source/recipe association the host has established.
func packageLinkedELF(
    _ elf: Data, prepared: PreparedManagedSketch,
    provenance: ManagedELFProvenance
) async throws -> ManagedSketchArtifact {
    try await ManagedELFConverter.convert(
        elf, prepared: prepared, provenance: provenance
    )
}
```

``ManagedELFProvenance`` declares bounded compiler identity and exact recipe/toolchain
manifest hashes. The host owns trustworthy build/source association and asset
verification; this metadata does not authenticate or execute a compiler.

The converter accepts bounded little-endian ARM ELF32 executable output with the
selected stateless `.text` at `0x10200100`, consistent readonly LOAD mapping, and
defined global Thumb setup/loop wrappers. Code is 4–3840 bytes and aligned to four;
writable storage, runtime initializers, unresolved symbols, relocations, stripped
entry symbols and conventional firmware/UF2 layouts fail. Mapped ELF metadata is
excluded from capsule code. Cancellation prevents returning a completed result.

``ManagedSketchArtifact`` contains a `.fms` capsule, matching report, and immutable
receipt. Compare its source revision, document and build identity against current
host state before accepting the result. A later edit needs a new request; stale
artifacts cannot be treated as a newer build. The receipt is evidence retained by
the host and does not authorize upload.

See <doc:ManagedUploads> for separate capability, resident-binding and physical
authorization gates. Parser fixtures are non-executable and must never be uploaded.

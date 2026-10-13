# Local compiler implementation status

Current supplied-ELF conversion and package identities: [shared ELF packaging](elf-packaging.md). Earlier implementation records below remain historical evidence.

Current public preparation integration and updated package identities: [service-free preparation](service-free-preparation.md). Earlier records remain historical evidence.

The [standalone retirement record](compiler-retirement.md) identifies removed developer paths and current SDK validation commands; public compatibility APIs remain available.

Current build-facade/package integration: [shared compiler adapter](compiler-adapter.md).
The following original implementation records remain historical evidence where they describe SDK-owned compiler execution or earlier resource hashes.

## Ownership transition — 2026-10-12

Firmingo-Compiler now owns the intended language-neutral preprocessing, WASM
pipeline, recipes, ELF/capsule packaging, compiler diagnostics, and static build
metadata. FirmingoKit owns the Swift facade/web-host adapter, resource access,
device associations and deployment checks. Firmware constraints and actual resident
build facts remain authoritative in Firmingo. See [the migration inventory](compiler-migration.md).

The implementation and evidence below describe the existing SDK-local path; no
code/assets/APIs or historical receipts have moved in this documentation increment.
Keep those checks until replacements pass. Portable asset maintenance and service
distribution/provenance review move with the compiler; Swift integration and
Apple-host qualification remain SDK work. The empty default catalogue and pending
service behavior remain unchanged.

FirmingoKit now provides experimental local single-file Nano compilation through
`ManagedSketchCompiler`: verify → preprocess → isolated WebKit/WASI compile/link →
strict ARM ELF validation → FMS1 capsule/report/receipt. Its public API contains no
UI frameworks or visible-webview requirement. The compiler never connects or writes
a board. The demo calls it from Build and from the explicitly confirmed Run flow.

The independent host/worker/facade/recipe and licensed WASI shim are packaged;
the custom-service binary remains an explicitly selected local input while its
redistribution license/provenance is unresolved. No host path, sibling dependency,
Node requirement, shell/compiler subprocess or remote fallback exists in the SDK.
The current macOS WebKit tests are offline with synthetic resident bindings;
none of their executable outputs may reach hardware. iOS/iPadOS and macOS signed
sandbox, minimum-OS execution, Clang resident-call behavior and physical deployment
remain unqualified. Pico and arbitrary Arduino sketches are unsupported.

`Tools/ManagedWASM/` retains the separate development Node/WASI compile/link runner
and SDK-local staging/validation workflow. See [the reproducible workflow](../Tools/ManagedWASM/README.md),
[service observations](compiler-service-observations.md),
[Node experiment provenance](compiler-wasm-experiment.json), and
[WebKit integration evidence](compiler-webkit-experiment.json).

## SDK runtime and demo integration

The accepted next implementation consumes a compiler-owned versioned asset package
and firmware catalogue through the SDK, specified in [compiler-catalogue.md](compiler-catalogue.md)
and tracked in TODO sections 7.1–7.2. It retains automatic SDK resource loading and offline
firmware-build selection, separates static build metadata from per-device
associations, and drives the demo through the same SDK APIs. The additive metadata
foundation and experimental offline compiler inputs/receipts are implemented;
default resource-loading APIs now verify a bounded package inventory and empty
catalogue, with explicit pending-service errors. Normal bundled demo compilation
remains blocked on approved service/production descriptor packaging. The explicit service and legacy
combined record below remain compatible current APIs.
Service redistribution clearance, trusted descriptor provenance and platform/board
qualification remain separate requirements.

### Catalogue metadata foundation

`ManagedCompilerCatalogue.load(manifestJSON:expectedSHA256:)` checks exact bytes
against an independently trusted anchor, then validates a closed schema-one
manifest (128 KiB, 32 entries, 8192 tokens). It supports explicit board/profile
queries and exact descriptor-ID lookup without selecting a latest build. Empty
catalogues and Pico expose no managed build choice. Availability here describes
metadata only, not service readiness or hardware qualification.

`ManagedFirmwareBuildDescriptor(recordJSON:)` validates static Nano/application,
ABI-one/target-one metadata against the current pinned experimental recipe. Its
content ID covers every schema field, including exact ELF/image/report hashes,
API address and recipe identity. `ManagedDeviceAssociation` strictly restores and
deterministically encodes separate bounded host evidence records; a matching pair
can be adapted using `ManagedResidentBinding(association:firmwareBuild:)`. These
declarations do not verify installed bytes or a referenced build report. The host
must review real evidence and preserve fresh-session/upload checks.

See `Sources/FirmingoKit/FirmingoKit.docc/ManagedCatalogue.md` for complete schemas
and a typechecked example. Legacy compiler requests/receipts remain device-bound;
the additive offline compiler path below uses no device placeholder. No
production catalogue or descriptor is bundled. Independent Python-generated
parser fixtures and ten rejection/identity/persistence tests are recorded in
`Tests/FirmingoKitTests/Fixtures/compiler-catalogue/provenance.json`; those synthetic
records must never be used for deployment. Validation receipts are in
[compiler-catalogue-experiment.json](compiler-catalogue-experiment.json).

### Device-independent compiler path

`ManagedOfflineBuildRequest(snapshot:catalogue:firmwareBuildID:)` resolves only an
explicit descriptor ID from verified catalogue bytes. The preprocessor overload
returns `PreparedManagedOfflineSketch`; the compiler overload produces
`ManagedOfflineCompilationResult` with a `ManagedOfflineSketchArtifact`. Neither
request nor artifact/receipt includes a physical-device ID. Shared source,
stateless ARM ELF and FMS1/report gates preserve existing validation behavior.
The converter overload requires exact descriptor/recipe identifier and hash;
externally declared provenance is still not proof of compiler/source association.

Offline receipts have a separate schema-one type: exact document/revision/name,
original/generated source hashes, catalogue byte hash, descriptor ID, board/profile
and all compiler/recipe/toolchain provenance affect `buildInputSHA256`. Output ELF
and whole-capsule digests are separate fields. A catalogue whitespace change or
source revision change alters input identity even when code bytes remain identical.
No build cache or stale-result reuse exists. Legacy request/artifact/receipt APIs
and stored records remain compatible.

`artifact.bind(to:)` requires a matching descriptor association and revalidates
the bytes against that device binding before returning the existing upload capsule
type. Binding is a local check, not evidence authentication or upload authorization;
it does not connect, stage, commit or replace firmware. The host retains current
source/selection checks and must validate fresh real-device identity/backend/targets
and reviewed installed-firmware evidence before deployment. See
`Sources/FirmingoKit/FirmingoKit.docc/OfflineManagedCompilation.md` for typechecked
build and current-selection/binding examples. Both compiler overloads share one
busy gate, runtime deadline and cancellation cleanup; mixed concurrent requests
cannot bypass isolation. All service resources and recipe bytes are unchanged.

Independent Python input/capsule hashes are test-only fixtures under
`Tests/FirmingoKitTests/Fixtures/compiler-offline/`. Seven ordinary tests and three
added real-WebKit tests establish metadata identities, structural packaging,
explicit binding, cancellation/reentry and mixed-overload exclusion. Exact
implementation receipts and limits are in
[compiler-offline-experiment.json](compiler-offline-experiment.json). Production
descriptor/service packaging, automatic loading, normal bundled demo setup, signed sandbox,
physical iPad/minimum-OS execution and hardware ABI behavior remain open.

### Verified runtime resources

`ManagedSketchCompiler(serviceURL:)` accepts only the exact reviewed bounded
ABI-two binary: 101196044 bytes, SHA-256
`3e2544acf7f88f6f1d5fbce34648df8eb96dfff47afa242a3e008bc8f86e2f33`.
Every build verifies that file and a pinned SDK runtime manifest off the main actor.
The facade/argument recipe, host page, worker and third-party code are covered by
that manifest. Versioned SHA receipts identify expected bytes; they do not authenticate
a publisher. The independently supplied service must come from a trusted source.

The internal main-actor WebKit host is nonpersistent and uses an exact two-resource
private URL origin (`host.html`, `compiler.wasm`). It denies other navigation, never
preopens the real filesystem/network in WASI, and uses a classic blob worker for
compatibility with the local origin. The page content policy permits inline reviewed
code, WASM evaluation and blob workers, with connections restricted to the private
resource scheme. A worker-only SHA-256 implementation covers opaque origins without
SubtleCrypto; independent vectors and padding-boundary tests check it. No arbitrary
JavaScript evaluation or caller script injection is needed.

Each build owns a fresh page, worker, WASI instance and bounded workspace. An actor
reservation rejects overlapping revisions across suspension. Runtime navigation,
worker errors, WebKit process termination, cancellation and the 60-second runtime
deadline discard the build context. Native result parsing independently validates
closed schemas, duplicate keys, scalar types, source coordinates, finite timings,
linear memory, safe re-entry and bounded canonical ELF base64. Frontend errors fail
even with status zero. Native/user-selected-file failures preserve their causes.
Progress is a finite synchronous observer with at most eight notifications; UI
consumers dispatch onto their main actor. No warm mutable state/cache is reused.

The demo requires selecting the approved service until packaging review is complete.
Its default catalogue mode imports a reviewed schema-one catalogue against an
independently supplied SHA-256 under **Development resources**, then requires an
explicit SDK-listed board/build choice. Build uses the device-independent compiler
API without device settings or association review. Run requires a separately
imported matching `ManagedDeviceAssociation`, review of its exact evidence/verification
limits and a matching Nano/application device selection. Schema details are in the
DocC catalogue guide; no production or synthetic catalogue is included in the app.
Anchor/board/build/mode changes expire outputs and device review without a latest
fallback. Failed catalogue imports do not switch to legacy mode. Reviewed device
associations can be explicitly saved and restored from bounded app-private
storage. A restored roster never selects a device/build or restores trust. Run
rechecks the exact saved record before compiler loading; stale-window save/delete
requests fail and refresh evidence without retry. See
[association persistence evidence](demo-associations-experiment.json).

The explicit **Legacy resident record** mode retains the combined host-known
build/install record. Its at-most-2048-byte JSON format has exact keys:

| Key | Value |
| --- | --- |
| `schema` | Integer `1` |
| `board` | `nano_rp2040_connect` |
| `profile` | `nano-managed-v1` |
| `deviceID` | Exact 16-character lowercase hex physical-device association |
| `residentELFSHA256` | Exact 64-character lowercase resident ELF hash |
| `firmwareImageSHA256` | Exact 64-character lowercase complete installed image hash |
| `apiAddress` | Unsigned decimal integer, aligned API-table address from that exact ELF |

`ManagedResidentBinding(recordJSON:)` validates schema and ranges, not provenance or
installed bytes. The user explicitly confirms the trusted record's association with
the installed resident. Hello cannot supply that exact binding. No sample address,
synthetic binding or familiar board name is selected by the demo.

Build uses a UUID/revision/name/source snapshot and real SDK progress/diagnostics.
Edits, filename changes and target changes invalidate results/cancel pending work.
Run builds again, closes its console, connects with expected board/backend/device ID,
stages through the SDK, synchronizes latest/history journals before commit, then
attempts commit once. A known accepted commit allows one fresh read-only status
sample. Unknown results require a separate explicit outcome check; there is no commit
retry or automatic new upload. Only startup confirmation permits opening the console,
again with expected device ID. Useful behavior remains unconfirmed. Saved context
blocks another Run until explicit review/clear; corrupt journals also block Run.
Clearing context retains history and does not reverse a board operation. Complete
firmware installation is separately gated against an active managed operation.

The demo's shared journal actor reserves device actions across document windows.
A new Run or firmware installation rereads the durable managed context before
compilation or writing; pending and unreadable context prevent deployment. Outcome
review requires the current saved transaction. Explicit clear atomically compares
the window's reviewed record and refuses to remove a newer valid transaction.
Conflicts refresh that window's context without retrying its action or connecting.
Reservations cover suspension and cleanup, and only their owner can release them.
Offline builds remain independent. This is coordination within one app process,
not a cross-process device lock or hardware qualification.

## Reference provenance

ArduinoKit is pinned at `0eb3cd1841147dfc7ea25bf076545e38b01601e4` with a clean
checkout. [compiler-reference.json](compiler-reference.json) records byte counts
and SHA-256 for the overview, manifest, Swift compiler/preprocessor/runtime,
ELF/UF2 readers, JavaScript recipe/diagnostics, and WASI service files inspected.
The new Swift implementation is independently authored, informed by those
boundaries; no custom ArduinoKit runtime/service source was copied. A licensed
third-party WASI shim is vendored separately for development, with full licenses
and receipts. The service binary is copied/adapted only under SDK `.build/`;
redistribution remains pending.
`adapted_files` remains empty for copied files, and
`independently_authored_adaptations` lists the new implementation.

Firmingo is pinned at `f17fdf0301256ba48270230cbf213126e70aa8d0`.
[compiler-firmware-reference.json](compiler-firmware-reference.json) records the
exact managed builder, linker, entry wrappers, facade, ABI/image headers, sample
source, and integration-guide hashes. Working bytes matched that commit; the
existing local `AGENTS.md` difference was guidance outside the selected contract.
Neither reference checkout was built, modified, or disturbed.

The ArduinoKit reference uses an isolated WebKit worker and WASI Clang/LLD
service ABI 2. Its Nano recipe uses ArduinoCore-mbed 4.6.0 / ArduinoBLE 2.1.0 and
Clang/LLD 22.1.8 for conventional UF2. The Firmingo proof instead uses GCC-built
stateless modules and a constrained facade. Changing a board name or adding an
FMS header to conventional Arduino output cannot establish compatibility.
ArduinoKit's `arduino_nano_rp2040_connect` maps explicitly to Firmingo's
`nano_rp2040_connect`; Pico has no reviewed managed target.

## Source preparation

`SketchSourceSnapshot` preserves document UUID, revision, filename, and exact
original UTF-8 source. Source is nonempty, NUL-free, and at most 256 KiB. The
filename is a portable ASCII `.ino` leaf up to 96 bytes; paths, hidden names,
doubled dots, and directive-injection characters fail. Inputs cannot supply
libraries, dependency discovery, extra source files, or arbitrary compiler flags.
`ManagedSketchBuildRequest` requires the Nano board, explicit `nano-managed-v1`
profile, and host-known `ManagedResidentBinding`. Hello is insufficient to create
that binding. No board connection is necessary for offline preparation.

`ManagedSketchPreprocessor.prepare` normalizes CRLF/CR to LF, removes an initial
BOM from compiler input, inserts the local Arduino facade include and a filename
`#line`, and hashes both original and generated bytes off the main actor. It
preserves source order and **does not generate function prototypes**: declare
helpers before use. Only literal `<Arduino.h>` / `"Arduino.h"` includes are
accepted. Macros, conditional directives, pragmas, location overrides, user
libraries, and escaped physical newlines are rejected. The latter restriction
also applies inside comments/literals, avoiding translation-phase line-splicing
ambiguity. Comments, quoted/raw strings, and numeric digit separators are scanned
before directives; rejection returns at most 64 diagnostics with original
one-based lines and UTF-8 byte columns. Compiler syntax/type errors and linker
statelessness checks remain separate. A prepared source is not compiled code.

The selected firmware facade documents a narrow `pinMode`, `digitalWrite`,
`millis`, `delay`, and `Serial` subset, with Nano `LED_BUILTIN` 6. Full Arduino
cores/libraries, global/static storage or initialization, USB/NINA access and
unbounded execution are outside the experiment. The SDK packages an independently
authored constrained facade; Clang's calls against the real resident remain
unqualified. Setup/loop must return; source
preparation cannot prove that behavior or validate every Arduino call.

## Independently linked ELF packaging

`ManagedELFConverter.convert` accepts a `PreparedManagedSketch`, a bounded ELF,
and `ManagedELFProvenance`. The host must establish that its trusted independent
build used that generated source, resident API definition, exact recipe, and
verified toolchain assets. Provenance hashes are syntactically validated
**declarations**, not asset verification or proof that a compiler ran. The receipt
cannot attest source-to-code association, instruction selection or ABI behavior.

The parser implements the pinned `module.ld` subset, informed by
[Arm AAELF32 2025Q1](https://github.com/ARM-software/abi-aa/blob/2025Q1/aaelf32/aaelf32.rst),
the [ELF section specification](https://gabi.xinuos.com/elf/03-sheader.html), and
[ELF symbol specification](https://gabi.xinuos.com/elf/05-symtab.html). Its deliberately
narrow policy is:

- ELF32, little endian, System V ABI zero, ARM `ET_EXEC`, EABI five base/soft float;
  file 52 bytes–2 MiB, bounded ordinary tables (no extended counts).
- Exactly one nonempty allocated `.text`: readonly/executable `PROGBITS` at
  `0x10200100`, 4–3840 bytes, a multiple of four per the selected linker alignment.
  Constants must already be folded into that section. Writable allocated sections,
  `.bss`, relocations, dynamic linking, runtime initializer arrays and unresolved
  named/common symbols fail.
  The two reviewed metadata flags are `0x06` and LLD's readonly merged-string
  form `0x36`; writable and other unknown flags still fail.
- Consistent readonly LOAD mapping with equal file/memory sizes and virtual/physical
  addresses. Mapped ELF headers before `.text` are metadata, never capsule code.
  Arbitrary RAM/full-firmware layouts and conventional UF2 are rejected.
- A bounded static symbol table defines unique global Thumb-function wrappers
  `firmingo_sketch_setup` and `firmingo_sketch_loop`, with nonzero sizes wholly in
  `.text`. ELF entry matches setup. Stripped output lacking those symbols fails.

The converter writes the little-endian FMS1 ABI-one/64-byte header, Nano tag,
explicit resident API address, code address, lengths, Thumb entries and code
SHA-256; padding to byte 256 is zero. It produces `.fms`, a deterministic report,
and a schema-one typed receipt. The existing `ManagedCapsule` independently checks
that output/report/resident association. Complete-firmware UF2 remains a different
artifact and operation. Packaging does not authorize upload.

The receipt retains document/revision/name, original/generated source hashes,
board/profile, device/resident ELF/firmware/API association, compiler/recipe/toolchain
identity, linked ELF hash and capsule hash. Its complete input digest changes with
every current build-affecting input. No build cache exists. Hosts must compare the
receipt against their current document/target before accepting an asynchronous
result; conversion never reads an editor again. Preparation/conversion check task
cancellation; ordinary validation errors remain distinct from cancellation.

## Evidence and remaining runtime work

Packaged `Fixtures/compiler/stateless.elf.hex` is an independently hand-authored,
non-executable ELF layout whose eight-byte code is the pinned firmware parser
vector. Its manifest checksums are verified locally. Tests compare the resulting
complete capsule to the firmware bytes, exercise every truncation and malformed
mapping/table/symbol gate, exact capsule limits, preprocessing diagnostics and
complete receipt identity. These tests need no sibling checkout.

A one-time structural check copied an existing ignored GCC ELF/FMS/report only
into SDK `.build/compiler-observed/`. The converter reproduced the independent
688-byte capsule exactly. [compiler-observed.json](compiler-observed.json) records
these **provisional observed** output hashes separately from committed references.
The check used an explicitly synthetic firmware-image binding and fake recipe
hashes: it establishes packaging layout only, not installed-image association,
source compilation, actual compiler execution, or hardware compatibility. No
firmware tool or device-changing backend was invoked.

All three reference resource sizes/hashes below were independently checked against
their files and committed manifest. Only the service was copied under SDK `.build/`;
none is packaged with the library. The conventional sysroot is unnecessary for
this deliberately freestanding development recipe. Its advertised hash in the
earlier documentation was transcribed incorrectly and is corrected here.

| Resource | Bytes | Advertised SHA-256 |
| --- | ---: | --- |
| WASI service | 101196042 | `bce6632512852bf86baf7ca7b6eddd07209c0c4e29ae3b2288ec27e69028887d` |
| Host page | 43004 | `9d1cdd60201ca2df677a0da147a73402c3b3f041c27cdf21573124d4c549f9c4` |
| Conventional Nano sysroot | 61751296 | `ea7d0057399626ee7f05315deac634d0973248d932a9368a3c1ab300d6eefbd6` |

Remaining work includes complete service-build/patch/staging and component-license
review; qualified resident ABI call behavior; approved bundled resources; the
signed-host/runtime distribution checks; executable ABI/physical deployment tests; and macOS/physical iPad performance,
minimum-OS and sandbox evidence. Development workers validate cancellation,
timeouts, strict responses, fresh state and explicit failure handling, but do not
complete the product runtime gate. No native compiler or remote fallback is introduced.

No top-level ArduinoKit license file was found in the tracked inventory. License
and attribution review remains a prerequisite to copying any compiler/runtime
source or packaging each third-party asset. The custom-service license question is
pending with the user. The imported firmware parser vector
retains its existing GPLv3 fixture attribution; the additional ELF envelope is
independently authored. Reference access creates no runtime/build dependency.

## Default package resource loading — 2026-09-30

`ManagedCompilerCatalogue.loadBundled()` needs no host-supplied manifest/hash and
returns a verified empty catalogue until trusted firmware-build metadata is staged.
`ManagedSketchCompiler()` performs no I/O at construction and uses the independently
pinned package inventory on each build. It currently fails with the structured
`ManagedCompilerResourceError.serviceApprovalPending` before source preparation.
Development callers retain `init(serviceURL:)` and exact existing receipt/toolchain
identities. No automatic external fallback or publisher/device attestation is added.

The schema, finite roles, review boundary, maintenance workflow and qualification
limits are in [compiler-catalogue.md](compiler-catalogue.md) and the DocC **Load SDK
compiler resources** guide. Eight resource test functions and eight opt-in real
WebKit functions (including approved-branch test-only runtime parity) pass. Exact
checks are in [compiler-resources-experiment.json](compiler-resources-experiment.json).
Production services/descriptors, signed-host/physical-device and hardware evidence
remain open; default API availability does not claim successful bundled compilation.

## Host resource verification and default demo sources — 2026-09-30

`ManagedSketchCompiler.verifyResources()` verifies the selected SDK or explicit
development assets without source preparation, WebKit or board I/O. It shares the
build reservation, propagates cancellation, retains no resource cache and does
not prove compilation/ABI/hardware behavior. Every Build verifies independently.
The current default selection still reports pending-service review.

The demo starts with SDK metadata and compiler verification, displays SDK-issued
empty/unavailable reasons and retains explicit independent providers/imports under
Development resources. Source changes invalidate output/review and returning to
SDK compilation releases the imported service capability. Default Build calls the
SDK default initializer rather than reusing an old imported service. No production
resources were added. Evidence and remaining limits are in
[demo-default-resources-experiment.json](demo-default-resources-experiment.json).

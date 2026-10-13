# Compiler split — ownership and migration inventory

Current build-facade/package integration: [shared compiler adapter](compiler-adapter.md).
The following original implementation records remain historical evidence where they describe SDK-owned compiler execution or earlier resource hashes.

Accepted 2026-10-12. This is the prerequisite inventory and compatibility plan for
extracting the compiler from FirmingoKit. The initial increment refocused documents;
subsequent compiler-foundation/portable-stage progress is recorded below. Existing
SDK executable code, staged assets, public APIs, fixture bytes and persistence remain
unchanged. Keep the existing implementation until each replacement gate passes.

## Reference snapshot and authority

| Repository | Inspected source commit | Working state before this documentation change |
| --- | --- | --- |
| FirmingoKit | `05cae8fa8e58c706eceb6a15812d7ca500375d7b` | Clean |
| Firmingo | `f17fdf0301256ba48270230cbf213126e70aa8d0` | Pre-existing `AGENTS.md` CI guidance edits; retained |
| ArduinoKit | `0eb3cd1841147dfc7ea25bf076545e38b01601e4` | Clean, read-only reference |

[The reference inventory](compiler-migration-reference.json) records SHA-256 for
tracked production sources, resources, and relevant fixtures/tools at the start
of this increment. It is an inventory snapshot, not a new compatibility claim,
trusted release manifest, or executable asset distribution. No ArduinoKit source
or service was copied. Existing compiler/protocol provenance JSON and test fixture
manifests remain unchanged; they describe their original selected evidence.

Historical evidence links remain with their originating projects. Documentation
edits change documentation hashes, including the managed-sketch guide in a newly
generated contract ZIP, without changing wire bytes, ABI headers, firmware
recipes, or the identity of previously exported archives. Do not rewrite old
receipts to make them describe this documentation revision.

## Ownership after the split

| Responsibility | Owner and boundary |
| --- | --- |
| Device ABI/facade/layout, image/protocol rules, supported capabilities and actual resident build facts | Firmingo; export verified versioned inputs |
| Preprocessing, WASM pipeline, recipes, ELF validation/capsule generation, compiler diagnostics and receipts | Firmingo-Compiler; portable implementation without Swift |
| Static compiler asset manifests/catalogues and recipe-compatible firmware descriptors | Firmingo-Compiler, derived from verified firmware exports |
| Swift facade, WebKit origin/view lifecycle, platform resource access, message translation and package trust anchors | FirmingoKit |
| Device associations, installed-firmware evidence, installation, communication, upload and deployment validation | FirmingoKit |
| Editing, source revisions/selections, diagnostics presentation and explicit user actions | Host application/demo |

Firmware exports facts; the compiler adds recipe/catalogue identity; the SDK
loads/translates the package and binds artifacts to actual devices. No compiler
request needs a device ID or upload permission. Neither a receipt nor metadata
integrity establishes installed-image identity or publisher authentication.

## Production implementation inventory

Paths below are relative to FirmingoKit unless stated otherwise. "Extract" means
port/reimplement behavior where necessary; Swift files cannot simply be moved
into a language-neutral library. Public Swift types may remain as adapters.

| Current component | Destination or retained responsibility | Migration check |
| --- | --- | --- |
| `Compiler/ManagedSketchPreprocessor.swift`, `PreparedManagedSketch.swift`, `PreparedManagedOfflineSketch.swift` under `Sources/FirmingoKit/` | Preprocessing/source mapping in compiler; Swift compatibility types/adapters retained as needed | Original/generated hashes, normalization/restrictions, coordinates, cancellation and unchanged caller behavior |
| `Compiler/ManagedELFImage.swift`, `ManagedELFConverter.swift`, `ManagedELFPackage.swift`, `ManagedELFProvenance.swift` | Portable ELF validation, packaging and canonical provenance generation in compiler | Independent vectors, malformed/truncated ELF, limits and exact capsule/report bytes |
| `Compiler/ManagedSketchCompiler.swift` | Retain Swift async facade; delegate source-to-artifact work to compiler | Legacy/offline overloads, busy behavior, progress, cancellation, deadline and clean reentry |
| Source/request/diagnostic/result/artifact types under `Compiler/` | Portable schemas/semantics in compiler; Swift translations/public compatibility here | Explicit versioning, source identity, diagnostic locations, no fabricated device fields |
| `Compiler/ManagedCompilerCatalogue.swift`, `ManagedFirmwareBuildDescriptor.swift` | Compiler owns static definitions/production; SDK retains bounded reading/querying and public Swift views | Content identity, exact selection, unsupported targets, old descriptor retention and persistence |
| `Compiler/ManagedOfflineSketchArtifact.swift` | Compiler produces offline bytes/receipt; SDK retains `bind(to:)` and deployment checks | Match actual association without changing stored records or granting permission |
| `CompilerRuntime/ManagedWebKitHost.swift`, `ManagedCompilerOrigin.swift`, `ManagedWorkerOutput.swift` | Retain platform hosting, local navigation/access policy and strict Swift bridge adapter | Portable bridge conformance, bounded replies, process termination and stale-event rejection |
| `CompilerRuntime/ManagedCompilerBundle.swift`, resource inventory/readers and verified-resource/toolchain types | Compiler produces portable inventory; SDK retains discovery, trusted anchors, local access and platform package verification | Pinned versions/hashes, corrupt/missing resources, consumer/archive loading and no fallback |
| `Tools/ManagedWASM/Sources/` | Compiler owns WASI/service/workspace/recipe/worker execution | Same production core for web and CLI; memory/output limits, isolation and cleanup |
| `Tools/ManagedWASM/Recipe/` | Compiler owns explicit Clang Nano recipe/facade/entry/linker adaptation | Conformance with firmware's authoritative ABI/layout and supported-call constraints |
| `Tools/ManagedWASM/HostBridge.js`, `NodeController.mjs`, `NodeWorker.mjs`, `DevelopmentAssets.mjs` | Portable bridge/dev-host behavior moves or is split into compiler core and harness adapters | Define general web entry point; keep Swift-specific message integration here |
| `Tools/ManagedWASM/Vendor/`, service-memory/manifest/recipe maintenance scripts | Compiler owns licensed dependencies, service/recipe build maintenance and provenance | Preserve notices/pins; redistribution and reproducible service build still unresolved |
| `stage-sdk-runtime.mjs`, `update-resource-inventory.py`, resource consumer/archive tools | Split compiler packaging from retained SDK staging/consumer verification | SDK consumes a pinned package and never independently edits compiler recipes |
| `Sources/FirmingoKit/Resources/ManagedCompiler/` | Existing staged bytes remain until compiler package replacement passes | No unreviewed service/synthetic descriptor added; same empty/pending behavior during transition |
| `Models/ManagedCapsule*`, `ManagedResidentBinding*`, `ManagedDeviceAssociation*`, upload models; `Protocol/NanoManagedContract.swift` | Retain independent SDK deployment/report/association validation and wire-facing constraints | Compiler output still undergoes board/format/hash/binding checks before writes |
| `Networking/`, `Protocol/`, `Lifecycle/`, demo/controllers and durable journals | Remain SDK/host responsibilities | No network, install, upload or journal behavior change from extraction |

## Tests and maintenance tools

| Current checks | Ownership after extraction |
| --- | --- |
| `SketchPreparationTests.swift`, `ManagedELFConverterTests.swift`, relevant compiler fixtures | Port portable behavior/golden tests to compiler; retain Swift adapter compatibility tests |
| `Tools/ManagedWASM/Tests/` and `run-validation.mjs` | Compiler real-service/worker/developer-CLI checks; replace Swift-only packaging step with portable production validation |
| `ManagedCompilerBridgeTests.swift`, `ManagedWebKitCompilerTests.swift` | SDK adapter/platform execution; compiler additionally owns neutral bridge and execution tests |
| `ManagedCatalogueTests.swift`, `ManagedCompilerResourceTests.swift`, `ManagedOfflineBuildTests.swift` | Split portable schema/identity cases from SDK resource access, public API, association and platform cases |
| `VerifyCapsules.swift` | Retain independent SDK validation harness as useful; compiler CLI does its own production packaging |
| `VerifyWebKit.swift`, `VerifyDemo*.swift`, association/journal/device-operation harnesses | Retain SDK/host integration, revision, durability and deployment checks |
| FMGO, capsule/upload, installer/lifecycle and UF2 transfer tests | Remain SDK checks; do not weaken them because compiler validates its own output |
| Firmingo native GCC modules, parser/session/install tests, hardware harnesses | Remain independent firmware reference and device evidence |

Keep current tests until their replacement passes. Import copies of independent
fixtures with provenance, not a dependency on a sibling checkout. Updating a
portable contract requires its compiler and wrapper conformance checks together.

## Compatibility that must survive

- Public Swift constructors/build overloads, source revision handling, diagnostic
  coordinates, progress, busy/error/cancellation semantics, and explicit service
  selection need a deliberate adapter/deprecation plan before any change.
- Existing legacy and offline receipts, descriptor IDs, association records, and
  upload/install journals must not be silently re-encoded or rebound. Preserve
  canonical identity where possible; incompatible schemas need explicit versions
  and tested migration/rejection behavior.
- The intentionally empty bundled catalogue and default pending-service error
  remain truthful until approved assets and real descriptors are provided. Do not
  auto-select latest, invent firmware evidence, or fall back after an error.
- Keep `.fms` capsules distinct from full UF2 images. SDK binding, fresh capabilities,
  one commit, uncertainty handling, and durability gates remain in force.
- No runtime dependency on sibling paths, Swift in the compiler, native compiler,
  Node in consumer builds, remote fallback, or visible web view is introduced.
- Nano source/API/statelessness limits stay explicit. Pico managed support and
  conventional Arduino output remain separate unimplemented compiler targets.

## Staged implementation and acceptance

1. **Prerequisite documentation:** align ownership/guidance/roadmaps, record this
   inventory and baseline hashes, and preserve existing implementation/evidence.
2. **Portable Nano path:** define the compiler interface, port preprocessing and
   ELF/capsule behavior, execute the real WASM service, and validate using independent
   vectors. CLI and browser must use the same implementation.
3. **SDK adapter:** consume pinned compiler assets through the Swift web host;
   preserve public API/persistence where practical and pass existing wrapper and
   device-safety regressions before retiring duplicate pipeline code.
4. **Verified distribution:** Firmingo supplies exact-build exports; the compiler
   resolves service provenance/distribution and packages compatible descriptors;
   the SDK verifies clean consumers and Apple-host packaging. Local-service tests
   can progress before production assets are distributable.
5. **Qualification:** compile two sketches through actual wrappers, validate,
   deploy in an authorized workflow, and record startup/useful behavior for each
   claimed resident/recipe/board/runtime combination.

The firmware export plan is in
[Firmingo's compiler contract document](../../Firmingo/docs/integration/compiler-contract.md).
Compiler implementation milestones are in
[Firmingo-Compiler's ledger](../../Firmingo-Compiler/TODO.md); SDK tasks remain in
[this repository's checklist](../TODO.md). Sibling links aid local coordination
and are not runtime/build inputs.

Only stage 1 is handled by this increment. Source/assets have not been extracted;
distribution review, exact-build exports, real-runtime migration tests, signed
hosts/physical iPad, hardware deployment, CI execution, and publication are open.

## Documentation-refocus validation — 2026-10-12

- `python3 Tools/verify-fixtures.py` passed: 34 existing fixtures across five
  provenance sets; no fixture bytes or manifests were changed.
- `git diff --check` passed in Firmingo and FirmingoKit.
- A read-only documentation/inventory audit verified 26 new local link occurrences,
  all 192 recorded file sizes/hashes, unchanged tracked files outside the listed
  documentation edits, and preservation of historical completed-task counts.
- Firmingo's pre-existing CI guidance edits were retained; ArduinoKit remained
  clean at its original reference commit.

No firmware/native build, Swift build/test, WASM execution, GitHub CI, hardware
operation, asset staging, or publication ran for this documentation-only increment.

## Compiler foundation — subsequent increment, 2026-10-12

Firmingo-Compiler has selected the existing Nano contract and recipe, recorded
reference/service identities, and implemented portable input validation and
descriptor/request identity with tests. Its
[interface draft](../../Firmingo-Compiler/docs/interface.md) and
[support matrix](../../Firmingo-Compiler/docs/compatibility.md) distinguish this
foundation from the future preprocessing/WASM/packaging path. The SDK's existing
descriptor ID is preserved by an independent golden check. No SDK source/API,
staged resource, saved receipt or device operation changed in that increment.

## Portable compiler stages — subsequent increment, 2026-10-12

Firmingo-Compiler now prepares source, validates the strict Nano ELF/FMS1 subset,
packages independently supplied ELF, and returns a distinct declared-provenance
packaging receipt. The Nano manifest/four assets are copied unchanged into its
recipe tree, preserving the existing recipe hash; the SDK copy stays until actual
runtime/adapter replacements pass. Whole firmware capsule bytes and independently
generated JSON/identity expectations agree. See the
[portable pipeline](../../Firmingo-Compiler/docs/portable-pipeline.md) and
[recorded checks](../../Firmingo-Compiler/docs/evidence/portable-pipeline.md).

Generated source/hash behavior matches existing vectors. Original first-line BOM
diagnostic columns include the removed BOM's three bytes, an intentional adapter
compatibility correction. No SDK source/API/receipt was changed by this port.
Actual WASM execution, runtime output/lifecycle schemas and the Swift adapter remain
open; standalone ELF packaging is not source-to-code or hardware evidence.


## Actual compiler execution — subsequent increment, 2026-10-12

Firmingo-Compiler now owns a working isolated portable WASI service/worker/controller,
strict version-one runtime events/codecs and execution receipts, plus an explicit
local-service compiler CLI. Actual Node/WASI tests exercise compile/link success,
frontend/facade/statelessness/link errors, cancellation/deadlines, busy/correlation
and clean subsequent builds. Two sketch ELFs match this SDK's reference path
byte-for-byte; Firmingo's independent production image validator accepts both
capsules and rejects corrupt code/wrong bindings. All bindings are synthetic,
NEVER DEPLOY. See [runtime](../../Firmingo-Compiler/docs/runtime.md) and
[execution evidence](../../Firmingo-Compiler/docs/evidence/wasm-runtime.md).

The bounded service stays an explicit local development input, with redistribution
and reproducible provenance unresolved. Web/Swift/package-consumption and hardware
gates remain open. No executable SDK source, resource, public API, persisted receipt,
device association or upload check changed. Next is web-host qualification and the
versioned Swift adapter; existing compiler copies stay until those checks pass.


## Standard browser-worker evidence — subsequent increment, 2026-10-12

Firmingo-Compiler now provides a minimal readonly local web harness and headless
standard-module-worker checks. Nine cases pass in Chrome 154.0.8037.93/macOS arm64/
HTTP loopback, with real compile/link output matching the independently validated
Node/SDK/firmware capsules. Without the explicit service, three browser checks pass
and six compilation cases skip; no missing-service compile success is claimed.
See [web harness](../../Firmingo-Compiler/docs/web-harness.md) and
[browser evidence](../../Firmingo-Compiler/docs/evidence/web-host.md).

This qualifies the recorded standard web host only. It does not qualify the SDK's
WebKit custom scheme, signed sandbox, Safari, iOS/iPadOS or hardware. The next migration
gate is versioned package consumption and a Swift/WebKit adapter preserving existing
APIs, receipts/correlation and independent deployment/association checks. Existing
SDK executable code/resources and saved records remain unchanged until that passes.

## Standalone runtime retirement — 2026-10-12

The [retirement record](compiler-retirement.md) and exact [source inventory](compiler-retirement.json) replace the obsolete SDK developer runtime/recipe/vendor stack with compiler-owned tooling. Retained public Swift preparation/conversion APIs and independent deployment validators remain explicit SDK compatibility/safety responsibilities.

## Supplied-ELF conversion retirement — 2026-10-12

Both public conversion overloads now use shared declared-provenance packaging. Native ELF parsing/capsule production are removed with exact [retirement hashes](elf-packaging-retirement.json); public receipt meaning and independent deployment checks remain. See [current contract and verification](elf-packaging.md).

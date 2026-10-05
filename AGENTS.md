# FirmingoKit — coding agent instructions

## 1. Mission and task scope

FirmingoKit is a reusable Swift SDK for host applications communicating with microcontrollers running Firmingo firmware. The intended host platforms are macOS and iOS/iPadOS. The initial firmware boards are Arduino Nano RP2040 Connect and Raspberry Pi Pico, with different capabilities and qualification status. Additional boards are expected to be added in time, with consistent support for upgrades and bug fixes in the firmware expected as well. 

The SDK must let a host app guide an end user through installing Firmingo for the first time and using its features. Initial Firmingo installation, supported Firmingo updates, communication, and managed-sketch upload are package responsibilities. These are requirements to implement and qualify, not claims of existing support.

Reverting a microcontroller to default Arduino firmware or a traditional Arduino build is outside FirmingoKit's scope. The host-app developer owns any such feature, including its artifacts, compiler recipes, flashing orchestration, user interface, and verification. Do not add Arduino restoration APIs, bundled recovery images, restoration-specific compiler recipes, or restoration tests to this package. Firmingo installation must not depend on preparing an Arduino return path. Recovery within this document means recovering an interrupted Firmingo operation or reinstalling supported Firmingo firmware, not restoring Arduino firmware.

The SDK must also compile Arduino sketches locally for supported boards running Firmingo, using a WebAssembly-based compiler suitable for macOS and the iOS/iPadOS sandbox. Use the companion ArduinoKit compiler as a read-only implementation reference. Compilation belongs in FirmingoKit; host apps supply sketches and build selections and present the SDK's diagnostics, progress, and artifacts.

- Implement the user's requested scope. Do not build the demo, add integrations, change the firmware source, or implement a roadmap merely because this document describes them.
- Inspect relevant code, tests, and repository status before editing. Preserve unrelated work.
- ArduinoKit is reference-only: never edit its code or other files, regenerate its assets, run tools that write into its checkout, or change its Git state. Implement and test adaptations inside FirmingoKit. Do not introduce a runtime or build dependency on the sibling checkout.
- Firmingo is also reference-only and is actively maintained by a separate AI coding agent. Never edit its code, documentation, fixtures, generated artifacts, or Git state from this conversation. Do not run builds, tests, exports, flashing helpers, or other commands that write into that checkout. Keep SDK changes, adapted resources, and validation outputs inside FirmingoKit; directory access does not grant permission to modify the firmware project.
- Prefer the smallest cohesive implementation that satisfies the contract. Avoid speculative abstractions and dependencies.
- When a missing decision affects compatibility or observable behavior, explain it and request clarification while continuing independent work. Resolve routine implementation details using these instructions.
- Never equate a successful build, mocked test, or simulator run with hardware qualification.
- The user disabled visual inspection. Do not use screenshots, computer-use/native UI inspection, or ask to enable that capability. Validate through source review, deterministic tests, controller harnesses and builds; state the remaining UI/accessibility qualification limits.

## 2. Repository facts and proposed layout

Snapshot verified on 2026-09-30:

- `Package.swift` declares the `FirmingoKit` library and `FirmingoKitTests` test target, Swift tools 6.4, and `ApproachableConcurrency` for both targets. `Sources/FirmingoKit/Lifecycle/` provides bounded local complete-image acquisition, release/UF2 validation, artifact preflight, experimental macOS ROM programming with one-shot execution/durable record gates, and fresh-hello verification; hardware/sandbox qualification remains open.
- The package declares macOS 14 and iOS 17 deployment minimums. `Sources/FirmingoKit/` contains bounded FMGO framing, hello inspection, persistent serial sessions, experimental Nano FMS1/report validation and managed upload/reconciliation, and public domain models; `Tests/FirmingoKitTests/` uses Swift Testing and packaged pinned firmware vectors plus non-executable lifecycle parser fixtures. These workflows have no SDK hardware qualification.
- `Validation/FirmingoKit.xcworkspace` provides a shared package scheme. `Demo/FirmingoDemo.xcodeproj` is a separate native document app consuming the local package; it supports `.ino` editing, read-only device inspection, a live serial console, local Firmingo image/installation-plan review, explicit experimental macOS installation, and saved operation context/verification. Experimental Build/Run use SDK-filtered catalogue selections, device-independent compilation and separate reviewed associations, or explicit legacy resident records; durable managed journals and cross-window guards remain. The demo starts with SDK-owned catalogue loading and compiler-resource verification; explicit development catalogue/service sources remain available under advanced controls pending approved production resources. Explicitly saved per-device associations restore a bounded roster without automatic selection/trust; Run rechecks current saved evidence before compiler loading, and stale save/delete requests cannot overwrite newer records. Legacy descriptor migration is explicit. Programming, compilation, UI and restart behavior are not hardware/sandbox-qualified.
- A DocC overview and native Xcode documentation build are configured. No Swift-DocC plugin dependency or CI workflow is configured. `Demo/Shared/` exists; root `Mac/`, `iOS/`, and `Shared/` are not source directories.
- `Sources/FirmingoKit/Compiler/` provides immutable single-file source/target selection, bounded facade-only preprocessing with source diagnostics, and strict independently linked stateless Nano ELF-to-FMS1 packaging/receipts. `ManagedSketchCompiler` and `CompilerRuntime/` now provide experimental local WebKit/WASI compilation using packaged independently authored host/worker/recipe and licensed WASI shim resources. The exact memory-bounded service is host-supplied pending redistribution review; no qualified Clang/hardware recipe is claimed. Preparation and packaging alone do not compile source. Tests include non-executable compiler parser fixtures.
- `ManagedCompilerCatalogue` verifies bounded host-supplied metadata and exposes explicit experimental build choices; `ManagedFirmwareBuildDescriptor` separates static metadata from persistable `ManagedDeviceAssociation` evidence. `ManagedOfflineBuildRequest` and the experimental compiler/preprocessor/converter overloads produce device-independent artifacts/receipts with explicit association binding; legacy APIs/receipt schemas remain compatible. Shared source/ELF/FMS1 gates avoid fake device IDs. The demo exposes these APIs through imported development metadata; default SDK resource-loading APIs verify a bounded inventory and intentionally empty catalogue; default builds explicitly fail pending service review. Approved service/production descriptor packaging and normal bundled demo compilation remain open. Synthetic catalogue/offline fixtures are test-only, never deployment records.
- `Tools/ManagedWASM/` provides an independently authored experimental Nano recipe and browser-capable worker core tested through Node/WASI, with bounded workspaces, strict bridge responses, cancellation/deadlines, licensed third-party shim receipts, and SDK ELF/capsule validation. The service binary/derived memory-bounded copy stays only under `.build`; no service binary is packaged; the SDK WebKit host and opt-in real-runtime tests now exercise the same independently authored core. Outputs use synthetic resident bindings and must never reach hardware; custom-service redistribution/license review and qualification remain open.

Reinspect these facts before relying on them. Update this section when the structure changes.

`Demo/Shared/InstallationRecordStore` also coordinates device actions across document windows in one app process. Run and firmware installation recheck durable managed context; stale outcome/clear requests cannot replace newer valid records. Offline builds remain independent. `Tools/verify-demo-device-operations.swift` exercises these host-only gates without a compiler module or device connection; cross-process/hardware qualification remains open.

Use the following locations as work requires them; do not create empty architecture in advance:

| Location | Purpose |
| --- | --- |
| `Sources/FirmingoKit/` | Library implementation; organize by responsibility within one library target |
| `Tests/FirmingoKitTests/` | Deterministic tests and packaged test resources |
| `Sources/FirmingoKit/FirmingoKit.docc/` | Public DocC overview, guides, and examples |
| `docs/firmware-compatibility.md` | Firmware contract revision, fixture provenance, capability and qualification matrix |
| `docs/firmware-lifecycle.md` | Board-specific Firmingo installation, update, interruption recovery, artifact provenance, and platform limitations |
| `docs/compiler.md` | ArduinoKit reference provenance, WASM runtime, board recipes, bundled assets, artifact contracts, and compiler qualification |
| `docs/compiler-catalogue.md` | Accepted bundled-resource/catalogue design, offline build metadata, per-device association, implementation order, and acceptance gates |
| `docs/development.md` | Reproducible setup and validation commands |
| `docs/demo-design.md` | Demo product requirements when demo work begins |
| `Demo/` | Separate host app project; not a Swift package target |
| `Demo/AGENTS.md` | Demo-specific UI, accessibility, and platform instructions |

## 3. Firmware contract: read before implementing communication

Use the companion Firmingo repository at `../Firmingo` as a read-only reference when available. Otherwise use an explicitly supplied read-only checkout or checksummed SDK contract export. Do not embed developer-specific absolute paths in source or tests. Firmware implementation and changes remain the responsibility of the separate firmware agent.

Read these paths relative to that firmware checkout:

1. `docs/protocol.md`: authoritative wire format, schemas, limits, identity, ownership, and transaction behavior.
2. `docs/integration/managed-sketch-sdk.md`: SDK responsibilities, reference workflow, upload reconciliation, and experimental restrictions.
3. `docs/boards.md` and the relevant `boards/<board-id>/baseline.json`: board-specific configuration and qualification.
4. `tests/fixtures/protocol-v1/`, including `managed-upload/`: shared protocol vectors.
5. Referenced evidence and ABI/image headers when the requested feature depends on them.
6. `docs/releasing.md`, `docs/development.md`, and the applicable release manifest: initial installation artifacts, board matching, integrity checks, and existing flashing/recovery tooling.

For implementation details, inspect `src/core/protocol.h` and `protocol.cpp` for framing, `src/core/json.h` and `json.cpp` for JSON validation, `src/core/session.h` and `session.cpp` for session behavior, and `src/core/session_upload.cpp` for upload handling. The `experiments/managed_sketch/` recipe, ABI, and capsule files referenced in the compiler section provide the managed-build implementation reference. Read these sources to understand the selected contract; do not patch firmware behavior to accommodate an SDK implementation.

Because another agent may be changing this checkout, identify the commit and relevant file hashes used for each SDK change. Treat uncommitted reference changes as provisional and record them separately from the committed contract. Before relying on a set of files, verify that they form a consistent snapshot; use a pinned commit or supplied contract bundle when concurrent changes make that uncertain. Do not reset, stash, clean, switch branches, or otherwise disturb the other agent's work.

If SDK work needs a firmware change, document a concise handoff in FirmingoKit containing the affected contract, observed limitation, proposed firmware behavior, compatibility implications, and acceptance tests. Report it to the user for coordination with the firmware agent; send messages to that agent only when the user authorizes coordination. Continue independent SDK work without claiming the missing firmware capability exists. Do not change the firmware checkout to resolve the dependency.

For Firmingo installation, also consult the board manufacturer's bootloader-entry and programming procedure. The FMGO specification governs communication with Firmingo; it does not define how to provision a board that is not running Firmingo. Record versioned upstream references in `docs/firmware-lifecycle.md`, using the firmware's development/release guidance and relevant board documentation, such as [Raspberry Pi Pico documentation](https://www.raspberrypi.com/documentation/microcontrollers/pico-series.html). Manufacturer instructions that install a default Arduino image are contextual references only; implementing that restoration workflow belongs to the host-app developer.

The contract is under development. The revision inspected for this proposal was `f17fdf0301256ba48270230cbf213126e70aa8d0`; this is provenance, not a claim that FirmingoKit supports that revision.

When implementing the first protocol feature, record the selected full firmware commit, protocol major, supported profiles, and fixture checksums in `docs/firmware-compatibility.md`. For a contract export, record its manifest and archive checksum. Keep contract-dependent fixtures in this repository as SwiftPM test resources so normal tests do not depend on a sibling checkout or board.

Update contract references and tests together when compatibility changes. Do not silently follow a moving firmware branch. If the specification, fixtures, implementation, or evidence disagree, describe the conflict and pause only the affected behavior until resolved. Do not invent missing operations, discovery mechanisms, authorization, or retry semantics.

### Capability and qualification boundaries

At the inspected revision:

- Release references advertise no upload targets. The experimental Nano `0.1.0-m9exp1` resident supports a constrained managed-sketch upload target.
- That experiment does not establish Pico managed-sketch support, arbitrary Arduino sketch/library support, or general `.ino` compilation.
- FMGO integration on iOS/iPadOS and a Firmingo-compatible iPad compilation route are not established by the firmware handoff. ArduinoKit provides an existing sandbox-oriented Arduino compiler reference, but its conventional Nano UF2 output does not establish Firmingo managed-capsule compatibility.
- Bonjour discovery is not implemented. A numeric endpoint is selected explicitly; an IP address is not device identity.
- The application and UART backends differ. For example, application-backend baud controls and `device.reset` are unsupported.

Recheck these limits against the selected contract. Gate FMGO operations on the negotiated protocol and advertised capabilities. Gate initial Firmingo installation and bootloader-based reinstallation separately on the board, selected artifact, programming backend, and host-platform capabilities; they must not require a working Firmingo connection. A familiar board name, shared chip, or firmware version string is insufficient evidence of support or exact installed-image identity. Keep platform build support, firmware capability, and measured hardware support separate in documentation. Existing firmware flashing scripts do not establish SDK installation support.

## 4. Ownership and architecture

| Component | Owns |
| --- | --- |
| SDK | Sketch preprocessing, sandbox-compatible WASM compilation/linking, Firmingo-compatible board recipes, artifact generation, structured diagnostics, transport, framing, session management, managed uploads, and Firmingo installation/update/interruption recovery |
| IDE/demo | Documents and editing, source snapshots, board/build selection, calls to SDK compilation APIs, diagnostics/progress presentation, user decisions, and presentation of SDK-provided Firmingo installation/recovery steps |
| Host-app developer, outside this package | Any optional return to default Arduino firmware or a traditional Arduino build, implemented independently of FirmingoKit's feature requirements |
| Firmware | Device-side validation, authorization, execution, and installation of supported compiled capsules |
| Board bootloader/ROM | Board-specific programming and recovery entry points that can operate without Firmingo |

- Keep the public API and business logic independent of SwiftUI, AppKit, UIKit, application lifecycle, and global UI state. An internal WebKit compiler host is permitted as a runtime implementation detail; do not expose `WKWebView` or require a host-provided visible view. It must be usable by another host app without the demo.
- Keep transport I/O, frame encoding/decoding, session state, and domain models separate. Pure codecs and injectable transport boundaries should support deterministic tests.
- Apply MVC to the demo where useful; do not force every library responsibility into a controller.
- The SDK compiles `.ino` source using its verified WASM assets and supported Firmingo recipes, or accepts independently built Firmingo artifacts after validation. It performs Firmingo installation/update only after an explicit host request. Normal app builds must not depend on a native Arduino CLI, compiler subprocess, shell, or external compiler installation. Building and packaging the bundled WASM toolchain during development is a separate maintenance workflow.
- Separate complete Firmingo firmware installation/update and bootloader-based reinstallation from FMGO managed-sketch upload. Share artifact validation and progress models where useful, but do not reuse incompatible transfer protocols or success criteria.
- Separate artifact acquisition, board/bootloader discovery, installation backends, and lifecycle state management. Inject these boundaries for testing. Keep platform-specific device and filesystem access behind explicit backend capabilities.
- Keep implementation symbols internal or private unless callers need them. Document public behavior and review source compatibility before changing public APIs.

### Compiler reference: ArduinoKit is read-only

Locate the reference at `../ArduinoKit` or the explicitly supplied ArduinoKit directory. Read it in place; put all adaptation, temporary files, generated resources, and test outputs in FirmingoKit or its build directory. If the reference is unavailable, report that and continue independent work; do not silently substitute a different compiler design.

The inspected ArduinoKit commit is `0eb3cd1841147dfc7ea25bf076545e38b01601e4`. Record the reference commit, relevant local differences if present, adapted files, asset hashes, and license/attribution requirements in `docs/compiler.md`. Recheck the reference before implementation; the following describes inspected code and documentation, not tests run for FirmingoKit.

Read these paths relative to ArduinoKit:

| Reference | What to learn or adapt |
| --- | --- |
| `README.md`, `Package.swift`, `Tools/ArduinoDirectWASM/README.md` | SDK boundaries, resource packaging, supported platforms, toolchain construction, and reported validation |
| `Source/Compiler/SketchCompiling.swift`, `CompilationRequest.swift`, `CompilationResult.swift`, `ArduinoSketchPreprocessor.swift` | Async compiler boundary, immutable build inputs, preprocessing, diagnostics, and result models |
| `Source/CompilerRuntime/DirectWebAssemblySketchCompiler.swift` | Verified-resource loading, build stages, compiler orchestration, and artifact conversion |
| `Source/CompilerRuntime/DirectWASMCompilerHost.swift`, `DirectWASMCompilerHost+Extensions.swift`, `CompilerResourceSchemeHandler.swift` | Isolated WebKit hosting, bridge validation, cancellation, and content-process recovery |
| `Source/CompilerRuntime/DirectWASMToolchainManifest.swift`, `DirectWASMToolchainLoader.swift`, `DirectWASMToolchainVerifier.swift`, `Source/Resources/direct-toolchain-assets.json` | Versioned recipe/ABI metadata and byte-count/SHA-256 checks for packaged assets |
| `Tools/ArduinoDirectWASM/HostRuntime/Sources/BuildRecipe.js`, `DirectCompilerBridge.js`, `DirectCompilerWorker.js` | Fixed target recipes, WASI execution, isolated workers, and Swift/JavaScript communication |
| `Tools/ArduinoDirectWASM/CompilerService/`, `Tools/ArduinoDirectWASM/stage-direct-resources.mjs` | Clang/LLD service ABI, reproducible cross-build inputs, patches, and resource staging |
| `Source/Compiler/ELFImageParser.swift`, `RP2040UF2Converter.swift` | Validating linked output and generating conventional RP2040 UF2 artifacts |
| `Tests/ArduinoKitTests/DirectWebAssemblyCompilerIntegrationTests.swift`, `Tools/ArduinoDirectWASM/Tests/` | Real-runtime artifact assertions and JavaScript/WASI tests |

At that revision, the compiler invokes Clang/LLD through a versioned WASI service inside a local WebKit worker, without compiler subprocesses. It verifies bundled host-page, compiler-module, and sysroot assets. Its current recipe is Nano-specific: Clang/LLD 22.1.8 with ArduinoCore-mbed 4.6.0 and ArduinoBLE 2.1.0, producing a conventional UF2. The reference documentation reports macOS and physical iPad validation; its package declares macOS 14 and iOS 17 minimums. These are reference capabilities, not proof of Pico support or compatibility with Firmingo's resident ABI.

Use ArduinoKit's `Source/Compiler/RP2040UF2Converter.swift` and `Tools/ArduinoDirectWASM/HostRuntime/Sources/BuildRecipe.js` to understand conversion and recipe mechanics. Their conventional Arduino output is not a requirement to expose a default-Arduino build or restoration feature in FirmingoKit. Adapt only the behavior needed for supported Firmingo workflows.

### Compiler implementation and artifact contracts

- Expose an async compiler API accepting an immutable sketch/source snapshot, source revision, explicit board and build profile, supported dependencies/options, and required firmware binding metadata. Return structured source-mapped diagnostics, progress, typed artifacts, and a build receipt. A build must not connect to or write a board as a side effect; offline builds can use an explicitly supplied target description and resident metadata.
- Adapt the ArduinoKit pipeline: verify resources, preprocess, compile, link, validate linked output, and package the target artifact. Report real phase progress. Document supported sketch layouts, preprocessing behavior, Arduino API subset, and library dependencies; reject unsupported inputs with actionable diagnostics rather than claiming arbitrary Arduino compatibility.
- Use an extensible registry of explicit board/profile recipes. Each recipe defines the target CPU/triple, core or Firmingo facade, headers/libraries, flags, linker script, flash/memory limits, artifact format, and versioned ABI requirements. Do not generalize the Nano recipe by changing only a board name. Map reference IDs explicitly: ArduinoKit's `arduino_nano_rp2040_connect` and Firmingo's `nano_rp2040_connect` denote the same board using different identifier schemes.
- Keep a conventional complete-firmware UF2 distinct from a Firmingo managed-sketch capsule in the type/API model. For the current experimental Nano target, produce `nano-managed-v1` `.fms` capsules with the required FMS1 header, entry points, size/digests, and build report. Use the selected firmware's `experiments/managed_sketch/build_module.py`, `module.ld`, `module_entry.cpp`, `facade/`, `abi.h`, and `image.h` as authoritative recipe/format references alongside the protocol. Do not upload an ArduinoKit UF2 as a managed capsule or treat wrapping it in a header as conversion.
- Link managed code against the exact resident ABI/API binding identified by verified resident metadata. Do not hardcode a sample API address or infer an exact ELF identity from hello. The current proof uses pinned GCC-built modules and a constrained facade; a Clang/LLD WASM implementation needs its own documented recipe, ABI/linker validation, and hardware evidence. Do not silently swap toolchains or lift firmware restrictions on globals, libraries, or execution behavior.
- Initially qualify recipes for each supported Nano/Pico workflow independently, then add boards through recipe assets and tests. A board's conventional Arduino compilation support does not establish its Firmingo managed-upload support. Where firmware lacks a managed target, expose the unsupported build/upload combination explicitly; never silently replace resident firmware to make Run work.
- Keep compilation local and offline once required verified assets are packaged. Use the isolated WebKit/WASI runtime approach with read-only toolchain assets and a separate writable per-build workspace; restrict resource loading to intended local assets. Do not introduce a remote compiler, native executable fallback, or host-shell dependency to compensate for an unsupported iOS recipe.
- Validate bridge schemas, service ABI, recipe/board/target identity, resource sizes/hashes, and bounded outputs. Reject path traversal, unsafe archive entries, arbitrary shell arguments, and incompatible assets. Package approved resources with FirmingoKit and retain reproducible maintenance scripts/receipts there; never depend on ArduinoKit's checkout at runtime.
- Serialize builds per runtime or isolate concurrent jobs. Preserve cancellation, timeouts, worker termination, content-process recovery, and safe-reentry checks before warm reuse. Key any build cache by all source, dependency, recipe, toolchain, and resident-binding inputs. Never return a stale artifact as the result of a newer document revision.
- Keep WebKit interactions on the required main actor while compilation executes in its isolated worker. Avoid blocking UI with hashing, unpacking, or conversion. Measure cold/warm duration, memory, and packaged resource size on macOS and physical iOS/iPadOS devices; do not claim sandbox compatibility, minimum-OS support, or distribution suitability from a macOS build alone.

### Accepted bundled compiler and firmware catalogue

The user accepted this direction on 2026-09-30. Apply [docs/compiler-catalogue.md](docs/compiler-catalogue.md) when implementing the compiler/catalogue scope; it distinguishes delivered metadata/offline compiler/demo selection APIs from the remaining backlog. Actual compilation still requires explicit service selection pending service review; default SDK resource-loading APIs now verify the bundled inventory/empty catalogue and report the pending service explicitly; the demo imports verified development catalogues and separate reviewed associations, with a legacy compatibility mode. This documentation does not authorize hardware operations or edits/builds in either reference checkout.

- Bundle approved compiler/runtime assets, explicit board/profile recipes, versioned trusted firmware-build descriptors and licenses in FirmingoKit resources. Provide SDK catalogue queries and default verified compiler loading so every host, including the demo, uses the same SDK-owned resources and compatibility logic. Do not duplicate assets or selection logic in the demo.
- Separate immutable firmware-build metadata (board/profile, exact resident ELF/image hashes, ABI/API address, recipe and provenance) from persisted per-device association/installation records and managed transaction journals. Review public API and persistence compatibility before refining the current combined `ManagedResidentBinding` model.
- Offline Build must use an exact verified target descriptor without a connected board or fabricated device identity. Preserve descriptor/catalogue/recipe/toolchain/source identities in artifacts and receipts; adapt device-bound artifact APIs deliberately rather than filling their fields with synthetic values.
- Run must validate a real selected device association and fresh negotiated capabilities against the build. A catalogue hash, board selection, version string or matching API address does not attest installed firmware. Use trusted installation/build evidence or explicit existing-device setup, report verification limits, and never automatically rebind an association to "latest" firmware.
- Normal demo selection is driven by SDK catalogue entries and clear experimental/unavailable reasons. Move manual compiler/record import to an optional advanced path after automatic loading exists; preserve its validation. Keep unsupported Pico managed Build/Run unavailable, and keep source/API/library restrictions explicit.
- Resolve compiler-service/component redistribution licenses, attribution and exact firmware metadata provenance before shipping affected resources. Continue independent catalogue/model/test work while blocked; do not bundle unapproved services or invented records. Share identical compiler assets across compatible recipes and retain SDK-local reproducible maintenance receipts.
- Validate clean package consumers/archive resource loading and actual offline compilation in signed macOS and physical iPad hosts. Measure duration, total memory and packaged size; qualify deployment separately through SDK uploads and useful behavior. Keep initial installation/recovery separate, explicit and platform-gated, with no Arduino restoration or silent resident replacement.

### Firmingo installation, updates, and interruption recovery

The intended user journey is: select a supported board, install Firmingo, compile supported sketches, and use Firmingo's features. Provide reusable SDK APIs and structured states so any host can implement this journey without duplicating Firmingo flashing logic. Support qualified Firmingo updates and recovery from interrupted operations independently of any host-provided Arduino restoration feature.

Explain exactly what Firmingo installation or update replaces and preserves, including existing sketches, settings, and filesystems. Do not promise preservation, automatic backup, or exact rollback without an implemented and verified mechanism. Keep auxiliary-device firmware, such as the Nano's NINA radio firmware, outside the operation unless that is an explicitly supported Firmingo target.

Implement the lifecycle as explicit, inspectable steps:

1. **Preflight:** identify the selected physical board and host capabilities; resolve an exact supported Firmingo artifact. Return a plan describing versions, affected flash regions/data, required user actions, prerequisites, and available verification. Identify the supported recovery procedure for an interrupted Firmingo installation; do not require an Arduino image or restoration toolchain.
2. **Prepare artifacts:** match the Firmingo release manifest's board ID, profile, version, byte count, and SHA-256, and record the release source and build provenance. Validate format, address ranges, and layout as required by the board backend. A checksum alone is not publisher authentication; use trusted release sources and verify signatures when provided. Never select by filename or shared RP2040 family ID alone.
3. **Request execution:** return the reviewable plan to the host, then execute only on an explicit host request bound to that board and artifact. Discovery, connection, and downloading must not trigger flashing. The host presents the effect on existing firmware/data and obtains the end user's action. Revalidate the target before writing, especially after USB re-enumeration; if board identity is ambiguous, require target selection instead of guessing.
4. **Enter programming mode:** support the documented bootloader/ROM method independently of FMGO. Return structured instructions when a button, jumper, reconnect, volume selection, or permission is required. Do not assume a software reset works under every installed firmware. For the Nano, distinguish physical ROM recovery from managed-upload authorization; for Pico, use its board-specific BOOTSEL procedure. A generic `RPI-RP2` volume name does not establish the board model or intended device.
5. **Write and verify:** serialize device-changing operations, close active sessions, and use the appropriate backend to write only the validated Firmingo target. Expose progress and explicit cancellation boundaries. Distinguish file transfer completion, device reboot, post-install verification, failure, and uncertain outcome. A completed file copy or disappearing bootloader volume alone does not prove successful installation.
6. **Reconnect or recover:** after installation, perform hello and validate the expected Firmingo board/profile/capabilities, reporting the limits of image-identity verification. Return actionable steps to recover or reinstall supported Firmingo firmware after an interruption. Never claim automatic rollback or blindly repeat a possibly completed write.

Keep the selected artifacts, plan, and useful recovery information available across expected disconnects. Expose a persistable operation record so a host can recover context after app restart; it must not imply that an interrupted flash can safely resume. Report what is known, what is uncertain, and the next supported action.

Document separate support for Firmingo installation, update, and interruption recovery for each board and host platform. Direct USB/bootloader access on macOS does not establish support on iOS/iPadOS. Qualify sandbox, filesystem, entitlement, and device-access requirements in a real host app. Where direct execution is unavailable, report that limitation and provide a guided Firmingo transfer/recovery route if supported; do not present instructions alone as an automated flashing backend. Adding a board requires its own Firmingo artifact mapping, backend capabilities, recovery procedure, and acceptance evidence.

## 5. Protocol invariants

The selected firmware specification remains authoritative for exact values and schemas. Enforce these invariants in code and tests:

- TCP is a byte stream: handle fragmented headers/payloads and coalesced frames. Retain unconsumed bytes.
- Validate frame fields and negotiated size limits before collecting or allocating payload storage. Follow terminal protocol-error rules; do not invent resynchronization.
- Encode binary framing explicitly with the specified byte order. Use `Codable` for JSON payloads where appropriate, with additional validation required by the contract. Do not assume synthesized decoding enforces every wire constraint.
- Perform hello once per connection and validate identity, protocol, backend, limits, and capabilities before operations. Correlate replies by request ID and process serial bytes independently.
- Preserve serial bytes exactly, including invalid UTF-8 and zero bytes. Text decoding, newline conversion, and console presentation belong to the host app.
- Acquire and release channel ownership explicitly. Preserve partial writes and implement bounded backpressure. TCP acceptance does not prove sketch consumption.
- Reconnection creates a fresh session and decoder. Do not implicitly replay commands, chunks, or serial bytes. Dispose of queues as the contract requires.
- Bound pending requests, buffers, and waits. Distinguish SDK operation deadlines from firmware deadlines and reference-harness timeouts.
- Expose unsupported operations as explicit failures. Never return success for an unimplemented or rejected operation.

### Managed upload

- Require an advertised target and matching board, format, size, digest, and build metadata. Validate the resident/ABI binding required by the selected contract; self-reported identity is not cryptographic attestation.
- Close the console before upload. Respect session ownership, physical authorization, negotiated chunk limits, offsets, and state transitions.
- Distinguish build success, staged transfer, verification, commit acceptance, installation, startup confirmation, and useful sketch behavior.
- Send commit once. If its reply is lost, query status on a freshly validated connection; never automatically resend commit.
- Reconcile using the device ID, boot ID, transaction ID, size, and digest required by the contract. A changed boot or superseded record can leave the outcome unknown.
- A successful response envelope can report a failed transaction. Inspect transaction state and its error fields.
- Cancellation or disconnection after commit does not prove that installation stopped. Report uncertainty instead of claiming success, rollback, or a safe automatic retry.
- The host must request a new action after an uncertain result. The SDK must not start another upload automatically.
- Firmware test capsules are non-executable parser fixtures. Never upload them to hardware.

## 6. Swift implementation conventions

### Concurrency and errors

- Use `async throws` for operations. Prefer an `AsyncSequence` API for streaming data/events; explicitly define buffering, backpressure, termination, and cancellation. Do not use an unbounded or silently dropping stream for lossless serial delivery.
- Use Combine only for an established consumer requirement or a focused adapter. Do not maintain duplicate public concurrency APIs by default.
- Isolate mutable connection/session state with an actor or a documented equivalent. Account for actor reentrancy across suspension points and ensure a single ordered reader for the transport.
- Use `Sendable` correctly across isolation boundaries. Do not silence concurrency diagnostics with `@unchecked Sendable` or unsafe isolation without a documented invariant and focused validation.
- Keep transport/codec work off the main actor. UI state belongs on `@MainActor` in the demo.
- Give tasks a clear owner and lifetime. Cancellation must release resources and resolve pending operations consistently with protocol state.
- Propagate errors unless the current layer can recover meaningfully. Catch to recover, add useful context, or clean up; preserve underlying causes and device error codes.
- Distinguish transport failures, protocol violations, device rejections, unsupported capabilities, cancellation, and uncertain outcomes. Keep user-facing descriptions to two sentences or fewer.
- Do not silently swallow errors with `try?`, force errors with `try!`, or force-unwrap optionals. Use assertions for programmer invariants, never as validation of device input.

### Files and naming

- Use one primary top-level named type per file. Keep small, tightly related nested types and test helpers together when separation would obscure their relationship.
- Use `<Type>+Extensions.swift` for general extensions. Focused files such as `<Type>+Codable.swift` are allowed when they keep distinct responsibilities coherent. Keep access-sensitive extensions with their type when Swift access control requires it.
- Prefer cohesive namespaced constants near the behavior they configure. Protocol constants belong with the codec/contract, not in a global miscellaneous file.
- Demo-wide configuration may live in `Demo/Shared/Constants.swift`; demo brand colors may live in `Demo/Shared/Colors.swift`. Neither belongs in the SDK.
- Prefer `if let value` and `guard let value` shorthand. Put the exit statement of a guard on its own line.

## 7. Tests and evidence

Use Swift Testing (`import Testing`) for new package tests unless existing integration requirements justify another framework. Document each new test's purpose with `///`; use inline comments to explain non-obvious setup and protocol invariants.

Add behavior-focused tests alongside changes. Prefer firmware-provided expected bytes and outcomes over round trips generated solely by SDK code. An encoder and decoder can share the same bug.

For affected behavior, cover:

- Golden frame vectors, binary byte preservation, valid boundary values, and capability negotiation with empty and populated targets.
- Header/payload splits, multiple frames per read, malformed headers, oversized lengths, and terminal errors.
- Interleaved serial bytes and control responses, partial writes, backpressure, and ownership rejection.
- Timeout, cancellation, disconnect, fresh-session behavior, and absence of implicit replay.
- Upload state transitions, rejected metadata, lost commit replies with exactly one commit sent, failed transaction states inside successful envelopes, and identity/boot/hash mismatches during reconciliation.
- Firmingo installation/update plans, missing Firmingo artifacts, wrong-board images, corrupt downloads/checksums, invalid flash ranges, and unsupported host backends. These failures must prevent writing.
- Bootloader discovery with multiple or ambiguous devices, re-enumeration, permission denial, expected versus unexpected disconnects, cancellation before/during writes, restart with a saved operation record, and post-install verification failures. Never infer success from copy completion alone.
- Compiler preprocessing/source mapping, invalid sketches, unsupported board/profile/library combinations, corrupt or missing WASM assets, bridge/ABI mismatches, workspace isolation, cancellation, runtime termination, cold/warm reuse, and stale-result/cache rejection.
- Artifact distinctions and binding: reject UF2-as-capsule mistakes, invalid ELF ranges/entry points, incompatible resident metadata, and capsule size/digest failures. Compare Firmingo package output with independent firmware vectors/validators rather than only SDK round trips.

Use fake transports, artifact providers, bootloader/filesystem backends, and a controllable clock. Ordinary tests must be deterministic, run without hardware or live network services, and avoid timing-sensitive sleeps. Package fixture resources explicitly and preserve their provenance.

Add real WASM compile/link integration tests using packaged FirmingoKit resources; mocked compiler tests alone are insufficient. Use pinned expected artifacts where reproducible, and independently validate format/ABI semantics when changing compiler recipes. Run adapted JavaScript/WASI tests from FirmingoKit's own tools directory, never from the read-only ArduinoKit checkout. Verify compilation inside a sandboxed macOS host and a physical iOS/iPadOS host. Track compiler support separately from USB installation and FMGO support.

Keep hardware tests opt-in and separate from ordinary test runs. Record exact board, firmware artifact hash/profile, SDK revision, host OS, procedure, and observations. Do not reuse another board's or firmware image's pass as qualification. Execute device-changing tests only within the requested hardware workflow.

Before claiming supported Firmingo installation, qualify it through an actual SDK host for each claimed board/platform pair: start with a supported board that is not running Firmingo, install the selected Firmingo release, connect, and exchange exact bytes. Qualify claimed Firmingo updates and documented recovery from an unavailable connection or interrupted operation on dedicated test hardware. Record remaining gaps separately; successful managed-sketch uploads do not qualify complete firmware installation. Arduino restoration is not an SDK acceptance criterion.

For each claimed Firmingo sketch-compilation target, also compile source through the SDK's actual WASM runtime, validate the artifact against the selected resident, upload it through the SDK, confirm startup and expected behavior, and repeat with a different sketch. Record exact compiler/recipe/asset/resident versions. ArduinoKit's reported UF2 hardware success does not satisfy this acceptance test.

## 8. Toolchain, platforms, and validation

### Baseline policy

- Keep Swift tools 6.4 and Swift 6 language semantics unless the task explicitly changes compatibility. Preserve the existing concurrency settings unless a documented correction is necessary.
- Xcode 27.0 with Apple Swift 6.4 was available when this proposal was written. Use it as the initial Apple-platform validation baseline; record the exact toolchain used. Other toolchains are not qualified merely by accepting the manifest.
- Declared minimum deployment targets are macOS 14 and iOS/iPadOS 17, aligned with the ArduinoKit compiler reference. These are build settings, not tested runtime or compiler support claims. Validate the full compiler runtime on supported hosts before advertising compilation support.
- Use availability checks for newer APIs. Do not raise platform minimums just to use the latest UI component. Do not promise older-runtime support based only on a build against the latest SDK.

### Commands and setup status

Run package commands from the repository root:

```sh
swift --version
xcodebuild -version
swift build
swift test
git diff --check
```

For iOS compilation, the committed validation workspace at `Validation/FirmingoKit.xcworkspace` references the local package and exposes a verified shared `FirmingoKit` scheme. Use:

```sh
xcodebuild -list -workspace Validation/FirmingoKit.xcworkspace
xcodebuild build \
  -workspace Validation/FirmingoKit.xcworkspace \
  -scheme FirmingoKit \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/xcode-simulator \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build \
  -workspace Validation/FirmingoKit.xcworkspace \
  -scheme FirmingoKit \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .build/xcode-device \
  CODE_SIGNING_ALLOWED=NO
```

These commands passed for the initial inspection increment; exact results and limits are in `docs/development.md`. For simulator tests, select an installed simulator from `xcodebuild -showdestinations` and record its ID in the actual test command; a generic destination cannot run tests.

Run package tests for behavioral changes, Apple-platform builds for platform/concurrency/dependency changes, and documentation generation for API/documentation changes. CI should exercise macOS tests, both iOS build destinations, and DocC generation once configured. Run focused checks first, then the applicable full checks; do not repeat unchanged successful checks without a reason.

The development-only Node/WASI recipe, resource validation, JavaScript tests and Swift capsule check are recorded in `Tools/ManagedWASM/README.md` and `docs/development.md`. When production compiler integration is implemented, record exact FirmingoKit-local commands for real-runtime Swift integration tests and sandbox host execution in `docs/compiler.md` and CI. The experimental WebKit integration and opt-in macOS tests are configured; approved service packaging, signed sandbox/physical-device qualification and CI remain open. A simulator compilation check and a device-target build do not replace physical-device compiler execution.

If setup, SDKs, permissions, or hardware are unavailable, report the exact blocked check and complete the independent checks. Do not claim that a proposed command passed. Prose-only changes require review of links, factual claims, commands, and diff hygiene, not new implementation tests.

## 9. Documentation and GitHub Pages

- Document every new or materially changed named declaration, including private types, properties, initializers, functions, and tests, using `///` comments. Describe responsibility and invariants rather than repeating the name. Ordinary local variables do not need symbol documentation.
- Public API documentation must explain behavior and, where relevant, parameters, units, returns, errors, cancellation, isolation, byte ordering, ownership, and required capabilities.
- Include practical sketch compilation, Firmingo installation/update/interruption recovery, connection, console, cleanup, and upload examples as those features exist. Document compiler recipes and Arduino API/library restrictions, artifact provenance, data preservation limits, required physical steps, and platform-specific execution support. State the host developer's ownership of any Arduino restoration feature without adding an SDK restoration tutorial. Clearly label experimental features and unknown outcomes. Keep examples compatible with the declared platform baseline.
- Keep implementation documentation in source. Publish the public library API and intentional guides; private comments do not imply that private symbols appear on the public site.
- Maintain one canonical rule set here rather than duplicating documentation instructions elsewhere.

References:

- [Writing symbol documentation](https://www.swift.org/documentation/docc/writing-symbol-documentation-in-your-source-files)
- [Swift-DocC plugin setup](https://github.com/swiftlang/swift-docc-plugin)
- [Generating documentation for hosting online](https://swiftlang.github.io/swift-docc-plugin/documentation/swiftdoccplugin/generating-documentation-for-hosting-online/)

When documentation tooling setup is in scope, add a reviewed, explicitly versioned Swift-DocC plugin dependency and record the tested version in `docs/development.md`. The plugin is not currently installed in this package. Keep generated output under `.build/`; do not mix it with authored Markdown in `docs/`.

For a GitHub Pages project site hosted under `/FirmingoKit/`, generate with:

```sh
swift package --allow-writing-to-directory .build/docc-site \
  generate-documentation --target FirmingoKit \
  --output-path .build/docc-site \
  --transform-for-static-hosting \
  --hosting-base-path FirmingoKit
```

Verify the actual Pages URL before configuring deployment. Change the base path to match that URL; omit the option for a site hosted at the domain root. The repository currently has no configured remote or verified Pages destination, so this path is a proposed hosting configuration.

Resolve documentation warnings introduced by the change. Preview the generated site under its intended base path and verify the library landing page, symbol links, assets, navigation, and examples. Configure Pages deployment to publish `.build/docc-site` as an artifact when publishing setup is requested; successful generation alone does not establish a working deployment.

## 10. Demo guidance — applies only when demo work is requested

Move detailed requirements into `docs/demo-design.md` and these UI conventions into `Demo/AGENTS.md` when creating the demo. Keep the root focused on SDK integration boundaries.

- Build a native document-based host for Arduino-style `.ino` files, with an editor and console. Treat roughly two-thirds editor and one-third console as initial proportions; allow resizing and smaller-screen adaptations.
- Show the selected/connected board and connection state. Provide Build and Run in platform-appropriate toolbars or menus. Provide a utility to install supported Firmingo images on new boards. Use macOS window/toolbars and keyboard commands, and iOS/iPadOS navigation patterns.
- Provide Install Firmingo and supported Firmingo update/recovery workflows backed by the SDK lifecycle APIs. Present the exact board, selected release/build, effect on existing data, physical steps, progress, verification result, and recovery options in plain language. Make bootloader-based Firmingo recovery reachable when Firmingo is disconnected or unresponsive; do not route it through managed-sketch Run. A Restore Arduino feature is not part of this repository's SDK demo requirements; a host-app developer may implement it separately.
- Build passes the document snapshot and selected board/profile to the SDK's WASM compiler and displays its structured diagnostics/progress. Run builds, validates a supported target/artifact, uploads through the SDK, reconciles the outcome, and opens the console when appropriate. A failed, cancelled, or stale build must prevent upload.
- Explain unavailable compilation or upload capabilities. Do not imply that choosing any `.ino` document guarantees a supported build. Use the SDK's local sandbox-compatible compiler on iOS/iPadOS; do not require an external CLI or silently send source to a remote build service.
- Distinguish installed, startup-confirmed, failed, and unknown outcomes in accessible UI. Do not present compile success or commit acceptance as successful execution.
- Use platform-native components supported by the minimum OS. Choose SwiftUI, AppKit, or UIKit by the actual interaction requirements. Keep UI frameworks out of the library.
- Use semantic system colors where possible. For custom colors, target Web Content Accessibility Guidelines (WCAG) 2.1 AA: at least 4.5:1 contrast for normal text, 3:1 for large text, and 3:1 for applicable essential non-text controls and graphics. Test light and dark appearances and increased contrast.
- Provide meaningful accessibility names, values, and state; avoid redundant labels on native controls. Support VoiceOver, logical focus order, keyboard operation, and status cues that do not depend only on color.
- Support Dynamic Type on iOS/iPadOS and scalable editor/console text on macOS. Respect reduced motion. Avoid flooding VoiceOver with every incoming console byte; provide controlled announcements and accessible review of output.
- Keep the UI responsive during high-volume console output through bounded presentation buffers and batched updates, with visible truncation when needed. Presentation truncation must not silently alter the SDK's byte-delivery contract.
- Add iCloud, Spotlight, notifications, or shortcuts only when requested or required by an accepted demo design.

## 11. Completion report

Before finishing an implementation task:

1. Verify the change meets the requested behavior and selected firmware contract.
2. Review public API, platform availability, resource lifetime, failure paths, and applicable protocol invariants.
3. Run the relevant tests, builds, and documentation checks above; inspect the final diff and new files.
4. Report what changed and why, the exact checks that passed, checks not run or blocked with reasons, and remaining compatibility or hardware limitations.

Do not describe unimplemented features, experimental evidence, or unrun validation as completed support.

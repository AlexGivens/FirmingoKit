# FirmingoKit — coding agent instructions

## 1. Mission and task scope

FirmingoKit is a reusable Swift SDK for host applications communicating with microcontrollers running Firmingo firmware. The intended host platforms are macOS and iOS/iPadOS. The initial firmware boards are Arduino Nano RP2040 Connect and Raspberry Pi Pico, with different capabilities and qualification status. Additional boards are expected to be added in time, with consistent support for upgrades and bug fixes in the firmware expected as well. 

The SDK must let a host app guide an end user through installing Firmingo for the first time and using its features. Initial Firmingo installation, supported Firmingo updates, communication, and managed-sketch upload are package responsibilities. These are requirements to implement and qualify, not claims of existing support.

Reverting a microcontroller to default Arduino firmware or a traditional Arduino build is outside FirmingoKit's scope. The host-app developer owns any explicitly scoped restoration orchestration, user interface, artifact selection, and verification. Conventional Arduino compiler recipes are a secondary Firmingo-Compiler responsibility, not an SDK restoration requirement. Do not add Arduino restoration APIs, bundled recovery images, restoration-specific compiler recipes, or restoration tests to this package. Firmingo installation must not depend on preparing an Arduino return path. Recovery within this document means recovering an interrupted Firmingo operation or reinstalling supported Firmingo firmware, not restoring Arduino firmware.

The SDK exposes local sketch-compilation APIs by wrapping Firmingo-Compiler's language-neutral WASM interface in a macOS/iOS/iPadOS-compatible web host. Firmingo-Compiler owns preprocessing, WASM execution, board recipes, ELF/capsule packaging, compiler diagnostics, and static build metadata. FirmingoKit owns Swift APIs/hosting adapters, resource access, device communication, installation, uploads, device associations, and deployment validation. Host apps supply source snapshots/selections and present results. Build execution now uses the imported compiler package. Public preparation and supplied-ELF conversion now delegate to the shared service-free worker, with preserved Swift receipts and independent deployment validation. Native lexical scanning, ELF parsing and capsule production are retired; see `docs/elf-packaging.md`. Preserve public type/receipt meaning during further migration. See [docs/compiler-migration.md](docs/compiler-migration.md).

- Implement the user's requested scope. Do not build the demo, add integrations, or implement a roadmap merely because this document describes them. Make companion changes only when needed for the authorized increment.
- Inspect relevant code, tests, and repository status before editing. Preserve unrelated work.
- ArduinoKit is reference-only: never edit its code or other files, regenerate its assets, run tools that write into its checkout, or change its Git state. Put adaptations and outputs in the repository owning that behavior. Do not introduce a runtime or build dependency on its checkout.
- The user authorizes this agent to work across FirmingoKit, Firmingo-Compiler, and Firmingo when the requested task requires it. Inspect each checkout's guidance/status and preserve unrelated work. Earlier read-only restrictions on Firmingo are superseded; ordinary SDK builds/tests must still use pinned imported contracts and packages without sibling checkout dependencies. Access does not authorize unrequested hardware actions or publication.
- Prefer the smallest cohesive implementation that satisfies the contract. Avoid speculative abstractions and dependencies.
- When a missing decision affects compatibility or observable behavior, explain it and request clarification while continuing independent work. Resolve routine implementation details using these instructions.
- Never equate a successful build, mocked test, or simulator run with hardware qualification.
- The user disabled visual inspection. Do not use screenshots, computer-use/native UI inspection, or ask to enable that capability. Validate through source review, deterministic tests, controller harnesses and builds; state the remaining UI/accessibility qualification limits.

## 2. Repository facts and proposed layout

On 2026-10-14 the exact reproduced Compiler service `a7648688…` passed scoped
paired-source/notice review and replaced the historical `3e2544ac…` consumer pin.
The imported fifty-source package is `4cbdf856…`, with four additional service
notice/provenance roles in the SDK's twelve-role inventory. No WASM binary or
source archive is bundled, the production descriptor catalogue stays empty, and
default builds report missing `compiler.wasm` instead of licensing-pending status.
Public private-origin/fresh-consumer checks are recorded in
`docs/compiler-delivery.md`; scoped signed macOS and physical iPad results are
recorded below. Minimum OS, iPhone and board deployment remain unqualified.
Older facts below are historical snapshots, not current pins.

The experimental consumer package now supplies exact Nano descriptor `c44d25ef…`
from Firmware `e0a79d1…`, catalogue `e341bfc0…`. Thirteen verified metadata roles
include `consumer-package.json`; inventory `e3c6080b…` replaces the empty-catalogue
inventory. `prepare-sdk-package.mjs` produces a clean SDK copy with the reviewed
binary in app resources and complete source/notices outside them. No binary is
committed or auto-downloaded. Source-checkout compilation still reports absent
`compiler.wasm`; default API execution belongs to the prepared package. Metadata
availability does not attest installed firmware or qualify hardware. See
`docs/compiler-package-provisioning.md` for the maintenance/consumer workflow.

`Validation/CompilerHost` and explicit generator/runner tools now exercise the
prepared SDK in a development-signed ARM64 macOS 27.0 Release app, sandbox and
hardened runtime verified. Six actual checks pass. Source CI runs six tiny tool
fixtures and warnings-as-errors type-checking without app execution or binaries.
The macOS app exports its own journal; do not request private-container/FDA or
visual inspection to collect it. See `docs/compiler-host-qualification.md`. Two
development-signed Release launches now pass all six checks on a physical 11-inch
iPad Pro (3rd generation), iPadOS 27.0.1. CoreDevice retrieves only this app's run
directories; `docs/compiler-host-ipad.json` records reports and independently
validated capsule bytes. Physical iPhone, minimum OS, total memory, forced
deadline/termination and device deployment remain unqualified.

Snapshot verified on 2026-09-30:

Ownership update on 2026-10-12: the snapshot below describes the existing implementation, not its future owner. The portable preparation/ELF/capsule and actual isolated Node/WASI path now exists in Firmingo-Compiler, with event/receipt contracts, an explicit-service CLI and local compile/link/disposal evidence. The default standard module-worker path now also passes nine headless Chrome 154.0.8037.93/macOS arm64/HTTP-loopback checks. The pinned source-only compiler package now passes nine actual macOS WebKit cases and a separate SwiftPM consumer; see `docs/compiler-adapter.md`. Signed/minimum-OS and physical iOS/iPadOS execution, other browsers and hardware remain unqualified. FirmingoKit retains its working APIs/resources until the migration gates pass; compiler-owned code/tests/assets move to Firmingo-Compiler, while Swift hosting and device safeguards stay here.

- `Package.swift` declares the `FirmingoKit` library and `FirmingoKitTests` test target, Swift tools 6.4, and `ApproachableConcurrency` for both targets. `Sources/FirmingoKit/Lifecycle/` provides bounded local complete-image acquisition, release/UF2 validation, artifact preflight, experimental macOS ROM programming with one-shot execution/durable record gates, and fresh-hello verification; hardware/sandbox qualification remains open.
- The package declares macOS 14 and iOS 17 deployment minimums. `Sources/FirmingoKit/` contains bounded FMGO framing, hello inspection, persistent serial sessions, experimental Nano FMS1/report validation and managed upload/reconciliation, and public domain models; `Tests/FirmingoKitTests/` uses Swift Testing and packaged pinned firmware vectors plus non-executable lifecycle parser fixtures. These workflows have no SDK hardware qualification.
- `Validation/FirmingoKit.xcworkspace` provides a shared package scheme. `Demo/FirmingoDemo.xcodeproj` is a separate native document app consuming the local package; it supports `.ino` editing, read-only device inspection, a live serial console, local Firmingo image/installation-plan review, explicit experimental macOS installation, and saved operation context/verification. Experimental Build/Run use SDK-filtered catalogue selections, device-independent compilation and separate reviewed associations, or explicit legacy resident records; durable managed journals and cross-window guards remain. The demo starts with SDK-owned catalogue loading and compiler-resource verification; explicit development catalogue/service sources remain available under advanced controls pending approved production resources. Explicitly saved per-device associations restore a bounded roster without automatic selection/trust; Run rechecks current saved evidence before compiler loading, and stale save/delete requests cannot overwrite newer records. Legacy descriptor migration is explicit. Programming, compilation, UI and restart behavior are not hardware/sandbox-qualified.
- A DocC overview and native Xcode documentation build are configured. No Swift-DocC plugin dependency is configured. A manual SDK CI workflow now exists; runner provisioning and a verified GitHub run remain open. `Demo/Shared/` exists; root `Mac/`, `iOS/`, and `Shared/` are not source directories.
- `Sources/FirmingoKit/Compiler/` provides immutable single-file source/target selection, bounded facade-only preprocessing with source diagnostics, and strict independently linked stateless Nano ELF-to-FMS1 packaging/receipts. `ManagedSketchCompiler` and `CompilerRuntime/` now provide experimental local WebKit/WASI compilation using packaged independently authored host/worker/recipe and licensed WASI shim resources. The exact memory-bounded service is host-supplied pending redistribution review; no qualified Clang/hardware recipe is claimed. Preparation and packaging alone do not compile source. Tests include non-executable compiler parser fixtures.
- `ManagedCompilerCatalogue` verifies bounded host-supplied metadata and exposes explicit experimental build choices; `ManagedFirmwareBuildDescriptor` separates static metadata from persistable `ManagedDeviceAssociation` evidence. `ManagedOfflineBuildRequest` and the experimental compiler/preprocessor/converter overloads produce device-independent artifacts/receipts with explicit association binding; legacy APIs/receipt schemas remain compatible. Shared source/ELF/FMS1 gates avoid fake device IDs. The demo exposes these APIs through imported development metadata; default SDK resource-loading APIs verify a bounded inventory and intentionally empty catalogue; default builds explicitly fail pending service review. Approved service/production descriptor packaging and normal bundled demo compilation remain open. Synthetic catalogue/offline fixtures are test-only, never deployment records.
- `Tools/ManagedWASM/` now owns the SDK-only native bridge, explicit source-package import, resource inventory/consumer/archive checks and Swift SDK validation entry point. Its old standalone Node/WASI/recipe/vendor stack and ELF-only decoder are retired with exact original hashes in `docs/compiler-retirement.json`. Portable execution, recipes, service maintenance and Node tests live in Firmingo-Compiler. Public preparation and conversion are shared-worker adapters; native ELF/capsule production is retired with exact hashes in `docs/elf-packaging-retirement.json`. No service is bundled; synthetic test outputs must never reach hardware.

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
| `docs/compiler.md` | Existing compiler implementation/evidence, wrapper integration, runtime limits, artifact contracts, and qualification |
| `docs/compiler-migration.md` | Pinned source inventory, extraction/retention map, ownership split, compatibility and staged acceptance gates |
| `docs/compiler-catalogue.md` | Accepted bundled-resource/catalogue design, offline build metadata, per-device association, implementation order, and acceptance gates |
| `docs/development.md` | Reproducible setup and validation commands |
| `docs/demo-design.md` | Demo product requirements when demo work begins |
| `Demo/` | Separate host app project; not a Swift package target |
| `Demo/AGENTS.md` | Demo-specific UI, accessibility, and platform instructions |

## 3. Firmware contract: read before implementing communication

Use the companion Firmingo repository at `../Firmingo` as the authoritative firmware-contract source when available. Otherwise use an explicitly supplied checkout or checksummed contract export. Do not embed developer-specific absolute paths in source or tests. Firmware implementation belongs in Firmingo; requested coordinated changes may be made there under the cross-repository authorization above.

Read these paths relative to that firmware checkout:

1. `docs/protocol.md`: authoritative wire format, schemas, limits, identity, ownership, and transaction behavior.
2. `docs/integration/managed-sketch-sdk.md`: SDK responsibilities, reference workflow, upload reconciliation, and experimental restrictions.
3. `docs/boards.md` and the relevant `boards/<board-id>/baseline.json`: board-specific configuration and qualification.
4. `tests/fixtures/protocol-v1/`, including `managed-upload/`: shared protocol vectors.
5. Referenced evidence and ABI/image headers when the requested feature depends on them.
6. `docs/releasing.md`, `docs/development.md`, and the applicable release manifest: initial installation artifacts, board matching, integrity checks, and existing flashing/recovery tooling.

For implementation details, inspect `src/core/protocol.h` and `protocol.cpp` for framing, `src/core/json.h` and `json.cpp` for JSON validation, `src/core/session.h` and `session.cpp` for session behavior, and `src/core/session_upload.cpp` for upload handling. The `experiments/managed_sketch/` recipe, ABI, and capsule files referenced in the compiler section provide the managed-build implementation reference. Read these sources to understand the selected contract; do not patch firmware behavior to accommodate an SDK implementation.

Because another agent may be changing this checkout, identify the commit and relevant file hashes used for each SDK change. Treat uncommitted reference changes as provisional and record them separately from the committed contract. Before relying on a set of files, verify that they form a consistent snapshot; use a pinned commit or supplied contract bundle when concurrent changes make that uncertain. Do not reset, stash, clean, switch branches, or otherwise disturb the other agent's work.

If SDK work needs a firmware or compiler change, document the affected contract, observed limitation, proposed behavior, compatibility implications, and acceptance tests. Implement coordinated changes in their owning repository when necessary for the authorized task, or record a handoff when deferred. Continue independent work without claiming missing capabilities exist. Messages to other agents/chats still require user authorization; cross-repository access alone does not authorize messaging.

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
| FirmingoKit | Swift compiler facade/web-host adapter, verified package loading, transport, framing, sessions, device associations, deployment validation, managed uploads, and Firmingo installation/update/interruption recovery |
| Firmingo-Compiler | Language-neutral preprocessing, web/WASM execution, board recipes, ELF/capsule packaging, compiler diagnostics, and static compiler/build metadata |
| IDE/demo | Documents and editing, source snapshots, board/build selection, calls to SDK compilation APIs, diagnostics/progress presentation, user decisions, and presentation of SDK-provided Firmingo installation/recovery steps |
| Host-app developer, outside this package | Any optional return to default Arduino firmware or a traditional Arduino build, implemented independently of FirmingoKit's feature requirements |
| Firmingo | Resident ABI/facade/layout, protocol/image contracts, verified firmware build facts, and device-side validation, authorization, execution, and installation |
| Board bootloader/ROM | Board-specific programming and recovery entry points that can operate without Firmingo |

- Keep the public API and business logic independent of SwiftUI, AppKit, UIKit, application lifecycle, and global UI state. An internal WebKit compiler host is permitted as a runtime implementation detail; do not expose `WKWebView` or require a host-provided visible view. It must be usable by another host app without the demo.
- Keep transport I/O, frame encoding/decoding, session state, and domain models separate. Pure codecs and injectable transport boundaries should support deterministic tests.
- Apply MVC to the demo where useful; do not force every library responsibility into a controller.
- The SDK's Swift facade invokes the shared compiler using verified versioned assets and explicit recipes, or accepts independently built Firmingo artifacts after deployment validation. During migration the existing implementation remains active. Firmingo installation/update requires an explicit host request. Normal app builds must not depend on a native Arduino CLI, compiler subprocess, shell, or external compiler installation. WASM toolchain/recipe maintenance belongs in Firmingo-Compiler; SDK package integration belongs here.
- Separate complete Firmingo firmware installation/update and bootloader-based reinstallation from FMGO managed-sketch upload. Share artifact validation and progress models where useful, but do not reuse incompatible transfer protocols or success criteria.
- Separate artifact acquisition, board/bootloader discovery, installation backends, and lifecycle state management. Inject these boundaries for testing. Keep platform-specific device and filesystem access behind explicit backend capabilities.
- Keep implementation symbols internal or private unless callers need them. Document public behavior and review source compatibility before changing public APIs.

### Compiler migration, hosting, and artifact contracts

The ownership split accepted on 2026-10-12 supersedes the former SDK-owned compiler plan. Follow [docs/compiler-migration.md](docs/compiler-migration.md) for the inventory, compatibility gates, and staged extraction. [docs/compiler-adapter.md](docs/compiler-adapter.md) records the active shared-compiler build facade; [docs/compiler-catalogue.md](docs/compiler-catalogue.md) defines the revised catalogue/wrapper boundary. The source package and runtime/inventory anchors are intentionally replaced by the tested adapter; public build APIs, native receipt schemas and historical records retain their meaning. Compatibility preparation/conversion APIs remain available.

ArduinoKit remains a read-only reference. Its inspected commit is `0eb3cd1841147dfc7ea25bf076545e38b01601e4`; reported conventional Nano UF2/macOS/iPad results do not qualify Firmingo capsules. Relevant reference paths/provenance remain in `docs/compiler.md`. Reference access creates no runtime dependency. Portable adaptations and toolchain/license review belong in Firmingo-Compiler; Swift host adaptations belong here.

- Preserve the public async Swift compiler facade where practical. Translate immutable source/revision, explicit target/build descriptor, and supported options into the portable interface; translate structured progress, diagnostics, artifacts, and receipts back into SDK types. Do not expose WebKit objects or require a visible view.
- Keep Swift actor isolation, WebKit navigation/resource access, bridge validation, content-process cleanup, cancellation propagation, and platform lifecycle integration here. Firmingo-Compiler owns WASI workers, workspace isolation, actual pipeline stages, execution limits, and source-to-artifact validation. Both boundaries enforce their own limits and reject stale results.
- Keep compilation device-independent. Static descriptors come from compiler recipes paired with verified firmware exports; physical-device IDs, associations, installation evidence, and upload authorization never become mandatory compiler inputs. Adapt legacy device-bound APIs explicitly without fabricating identity or changing persistence silently.
- Firmware is authoritative for ABI/facade behavior, memory layout, image format, and device capabilities. The compiler owns compatible recipes. Preserve explicit Nano ID mapping (`arduino_nano_rp2040_connect` in the historical reference versus `nano_rp2040_connect` in Firmingo). Unsupported boards/profiles/libraries remain unavailable; Pico managed support is not established by sharing RP2040.
- Keep complete-firmware UF2 distinct from managed FMS1 capsules. Retain SDK-side capsule/report validation, exact descriptor/device binding, source-revision checks, and fresh capability checks before deployment. A compiler success, digest, catalogue match, or hello does not attest installed firmware or authorize writes.
- Consume a pinned versioned compiler asset package with sizes/hashes, interface/service/recipe versions, descriptors, and notices. SDK resource discovery, trusted anchors, and package-consumer verification stay here. The compiler builds/packages its assets; do not independently edit a staged recipe or runtime copy in SDK resources.
- Keep default compilation offline after approved assets are provisioned. No native compiler, Node, shell, sibling checkout, or remote fallback belongs in a consumer build. Preserve the current explicit development-service path, empty default catalogue, and pending-service errors until approved replacements exist.
- Keep the compiler-service redistribution/provenance status unresolved until documented evidence changes it. Firmingo-Compiler leads that review and asset production; FirmingoKit verifies the selected package and Apple-host distribution behavior. Do not bundle unreviewed binaries or synthetic production descriptors to remove the blocker.
- Port compiler-owned tests to the new repository and retain them here until replacements pass. Swift bridge/WebKit, resource loading, public API, device association, installation, and upload tests remain here. Independent deployment validation is intentional, not a duplicate compiler implementation.

### Catalogue, demo, and wrapper qualification

The user-facing self-contained offline Build direction accepted on 2026-09-30 remains. Its implementation ownership changed on 2026-10-12: Firmingo exports verified resident facts, Firmingo-Compiler creates compatible static descriptors/catalogues and build receipts, and FirmingoKit loads/translates them and manages real-device associations. Default SDK APIs still have their documented empty/pending behavior; this guide does not claim migration completion.

- Provide SDK queries and explicit supported/experimental/unavailable reasons from verified compiler metadata. The demo consumes those APIs without maintaining its own recipes, compiler assets, or compatibility registry.
- Keep immutable firmware-build descriptors separate from persisted device evidence and upload journals. Descriptor integrity does not authenticate a publisher or attest installed bytes. Restore context without granting trust, selecting latest, or replaying writes.
- Offline Build selects an exact compatible descriptor without a connected board. Run separately validates current source/selection, real association, fresh capabilities, durable journals, one commit, uncertainty, and process-local device-operation guards.
- Keep imports and legacy compatibility as explicit development/setup paths; errors never trigger silent fallback or resident replacement. Unsupported Pico managed Build/Run remains unavailable.
- Verify actual shared-compiler execution through signed macOS and physical iOS/iPadOS hosts, including cold/warm duration, memory, package size, minimum OS, cancellation, and fresh subsequent builds. Qualify hardware deployment separately. Simulator/device-target builds do not establish runtime or hardware support.

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

Add real shared-compiler integration tests through the SDK web host; mocked tests alone are insufficient. Portable recipe/runtime/packaging tests move to Firmingo-Compiler after their replacements pass; existing SDK-local JavaScript/WASI checks remain active during transition. Keep independent deployment validators and pinned expected artifacts. Never run writing tools in ArduinoKit. Verify compilation inside a sandboxed macOS host and a physical iOS/iPadOS host. Track compiler support separately from USB installation and FMGO support.

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

Current SDK resource, Swift adapter, independent capsule and optional WebKit checks are documented in `Tools/ManagedWASM/README.md` and `docs/compiler-retirement.md`. Portable Node/WASI recipe/runtime tests and service maintenance are owned by Firmingo-Compiler; older `docs/development.md` commands remain dated historical records. When production compiler integration is implemented, record exact FirmingoKit-local commands for real-runtime Swift integration tests and sandbox host execution in `docs/compiler.md` and CI. The experimental WebKit integration and opt-in macOS tests are configured; approved service packaging and signed sandbox/physical-device qualification remain open. Manual CI definitions now exist in `.github/workflows/adapter.yml`; runner provisioning and a verified GitHub run remain open. A simulator compilation check and a device-target build do not replace physical-device compiler execution.

If setup, SDKs, permissions, or hardware are unavailable, report the exact blocked check and complete the independent checks. Do not claim that a proposed command passed. Prose-only changes require review of links, factual claims, commands, and diff hygiene, not new implementation tests.

## 9. Documentation and GitHub Pages

- Document every new or materially changed named declaration, including private types, properties, initializers, functions, and tests, using `///` comments. Describe responsibility and invariants rather than repeating the name. Ordinary local variables do not need symbol documentation.
- Public API documentation must explain behavior and, where relevant, parameters, units, returns, errors, cancellation, isolation, byte ordering, ownership, and required capabilities.
- Include practical sketch compilation, Firmingo installation/update/interruption recovery, connection, console, cleanup, and upload examples as those features exist. Document consumption of compiler recipes and their declared Arduino API/library restrictions, artifact provenance, data preservation limits, required physical steps, and platform-specific execution support. State the host developer's ownership of any Arduino restoration feature without adding an SDK restoration tutorial. Clearly label experimental features and unknown outcomes. Keep examples compatible with the declared platform baseline.
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

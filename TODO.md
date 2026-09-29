# FirmingoKit project checklist

Implementation and qualification roadmap based on [AGENTS.md](AGENTS.md). That file remains the canonical source of project rules. Work through the dependencies below; this checklist does not authorize flashing hardware, modifying reference projects, or publishing releases.

## Starting point — inspected 2026-09-29

- [x] Inspect the package manifest, starter source/test, repository status, and project instructions.
- [x] Create this implementation roadmap.
- The package currently contains a `hello()` placeholder and an empty Swift Testing example. It declares Swift tools 6.4 and `ApproachableConcurrency` for both targets.
- Platform minimums, a demo, a validation workspace, documentation tooling, CI, and a Git remote are not configured. No SDK behavior or hardware support has been qualified.
- Firmware and compiler revisions mentioned in `AGENTS.md` are reference provenance, not selected or verified SDK compatibility. Select consistent snapshots before implementation.

Mark implementation tasks complete only with relevant checks and evidence. Record blocked tasks with their dependency and next action; do not mark an unavailable feature as implemented because it returns an unsupported error. Keep support status separate for each board, firmware profile, host platform, and operation.

## 1. Establish contracts, scope, and acceptance criteria

- [ ] Inspect Firmingo and ArduinoKit in place, read-only. Record full commits and relevant local differences; use pinned committed files or a checksummed contract bundle when concurrent changes prevent a consistent snapshot.
- [ ] Read Firmingo's protocol, managed-sketch SDK handoff, board baselines, release/development guidance, applicable release manifests, protocol/upload fixtures, and relevant implementation/evidence identified in `AGENTS.md`.
- [ ] Create `docs/firmware-compatibility.md` with the selected firmware revision, protocol major, profiles, relevant file/fixture checksums, and provisional changes kept separate from committed evidence.
- [ ] Build a capability and qualification matrix for Nano RP2040 Connect and Raspberry Pi Pico on macOS and iOS/iPadOS. Track communication, initial installation, updates, interruption recovery, compilation, and managed upload independently.
- [ ] Recheck release versus experimental capabilities, application versus UART behavior, managed target availability, and physical authorization requirements. Keep unsupported combinations explicit; do not infer Pico support from Nano evidence.
- [ ] Define first-release acceptance criteria against that matrix, including experimental labels and deferred firmware dependencies. Preserve the longer-term board/platform requirements as open work.
- [ ] Resolve contract conflicts before implementing affected behavior. Write firmware handoffs inside FirmingoKit with the limitation, proposed contract, compatibility effect, and acceptance tests; coordinate with the firmware agent only when authorized.
- [ ] Establish fixture import/provenance conventions so tests and builds never depend on sibling checkouts. Keep all adaptations, tools, assets, and validation outputs inside FirmingoKit.

**Gate:** The selected contract and intended support matrix are explicit. Missing firmware capabilities are tracked dependencies rather than invented SDK behavior.

## 2. Configure package and reproducible validation

- [ ] Keep Swift tools 6.4, Swift 6 semantics, and the existing concurrency settings; record the exact Xcode 27.0/Swift toolchain used for baseline validation.
- [ ] Declare macOS 14 and iOS/iPadOS 17 minimums in `Package.swift`; track runtime qualification separately from these build settings.
- [ ] Replace starter code/tests as real functionality lands. Organize implementation by responsibility within the library target, creating directories only when needed.
- [ ] Configure SwiftPM resources for selected fixtures and, later, verified compiler assets. Verify resource loading in package consumers and archive/distribution builds.
- [ ] Create `Validation/FirmingoKit.xcworkspace` referencing the local package with a verified shared `FirmingoKit` scheme. Commit reproducible configuration and verify it with `xcodebuild -list`.
- [ ] Create `docs/development.md` with setup, `swift build`, `swift test`, simulator/device build commands, concrete simulator test selection, documentation generation, and output locations under `.build/`.
- [ ] Establish baseline macOS package tests and generic iOS Simulator/iOS device builds using the commands in `AGENTS.md`. Record unavailable SDKs or setup blockers accurately.
- [ ] Configure CI for macOS tests, both iOS build destinations, and DocC generation as each workflow becomes available; add compiler checks when its tooling exists.

**Gate:** A fresh checkout can build and run deterministic tests without reference repositories, hardware, or live network services.

## 3. Define SDK boundaries and common models

- [ ] Define explicit board/profile, protocol/capability, device/boot identity, artifact, progress, and outcome models where needed. Keep complete Firmingo images distinct from managed capsules.
- [ ] Define injectable transport, clock, artifact-provider, programming-backend, and compiler boundaries alongside their first consumers; avoid speculative abstractions.
- [ ] Expose `async throws` operations and bounded event/byte sequences with documented buffering, backpressure, cancellation, termination, and ownership.
- [ ] Define errors that distinguish transport failures, protocol violations, device rejection, unsupported capabilities, cancellation, and uncertain outcomes; retain underlying causes and firmware codes.
- [ ] Design actor isolation, ordered transport reading, task lifetimes, deadlines, and serialization of device-changing operations. Review reentrancy across suspension points.
- [ ] Keep public APIs independent of UI frameworks and global application state. Keep WebKit compiler hosting internal and usable without a visible host-supplied view.
- [ ] Document named declarations and public behavior as implementation lands, following `AGENTS.md`; review API visibility, `Sendable` correctness, and source compatibility.

**Gate:** A host can own presentation and user decisions while the SDK owns compilation, communication, and Firmingo lifecycle logic.

## 4. Implement protocol framing and payload validation

- [ ] Import selected firmware golden vectors as SwiftPM test resources with provenance and checksums.
- [ ] Implement explicit binary framing and byte order, validating fields and negotiated limits before collecting or allocating payload storage.
- [ ] Implement incremental decoding for every header/payload split, coalesced frames, and retained trailing bytes. Apply terminal protocol-error behavior without invented resynchronization.
- [ ] Implement JSON request/response/domain validation beyond synthesized `Codable`, including required fields, permitted values, bounds, and error envelopes.
- [ ] Test golden bytes, boundary values, invalid headers/payloads, oversized lengths, malformed JSON, terminal errors, and exact preservation of zero bytes and invalid UTF-8.

**Gate:** Codec behavior matches independent firmware vectors; encoder/decoder round trips are supplementary evidence only.

## 5. Implement transport, sessions, and console operations

- [ ] Implement the Apple-platform TCP transport and deterministic fake transport. Start with explicit numeric endpoint selection; do not invent Bonjour discovery or treat an IP address as identity.
- [ ] Perform hello once per connection and validate device identity, protocol, backend, limits, and capabilities before permitting operations.
- [ ] Implement request IDs/correlation, bounded pending requests and deadlines, one ordered reader, and independent handling of interleaved control responses and serial data.
- [ ] Implement capability-gated channel acquisition/release, console opening/closing, supported serial controls, and other selected contract operations. Return explicit unsupported failures for unavailable controls.
- [ ] Preserve partial writes and bounded backpressure. Deliver serial bytes losslessly; leave text interpretation, newline conversion, and display buffering to the host.
- [ ] Implement cancellation, disconnect cleanup, ownership release where possible, and task/pending-request resolution. Every reconnection creates a fresh session/decoder without replaying commands or serial data.
- [ ] Test empty/populated capabilities, ownership rejection, interleaved replies, partial writes, slow consumers, bounds, deadlines, cancellation, disconnects, and fresh-session behavior using a controllable clock.
- [ ] Validate macOS and iOS/iPadOS host networking permissions and lifecycle behavior, recording platform-specific restrictions.

**Gate:** A host can connect, validate capabilities, exchange exact bytes, and clean up reliably through documented APIs.

## 6. Implement Firmingo installation, updates, and interruption recovery

This track can progress alongside communication after contract selection. Initial installation and bootloader reinstallation must work without an existing Firmingo connection; post-install verification depends on the session API.

- [ ] Create `docs/firmware-lifecycle.md` with versioned manufacturer programming references, selected Firmingo release provenance, supported backends, and separate Nano ROM/Pico BOOTSEL procedures.
- [ ] Define the effect of each supported operation on firmware, sketches, settings, filesystems, and flash regions. Do not promise unimplemented preservation, backup, rollback, or NINA firmware updates.
- [ ] Implement artifact acquisition and validation against exact board/profile/version/byte count/SHA-256 metadata, trusted release sources, and signatures when provided.
- [ ] Validate artifact format, flash addresses, ranges, and layout for each backend. Reject wrong-board, corrupt, missing, or incompatible images before any write.
- [ ] Implement board/bootloader discovery behind platform capabilities. Handle multiple devices, ambiguous identities, filesystem access, and permissions; a shared family ID or `RPI-RP2` label is insufficient selection evidence.
- [ ] Produce a reviewable preflight plan bound to the selected board and artifact, including prerequisites, affected data, required physical actions, verification limits, and interruption recovery steps.
- [ ] Require an explicit host execution request for that plan. Revalidate selection after re-enumeration, close active sessions, and serialize device-changing operations.
- [ ] Implement supported programming backends with real progress, documented cancellation boundaries, and distinct transfer, reboot, verification, failure, and uncertain states.
- [ ] Verify reconnection through hello against expected board/profile/capabilities and report exact-image identity limits. Do not infer success from a completed copy or disappearing volume.
- [ ] Expose a persistable operation record preserving the plan, artifacts, observations, and recovery context across disconnects/restarts without implying resumable flashing.
- [ ] Implement qualified update and supported Firmingo reinstall/recovery paths. Require a new host action after uncertain results; do not blindly repeat writes.
- [ ] Report unsupported direct execution on each platform and provide guided Firmingo transfer/recovery only where supported, clearly distinguished from automated flashing.
- [ ] Test preflight/write prevention, ambiguous targets, re-enumeration, permission denial, expected/unexpected disconnects, cancellation, saved-record recovery, and verification failure with fake providers/backends.

**Gate:** Plans and execution are separate, unsafe inputs cannot reach a writer, and interrupted operations preserve actionable context without false success claims.

## 7. Adapt the local WASM compiler

- [ ] Read the ArduinoKit compiler API, preprocessor, runtime, manifest/verifier, resource handler, build recipe, bridge/worker, service/staging tools, ELF/UF2 code, and integration tests listed in `AGENTS.md`.
- [ ] Create `docs/compiler.md` recording the selected ArduinoKit commit, relevant local differences, adapted files, asset hashes, licenses/attribution, and reproducible FirmingoKit-local maintenance commands.
- [ ] Define immutable build inputs: source snapshot/revision, board/profile, supported dependencies/options, and required resident binding. Return source-mapped diagnostics, phase progress, typed artifacts, and a build receipt.
- [ ] Support offline target/resident descriptions. Ensure compilation never connects to or modifies a board.
- [ ] Adapt preprocessing with documented sketch layouts, source mapping, supported Arduino APIs/libraries, and actionable rejection of unsupported constructs.
- [ ] Implement an explicit board/profile recipe registry defining CPU/triple, facade/core, headers/libraries, flags, linker script, memory limits, artifact format, and ABI requirements. Map ArduinoKit/Firmingo Nano identifiers explicitly.
- [ ] Inspect Firmingo's selected managed-build recipe, linker script, module entry, facade, ABI, and image headers. Establish Clang/LLD compatibility independently of the reference GCC proof.
- [ ] Bind managed code to exact verified resident ABI/API metadata; reject missing/incompatible bindings without guessing addresses or deriving ELF identity from hello.
- [ ] Package verified host-page, compiler-module, sysroot, and recipe assets within FirmingoKit with versioned service ABI, sizes, and hashes. Include reproducible staging/service build scripts and receipts.
- [ ] Implement isolated local WebKit/WASI workers, read-only asset access, and separate writable build workspaces. Validate bridge messages, bound outputs, and reject path traversal, unsafe archives, and unsupported arguments.
- [ ] Keep WebKit interactions on the main actor and expensive hashing/unpacking/conversion off UI execution. Restrict resource loads to intended local assets.
- [ ] Implement verify → preprocess → compile → link → validate → package with real phase progress and structured failures; no runtime shell, compiler subprocess, remote service, or sibling-checkout dependency.
- [ ] Serialize builds per runtime or isolate jobs; implement timeouts, cancellation, worker termination, content-process recovery, and safe warm reuse.
- [ ] Reject stale results using source revision/build identity. If caching is introduced, key it on every source, dependency, recipe, toolchain, and resident-binding input.
- [ ] Validate linked ELF ranges/entry points and generate the selected Nano `nano-managed-v1` FMS1 `.fms` capsule with required size, digests, entry points, and build report. Never wrap conventional UF2 output as a managed capsule.
- [ ] Keep Pico and other missing managed recipes explicitly unavailable until their firmware target, recipe, and independent qualification exist; do not silently replace resident firmware to enable Run.
- [ ] Add preprocessing, diagnostic mapping, missing/corrupt asset, bridge/ABI, workspace isolation, invalid ELF/capsule, cancellation, crash/reentry, and stale-result tests.
- [ ] Add actual WASM compile/link integration tests using packaged resources and FirmingoKit-local JavaScript/WASI tests. Compare artifact semantics against independent firmware vectors/validators.
- [ ] Measure cold/warm build duration, peak memory, and package size in sandboxed macOS and physical iOS/iPadOS hosts, including the claimed minimum OS versions.

**Gate:** Supported source compiles locally through the actual runtime to independently validated Firmingo artifacts. Mocked tests and ArduinoKit's conventional UF2 results do not establish this gate.

## 8. Implement managed upload and reconciliation

Artifact validation and upload can start with independently built, validated executable capsules while the compiler is under development. Firmware parser fixtures must never be uploaded to hardware.

- [ ] Validate advertised target, board, format, size, digest, build metadata, and resident/ABI binding before starting a transaction.
- [ ] Close the console, respect ownership and physical authorization, and implement the selected transaction/chunk protocol with negotiated limits and exact offset/state validation.
- [ ] Expose transfer, verification, commit acceptance, installation, startup confirmation, failure, and unknown outcome separately.
- [ ] Send commit exactly once. Reconcile a lost reply by querying status on a freshly validated connection; never automatically resend commit.
- [ ] Match device ID, boot ID, transaction ID, size, and digest during reconciliation. Treat changed boots, superseded records, and insufficient evidence as unknown outcomes.
- [ ] Inspect transaction state/error fields even inside successful envelopes. Preserve uncertainty after cancellation/disconnection following commit and require a new host action before another upload.
- [ ] Test rejected metadata, ownership/authorization failures, chunk boundaries, failed transactions, timeouts/disconnects before and after commit, exactly-one-commit behavior, and reconciliation mismatches.

**Gate:** The SDK cannot confuse accepted transfer/commit with installed and running code, or automatically repeat an uncertain transaction.

## 9. Build the native demo host

- [ ] Define the accepted product flow in `docs/demo-design.md`; move demo-specific UI conventions into `Demo/AGENTS.md` when creating the app, keeping root instructions focused on SDK boundaries.
- [ ] Create a separate native document-based Xcode app under `Demo/`, consuming the local package rather than becoming a package target. Configure macOS and iOS/iPadOS schemes, signing, sandbox, and required permissions.
- [ ] Implement `.ino` document creation/open/save, editing, immutable build snapshots, source revisions, and selected board/profile state.
- [ ] Build an adjustable editor/console layout starting near two-thirds/one-third, adapted for smaller screens, with visible selected/connected board and connection state.
- [ ] Add native Build/Run commands, platform-appropriate toolbars/menus/navigation, keyboard actions, structured diagnostics, source locations, progress, and cancellation.
- [ ] Make Build invoke the SDK compiler. Make Run build, reject failed/cancelled/stale output, validate the selected target, upload, reconcile, and open the console when appropriate.
- [ ] Present unsupported targets and experimental restrictions clearly; distinguish build success, installation, startup confirmation, useful behavior, failure, and uncertainty.
- [ ] Add Install Firmingo and supported update/recovery flows presenting the SDK plan, exact target/release, affected data, user actions, progress, verification, and recovery choices. Keep bootloader recovery reachable while disconnected.
- [ ] Add console input/output presentation with explicit text settings, bounded display buffers, batched updates, and visible truncation without altering SDK byte delivery.
- [ ] Validate VoiceOver, focus order, keyboard access, Dynamic Type/scalable text, reduced motion, light/dark/increased contrast, non-color status cues, and controlled console announcements.
- [ ] Test document edits during compilation, repeated commands, disconnects, cancellation, uncertain outcomes, and app restart with saved lifecycle context.
- [ ] Keep the demo limited to Firmingo workflows. The isolated default-Arduino wording in root demo guidance must be reconciled with the explicit package/demo exclusion when moving that guidance; do not add restoration functionality.

**Gate:** The demo exercises reusable SDK APIs for the intended journey without duplicating compiler, protocol, upload, or flashing logic.

## 10. Qualify real hosts, boards, and failure recovery

- [ ] Maintain opt-in hardware procedures and evidence separate from deterministic tests; execute device-changing tests only within an authorized hardware workflow.
- [ ] Record board model/revision, firmware artifact hash/profile, resident metadata, SDK revision, compiler/recipe/assets, host OS/toolchain, procedure, observations, and unresolved limitations for each run.
- [ ] For every claimed board/platform installation pair, use an actual SDK host to install supported Firmingo on a board not running Firmingo, reconnect, and exchange exact bytes.
- [ ] Qualify supported updates and documented recovery from an unavailable connection and interrupted operations on dedicated hardware, including ambiguous device selection and post-reboot identity checks.
- [ ] For every claimed compilation/upload target, compile through the actual SDK WASM runtime, validate binding, upload through the SDK, confirm startup and expected behavior, then repeat with a different sketch.
- [ ] Exercise console load/backpressure, ownership contention, malformed input, network loss, lost commit replies, cancellation, and unknown outcomes in the relevant real-host workflows.
- [ ] Qualify sandbox/filesystem/entitlement/device-access requirements on macOS and physical iOS/iPadOS hosts independently. Device-target builds and simulator tests are not physical-device evidence.
- [ ] Update the support matrix with implemented, experimental, qualified, unsupported, and blocked status backed by evidence. Keep platform builds, compiler execution, USB installation, and FMGO capabilities separate.

**Gate:** Every advertised support claim has evidence for its exact board/profile/platform combination; remaining requirements stay open or explicitly deferred.

## 11. Complete documentation and release tooling

- [ ] Write a README covering purpose, package integration, supported/experimental combinations, demo setup, and links to the detailed guides.
- [ ] Create `Sources/FirmingoKit/FirmingoKit.docc/` with an overview and working examples for compilation, installation/update/recovery, connection, console, cleanup, and managed upload as those APIs exist.
- [ ] Document capability requirements, cancellation/ownership, artifact provenance, source restrictions, data-preservation limits, required physical steps, and uncertain outcomes. Keep Arduino restoration outside SDK tutorials.
- [ ] Add a reviewed, explicitly versioned Swift-DocC plugin and record its tested version and generation commands in `docs/development.md`.
- [ ] Generate documentation under `.build/`, resolve introduced warnings, and verify public symbol links, examples, navigation, and assets.
- [ ] Establish the intended Git remote and verify the actual GitHub Pages destination before configuring deployment. Use `/FirmingoKit/` only if it matches that destination.
- [ ] Preview static documentation under its intended base path and configure CI artifact publication/deployment when publishing is requested; verify the deployed site separately from generation.
- [ ] Audit third-party asset licenses, attribution, resource integrity, versioned recipes, and reproducible toolchain maintenance. Verify a clean package/demo consumer needs no sibling checkouts or native compiler installation.
- [ ] Define versioning, compatibility/deprecation policy, changelog, release checks, and the process for adding boards or updating firmware contracts and compiler assets together with tests.

**Gate:** A new host-app developer can integrate the package using published APIs and accurate documentation, with reproducible assets and clearly stated limitations.

## 12. Final acceptance and ongoing maintenance

- [ ] Review the complete supported journey: select board → install Firmingo → connect → build supported source → upload → confirm behavior → use console → update/recover when needed.
- [ ] Run the applicable package tests, Apple-platform builds, real WASM integration/JavaScript tests, documentation generation, demo checks, and opt-in hardware acceptance procedures. Record exact commands and results.
- [ ] Review API compatibility, concurrency/resource lifetimes, cancellation/failure paths, artifact security boundaries, protocol invariants, and accessible demo behavior.
- [ ] Reconcile this checklist and all compatibility/lifecycle/compiler documentation with delivered behavior. Record blocked checks and remaining dependencies without declaring them complete.
- [ ] Update the repository facts in `AGENTS.md` as structure changes; inspect final diffs and run `git diff --check` for each implementation increment.
- [ ] Prepare a release only when its declared scope meets the acceptance gates; list experimental features and unqualified board/platform combinations explicitly.
- [ ] For later firmware fixes, upgrades, or additional boards, pin the new contract/artifacts, update fixtures and recipes, review compatibility, and repeat the affected qualification matrix before expanding support claims.

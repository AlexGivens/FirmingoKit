# FirmingoKit project checklist

Implementation and qualification roadmap based on [AGENTS.md](AGENTS.md). That file remains the canonical source of project rules. Work through dependencies without treating this checklist as authorization for hardware or publication. Requested coordinated work may touch FirmingoKit, Firmingo-Compiler, and Firmingo; ArduinoKit stays read-only.

## Current position — compiler split, 2026-10-12

Ownership guidance, integration documents, and the [migration inventory](docs/compiler-migration.md) are refocused. Both SDK build APIs now delegate to the pinned shared compiler package; public preparation/conversion compatibility APIs remain. Fixture manifests and stored records are retained. Completed compiler entries below record earlier SDK implementation, not completion in Firmingo-Compiler. Compiler-only backlog now belongs to that repository's M1–M7/M9 milestones; SDK hosting, package consumption, public API/persistence, associations, installation, and upload checks remain here.

Firmingo-Compiler now has a pinned Nano baseline, portable request/preprocessing/
ELF/FMS1 stages, unchanged recipe assets, and a distinct independent-packaging
receipt with golden tests. The real isolated Node/WASI path, event/receipt contract
and explicit-service CLI now pass local compile/link/failure/disposal tests. The
standard module-worker path also passes nine headless Chrome/HTTP-loopback cases;
the macOS SDK WebKit adapter also passes nine actual cases and a separate packaged consumer; signed/physical Apple-host and other browser execution remain open.
See its `docs/interface.md`, `docs/portable-pipeline.md` and
`docs/compatibility.md` for implemented versus proposed behavior.

The old SDK standalone Node compiler and ELF-only bridge are retired, with traceable source hashes in `docs/compiler-retirement.json`. Both preparation and conversion overloads now delegate to the shared service-free worker; native lexical scanning, ELF parsing and capsule production are removed while receipts/deployment validators remain. See `docs/elf-packaging.md` and its retirement inventory. Next: qualify signed/physical Apple hosts and provision SDK CI. Exact firmware exports and approved service assets
remain dependencies, not reasons to weaken deployment checks.

## Starting point — inspected 2026-09-29

- [x] Inspect the package manifest, starter source/test, repository status, and project instructions.
- [x] Create this implementation roadmap.
- At kickoff the package contained a `hello()` placeholder and an empty Swift Testing example. It declared Swift tools 6.4 and `ApproachableConcurrency` for both targets.
- At kickoff platform minimums, a demo, validation workspace, documentation tooling, CI, and Git remote were absent. The first inspection increment and its checks are recorded in `docs/development.md`; no hardware support has been qualified. CI, DocC plugin, and Git remote remain open.
- Firmware and compiler revisions mentioned in `AGENTS.md` are reference provenance, not selected or verified SDK compatibility. Select consistent snapshots before implementation.

Mark implementation tasks complete only with relevant checks and evidence. Record blocked tasks with their dependency and next action; do not mark an unavailable feature as implemented because it returns an unsupported error. Keep support status separate for each board, firmware profile, host platform, and operation.

## 1. Establish contracts, scope, and acceptance criteria

- [ ] Select consistent Firmingo and Firmingo-Compiler inputs for each implementation increment; record full commits/local differences or checksummed bundles. ArduinoKit remains read-only. The initial split inventory is recorded in section 7.2 without selecting a new protocol compatibility baseline.
- [ ] Read Firmingo's protocol, managed-sketch SDK handoff, board baselines, release/development guidance, applicable release manifests, protocol/upload fixtures, and relevant implementation/evidence identified in `AGENTS.md`.
- [x] Create `docs/firmware-compatibility.md` with the selected firmware revision, protocol major, profiles, relevant file/fixture checksums, and provisional changes kept separate from committed evidence.
- [x] Build a capability and qualification matrix for Nano RP2040 Connect and Raspberry Pi Pico on macOS and iOS/iPadOS. Track communication, initial installation, updates, interruption recovery, compilation, and managed upload independently.
- [x] Recheck release versus experimental capabilities, application versus UART behavior, managed target availability, and physical authorization requirements. Keep unsupported combinations explicit; do not infer Pico support from Nano evidence.
- [ ] Define first-release acceptance criteria against that matrix, including experimental labels and deferred firmware dependencies. Preserve the longer-term board/platform requirements as open work.
- [ ] Resolve contract conflicts before implementing affected behavior. Record limitation, proposed behavior, compatibility effect and acceptance tests; make requested changes in the owning repository or document a deferred handoff. Messages to other agents/chats require user authorization.
- [x] Establish fixture import/provenance conventions so tests and builds never depend on sibling checkouts. Keep all adaptations, tools, assets, and validation outputs inside FirmingoKit.

**Gate:** The selected contract and intended support matrix are explicit. Missing firmware capabilities are tracked dependencies rather than invented SDK behavior.

## 2. Configure package and reproducible validation

- [x] Keep Swift tools 6.4, Swift 6 semantics, and the existing concurrency settings; record the exact Xcode 27.0/Swift toolchain used for baseline validation.
- [x] Declare macOS 14 and iOS/iPadOS 17 minimums in `Package.swift`; track runtime qualification separately from these build settings.
- [x] Replace starter code/tests as real functionality lands. Organize implementation by responsibility within the library target, creating directories only when needed.
- [ ] Configure SwiftPM resources for selected fixtures and, later, verified compiler assets. Verify resource loading in package consumers and archive/distribution builds.
- [x] Create `Validation/FirmingoKit.xcworkspace` referencing the local package with a verified shared `FirmingoKit` scheme. Commit reproducible configuration and verify it with `xcodebuild -list`.
- [x] Create `docs/development.md` with setup, `swift build`, `swift test`, simulator/device build commands, concrete simulator test selection, documentation generation, and output locations under `.build/`.
- [x] Establish baseline macOS package tests and generic iOS Simulator/iOS device builds using the commands in `AGENTS.md`. Record unavailable SDKs or setup blockers accurately.
- [ ] Configure CI for macOS tests, both iOS build destinations, and DocC generation as each workflow becomes available; add compiler checks when its tooling exists.

**Gate:** A fresh checkout can build and run deterministic tests without reference repositories, hardware, or live network services.

## 3. Define SDK boundaries and common models

- [ ] Define explicit board/profile, protocol/capability, device/boot identity, artifact, progress, and outcome models where needed. Keep complete Firmingo images distinct from managed capsules.
- [ ] Define injectable transport, clock, artifact-provider, programming-backend, and compiler boundaries alongside their first consumers; avoid speculative abstractions.
- [x] Expose `async throws` inspection/console operations and a bounded pull-based serial byte sequence with documented buffering, backpressure, cancellation, termination, and ownership. Upload/lifecycle APIs are now experimental; the actual compiler remains open.
- [ ] Define errors that distinguish transport failures, protocol violations, device rejection, unsupported capabilities, cancellation, and uncertain outcomes; retain underlying causes and firmware codes.
- [ ] Design actor isolation, ordered transport reading, task lifetimes, deadlines, and serialization of device-changing operations. Review reentrancy across suspension points.
- [ ] Keep public APIs independent of UI frameworks and global application state. Keep WebKit compiler hosting internal and usable without a visible host-supplied view.
- [ ] Document named declarations and public behavior as implementation lands, following `AGENTS.md`; review API visibility, `Sendable` correctness, and source compatibility.

**Gate:** A host owns presentation/user decisions; the SDK wraps the shared compiler and owns communication, device evidence, and Firmingo lifecycle logic.

## 4. Implement protocol framing and payload validation

- [x] Import selected firmware golden vectors as SwiftPM test resources with provenance and checksums.
- [x] Implement explicit binary framing and byte order, validating fields and negotiated limits before collecting or allocating payload storage.
- [x] Implement incremental decoding for every header/payload split, coalesced frames, and retained trailing bytes. Apply terminal protocol-error behavior without invented resynchronization.
- [ ] Implement JSON request/response/domain validation beyond synthesized `Codable`, including required fields, permitted values, bounds, and error envelopes.
- [x] Test golden bytes, boundary values, invalid headers/payloads, oversized lengths, malformed JSON, terminal errors, and exact preservation of zero bytes and invalid UTF-8.

**Gate:** Codec behavior matches independent firmware vectors; encoder/decoder round trips are supplementary evidence only.

## 5. Implement transport, sessions, and console operations

- [x] Implement the Apple-platform TCP transport and deterministic fake transport. Start with explicit numeric endpoint selection; do not invent Bonjour discovery or treat an IP address as identity.
- [x] Perform hello once per connection and validate device identity, protocol, backend, limits, and capabilities before permitting implemented operations.
- [x] Implement request IDs/correlation, one bounded pending request with deadlines, one ordered reader, and independent handling of interleaved control responses and serial data.
- [ ] Implement capability-gated channel acquisition/release, console opening/closing, supported serial controls, and other selected contract operations. Return explicit unsupported failures for unavailable controls.
- [x] Preserve partial writes and bounded backpressure. Deliver serial bytes losslessly; leave text interpretation, newline conversion, and display buffering to the host.
- [ ] Implement cancellation, disconnect cleanup, ownership release where possible, and task/pending-request resolution. Every reconnection creates a fresh session/decoder without replaying commands or serial data.
- [x] Test empty/populated capabilities, ownership rejection, interleaved replies, partial writes, slow consumers, bounds, deadlines, cancellation, disconnects, and fresh-session behavior using injected deadlines. Hardware tests remain separate.
- [ ] Validate macOS and iOS/iPadOS host networking permissions and lifecycle behavior, recording platform-specific restrictions.

**Gate:** A host can connect, validate capabilities, exchange exact bytes, and clean up reliably through documented APIs.

## 6. Implement Firmingo installation, updates, and interruption recovery

This track can progress alongside communication after contract selection. Initial installation and bootloader reinstallation must work without an existing Firmingo connection; post-install verification depends on the session API.

- [x] Create `docs/firmware-lifecycle.md` with versioned manufacturer programming references, selected Firmingo release provenance, backend limitations, and separate Nano ROM/Pico BOOTSEL procedures. Actual flashing qualification remains open.
- [x] Define the effect of the planned complete-image transfer on firmware, sketches, settings, filesystems, and flash regions. No preservation, backup, rollback, or NINA update is promised.
- [ ] Implement artifact acquisition and validation against exact board/profile/version/byte count/SHA-256 metadata, trusted release sources, and signatures when provided.
- [ ] Validate artifact format, flash addresses, ranges, and layout for each backend. Reject wrong-board, corrupt, missing, or incompatible images before any write.
- [ ] Implement board/bootloader discovery behind platform capabilities. Handle multiple devices, ambiguous identities, filesystem access, and permissions; a shared family ID or `RPI-RP2` label is insufficient selection evidence.
- [ ] Produce a reviewable preflight plan bound to the selected board and artifact, including prerequisites, affected data, required physical actions, verification limits, and interruption recovery steps.
- [x] Implement the artifact-preflight subset: bounded explicit local file acquisition, strict unsigned schema-one `0.1.0` release/board/profile matching, size/digest checks, UF2 block/address validation, and SDK physical/recovery guidance. Physical model identification remains a host/user assertion. Artifact-only plans cannot execute; separate attachment-bound tokens enable experimental macOS execution without hardware/sandbox qualification.
- [x] Implement the explicit one-shot execution boundary: target-bound process-local token, physical-model assertion, attachment revalidation, relevant idle session shutdown, unresolved-work rejection, and process-wide attachment leases. No hardware qualification is implied.
- [ ] Qualify the experimental macOS mounted-ROM backend on each board in a signed sandbox host. Its bounded partial writes, awaited progress, sync/close, cooperative cancellation and distinct transfer/hello/unknown states are implemented; reboot/install success is not inferred.
- [x] Implement separately requested fresh-hello verification against board/profile/protocol/release/capabilities, with optional prior device identity. Preserve unknown writes and exact-image/USB association limits; physical verification remains unqualified.
- [x] Expose schema-validated persistable operation provenance, byte/state/hello observations, and recovery context. Require awaited host durability before write permission; restored records cannot resume/replay. Image bytes must be explicitly reacquired/validated, and real restart recovery remains unqualified.
- [ ] Implement qualified update and supported Firmingo reinstall/recovery paths. Require a new host action after uncertain results; do not blindly repeat writes.
- [x] Report direct iOS/iPadOS programming as unavailable and present the external computer route. Distinguish experimental macOS automation from guided transfer and from hardware qualification.
- [x] Test explicit target/write prevention, stale/re-enumerated attachments, leases, one-shot tokens, permission/persistence failure, partial writes/sync failure, cancellation, unresolved sessions, restored uncertainty, and hello mismatch with fake backends. Normal directories/invalid ROM metadata are rejected; real ambiguous-device and disconnect behavior remains qualification work.
- [x] Test the implemented local artifact/plan boundary with non-executable UF2 fixtures, corrupt metadata/bytes, unsafe paths/sources, wrong board plans, missing artifacts/files, bounded acquisition, cancellation, and board/platform guidance. Four provisional observed images also passed one-time Swift validation without hardware; backend state-machine and transfer-loop tests are implemented with memory sinks; no native writer or real board was exercised.

**Gate:** Plans and execution are separate, unsafe inputs cannot reach a writer, and interrupted operations preserve actionable context without false success claims.

## 7. Preserve the existing compiler until extraction passes

Current update: scoped service review is complete. One checked experimental Nano
descriptor and complete compiler package are staged as thirteen metadata roles.
Clean SDK preparation supplies the binary outside Git for default loading; ordinary
source-checkout availability remains missing-service. See [provisioning](docs/compiler-package-provisioning.md).
Earlier pending/empty-catalogue entries are historical checkpoints. Hosted delivery
and signed/minimum-OS/physical/device qualification remain open.

The completed entries below retain their original evidence. Portable preprocessing,
recipes, runtime execution, ELF/capsule packaging, and related maintenance move to
Firmingo-Compiler under [the inventory](docs/compiler-migration.md). Former unchecked
compiler implementation tasks are transferred to its roadmap rather than treated
as new SDK ownership. Current SDK work is in sections 7.1–7.2.

- [x] Add immutable single-file snapshot/revision, explicit Nano managed profile and offline resident selection, without a compiler stub or board side effect.
- [x] Implement bounded facade-only preprocessing, BOM/line-ending normalization, original source diagnostics, explicit forward-declaration policy and original/generated hashes. Keep C++ checking and stateless linking separate.
- [x] Validate the pinned stateless ELF subset and package independently linked code into FMS1/report/typed receipts. Compare complete bytes to the firmware parser vector; never convert conventional UF2 into a managed capsule.
- [x] Record exact source/revision/board/profile/resident/recipe/toolchain/ELF/capsule identity in packaging receipts. No build cache exists; the SDK compiler is experimental with an explicitly supplied service.
- [x] Record pinned compiler/firmware reference hashes, independently authored implementation, synthetic fixture provenance and separate provisional observed GCC packaging evidence in `docs/compiler*.json` and `docs/compiler.md`.
- [x] Test source bounds/directives/coordinates/cancellation, golden FMS1 output, exact code limits, every ELF truncation, malformed tables/mappings/symbols, forbidden storage/relocations and complete receipt identity.
- [x] Add independent experimental stateless Clang/LLD recipe and a real local development WASI/worker runner. Compile Blink/Console to ELF and validate FMS1 through SDK APIs; do not promote this to WebKit/iPad or hardware support.
- [x] Test closed worker schemas, source diagnostics despite zero frontend status, bounded readonly/writable capabilities, memory declarations, asset hashes, isolated revisions, worker cancellation/deadlines and fresh subsequent builds.
- [x] Record the exact original/derived service identities, 256-MiB memory-limit maintenance adaptation, licensed third-party shim receipts and executable development output hashes. Keep service redistribution pending the custom license/component review; never upload synthetic-binding development capsules.
- [x] Integrate independently authored private main-actor WebKit origin/page/worker lifecycle and public actor-isolated async compiler API. Verify runtime and explicit service bytes off UI execution; never expose WebKit or require a visible view.
- [x] Add strict native bridge schema/type/diagnostic/base64 validation, bounded record import and real macOS WebKit compile/link/cancellation/overlap/deadline/fresh-state tests. Keep signed-sandbox/minimum-OS/physical-device qualification separate.
- [x] Validate actual demo editor-change cancellation, fresh revision results, selection invalidation and bounded synchronized managed transaction journals/corrupt-context gates using SDK-local harness storage.
- [x] Serialize demo Run/outcome review/clear and firmware installation across document windows. Recheck durable context before deployment, reject stale clear/review decisions, refresh conflicts without replay, and test competing reservations/cancellation/storage failures without boards. Cross-process and hardware qualification remain open.
- [x] Validate independently linked ELF ranges/entry points and generate the selected Nano `nano-managed-v1` FMS1 `.fms` capsule with required size, digests, entry points, and build report. Development WASM linkage is demonstrated; signed-host/runtime distribution and recipe qualification remain open above.

Transferred backlog: portable source/diagnostic behavior, explicit recipes,
ABI-compatible linking, service/component review and asset production, WASI worker
isolation/limits, ELF/capsule validation, and portable real-service regressions
belong to Firmingo-Compiler M1–M5/M7. Broader boards/libraries belong to its M9;
SDK hosting, stale-result/deployment safeguards, and Apple-host measurements stay
in sections 7.1–7.2 below. No transferred task is marked complete by this move.

**Gate:** Supported source compiles locally through the actual runtime to independently validated Firmingo artifacts. Mocked tests and ArduinoKit's conventional UF2 results do not establish this gate.

### 7.1 Accepted bundled compiler and firmware catalogue

The self-contained experience was accepted on 2026-09-30; ownership changed on
2026-10-12. Follow `docs/compiler-catalogue.md` and the migration inventory. Completed
SDK-owned packaging entries describe the previous implementation. Going forward,
the compiler produces static assets/metadata and the SDK verifies/consumes them. These tasks replace
normal external-file setup once delivered; the current compiler/demo APIs still
use an explicitly selected service with catalogue or legacy resident metadata. Catalogue
availability, platform execution and hardware qualification are separate gates.

- [x] Document SDK-owned resource packaging, catalogue selection, firmware-build/device-record separation, demo flow, blockers and acceptance criteria. This completes planning only.
- [x] Implement the additive metadata foundation: bounded hash-verified host-supplied catalogue, explicit Nano/Pico availability queries, content-identified firmware-build descriptors, strict persistable device associations and a matching-ID legacy binding adapter. Ten tests cover independent golden identities, bounds, cancellation, duplicate/conflicting metadata, unsupported ABI/recipe/board fields and restored/mismatched evidence. No production descriptors/service, offline compiler migration or demo selection is delivered by this task.
- [ ] Verify a selected compiler package has recorded service/component distribution, attribution, reproducible-build and real firmware-metadata evidence before SDK bundling. Firmingo-Compiler owns production/review; Firmingo owns exact-build exports. Missing inputs stay explicit.
- [x] Define the bounded SDK-pinned schema-one resource inventory linking the existing descriptor catalogue, exact Nano/profile/recipe/source contract, ABI-two service identity/pending review and eight runtime/source/license/catalogue roles with byte counts/hashes. Strict role/path/scalar/duplicate/integrity tests pass; qualification remains experimental/unqualified. Production catalogue is intentionally empty and no service is staged; additional recipes/qualification require deliberate schema/anchor updates.
- [x] Separate immutable firmware-build descriptors, persisted physical-device associations and upload journals through additive SDK APIs and explicit demo Save/Restore/Forget. Bounded versioned app-private storage preserves exact IDs, never persists trust, rejects stale mutations/Run before compiler loading and keeps offline Build independent. Legacy records remain compatible but cannot be inferred into catalogue descriptors; migration requires explicit reviewed new evidence. Restart/controller/schema/concurrency checks pass; real signed app restart and hardware qualification remain open.
- [x] Add default SDK loading APIs: `ManagedCompilerCatalogue.loadBundled()` verifies package metadata and returns the empty catalogue; `ManagedSketchCompiler()` verifies SDK resources and fails explicitly before preprocessing while service review is pending. Preserve explicit development APIs without fallback. Resource bounds/integrity/approval tests, actual test-only approved runtime parity, separate local consumer and unsigned archive packaging checks validate the foundation; successful production bundled compilation remains blocked.
- [ ] Implement catalogue queries for supported, experimental and unavailable combinations with actionable reasons, plus default verified SDK resource loading. Report missing/corrupt/unapproved resources explicitly; normal consumers need no file picker, sibling checkout, Node, shell, native compiler or remote service.
- [x] Add device-independent offline build inputs, artifact packaging and receipts tied to exact source/catalogue/recipe/toolchain/firmware-build identities. `ManagedOfflineBuildRequest`, shared preparation/ELF/FMS1 validation and the compiler overload produce `ManagedOfflineSketchArtifact` without any device ID. Explicit association binding yields the existing capsule type; legacy APIs/receipts remain compatible. Seven ordinary tests and three added real-WebKit tests cover identities, cancellation, source diagnostics, packaging, binding and mixed-overload exclusion. Production resources, automatic loading, demo selection and hardware qualification remain separate open tasks.
- [x] Connect the demo to SDK catalogue queries and offline Build through an explicit development import path. Select exact board/build IDs without a latest fallback, validate catalogue bytes against independently supplied provenance, import/review separate device evidence before Run, bind the fresh artifact and retain journal/one-commit/cross-window gates. Preserve explicit legacy record compatibility. Controller/real-WebKit harnesses and Apple builds validate this increment; no production resources, automatic loading, association-store migration, visual UI or hardware qualification is claimed.
- [x] Connect default SDK loading/resource verification to demo startup and explicit independent compiler/catalogue providers. Move imports/provider selection/legacy mode under Development resources, show empty/pending SDK availability, invalidate old output/review and release unused service capabilities. Verify cancellation, failed reload, late startup and fresh Build revalidation through host-only controller checks; retain real-WASM and journaling harnesses. Actual bundled compilation, UI/accessibility and hardware qualification remain open.
- [ ] Consume pinned approved compiler-package assets/metadata/notices through SDK staging/loading without independently maintaining recipes or service binaries. Retain SDK consumer/archive verification. Keep complete-firmware lifecycle validation separate; no restoration assets are added.
- [ ] Bind an offline artifact to a real selected device only after valid association evidence and fresh protocol/backend/advertised-target checks. Reject stale/missing/mismatched evidence before staging; do not infer installed bytes from hello or automatically rebind to a "latest" descriptor.
- [ ] Test catalogue/schema/resource bounds, unsafe paths, corrupted/missing assets, ambiguous recipe selection, ABI/board/profile mismatch, stale/removed descriptors, restored associations, source revision changes, cancellation and fresh subsequent builds. Preserve current one-commit, uncertainty and journaling behavior.
- [ ] Verify a separate minimal package consumer and archive can load all required resources without sibling checkouts or imported compiler files. Execute actual offline compilation in signed macOS and physical iPad hosts; record cold/repeated duration, total memory, resource/app size and minimum-OS evidence.
- [ ] Qualify SDK compilation/upload/startup/useful behavior independently per board/profile/platform through a separately authorized hardware workflow. Keep Nano experimental until evidence exists, and Pico managed Build/Run unavailable until its target/recipe/qualification are implemented.

**Gate:** A clean host app can select an explicit supported firmware-build target
and compile using only approved SDK resources, then deploy only with valid real
device association and negotiated capabilities. No bundled-record authenticity or
hardware-support claim exceeds its recorded evidence.

### 7.2 Compiler split — prerequisite work and SDK adapter

- [x] Refocus root/demo ownership guidance, README, compiler/catalogue/handoff documents, and roadmap; preserve implementation and original evidence.
- [x] Record source commits/initial working state and source/resource hashes in `docs/compiler-migration-reference.json`; preserve pre-existing Firmingo guidance edits and read-only ArduinoKit.
- [x] Map portable extraction, retained Swift/device responsibilities, mixed tests/tools, compatibility gates, and unresolved exports/service distribution in `docs/compiler-migration.md`.
- [x] Translate the versioned portable request/event/result contract through the existing Swift facade and WebKit host, preserving public source/diagnostic/progress/error/cancellation behavior where practical.
- [x] Preserve legacy/offline receipt and descriptor identities or version changes explicitly; test persisted associations, journals, incompatible/stale records, and deliberate migration without granting trust or replaying writes.
- [x] Verify pinned compiler-package loading, trusted anchors, strict bridge bounds, local resource access, content-process failure, cancellation/deadline/reentry, and offline clean consumers without sibling dependencies.
- [x] Run actual compile/link/package through the adapter; retain independent SDK capsule/report/device binding and fresh capability gates before writes. Verify current source/selection and durable one-commit/uncertainty behavior.
- [x] Retire the replaced standalone SDK Node/WASI/recipe/vendor stack and old ELF-only bridge after shared compiler, real WebKit and consumer checks pass; record 36 unchanged original file hashes. Compiler-owned memory adaptation and tests now live in Firmingo-Compiler. Retain Swift/platform/package/deployment regressions.
- [x] Delegate both public Swift preparation overloads to the shared service-free compiler worker; remove the duplicate Swift lexical scanner and preserve source/generated hashes, revisions and line mapping. Record explicit resource/host requirements and corrected first-line BOM columns.
- [x] Migrate both supplied-ELF conversion overloads through separate declared-provenance packaging; preserve legacy/offline receipt goldens, retire native ELF parsing/capsule production and retain deployment validation. Record resource/WebKit requirements.
- [x] Update SDK CI definitions, development commands and DocC for the adapter/package change. Local macOS tests, iOS builds and DocC pass; CI runner/run, signed sandbox, physical iOS/iPadOS and hardware execution remain explicitly unqualified.

**Gate:** Prerequisite documentation/inventory is complete. Migration is complete
only when the SDK consumes the shared compiler through a tested adapter, public
compatibility/persistence is deliberate, and existing deployment safeguards pass.
Local shared-compiler integration is evidenced in `docs/compiler-adapter.md`; compatibility-path retirement and signed/physical-host/deployment qualification remain separate work.

## 8. Implement managed upload and reconciliation

Artifact validation and upload can start with independently built, validated executable capsules while the compiler is under development. Firmware parser fixtures must never be uploaded to hardware.

- [x] Validate the pinned experimental Nano target, board, format, size, digest, build report, and host-supplied exact resident/ABI binding before starting a transaction. Remote installed-image attestation remains unavailable.
- [x] Close the console, respect ownership and firmware-enforced physical authorization, and implement the selected transaction/chunk protocol with negotiated limits and exact offset/state validation.
- [x] Expose transfer, verification, commit acceptance, installation, startup confirmation, failure, and unknown outcome separately through progress, snapshots, and reconciliation results.
- [x] Attempt commit exactly once. Provide read-only reconciliation on a freshly validated connection; never automatically resend commit or reconnect after uncertainty.
- [x] Match device ID, boot ID, transaction ID, size, and digest during reconciliation. Treat changed boots, superseded records, and insufficient evidence as unknown outcomes.
- [x] Inspect transaction state/error fields even inside successful envelopes. Preserve uncertainty after cancellation/disconnection following commit and require a new host action before another upload.
- [x] Test rejected metadata, operation reservation/authorization failures, chunk boundaries, failed transactions, timeouts/disconnects before and after commit, exactly-one-commit behavior, and reconciliation mismatches. Hardware qualification remains open.

**Gate:** The SDK cannot confuse accepted transfer/commit with installed and running code, or automatically repeat an uncertain transaction.

## 9. Build the native demo host

- [x] Define the accepted product flow in `docs/demo-design.md`; move demo-specific UI conventions into `Demo/AGENTS.md` when creating the app, keeping root instructions focused on SDK boundaries.
- [ ] Create a separate native document-based Xcode app under `Demo/`, consuming the local package rather than becoming a package target. Configure macOS and iOS/iPadOS schemes, signing, sandbox, and required permissions.
- [ ] Implement `.ino` document creation/open/save, editing, immutable build snapshots, source revisions, and selected board/profile state.
- [x] Build an adjustable editor/console layout starting near two-thirds/one-third, adapted for smaller screens, with visible selected/connected board and connection state. Physical layout/accessibility validation remains open.
- [x] Add native toolbar Build/Run commands and keyboard shortcuts, structured source diagnostics, actual compiler progress and cancellation. Physical UI/accessibility validation remains open.
- [x] Wire experimental Build/Run to real SDK compilation and guarded managed staging/one-shot commit/reconciliation, with document revision checks, trusted imported resident records, durable context and identity-gated console acquisition. Actual hardware deployment remains unqualified.
- [ ] Replace normal compiler/resident-file setup with catalogue-driven board/profile/firmware-build selection and automatic SDK loading from section 7.1. Make offline Build available without a physical device; move validated imports into an optional advanced path.
- [ ] Present SDK-issued real device associations/setup and missing/mismatched evidence before Run. Keep catalogue changes, firmware replacement and document edits from silently selecting a different binding; preserve cross-window guards and saved-outcome review.
- [ ] Demonstrate the normal resource-only workflow in a signed physical iPad demo and a separate minimal host consumer. Keep UI, compiler execution, installation and managed hardware qualification evidence distinct.
- [ ] Present unsupported targets and experimental restrictions clearly; distinguish build success, installation, startup confirmation, useful behavior, failure, and uncertainty.
- [ ] Add Install Firmingo and supported update/recovery flows presenting the SDK plan, exact target/release, affected data, user actions, progress, verification, and recovery choices. Keep bootloader recovery reachable while disconnected.
- [x] Add console input/output presentation with explicit hex/UTF-8 display, bounded display buffers, batched updates, and visible truncation without altering SDK byte delivery. Configurable newline and UART settings remain open.
- [ ] Validate VoiceOver, focus order, keyboard access, Dynamic Type/scalable text, reduced motion, light/dark/increased contrast, non-color status cues, and controlled console announcements.
- [ ] Test document edits during compilation, repeated commands, disconnects, cancellation, uncertain outcomes, and app restart with saved lifecycle context.
- [ ] Keep the demo limited to Firmingo workflows. The isolated default-Arduino wording in root demo guidance must be reconciled with the explicit package/demo exclusion when moving that guidance; do not add restoration functionality.

**Gate:** The demo exercises reusable SDK APIs for the intended journey without duplicating compiler, protocol, upload, or flashing logic.

## 10. Qualify real hosts, boards, and failure recovery

Local host increment: a development-signed ARM64 macOS 27.0 Release app passes
six actual compiler checks with verified app sandbox/hardened runtime. Generator,
runner and measured journals are in [host qualification](docs/compiler-host-qualification.md).
Source CI covers tool fixtures/type-checking; complete app CI awaits prepared assets
and signing/runner provisioning. The same Release host now passes all six checks
in two physical iPad Pro (11-inch, 3rd generation) launches on iPadOS 27.0.1 and
two iPhone 15 Pro Max launches on iOS 27.0, using the identical signed app.
Exported capsule bytes match desktop vectors and independent firmware validation.
Minimum OS, other models/OS versions, total memory and board gates below remain open.

- [x] Execute the prepared default compiler in a development-signed minimal physical iPad host; record two launches, diagnostics, busy/cancellation, fresh reentry, capsule bytes, signing/provenance and first/subsequent compile times in `docs/compiler-host-ipad.json`. This does not qualify the demo, total memory, deadline expiry or device deployment.
- [x] Repeat the same six checks in two fresh physical iPhone app launches with the identical signed app and existing profile; preserve exact reports, capsule bytes and independent firmware validation in `docs/compiler-host-iphone.json`. Minimum OS, memory/lifecycle and deployment remain separate gates.
- [x] Verify wireless development installation, launch and own-report/capsule collection on both USB-disconnected physical Apple devices. CoreDevice reports `localNetwork` before/after; each run passes all six compiler checks with wired capsule parity. Preserve `docs/compiler-host-wireless.json`; simultaneous Nano USB Ethernet/Wi-Fi coexistence remains untested.
- [x] Add bounded repeated-build/self-footprint instrumentation and a strict schema-2 journal checker. Both devices pass 20 baseline and 20 fresh recovery builds after explicit whole-app termination; interrupted journals are rejected and remain unchanged. Record `docs/compiler-host-reliability.json`; the updated app retains the original six-check mode.
- [x] Investigate the roughly 790 MiB sampled host footprint and repeat physical measurements. Reserving the bounded owned snapshot and draining Foundation chunk temporaries reduces the native six-read comparison from 1,164 MiB to about 100 MiB. Two fresh 20-build runs per device pass all 80 builds with unchanged capsules; highest host samples are 214 MiB on iPad and 209 MiB on iPhone. Both original six-check modes pass. Record exact source/signing/context and observations in `docs/compiler-resource-memory.json`.
- [ ] Measure aggregate app/WebKit memory and qualify real pressure, remaining active-build background/foreground stages and child termination before broader host claims. Self-process samples exclude WebKit children/missed peaks and do not establish a leak-free result or a memory budget pass. The earlier app-scoped `xctrace` attachment failed; scoped source-compilation/deadline results below do not close these gates.
- [x] Add an opt-in idle background/return observer with bounded real scene events, same-process correlation, known exported builds before/after and a strict independent report checker. Eight source-tool fixtures and macOS/optimized iOS host-source checks pass.
- [x] Perform the idle transition check on physical iPad/iPhone and record exact app/source/signing/context and exported capsule bytes in `docs/compiler-host-lifecycle.json`. Both pass with 10.2/20.2-second background-to-active observations, unchanged PID/context and known capsules. No active-build interruption, actual OS suspension or memory-pressure claim follows from an idle transition.
- [x] Add a separate manually started active-call lifecycle harness: cancel the pending SDK task on inactivity, require CancellationError without a returned artifact, observe actual background/return and compile fresh through the same compiler instance. Nine tool/report fixtures and macOS/optimized iOS source checks pass; this adds no automatic SDK lifecycle policy.
- [x] Execute the active-call lifecycle mode on physical devices and record exact pending-attempt/last-progress/cancellation settlement, scene events, PID/context and fresh capsule bytes in `docs/compiler-host-active-lifecycle.json`. Both pass with last progress `verifying`, no returned artifact, 11.3/4.6-ms settlement and known fresh console bytes after actual return.
- [ ] Obtain separate evidence for entry-wrapper/link-stage interruption. The source-compilation observations below do not qualify those stages, OS suspension or real memory pressure.
- [x] Add an opt-in worker-source compilation variant with a pinned compile-time C++ fixture, measured complete preflight and first-compiling-notification eligibility. The exact fixture produces the unchanged GPIO capsule through macOS WebKit; ten report/tool fixtures and macOS/optimized iOS source checks pass. Physical worker-phase results remain separate.
- [x] Execute the worker-source mode on both physical devices. Build 7 cancels attempt 1 during the first source-compiling interval, settles with CancellationError in 19.6/10.2 ms without artifacts, and produces known fresh console capsules after actual background/return in the same PID/context. Record exact workload, 10.001/8.830-second complete preflights, source/signature, reports and four exported capsules in `docs/compiler-host-worker-lifecycle.json`. This is explicit test-host policy and callback-phase evidence, without an instruction-pointer or suspension claim.
- [x] Add a separate foreground-only production-deadline host/checker mode. Derive a pinned longer frontend workload without changing compiler assets, public timeout or recipe; require typed timedOut after the actual 60-second deadline, first-source progress, no artifact and a fresh same-instance console build. Eleven tool/report fixtures and Apple source checks cover the host; actual expiry remains a separate execution gate.
- [x] Execute and record the production-deadline mode on both physical devices in `docs/compiler-host-deadline.json`. Signed build 8 observes typed timeout without artifact at 60.201/60.155 seconds, exactly one source-compiling notification, continuous foreground and known same-instance fresh console builds in 0.694/0.681 seconds. Preserve exact workload/service/SDK/app/source/signature, independent launch PID/context, events and four exported capsules. A local actual macOS WebKit maintenance probe also passes, separately from signed macOS deadline qualification.
- [x] Extend the signed macOS runner with an explicit deadline mode using the shared schema-6 checker, independent child PID/context, bounded run-bound stdout exports of the two fixed capsules and independent byte/hash checks. Preserve original six-check behavior and private-container restrictions; twelve tool fixtures cover the tooling.
- [x] Execute and record the production-deadline mode in the signed sandboxed/hardened macOS app. ARM64 Release build 9 returns typed timeout without artifact at 60.344 seconds, observes first-source progress/foreground and produces the known same-instance fresh console capsule in 1.018 seconds. Independent launch PID/context and both bounded stdout exports validate; preserve `docs/compiler-host-deadline-macos.json`. Original six-check regression remains separately recorded with this exact app.

- [ ] Maintain opt-in hardware procedures and evidence separate from deterministic tests; execute device-changing tests only within an authorized hardware workflow.
- [x] Prepare exact Nano resident-only test inputs from the independently anchored consumer package, retaining all firmware evidence/catalogue and original manifest without a firmware rebuild, device access or flash operation. Document preserved managed-slot effects and separately reviewed ROM setup/readback.
- [x] Add a separate minimal Nano SDK qualification app/generator, explicit inspect/association/stage/one-shot commit/reconcile/behavior actions, query-only restored records and a connection-disabled offline mode. Four tooling fixtures, the production admission-policy executable, full 154-function Swift Testing entry point and macOS/optimized iOS source checks pass. No hardware behavior is qualified by these checks.
- [x] Build and execute the signed Nano app offline, independently verifying both actual exported capsules and exact package/source/signature context. Corrected source `24993ce…` produces the known 316/392-byte outputs in development-signed sandbox/hardened macOS build 2; both complete Release apps build, with iOS signing disabled. Record `docs/nano-hardware-preparation.json`, retaining the rejected first view-task startup and original XCTest-loader command failure separately.
- [x] Select the recoverable physical Nano and complete the Firmware-owned initial resident/managed-slot setup: exact exported resident plus known SDK GPIO capsule, full UF2 ROM verification before reboot, matching macOS hello. Sign/install/launch the existing Nano host on iPad over Wi-Fi with existing profile coverage; record `docs/nano-hardware-initial.json` and Firmware's separate initial-setup evidence. This is not an SDK initial-install backend or managed-upload qualification.
- [x] Record the first iPad Nano SDK offline builds/hello and manual D13-lit observation in `docs/nano-hardware-ipad.json`, retaining the prior Network-is-down inspection failure. Independently check actual capsule bytes through firmware's validator and retrieve the own-run journal while paired over `localNetwork`. This is not a clean cold-attachment, Internet-routing or managed-install pass. User feedback prompted persistent status/input labels; checked/signed build 3 was updated wirelessly.
- [x] Complete the scoped iPad SDK console/GPIO sequence in signed build 3: reviewed association, verified RAM staging, one host commit attempt and fresh boot-confirmed reconciliation for each capsule, exact 256-byte console echo, then manual D13 off-to-on observation after RESET/fresh inspection/association. Preserve both per-boot records and original failures in `docs/nano-hardware-ipad.json`; startup and useful behavior are separate outcomes.
- [x] Complete the equivalent physical iPhone managed workflow with the identical signed build 3: exact capsules, verified RAM stage, one host commit attempt and fresh boot-confirmed status for console/GPIO, exact 256-byte echo and manual D13 off-to-on transition after RESET/fresh association. Preserve the first access-prompt inspection failure and explicit successful read-only retry in `docs/nano-hardware-iphone.json`. Own-run retrieval remains over `localNetwork`; the user removed the D2 upload arm at completion.
- [ ] Qualify broader USB authorization/cold-attachment matrices, uncached Internet routing, throughput/soak and interruption/power-loss behavior separately. Improve first-permission network-error guidance without automatic reconnect or upload replay. No connection or device-changing operation is authorized merely by app launch/preparation.
- [ ] Record board model/revision, firmware artifact hash/profile, resident metadata, SDK revision, compiler/recipe/assets, host OS/toolchain, procedure, observations, and unresolved limitations for each run.
- [ ] For every claimed board/platform installation pair, use an actual SDK host to install supported Firmingo on a board not running Firmingo, reconnect, and exchange exact bytes.
- [ ] Qualify supported updates and documented recovery from an unavailable connection and interrupted operations on dedicated hardware, including ambiguous device selection and post-reboot identity checks.
- [ ] For every claimed compilation/upload target, compile through the actual SDK WASM runtime, validate binding, upload through the SDK, confirm startup and expected behavior, then repeat with a different sketch.
- [ ] Exercise console load/backpressure, ownership contention, malformed input, network loss, lost commit replies, cancellation, and unknown outcomes in the relevant real-host workflows.
- [ ] Qualify sandbox/filesystem/entitlement/device-access requirements on macOS and physical iOS/iPadOS hosts independently. Device-target builds and simulator tests are not physical-device evidence.
- [ ] Update the support matrix with implemented, experimental, qualified, unsupported, and blocked status backed by evidence. Keep platform builds, compiler execution, USB installation, and FMGO capabilities separate.

**Gate:** Every advertised support claim has evidence for its exact board/profile/platform combination; remaining requirements stay open or explicitly deferred.

## 11. Complete documentation and release tooling

- [x] Write a README covering purpose, package integration, supported/experimental combinations, demo setup, and links to the detailed guides.
- [ ] Create `Sources/FirmingoKit/FirmingoKit.docc/` with an overview and working examples for compilation, installation/update/recovery, connection, console, cleanup, and managed upload as those APIs exist.
- [ ] Document capability requirements, cancellation/ownership, artifact provenance, source restrictions, data-preservation limits, required physical steps, and uncertain outcomes. Keep Arduino restoration outside SDK tutorials.
- [ ] Add a reviewed, explicitly versioned Swift-DocC plugin and record its tested version and generation commands in `docs/development.md`.
- [ ] Generate documentation under `.build/`, resolve introduced warnings, and verify public symbol links, examples, navigation, and assets.
- [ ] Establish the intended Git remote and verify the actual GitHub Pages destination before configuring deployment. Use `/FirmingoKit/` only if it matches that destination.
- [ ] Preview static documentation under its intended base path and configure CI artifact publication/deployment when publishing is requested; verify the deployed site separately from generation.
- [ ] Audit the consumed compiler package's notices, distribution/provenance record, resource integrity, and compatible versions; compiler toolchain maintenance belongs to Firmingo-Compiler. Verify a clean package/demo consumer needs no sibling checkouts or native compiler installation.
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

## Source-built compiler host qualification — 2026-10-13

- [x] Add a macOS-only explicit maintenance WebKit host; reject external/ambiguous
  addresses before starting WebKit and bound native page/report lifetime.
- [x] Run nine actual standard-worker source-built service checks on the recorded
  macOS host; verify artifacts against independent firmware validation.
- [ ] Qualify an approved candidate through public SDK APIs/private resources and
  a packaged consumer before updating consumer pins. Signed/minimum-OS and physical
  iOS/iPadOS/device qualification remain separate.

See [maintenance hosting evidence](docs/built-service-webkit.md). Normal consumers
and SDK resources are unchanged; distribution review remains unresolved.

## Candidate inventory handoff — 2026-10-13

Firmware schema-2 source resources and the compiler's metadata-only candidate
inventory are implemented in their owning repositories. SDK compiler resources,
public service acceptance and descriptor identity remain unchanged. Consume only
a deliberately reviewed package in the next integration increment, then qualify
the actual public SDK/private WebKit scheme and a fresh packaged consumer before
claiming candidate support. No SDK source change or hardware operation was needed
for this metadata/export increment; see `docs/compiler.md`.

## Reviewed compiler delivery — 2026-10-14

- [x] Consume Compiler's exact reproduced service/source/notice review, deliberately
  update source/runtime/service/inventory anchors and retain four service notice
  documents in twelve verified resource roles. No WASM/source archive is bundled.
- [x] Qualify the new service through all nine real public SDK/private-WebKit tests
  and a fresh separate SwiftPM consumer using an SDK-local paired delivery.
  Preserve source preparation, declared-ELF conversion, public receipts and
  deployment/association checks; distinguish absent bytes from pending licensing.
- [x] Check iOS Simulator/device builds and DocC on the recorded toolchain.
- [ ] Provision reviewed binary/source downloads or bundled service resources,
  trusted firmware catalogue, signed/minimum-OS/physical wrapper tests and selected
  hardware deployment. Existing tests do not qualify those outcomes.

See [delivery integration](docs/compiler-delivery.md) for exact identities and checks.

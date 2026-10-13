# Bundled compiler and firmware catalogue

## Accepted direction and current status

Ownership revised on 2026-10-12: the self-contained SDK experience accepted on
2026-09-30 remains, while Firmingo-Compiler now produces the portable compiler,
recipes, static catalogues/descriptors, and receipts. FirmingoKit owns Swift
hosting/loading/query APIs and real-device evidence/deployment. Firmingo exports
verified resident facts. See [the migration inventory](compiler-migration.md).
The existing implementation and dated evidence below remain SDK-local until
replacement gates pass; no resources, identities, or persistence schemas changed.

On 2026-09-30 the user accepted a self-contained FirmingoKit compiler experience:
a host app receives the necessary approved compiler resources, supported board
recipes and trusted firmware-build metadata through the package. The native demo
must demonstrate those same SDK APIs so another developer can implement
board selection, custom supported `.ino` compilation and explicit managed upload.

This document is an implementation specification with a delivered metadata
foundation, not qualified compilation support. The current SDK packages its independent WebKit host/worker, constrained
facade/recipe and licensed WASI shim, but requires an explicitly selected compiler
service for actual compilation. The demo imports separate catalogue/device metadata
or explicit legacy records. Default SDK loading now verifies a package resource
inventory and an intentionally empty catalogue; default compilation reports pending
service distribution review. Approved services and trusted production descriptors
are not packaged.
Experimental device-independent requests, artifacts and receipts are delivered
through the existing explicitly supplied service. Current behavior and evidence remain in
[compiler.md](compiler.md).

`ManagedCompilerCatalogue` now verifies bounded host-supplied manifest bytes,
lists explicit experimental Nano builds and rejects duplicate/conflicting metadata.
`ManagedFirmwareBuildDescriptor` contains static content-identified build metadata;
`ManagedDeviceAssociation` separately persists real device IDs and reviewed evidence.
An additive `ManagedResidentBinding` adapter retains existing APIs. The schemas and
example are documented in the DocC **Select firmware-build metadata** guide. These
APIs validate metadata shape/integrity; they do not authenticate a publisher, attest
installed bytes or verify a referenced ELF/report. Only synthetic parser fixtures
exist in test resources; no production descriptors or service were added. The demo
now offers SDK-filtered selection from verified imported development catalogues
and separate association review, with an explicit legacy compatibility mode.

`ManagedOfflineBuildRequest` now resolves an exact descriptor from the verified
catalogue and retains its manifest identity. Compiler/preprocessor/converter
overloads produce `ManagedOfflineSketchArtifact` without a device ID; its receipt
covers source/revision, catalogue, descriptor, recipe/toolchain and output digests.
Both compiler paths share one busy gate and the same isolated worker and strict
source/ELF/FMS1/report validation. `bind(to:)` requires matching real-device evidence
and returns the existing upload capsule type without connecting or authorizing a
write. The host still checks current source/selection and fresh device capabilities.
See the DocC **Compile for a firmware build without a device** guide and
[offline implementation evidence](compiler-offline-experiment.json). Production
production metadata/approved service packaging, normal bundled demo setup and qualification
remain open; no synthetic deployment association is introduced by offline Build.

The demo's catalogue mode loads exact manifest bytes against an independently
supplied SHA-256, requires an explicit SDK-listed build ID and uses the offline
compiler overload. Device settings and association review do not gate this Build.
Run requires separate matching association evidence, explicit host review and
fresh session validation; the controller binds the newly compiled artifact before
staging. Anchor/board/descriptor/mode edits clear old selections or results rather
than selecting latest. Failed imports never fall back to another mode. Development
resources and legacy imports remain explicit while service/production metadata
packaging is unresolved. Explicitly reviewed associations can now be saved in a
bounded app-private roster. Restart restores the roster without choosing a device,
selecting a firmware descriptor or granting review. Run requires exact saved
evidence and renewed review; the shared actor rechecks it before compiler loading.
Legacy combined records are not automatically migrated because they lack the
static descriptor provenance required by the catalogue schema.
See [demo design](demo-design.md) and
[catalogue controller evidence](demo-catalogue-experiment.json) and
[association persistence evidence](demo-associations-experiment.json) for delivered behavior and limits.

The service's redistribution/component-license and reproducible build-provenance
review remains unresolved. Catalogue models, validation, tests and UI design can
progress independently. Do not package the service, fabricated firmware metadata
or synthetic development bindings as production resources to remove that blocker.
Requested coordinated work may touch the three Firmingo repositories; ArduinoKit
remains strictly read-only. Preserve other work and pinned consumer inputs.

## Ownership and resource contents

Firmingo-Compiler owns portable compilation, recipe selection/compatibility,
static catalogue/descriptor production, artifact packaging, and compiler resource
maintenance. FirmingoKit owns platform resource discovery/access, trusted package
verification, Swift catalogue queries, web hosting, device associations, and
independent deployment validation. The demo owns presentation, source snapshots,
user selection, and host persistence. Keep SDK capabilities usable without a
visible web view or the demo.

Produce approved versioned assets in Firmingo-Compiler. FirmingoKit consumes a
pinned package through its own resource/distribution adapter; the delivery mechanism
must be selected and tested during migration, without adding a Swift requirement
or sibling-path dependency to the compiler. Existing staged SDK resources and
maintenance tools stay until replacement checks pass. Do not independently edit
an upstream recipe/runtime in a staged copy. Historical SDK-local staging receipts
remain evidence, not an instruction to keep compiler maintenance here.

The shipped resource set must include:

- The approved WASM service, reviewed host/worker/runtime dependencies and licenses.
- An explicit recipe for every offered managed board/profile: CPU/triple, facade
  or core, required headers/libraries, fixed flags, linker script, memory limits,
  capsule format and firmware ABI compatibility. Include only assets the recipe
  needs; the current freestanding Nano recipe needs no conventional Arduino sysroot.
- Versioned firmware-build descriptors backed by exact trusted build/release
  evidence, including board/profile, resident ELF and complete-image hashes,
  API-table address, ABI/target/format identity, compatible recipe and provenance.
- A bounded catalogue/asset manifest tying those records to resource paths, exact
  byte counts, SHA-256, service ABI and catalogue/recipe versions. Record supported
  source/API restrictions and qualification separately for each workflow/platform.

Share identical compiler assets between compatible recipes. Do not ship a separate
compiler copy for each board unnecessarily. A board model must not implicitly
select arbitrary firmware or reuse another board's recipe. Preserve the explicit
ArduinoKit-to-Firmingo Nano ID mapping described in the root instructions.

If complete Firmingo installation images are included, validate and acquire them
through the existing release/lifecycle boundary, with separate provenance and
platform/backend gates. Catalogue selection never flashes, upgrades or reinstalls
firmware; managed capsules and complete-firmware UF2 remain distinct operations.
Conventional Arduino compilation is a secondary Firmingo-Compiler track, not a
managed recipe or an SDK restoration requirement. No restoration feature is added
by this migration; any future SDK programming support needs its own explicit scope.

## Separate build metadata from physical-device association

The current `ManagedResidentBinding` combines exact firmware-build information
with a physical `deviceID`. Refine this model for offline board selection while
reviewing source compatibility; prefer additive APIs/adapters when practical.
Public symbol names and persistence schemas must be settled during implementation,
documented and tested before changing existing callers or stored records.

| Record | Responsibility | Lifetime |
| --- | --- | --- |
| Firmware-build descriptor | Firmware exports actual resident facts; compiler adds compatible recipe/catalogue identity; SDK verifies/reads the result | Immutable, versioned compiler-package metadata |
| Device association/installation record | Link one selected physical device to an exact descriptor and record the evidence and verification limits | Persisted host context, updated through explicit setup/installation |
| Managed transaction record | Device/boot/upload identity, capsule size/digest and reconciliation context | Existing one-shot upload/recovery workflow |

Offline Build selects a verified descriptor and recipe without requiring a
connected device, invented device ID, fabricated digest or user confirmation
that an unconnected board runs that image. Its artifact/receipt must retain exact
source revision, catalogue/recipe/toolchain and firmware-build identities. A build
result is not permission to upload. Adapt artifact packaging and receipts so
device-independent builds can later be validated against a real selected device;
do not satisfy today's device-bound initializer with a placeholder.

Before Run, the SDK requires a real device association and a freshly validated
board/backend/protocol/advertised target matching the artifact's exact firmware
and ABI requirements. The host must establish association through trusted
installation/build evidence or an explicit guided existing-device setup. Record
what evidence is available and what remains unverified; an installation attempt
or completed file copy alone does not establish an exact installed-image identity.
Revalidate after reconnect, replacement or firmware changes. Never silently pick
a descriptor by board name, IP address, shared chip, firmware version or API address.

The selected hello contract cannot attest exact installed ELF/UF2 bytes. Bundled
hashes verify expected build metadata and assets, not installed flash or publisher
authentication. Do not claim cryptographic device attestation. If automatic exact
identification requires a firmware change, document compatibility impact and
acceptance tests and make it in Firmingo only when required by the authorized
increment. Continue unaffected work. Messaging other agents/chats still requires
user authorization.

Stored associations must reference immutable descriptor identities, not a mutable
"latest" entry. Retain old compatible descriptors deliberately or report a
specific mismatch after SDK/firmware updates. Validate restored context; never
upgrade, rebind, replay commit or resume a write because a stored record exists.

## SDK and demo behavior

Provide SDK catalogue queries with explicit supported, experimental and unavailable
board/profile/platform combinations and actionable reasons. Provide automatic
compiler initialization/resource loading from the package bundle. Missing,
corrupt, incompatible or unapproved resources must produce structured errors;
normal host apps need no file picker, external toolchain, sibling checkout, Node,
shell, compiler subprocess or remote compiler. Keep existing worker isolation,
bounded outputs, cancellation/deadlines and source-revision protection.

The normal demo flow becomes:

1. Select a board and managed profile supplied by the SDK catalogue. Show supported
   source restrictions and experimental/qualification status.
2. Create/open a `.ino` document and choose an exact compatible firmware-build
   descriptor if more than one exists. Do not hide a compatibility decision.
3. Build offline using the immutable source snapshot and packaged SDK resources;
   display actual diagnostics, progress and artifact/receipt identity.
4. Explicitly select/connect a physical device and establish or review its firmware
   association. Display missing or mismatched evidence before enabling deployment.
5. Explicitly Run using the current source revision. Keep session ownership,
   durable journaling, exactly-one commit, uncertain-outcome reconciliation and
   process-local cross-window operation guards. Distinguish build, transfer,
   installation, startup and useful behavior.

Move compiler-service and resident-record import controls into an optional advanced
development/setup path after the normal bundled flow exists. Imported resources
still require integrity and compatibility checks; importing a record does not
authenticate it. Do not present synthetic test metadata as a trusted device record.
Keep direct Firmingo installation/recovery separate and reachable while disconnected.

Start with the existing experimental Nano managed recipe. Pico remains unavailable
for managed Build/Run until its firmware target, independently implemented recipe
and qualification exist. A board picker entry or conventional Arduino support is
not evidence of managed support. No catalogue work broadens the current sketch,
library, statelessness or execution restrictions automatically.

## Implementation order and acceptance

1. **Inventory and contract:** align repository ownership, pin references, and map
   extraction versus retained wrapper behavior. The inventory is documented; code
   migration remains open. Firmware export and service-review gaps are dependencies.
2. **Portable compiler:** Firmingo-Compiler defines bounded request/result/resource
   schemas, extracts the Nano pipeline, and tests real CLI/web WASM output against
   independent firmware validators. Service distribution review progresses alongside
   opt-in local-service tests without invented production descriptors.
3. **SDK adapter and catalogue:** retain public Swift APIs where practical, consume
   pinned compiler metadata/assets, translate progress/diagnostics/artifacts, and
   preserve resource limits, descriptor identity, persistence, cancellation/reentry,
   explicit selection, and unsupported-target errors before retiring duplicate code.
4. **Demo and deployment:** continue selecting through SDK APIs; require real device
   evidence and current source/build identity before staging, preserving journals,
   one commit, reconciliation, and cross-window guards. Test rejection before writes.
5. **Packaged consumers and qualification:** ship only reviewed reproducible assets
   and real descriptors derived from firmware exports. Verify consumer/archive
   loading without sibling inputs, actual signed macOS/physical iPad compilation,
   memory/timing/minimum-OS behavior, then separately authorized hardware deployment.

Completion requires a new host to compile supported source using only approved
compiler assets hosted through the SDK and an explicit target descriptor, then deploy only after valid
device association and capability checks. Record each gate as implemented,
experimental, qualified, unsupported or blocked with evidence. The current service
is 101196044 bytes; plan for package/app size and repeated hashing costs, and
measure actual distribution/runtime behavior. Bundled catalogue changes require
pinned compiler-package updates and coordinated SDK/app resource releases; remote catalogue updates are outside this
increment. Simulator builds, reference tests and packaging alone do not qualify
physical iPad execution or managed sketch behavior.

Implementation tasks are tracked in [TODO.md](../TODO.md). Root
[AGENTS.md](../AGENTS.md) governs contract safety and reference access; demo UI
requirements remain in [demo-design.md](demo-design.md) and
[Demo/AGENTS.md](../Demo/AGENTS.md).

## Delivered resource-loading foundation — 2026-09-30

`ManagedCompilerCatalogue.loadBundled()` verifies SDK-owned `inventory.json` and
all runtime/license/catalogue roles, then exposes the intentionally empty catalogue.
`ManagedSketchCompiler()` selects the same package inventory; builds currently
throw `ManagedCompilerResourceError.serviceApprovalPending` before preparing source
or starting WebKit. `init(serviceURL:)` retains the explicit development path
without an automatic fallback. The demo now starts with SDK metadata/resource checks and retains explicit
advanced imports; actual bundled compilation remains blocked until approved
production resources exist.

The closed schema-one inventory is 16-KiB/1024-token bounded and pinned in SDK
code. It describes one explicit Nano recipe/profile, `nano-stateless-facade-v1`
source contract and experimental/unqualified status, the exact ABI-two service
identity and pending review, and eight finite local runtime/source/license/catalogue roles with byte counts
and digests. Paths, duplicate roles/keys, scalar types, recipe/board/ABI identities
and size limits are validated before any role is read. Inventory integrity precedes
interpretation of its review declaration. Service approval is checked before
service-file I/O; a copied file or edited inventory cannot grant permission.

The `nano-stateless-facade-v1` source contract denotes the existing single-file,
freestanding/stateless Nano facade and linker restrictions documented in
[compiler.md](compiler.md). It introduces no Arduino libraries, Pico recipe or
platform qualification. The finite schema must deliberately evolve for additional
recipes or qualification changes, with updated validation and independent anchors.

Approved-branch tests use internal test-only root/hash injection; no public bundled
API accepts an override. They verify exact service bytes and the same toolchain
identity/output as explicit loading, but do not approve service redistribution.
The package contains no service and no synthetic descriptor.

SDK-local maintenance scripts retain deterministic pending inventory and an empty
catalogue and reject a staged unapproved service. Their output hash is reviewed
and manually pinned; they never update the Swift anchor automatically. Trusted
production metadata and service approval require the separate provenance/license
review and a deliberate packaging workflow update. See the DocC **Load SDK compiler
resources** guide, [maintenance commands](../Tools/ManagedWASM/README.md), and
[resource-loading evidence](compiler-resources-experiment.json).

The demo now consumes default loading and `ManagedSketchCompiler.verifyResources()`
through independent catalogue/compiler providers. It reports actual empty/pending
SDK availability and moves provider/import/legacy controls into the advanced path.
It never falls back after SDK failure, uses the selected SDK/default compiler for
Build, and retains fresh resource verification plus existing upload/journal gates.
See [demo design](demo-design.md) and
[default demo evidence](demo-default-resources-experiment.json).

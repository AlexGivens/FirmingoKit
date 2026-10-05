# Native demo design

The intended journey is select board → install Firmingo → connect → edit and build
supported source → upload → confirm useful behavior → use console → update/recover.
The SDK owns compiler, protocol, serial ownership, upload, and installation logic.
The demo owns documents, immutable source snapshots/revisions, presentation, and
explicit user decisions. It contains no Arduino restoration feature.

## First increment

`Demo/FirmingoDemo.xcodeproj` is a separate universal macOS/iPhone/iPad app with a
local FirmingoKit package reference and shared scheme. Native `DocumentGroup`
handles creation, open, save, and multiple documents; `SketchDocument` preserves
UTF-8 source and line endings, rejects non-UTF-8 input and files above 4 MiB.
The editor uses scalable monospaced text. Source edits increment a window revision.

On macOS a vertical split begins near two-thirds editor/one-third device/status,
with a draggable divider. iOS/iPadOS uses a stacked layout with a scrollable status
area. A native inspection sheet accepts an explicit board, numeric address, and
port. The user must request inspection; creating/opening documents never connects.
Inspection reports hello identity/backend/target counts and then disconnects.
The UI describes this as an inspection snapshot, never an ongoing connection or
hardware qualification. Cancellation and closed-window/sheet cleanup belong to a
window-scoped model, with generation tokens to reject stale results.

## Second increment: serial console

The same sheet lets the user select the expected application or UART backend and
explicitly connect and acquire channel one through `FirmingoSession`. The status
pane renders received bytes as hex or UTF-8. UTF-8 decoding may replace invalid
sequences for display only; the SDK retains exact bytes. The demo sends explicitly
entered UTF-8 bytes, with no automatic newline. Display updates are batched at
roughly 50 ms and only the newest 16 KiB remain visible, with a truncation count.
The SDK's pull stream instead applies bounded lossless backpressure. Closing the
console releases ownership and disconnects; window closure cancels its tasks.
Network permission, accessibility, and physical-board behavior remain unqualified.

Build/Run were added in the experimental compiler increment described below.
Installation remains a separate experimental SDK workflow.
No demo control calls a nonexistent operation or substitutes another firmware.

## Third increment: complete-image review

Prepare Firmingo Installation opens a disconnected-capable native sheet. The
user selects an unsigned release manifest and UF2, explicit board/profile, and
acknowledges source trust. The SDK performs bounded security-scoped local reads
and release/UF2 validation off the main actor. The sheet displays exact artifact
provenance, affected sectors, data effects, board-specific ROM steps, external
computer requirements, and interruption/verification limits from the SDK plan.
Selection changes or sheet dismissal cancel owned work and reject stale results.
Artifact review performs no device action. The next increment adds a separately
requested experimental writer, described below. Visual/accessibility and physical
file-picker/sandbox qualification remain unrun.

## Fourth increment: experimental macOS execution and saved context

After image review and the board-specific physical steps, the user explicitly
selects a ROM volume folder and confirms its association with the physical model.
The SDK checks generic USB/ROM attachment metadata; it cannot infer Nano/Pico from
that interface. Prepare Selected Target obtains a process-local one-shot token
without writing. A separate Install Firmingo confirmation presents the board,
version/profile, selected mount and data effects before calling the SDK executor.
Changing an artifact or target expires preparation and physical confirmation.
No scanning, automatic board choice, retry, reset, or offset resume is performed.

The window blocks new communication while programming, cancels connection attempts,
and hands its session to the SDK's idle-console close/unresolved-work gate. The SDK
owns every programming/protocol decision. Actual accepted counts come from SDK
callbacks. Cancel requests cooperative cancellation; failure after permission is
shown as unknown rather than failed/rolled back. File transfer completion and a
matching hello are visibly separate from exact-image identity and useful behavior.

The host journal saves operation-specific and latest-context JSON files atomically,
synchronizes files/directory entries, and awaits each save before acknowledging the
SDK callback. Storage errors stop the write gate/progress and remain visible. Latest
context is restored on sheet opening without connecting, preparing or resuming.
The previous mount is context only. Verification uses an explicitly entered numeric
endpoint and one SDK fresh hello; without prior device identity the user must verify
association with the USB target. Unknown writes remain unknown after matching hello.
A saved operation supplies SDK ROM recovery instructions and requires a new physical
selection, artifact review and user action for a full reinstall.

iOS/iPadOS offers artifact guidance, saved-context review and hello verification;
its direct USB writer remains unavailable. The macOS backend, sandbox device access,
file-picker behavior, durable restart handling, cancellation during real disconnects,
and physical installation/recovery are not qualified. No board was flashed during
implementation or deterministic tests. The development journal check writes only
beneath `.build`, tests save/load/retained operations/corruption/storage failure, and
never calls a native writer.

## Fifth increment: real local Build/Run

The editor captures UUID, revision, original filename and exact source into an
SDK request. Select Compiler Service chooses the exact reviewed local WASM binary;
it is not bundled while custom-service redistribution remains unresolved. Import
Resident Record accepts the bounded SDK format documented in `docs/compiler.md`.
The user confirms that this trusted build/install record identifies the installed
resident for that physical device. No API address/image identity is inferred from
hello, and no synthetic example binding is automatically selected.

Build (`⌘B`) compiles locally through the SDK's private WebKit worker and presents
real finite phase progress and all bounded source diagnostics. Run (`⌘R`) requires
Nano/application selection, imported trusted metadata, no unresolved journal and
an explicit review of managed-slot replacement/physical authorization. It builds
again, rejects edits/filename/target changes before upload, closes the console,
validates a fresh matching device connection, stages, saves synchronized context,
then requests one commit. Its mutually exclusive window state blocks console
acquisition and complete-image programming while Run is active. Firmware
programming invalidates the previous resident association.

A known accepted commit permits one new status sample. The host distinguishes
committing, installed, startup-confirmed, failed and unknown states; it never
retries commit or starts another upload automatically. Check Outcome / Open
Console is a separate explicit action after uncertain results. Only startup
confirmation permits console acquisition, still gated on exact expected device ID;
it proves setup and one loop returned, not useful sketch behavior. Context persists
across window/app closure, blocks another Run and can be explicitly cleared while
retained history remains. Corrupt saved context blocks Run until explicit review/clear.
An offline Build remains possible without a connected microcontroller.

Real development macOS WebKit/controller checks use synthetic bindings and never
connect or upload. Signed app, actual file picker, physical deployment, useful
behavior, VoiceOver/layout, minimum-OS and physical iOS/iPadOS qualification remain
open. Pico/full Arduino libraries/runtime helpers and arbitrary sketch layouts
remain unsupported. Service selection is a temporary development capability;
normal builds do not require Node, shell, a native Arduino toolchain or a sibling checkout.

## Sixth increment: catalogue selection and independent offline Build

The default compiler selection mode now consumes SDK catalogue queries and offline
compiler APIs. Until approved resource packaging exists, **Development resources**
offers explicit service selection, a trusted catalogue SHA-256 field and a JSON
importer. The anchor must come from independently reviewed provenance; the demo
does not hash an untrusted file to manufacture its own trust anchor. Reads are
regular-file-only, bounded and cancellable off the UI actor, with balanced picker
scope. The SDK owns schema/hash/board/recipe validation and unavailable reasons.
No descriptor is bundled, automatically selected or fabricated.

The Build board is independent of device inspection settings. Firmware choices
come from `catalogue.builds(for:)`, identify exact content IDs and show profile,
experimental status and ELF/image hashes. No latest/first choice is implied. Pico
shows the SDK's unavailable reason. Board/build/mode/anchor changes discard old
selections or outputs and revoke physical review. Missing/failed imports never
fall back to another mode. Offline Build uses `ManagedOfflineBuildRequest`,
retains its exact catalogue/descriptor/source receipt and requires no connection,
endpoint, backend or device association. Source edits cancel work and reject stale
results. Revoking device review does not cancel an independent offline build.

Import Device Association strictly restores separate SDK evidence and validates
its exact descriptor match. The UI displays the declared device ID, evidence
kind and any installation-operation reference; it explains that these are host
assertions, not installed-image attestation. Import never grants review. Run is
enabled only after explicit review and save, matching Nano/application device selection,
loaded/unblocked journal context and idle host operations. It rechecks durable
cross-window journal and exact saved association before compiler loading, compiles the current snapshot, binds
the resulting artifact, connects with expected device ID and preserves the existing
stage/save/one-commit/uncertainty workflow. Device selection revokes association
review; the view revokes review at both the start and end of firmware programming
and disables evidence import/review during it. No automatic association is inferred
from hello.

Legacy resident record remains an explicit compatibility mode. Service/file scope
and all tasks remain window-owned. Reviewed catalogue associations can be explicitly
saved in app-private storage; reopening loads the roster without automatic device
or firmware selection and without restoring trust. Managed transaction persistence
is separate and unchanged. Legacy combined records require explicit new association
evidence rather than an inferred descriptor migration.
The controller harness uses synthetic parser metadata and real offline WebKit
compilation, never a board connection. Apple builds and retained legacy/coordination
harnesses pass. The user disabled agent visual inspection; source/controller/build
validation does not establish layout, keyboard or VoiceOver qualification. Signed
sandbox, physical iPad and hardware remain unqualified.
Exact evidence is in [demo-catalogue-experiment.json](demo-catalogue-experiment.json).

## Planned increment: bundled resources and normal setup

The user accepted [compiler-catalogue.md](compiler-catalogue.md) on 2026-09-30.
The imported catalogue flow above delivers part of this direction. Production
resources and automatic loading remain open.
The demo must consume SDK catalogue queries and default resource loading so a
developer sees how their own host receives the compiler, supported board recipes
and exact trusted firmware-build metadata from FirmingoKit.

Normal setup will select an SDK-listed board, managed profile and exact compatible
firmware-build descriptor. Build will compile a document snapshot offline without
a physical device, compiler picker or installed-image confirmation. Display source
restrictions, resource errors and experimental/unavailable status from SDK data;
keep Pico managed Build/Run unavailable until its firmware target and recipe exist.
Do not copy assets, invent device identifiers or implement recipe matching in UI.

Run still requires an explicitly selected connected device, reviewed association
with the exact firmware build, fresh negotiated capabilities and the current source
revision. Provide guided existing-device setup when evidence is missing; a bundled
descriptor alone cannot prove what is installed. Retain explicit deployment review,
one commit, durable context, uncertainty/reconciliation and cross-window guards.
Firmware installation/recovery remains a separate SDK workflow and user action.

After the normal bundled flow is implemented, move compiler/record import controls
to an optional advanced development/setup path with their validation intact.
Licence/provenance clearance precedes service distribution. Validate this flow in
a signed physical iPad app and a separate minimal package consumer; neither a
board-picker entry nor a successful Xcode build establishes hardware support.

## Subsequent acceptance

The shared journal actor now guards device operations across document windows.
Run and complete-firmware installation recheck saved managed context before
deployment; a pending or unreadable record blocks both. An outcome check reserves
the currently saved transaction, and an explicit clear rejects a newer valid
record instead of discarding another window's context. A conflict refreshes the
stale window without performing its rejected action. Only the reservation's owner
can release it; cancellation and cleanup retain ownership until the action ends.
Offline Build can proceed independently. The guard covers one app process and
does not establish cross-process, real-board or sandbox behavior.

- Build captures a document identity, source revision, exact catalogue/firmware-build
  selection and verified recipe/toolchain identity; progress and diagnostics come
  from the SDK. Legacy mode retains its explicit resident binding.
- Run rejects failed/cancelled/stale output and mismatched targets before writing,
  then distinguishes transfer, commit, installation, startup, and useful behavior.
- Installation/update/recovery remains reachable while disconnected and presents
  the SDK's reviewable plan and physical steps before an explicit execution request.
- Console text is a host interpretation of SDK bytes, with bounded batched display,
  visible truncation, explicit encoding/newline settings, and controlled announcements.
- VoiceOver, focus, keyboard editing/commands, scalable text, light/dark/increased
  contrast, reduced motion, compact iPhone layout, sandbox permissions, and restart
  recovery need host validation. Native controls alone do not qualify these checks.

The unsigned build commands do not select a signing team or install on hardware.
For a device run, select your development team in Xcode. Entitlements enable the
macOS App Sandbox, user-selected read/write documents, and outgoing TCP; Info.plist
includes local-network usage text. No Bluetooth/Bonjour discovery is configured. User-selected ROM folder access
reuses the existing read/write entitlement; real Disk Arbitration/IOKit visibility
and USB-volume access in a signed sandbox app still require qualification.

## Saved device associations — 2026-09-30

The shared journal actor stores a separate `device-associations-v1.json` host
envelope: schema version 1 and an array of base64-encoded strict SDK association
JSON records. It bounds the envelope to 16 KiB and sixteen distinct device IDs,
sorts by device ID and validates each record with the SDK on every load. Saves
use atomic replacement plus file/directory synchronization. No trust flag, endpoint,
compiler file, descriptor selection or device permission is persisted.

**Save Reviewed Association** requires an exact selected descriptor and current
host review. **Saved device associations** offers explicit restore only for a
matching selected build, and explicit confirmed removal even if that build has
been removed from the loaded catalogue. Reload revokes review. Save/removal compare
the complete window snapshot to current storage; changes refresh the roster and
revoke review without repeating the mutation. Device operations prevent roster
mutation, and Run rechecks the exact saved association before reserving the device.
These are process-local guards, not a cross-process file lock.

Malformed, oversized, duplicate-device, unreadable, symlinked or future-schema
storage blocks catalogue Run and association mutation; offline Build remains
independent. The demo does not automatically repair or migrate corrupt records.
After external correction, explicit reload is required. A save failure may follow
a completed atomic replacement, so the controller reloads instead of reporting
that nothing changed. Removal never clears upload journals or changes firmware.

The host-only regression harness covers durable reopen, no automatic selection or
trust, exact/missing descriptors, save/forget, stale Run before compiler/network
access, stale mutation, reservations, bounds, malformed records, cancellation and
I/O failure. See [association persistence evidence](demo-associations-experiment.json).

## SDK default sources — 2026-09-30

The demo now starts with SDK catalogue loading and resource verification. It calls
`ManagedCompilerCatalogue.loadBundled()` and `ManagedSketchCompiler.verifyResources()`
without importing a file, compiling source, starting WebKit or contacting a board.
The actual shipped catalogue is empty and service review is pending, so Build/Run
remain unavailable with separate SDK-issued metadata/compiler reasons. No descriptor,
device, review or development fallback is selected automatically.

Compiler and catalogue providers are explicit independent choices under
**Development resources**, alongside the retained legacy mode. Catalogue imports
remain anchored and service imports remain verified by the SDK. Returning to SDK
compiler resources releases the old file capability; returning to development
metadata requires explicit reimport. Provider/resource changes expire output and
physical review. An unused development hash edit does not discard SDK metadata.
Source/provider state is window-owned and not persisted.

**Reload SDK Resources** retries metadata discovery and, when the SDK compiler is
selected, resource verification. It is disabled when both providers use explicit
development imports. Late startup cannot override those choices. Changing source,
cancelling or closing a window prevents late dependency completions from publishing
metadata/readiness. Compiler verification uses the same SDK reservation as Build,
confirms integrity only and caches no bytes; actual Build independently revalidates.
A structured SDK resource failure during Build revokes the setup-ready observation.
Neither verification nor catalogue loading authorizes device operations.

The new host-only default controller harness validates actual shipped availability,
provider transitions and released capabilities, late startup, failed imports/reloads,
cancelled/closed-window callbacks and fresh retries. Internally injected synthetic
ready metadata tests controller observations only: requesting Build still reaches
the real SDK and fails pending-service verification before runtime/device access.
Retained real-WASM catalogue/legacy and association/coordination harnesses validate
existing behavior. No visual inspection, hardware or signed sandbox qualification
is claimed. See [default demo evidence](demo-default-resources-experiment.json).

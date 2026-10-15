# Nano SDK hardware qualification

The separate [FMS2 qualification procedure](nano-fms2-qualification.md) uses
NanoStateful and an explicit version-2 catalogue. Historical ABI-one evidence
below retains its original scope.

`Validation/NanoHost` is a separate minimal SDK test app for the constrained Nano
managed resident. The compiler-only app keeps its no-device behavior. This host
exposes explicit offline preparation, hello inspection, operator association,
RAM staging, one-shot commit, read-only reconciliation and observed behavior.
No connection, association, install or upload occurs at normal launch. There is
no initial firmware writer, discovery, automatic selection or commit retry.

## Pinned preparation without a board

```sh
node Tools/Hardware/prepare-nano-test.mjs REVIEWED_CONSUMER_PACKAGE NEW_TEST_INPUTS
python3 -I -S -B Tools/Hardware/make-nano-host.py \
  PREPARED_SDK PREPARED_MANIFEST_SHA256 NEW_TEST_INPUTS TEST_PLAN_SHA256 NEW_HOST
```

The first tool verifies the entire independently anchored consumer package
`1bbc0cc1…`, then copies only its twelve firmware evidence roles, catalogue and
original consumer manifest. It writes the new test-plan digest last. No compiler,
firmware build, board, network or flash operation is invoked. The second tool
verifies the caller's plan anchor, all copied evidence against the original
consumer anchor, and the prepared SDK through the existing compiler-host verifier.
It creates a distinct `NanoQualification` project/bundle identifier, with the
shared host Swift files and generated SDK context. Firmware files remain outside
the app's Sources/resources in `TestInputs`; the prepared SDK supplies compiler
resources and accompanying source/notices. Binaries remain outside Git.

The selected CI resident is Firmware `e0a79d1…`, build `c44d25ef…`, API
`0x10022c9c`, resident ELF `5b3116cd…` and resident-only UF2 `35678c95…`.
The full identifiers are in the anchored test plan. Source/toolchain provenance
limits remain those of that export; preparation does not qualify hardware.

**The resident-only UF2 preserves the existing managed slot.** Initial setup
must separately review/read back or initialize that slot before booting unknown
prior code. This package is not an automatically safe composite or a production
installation release. Select one recoverable physical Nano, record its identity,
then review the exact initial ROM setup and readback procedure using Firmingo's
managed-sketch/recovery guidance before any flash operation. Nano REC/GND recovery
and D2/GPIO25-to-GND upload authorization are different actions. No initial
flashing is included in this host or either preparation command.

## Build and offline check

Build the generated project using scheme `NanoQualification` and an explicitly
selected macOS/iOS destination, following the existing signed compiler-host build
procedure. The macOS entitlement file is `NanoQualification.entitlements`; the
expected bundle identifier is `com.firmingokit.nanoqualification`. iOS has an
explicit local-network usage description, no Bonjour declaration/background mode.
Actual iOS local-network permission and board connectivity remain hardware checks.

For an already development-signed sandboxed/hardened macOS app:

```sh
python3 -I -S -B Tools/Hardware/run-nano-offline.py \
  APP_PATH TEAM_ID GENERATED_HOST NEW_RESULTS_DIRECTORY
```

This launches only `--nano-offline` with a fresh run UUID. That mode refuses all
device connections, compiles the two fixed sources through the default public
SDK, checks known capsule identities, exports its own journal/capsules through
bounded stdout and exits on macOS. The runner checks signature/entitlements,
run/context, complete offline-only events and actual 316-byte GPIO/392-byte
console outputs. The outer timeout terminates only its own child. An offline
pass does not qualify hardware or upload behavior. Existing pending-transaction
restoration cannot be counted as a clean offline run.

## Explicit later board workflow

1. Prepare both sources offline. Enter the numeric endpoint and an independently
   selected real Nano device ID. Inspect sends only hello and checks board,
   application backend, resident version and the exact upload-target limits.
2. Review the exact installed resident using separately obtained installation/
   readback evidence. Type its full resident-only image digest and record how it
   was established. This is a `hostConfirmedExistingFirmware` assertion; hello,
   version and the UI action do not attest flash bytes. Setup fields are locked
   after association; reinspection invalidates it. Stage rechecks actual identity/boot.
3. After separately selecting physical D2/GPIO25-to-GND authorization, choose one
   of the two compiled sketches and explicitly stage it. The SDK verifies RAM
   transfer; no flash commit has happened. Persist the validated record before
   enabling commit. Staging holds a live connection with the firmware's idle
   expiry; it cannot be resumed after restart or foreground loss.
4. Explicitly install once, or abort the RAM stage. Commit intent is consumed
   and journaled before the SDK call. A missing/rejected reply stays uncertain.
   The host never resends commit. Keep the physical arm present through install.
5. Query status through a fresh identity-validated session. Distinguish queued,
   installed/readback, boot-confirmed, failed and unknown outcomes. No automatic
   polling/reconnect/retry occurs. Failed/unknown outcomes block new staging.
   Restored records allow queries only. A known boot-confirmed or aborted result
   permits a new explicit operation with fresh inspection/association.
6. For the console sketch, check all 256 byte values exactly with a five-second
   bound; retain mismatch offset/count evidence. Setup's `ready` output predates
   console ownership and is not required. For the GPIO sketch, record an actual
   D13/GPIO6 observation with board-correct polarity/measurement; startup alone
   cannot supply it. Journals never automatically mark overall hardware support.
7. Repeat with the other sketch. Record USB attachment/authorization, Internet
   coexistence and wireless app-development connectivity separately, iPad first
   then iPhone. Keep power-cut/flash-corruption tests out of this initial workflow.

Journals and immutable per-transaction records stay in the app's own Documents.
An unresolved pointer is saved atomically/synchronized before commit; this is not
a power-loss rollback or directory-fsync guarantee. Process restart never restores
a live RAM-stage/commit capability. Losing foreground cancels active normal-mode
work and closes a staged connection. Explicit offline-only compilation has no
device capability and does not impose this hardware-host foreground policy.
Share journals explicitly; keep device identities and setup notes local unless
reviewed for publication. Compiler-host raw evidence remains separate.

## Source checks and current boundary

```sh
python3 -I -S -B Tools/Hardware/test-nano-host.py
python3 -I -S -B Tools/Hardware/check-nano-gates.py
python3 -I -S -B Tools/Hardware/check-nano-host.py
python3 -I -S -B Tools/Hardware/check-nano-host.py --ios-products BUILT_IOS_PRODUCTS
```

Eight fixture-only input/generator/export cases and the production admission/
state-observation executables cover anchors, unsafe/replaced inputs, project isolation,
stale endpoint/device/boot, evidence, one-shot intent, restoration, terminal
advancement and rejected offline results. These are included in the ordinary SDK
validation entry point; optimized iOS source checks also run in Apple CI. Complete
app execution and every real board operation remain explicitly selected checks.
No GPIO, byte-integrity, upload, install, authorization or routing hardware pass
follows from source checks or offline compilation.

## Recorded offline preparation

[Preparation evidence](nano-hardware-preparation.json) records the exact test-plan
anchor `861e0089…`, fourteen copied evidence roles, generated app inputs, source
commits, signature, local tests and actual offline output. The corrected signed
ARM64 macOS app at `24993ce…` compiles both known capsules through prepared SDK
`4edc6aa…` and exports their independently checked bytes with a fresh launch UUID.
Both complete Release app builds pass, with no Swift warnings and only the
standard AppIntents no-framework note. The iOS build has signing disabled and
was not installed or run. No device connection, flash or upload occurred.

The first view-task-driven signed run exported nothing and reached its outer
180-second timeout; it remains a failure. Explicit offline startup now belongs
to the app lifetime, independent of view appearance, with bounded stage diagnostics.
The corrected signed run emits all four required offline stages and matching
capsules. No private container or native UI was inspected to collect either result.

The first full SDK entry-point invocation also failed overall: all 154 Swift
Testing functions passed, but an empty XCTest bundle failed architecture loading.
The package exclusively uses Swift Testing. The corrected entry point explicitly
selects that runner and rejects new XCTest imports/classes until the selection is
reviewed; the full command now succeeds with 154 functions and nine explicit
absent-service cases, the twelve compiler-host/four then-current Nano tooling fixtures,
production policy executable and both macOS host source checks. Optimized iOS
source checks and workflow YAML/bash checks pass separately. Remote SDK CI
remains unprovisioned/unrun. Neither failed invocation counts as a successful gate.

## Selected initial setup and iPad handoff

[Initial setup evidence](nano-hardware-initial.json) records the signed iOS build
2, existing profile coverage for both selected devices and successful wireless
iPad installation/launch. Normal launch performs no preparation or connection.
No provisioning updates were requested; the exact development entitlements are
recorded. UI/accessibility inspection was not used and is not qualified.

Firmware's [separate initial setup](../../Firmingo/docs/evidence/nano-sdk-initial.md)
records user-selected ROM identity, verified exported resident plus known SDK
GPIO capsule, full composite readback before reboot and a matching macOS hello.
The 314,368-byte composite `4fb60a48…` initializes the entire first managed sector;
its resident payload retains the distinct `35678c95…` identity. This avoids unknown
preserved sketch contents for this test. The initial ROM operation is a firmware
maintenance workflow, not an SDK installation-backend pass. Physical iPad USB
authorization/hello and subsequent managed stage/commit/startup/behavior remain
pending. Move the Nano only after this setup; use the app's explicit controls.

## First physical iPad inspection and label correction

[The iPad record](nano-hardware-ipad.json) retains build-2 run `0D622BC5…`:
both actual compiled capsule files match the known 316/392-byte vectors and pass
Firmingo's production validator, including wrong-API/corrupt-code rejection.
The first recorded inspection failed with `Network is down`; a subsequent
explicit inspection succeeded against the selected device and fresh boot.
Neither its cause nor a clean cold-attachment/authorization pass is established.
The user reported the checked-hello status and a lit D13 LED while the initial
ROM-installed GPIO sketch was selected. This is a manual LED observation, not
an electrical measurement, loop timing proof or SDK managed-install result.

The own-run journal/capsules were retrieved while CoreDevice still reported
`localNetwork` and the Nano occupied the iPad port. This establishes the scoped
SDK hello plus wireless development/report retrieval, not uncached Internet
coexistence or the wider USB authorization matrix. No association, RAM stage,
managed commit/startup or console behavior occurs in that recorded run.

The user also found that status and filled input fields were difficult to
identify. Build 3 (`796c776…`) adds a persistent Status heading, visible field
labels and rounded input borders. Source checks on both Apple platforms, four
tool fixtures, the complete signed iOS build and signature/generated-source
verification pass; the app was updated and reopened over Wi-Fi after preserving
the original run. It makes no SDK/compiler/protocol or admission-policy change.
Source/build checks do not establish visual or accessibility qualification.

The build-3 run `093CBE25…` now records a successful first managed console
upload: reviewed resident association, verified RAM stage, one host commit
attempt, `committing` reply, fresh `boot_confirmed` status with `error=none` and
`slotTouched=true`, then exact 256-byte console echo. Actual capsule bytes and
the saved transaction bind the same selected physical device/boot, resident
and 392-byte console digest. The firmware validator accepts those exported bytes.
The journal also retains one local prerequisite rejection before the successful
association; its cause is not established and it did not precede a stage/commit.
No intermediate `installed` status was separately sampled. There is no packet
trace counting wire commit requests or throughput/soak/trailing-frame interval
claim.

The same build-3 run now also completes the second managed GPIO upload. After
the first transaction was known boot-confirmed, the user explicitly started the
next operation and pressed RESET. A fresh hello observed the new boot and the
user reported D13 off. A fresh reviewed association and the known 316-byte GPIO
capsule then passed RAM verification, one host commit attempt and a fresh
boot-confirmed query. The user observed D13 on and saved that manual observation.
Both per-boot transaction records and the complete 23-event journal were retrieved
and checked against the prior console snapshot, exact resident/capsule identities
and new boot. The same production firmware validator accepts the actual exported
GPIO bytes. The second operation includes two explicit hello inspections; neither
implicitly associated or uploaded. This is a scoped iPad two-sketch workflow pass,
with a manual LED transition and exact console bytes, not general Arduino support,
minimum-OS, clean cold-attachment, Internet routing, soak or power-loss evidence.
The physical iPhone managed workflow is recorded separately below.

## Physical iPhone console and GPIO result

[The iPhone record](nano-hardware-iphone.json) pins the identical signed build-3
app on iPhone 15 Pro Max/iOS 27.0 (24A437), its actual compiler outputs and
22-event final journal. The first inspection failed with `Network is down`
around the user's reported access prompt; one later explicit read-only attempt
passed without reset/reconnect. Prompt type, cause and clean cold-attachment
timing were not independently established. Both known capsule bytes pass the
production firmware validator, including wrong-API/corrupt-code checks.

The reviewed console association/RAM stage led to one host commit attempt,
`committing` reply, fresh `boot_confirmed` status (`error=none`, `slotTouched=true`)
and exact 256-byte echo. The user explicitly started the next operation, pressed
RESET and observed D13 off after a fresh hello. A fresh reviewed association and
GPIO upload then produced the same stage/commit/startup outcomes, followed by
the user's D13-on observation. Both saved records match the selected device,
their different boots and exact resident/capsule identities. Earlier failed
attempts are retained. Intermediate installed status was not separately sampled.

Final own-run retrieval still used paired `localNetwork` while Nano occupied
the iPhone USB port. This is development/report connectivity, not uncached
Internet routing. PCB revision and cable/hub model were not recorded. The user
removed D2-to-GND and left REC disconnected at completion. No further Nano
operation followed. These are scoped experimental two-sketch passes on the
recorded Apple devices; general Arduino/other boards, minimum OS, electrical
GPIO timing, throughput/soak, full authorization/cold-attachment matrices and
interruption/power-loss/rollback remain unqualified.

## Subsequent initial-permission handling

[Connection readiness](connection-readiness.md) describes the subsequent SDK fix
and read-only fresh-bundle qualification mode. Initial Network.framework waiting
now stays within the original five-second deadline, while established path loss
still closes. The host lets only pending read-only inspection await an inactive
permission overlay; background/Cancel still cancels. This change does not rewrite
the build-3 first-attempt failures or promote the earlier records to clean cold
attachment passes. Subsequent signed NanoPermission build 4 records first-attempt
prompt approval/hello on iPhone, and an original-deadline timeout followed by a
separately requested successful inspection on iPad. The iPad approval time was
not measured; it is not a first-prompt pass. Exact evidence is in
[connection-readiness-qualification.json](connection-readiness-qualification.json).
These are read-only results with the updated SDK, separate from earlier build-3
uploads. Nano staging/commit retain their existing policies. Follow
[the read-only USB/routing procedure](nano-usb-readonly-checks.md) for separately
selected authorization, cold-attachment and Internet checks.

# Workbench managed upload and recovery

Started 2026-11-04. The app-owned shared engine now exposes separate FMS2 phases
through Test Lab, the paired CLI and the existing four MCP tools. They use public
FirmingoKit compiler/upload APIs, the existing demo-wide deployment guard and
bounded synchronized checkpoints. No application launch starts an upload.
Historical Nano hosts remain for unmatched interruption, fault and ROM tests.

| Scenario | Effect and required evidence |
| --- | --- |
| `managed.stage` | Compile fixed State A or B through actual SDK/WASM, check the pinned capsule, recheck selected identity/boot/backend/target, then verify RAM only. Requires reviewed resident digest/evidence and `stage-d2-gnd`. |
| `managed.commit` | Save commit intent and consume the current process's verified stage before one SDK commit call. Requires its exact record hash and separate `commit-once-d2-gnd`. Acceptance is not installation or startup. |
| `managed.abort` | SDK abort of the live pre-commit stage; requires an actual matching aborted snapshot with no slot write. |
| `managed.disconnect` | Close the pre-commit session without abort or commit; preserve query-only context and the pending guard. |
| `managed.restore` | Read the exact host checkpoint/current record hash by original operation ID. No network, automatic execution or restored commit permission. |
| `managed.reconcile` | One fresh SDK status query for the saved record. Committing/installed, failed, boot-confirmed, aborted and unknown remain different outcomes. |
| `managed.retire` | Release only known no-commit host context after an observed changed boot, or explicit retirement of a checkpoint with no issued record. It never changes an unknown device outcome to success. |

## Fixed inputs and prerequisites

This increment selects the existing reviewed Nano FMS2 descriptor
`dacbf259b96de0e050514764253403f3ef1ef51d0f9efaf1f43a10d8654c0e18`,
resident-only UF2 `1ef766226ce6a2c51c668562cd51a71ed0bfbe1634b76b54d704c7e710ca1b2f`
and resident ELF `bf32639c7fc2181c9ff6f99aaf8c64e19bda4f83f9690321e2b098bc81e451a8`.
It expects the separately installed `0.1.0-statefulupload-exp1` resident and
target 2 / `nano-managed-v2`. The ordinary 0.1.0 application used for the raw
console checks advertises no upload target and cannot perform this workflow.

Tracked `Resources/ManagedQualification` supplies only the unchanged two source
vectors, exact imported catalogue and provenance note. The driver verifies source,
catalogue and 544/548-byte capsule pins. It neither bundles installable firmware
nor promotes this experimental descriptor into the SDK's default catalogue.
Actual compilation still requires an explicitly prepared reviewed SDK package.
Missing assets are blocked, never a compiler or hardware pass.

First inspect the exact selected Nano. Establish its installed-resident association
separately from hello, then supply the reviewed image digest and actual evidence
note. Keep REC disconnected. Connect D2 to GND only when ready for the separately
authorized staging/commit workflow, and remove it after testing. The firmware
enforces physical authorization; a UI toggle or MCP string cannot simulate it.
Hello, hashes and constructing an SDK association do not attest installed bytes.

## Agent and manual flow

Use the same persistent Workbench app for every phase. Launch-and-exit automation
rejects live stage/commit/abort/disconnect; use `paired.py command` or MCP instead.
Test Lab presents the same action registry, reviewed resident fields, original
operation UUID, current record hash and separate stage/commit authorizations.
Selection changes expire consent. Selecting saved history loads query context
only; it never recreates a live session. Backgrounding or unpairing closes live
staging and preserves the pending checkpoint.

For MCP, submit `workbench_submit` with `action: run`, a new command UUID and a
fresh run UUID. Device fields are `device_address`, `device_board`, `device_id`
and the original inspected `device_boot_id`; no console probe or compiler
descriptor override is accepted. Stage additionally takes:

```json
{
  "scenario_id": "managed.stage",
  "managed_operation_id": "SAME_UUID_AS_THIS_STAGE_RUN",
  "managed_sketch": "state-a",
  "resident_image_sha256": "1ef766226ce6a2c51c668562cd51a71ed0bfbe1634b76b54d704c7e710ca1b2f",
  "resident_evidence": "ACTUAL_REVIEWED_INSTALLED_RESIDENT_EVIDENCE",
  "managed_authorization": "stage-d2-gnd"
}
```

After RAM verification, export that run with the same expected selection on
`workbench_result`. Its `managedEvidence.recordSHA256` is the exact canonical SDK
record identity. A later phase uses a new command/run UUID, the original device
selection and `managed_operation_id`, plus `managed_record_sha256`. Commit also
requires `managed_authorization: commit-once-d2-gnd`; other follow-ups reject it.
Do not repeat a commit after uncertainty. Query an uncertain controller command
by its original command ID; submit a separate reconciliation only when its
transaction context is established.

After app restart, explicitly select `managed.restore` using only
`managed_operation_id` and original device fields. The returned validated
checkpoint/current hash supports later status or host retirement. It permits
neither restaging nor commit. If no transaction record was issued before
interruption, its canonical hash is SHA-256 of JSON `null`; reconciliation reports
`recordNotIssued` without contacting the device. Explicit retirement records
`retired_unissued`, meaning only that this host never admitted commit.

`paired.py command --action run --wait` accepts the same field names with hyphens.
`check-codex-device.py --managed-action ...` provides an opt-in native Codex MCP
check. Stage mode first inspects the selected device and uses its actual boot;
follow-ups require the original operation/boot/hash. The helper refuses revocation
at the end of staging, preserves non-pass exports before exiting, and never sends
a second commit. These helpers perform no firmware setup or deployment.

## Contracts and safety boundaries

Managed requests/reports use schema **3**, with a closed `managed` selection and
explicit device selection. Compiler schema 1 and inspection/console schema 2
retain their original authority. The outer paired transport remains schema 1;
MCP adapter version is 0.3.0. Arbitrary source, artifact bytes, ports, service URLs,
shell, reset and ROM commands remain unavailable.

The original stage run ID exclusively reserves its context. A durable owner
blocks normal Run, console writes, firmware installation and generic journal
clearing even if the process exits before a transaction record is saved. Shared
SDK records and checkpoints synchronize before commit. Terminal matching startup
or abort, validated pre-commit retirement, and failed unissued-stage disposal are
the only automatic guard-release paths. History remains. Persistence failures
stop later side effects; report publication failures dispose a live stage.

Only a process-local verified SDK connection can commit or abort. It is consumed
before suspension, and no decoder recreates it. The controller tracks its own
stage for scoped unpair cleanup. Pending writes never resume on reconnect or
app launch. Commit uncertainty remains unknown even after cancellation. A failed
firmware snapshot inside a successful FMGO envelope remains failed. Boot-confirmed
startup is separate from useful console/state/GPIO behavior.

The global guard deliberately stays closed on post-commit unknown/failed outcomes;
those require separately reviewed recovery rather than automatic clearing. Real
reply withholding, termination at additional stage/commit boundaries, flash fault injection,
SDK ROM installation/recovery, initial resident setup and broader sketch/board
support are not migrated by these seven phases. Keep the existing Nano/ROM hosts
and their historical evidence until equivalent replacements pass.

## Work log and qualification

Implementation and source-checkout validation passed locally. The normal SDK
entry point passed 166 SDK cases discovered (ten opt-in runtime skips), eight
ROM-host cases and 39 Workbench cases discovered (TLS and the new explicit
prepared-driver runtime case skipped). CLI / paired / MCP fixtures passed
20 / 11 / 19 cases. Complete unsigned Release app builds passed for macOS, iOS
device and iOS Simulator. The real coordination harness and pinned official
modern/legacy MCP clients also passed. These are local results, not remote CI.
The host is now Xcode 27.2 (27B52) / Apple Swift 6.4.2; the separately provisioned
CI baseline remains pinned at Xcode 27.0 / Swift 6.4, with no toolchain upgrade
claimed by this change. The fixed driver
has an explicit `WORKBENCH_MANAGED_RUNTIME=1` test for real SDK/WASM compilation
of both vectors from a prepared package, with no network or board call. Ordinary
tests skip it when unprovisioned. Fixtures exercise production coordination,
versioned request/report scope, exact resident/record binding, intent/write gates,
restart without commit restoration, uncertainty, pre-commit/unissued retirement,
background disposal and failed success publication. The real demo-store harness
checks pending-owner exclusion and preservation of history. These source-only checks do not establish physical qualification. Previous
raw-console iPhone/iPad results remain scoped to
their original build 10 and ordinary application.


The clean implementation checkpoint `dd718468f6d498a825c1fa760f9e644c78fcd43f`
now passes the explicit real default-driver test from prepared inventory
`a9744e0ea658579f78b6f8b3a1a3391c0898ad7886687b090e742af1a448a907`:
both fixed vectors match in 2.346 seconds with no board connection. Development-
signed build 11 passes strict/deep signature verification. The reviewed FMS2
resident/initial State A composite has also been installed on the selected Nano
and all 158,208 included bytes independently compared in ROM before reboot.
[Preparation ledger](workbench-managed-preparation.json) retains exact identities;
the setup is separate from the managed path qualified below.
The older native checker cache referenced the removed macOS 27.0 SDK; an isolated
sanitized checker was freshly configured/built with the installed SDK before the
final image preflight. No firmware source or toolchain pin changed.


Signed build 11 now completes the selected Nano/iPad managed workflow through the
registered native Codex MCP host. [The qualification ledger](workbench-managed-ipad-qualification.json)
retains 29 checked reports and original native submission/report envelopes:

| Check | Observed result |
| --- | --- |
| State B RAM stage, explicit abort, fresh query | Aborted, slot untouched; State A exact echo retained |
| New State B stage and one explicit commit | Fresh boot-confirmed status; exact echo; user observed D13 lit |
| New State A stage and one explicit commit, then app restart | Saved commit intent restored; attempted commit from restored context refused locally; fresh boot-confirmed status and exact echo; user observed D13 off |
| New State B RAM stage, disconnect without commit | Fresh aborted/disconnected status, slot untouched; State A exact echo retained |
| New State B RAM stage, manual USB power cycle | Original transaction remains outcomeUnknown/bootChanged; explicit no-commit host retirement; fresh boot inspection and State A exact echo; user observed D13 off |

The two successful commit phases are distinct from the expected refused request
after restart: no firmware commit was replayed. Twenty-seven reports pass; the
refusal remains failed, and the changed-boot reconciliation remains unknown.
The restart followed an accepted commit reply, so it does not test reply loss.
Both unique capsule exports match the pinned vectors and pass the firmware's
independent native FMS2 checker; native validation does not execute ARM code.
The archived schema-three corpus is checked by `test-mcp.py` (20 passing cases),
including scope mismatches, the original refusal/unknown and final revocation.
The existing normal CI entry point runs that offline regression; no remote CI
result is claimed here. Pairings are revoked, the controller is stopped, and the
user removed D2. The Nano remains on the iPad running State A.

Next qualify the identical managed build on iPhone, then migrate the initialized-
data/BSS/counter probe and specialized reply-loss/flash-fault/SDK ROM paths. Manual
D13 observations are not electrical measurements, and command-2 echo does not
replace the state probe. Broader models, minimum OS, UI/accessibility, arbitrary
sketches and production 1.0 support remain outside this evidence.

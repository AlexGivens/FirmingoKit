# Nano FMS2 qualification

This opt-in host exercises the versioned stateful contract without changing the
default ABI-one catalogue. The app is **NanoStateful**, bundle
`com.firmingokit.nanostateful`; its Xcode project, scheme and executable remain
`NanoQualification`. Its container is separate from earlier qualification apps.
Normal launch performs no compilation or device operation.

## Explicit preparation

```sh
node Tools/Hardware/prepare-stateful-nano-test.mjs \
  REVIEWED_CONSUMER EXPLICIT_FMS2_EXPORT EXPLICIT_IMPORTED_METADATA NEW_TEST_INPUTS
python3 -I -S -B Tools/Hardware/make-nano-host.py \
  PREPARED_SDK PREPARED_MANIFEST_SHA256 NEW_TEST_INPUTS TEST_PLAN_SHA256 NEW_HOST \
  --stateful-contract
python3 -I -S -B Tools/Hardware/run-nano-offline.py \
  SIGNED_MACOS_APP TEAM_ID NEW_HOST NEW_RESULTS --stateful-contract
```

The preparer checks the independent consumer `1bbc0cc1…`, schema-3 firmware export
`90911f7d…` and imported catalogue `8b8f1432…`, then captures 42 evidence files.
The generator checks those anchors again, verifies the prepared SDK, and keeps
all firmware ELF/UF2 inputs outside app resources. Only this test app receives
the explicit catalogue, two fixed `.ino` sources and `FMS2_QUALIFICATION` flag.
There is no firmware download, sibling lookup, flash or device discovery.

Selected firmware source is `97be7bbbe29ef1d18ec886ae6eea1a2d41905869`, resident
`0.1.0-statefulupload-exp1`, target 2 / `nano-managed-v2`, resident-only UF2
`1ef766226ce6a2c51c668562cd51a71ed0bfbe1634b76b54d704c7e710ca1b2f`.
Descriptor `dacbf259…` binds API `0x10023074` and the 4 KiB state arena at
`0x2000893c`. Hello checks identity/capabilities; installed-image evidence comes
from the separately selected ROM installation/readback.

State A initializes its data counter to 7 and sets D13/GPIO6 low. State B uses
23 and high. Both have a BSS loop counter and a bounded binary console protocol:
command `01 NN` returns a 24-byte snapshot with variant tag, little-endian nonce,
startup data, startup BSS, live data and live loop count. Command `02` followed
by all 256 byte values echoes those bytes exactly. Sketches emit no unsolicited
console output. The exact capsule pins are:

| Sketch | Bytes | SHA-256 |
| --- | ---: | --- |
| State A | 544 | `537ce260fc33d4b23b2f8829aee6a9b12653236db6baad4c317040dbf087fd89` |
| State B | 548 | `505c723804addf218e9018375c1f63fd036c2e0bf19d0173ae189b04418aa9b0` |

Both contain four initialized data bytes and 20 BSS bytes. Each state check
requires the selected variant, separate nonces 49/115, initial value 7/23,
initial BSS zero, consistent advancing counters and two exact 24-byte replies.
There is no loop-rate or electrical GPIO measurement claim.

## Selected-board procedure

Initial setup belongs to Firmware's offline `compose_stateful_initial.py` and
explicit ROM workflow. Its production native validator checks the actual
capsule, and the composer checks API/state facts in the actual resident UF2.
Resident-only images preserve old sketch contents; use the checked initial
composite for this test. Select the physical Nano and verify its ROM identity,
all included bytes and initial managed sector before reboot. This is separate
from an SDK initial-installation backend qualification.

| Action | Expected result | Observation required |
| --- | --- | --- |
| Prepare on iPad, then inspect with D2/REC disconnected | Two known capsules; exact target-2 hello | Retrieve own journal, build reports and actual capsules; validate bytes independently |
| Record the reviewed resident-only digest | Association to selected device/boot | ROM evidence and exact digest, never hello alone |
| Connect D2 to GND; choose State B; stage and immediately install once | RAM verified, one commit attempt | Keep REC disconnected; stop on failure without replay |
| Query installation/startup | Fresh boot-confirmed result | Match device, boot, transaction, size and hash |
| Check initialized/advancing state and exact echo | Valid snapshots and all 256 bytes | Preserve raw snapshot bytes and journal |
| Record actual D13 observation | D13 on for B | User observation is separate from an automatic measurement |
| Explicit next operation; fresh inspection/association; upload State A without RESET | New initialized state in the same boot | Compare transaction boot identities; repeat snapshots, echo and actual D13-off observation |
| Press RESET manually, then check state after manual RESET | Changed boot, initial data/BSS and advancing state | Preserve both boot identities; no implicit reset or upload |
| Remove D2-to-GND | Upload arm removed | User confirmation |

Staged connections expire after 30 seconds; installation must immediately follow
staging. Each later operation needs an explicit action and fresh inspection/
association. A lost reply stays uncertain and is reconciled without commit replay.
Reboot state checks are read-only and require a changed boot ID. They do not
claim RAM persistence across reboot. App reports remain app-owned; keep physical
device identities and setup notes in ignored local evidence.

## Local checks and qualification limits

`Tools/ManagedWASM/run-validation.mjs` runs eight fixture-only Nano tool checks,
both preparation-tool syntax checks, production gate/state observation
executables and both host variants' macOS source checks. The Apple workflow also
compiles both variants as optimized iOS objects, separately named. State checks
include independent golden bytes, every single-byte corruption, wrong nonce/
variant, replay and modular progress. These source checks run without assets or
hardware. Complete signed execution requires explicit prepared compiler assets.

Signed macOS offline execution of both known capsules and wireless iPad app
installation are recorded in [preparation evidence](nano-fms2-preparation.json).
Physical managed uploads, in-boot state replacement and reboot checks must each
have their own actual observations before this candidate is qualified. Earlier
ABI-one hardware passes cannot supply those results. Minimum OS, iPhone,
Internet routing, cold-attachment matrices, aggregate WebKit memory, interruption/
power loss, rollback, general Arduino support and production promotion remain
separate gates. Visual/accessibility inspection was not used.

The [physical iPad record](nano-fms2-ipad.json) now pins the 30-event run and
both actual 544/548-byte capsules, independently validated against the resident.
Each target-2 upload records RAM verification, one host commit attempt,
`committing` reply and fresh `boot_confirmed` status. State B and then State A
both report their correct initialized data, zero startup BSS and advancing
counters in the same boot; both exact 256-byte echoes pass. The user's D13
observations change off/on/off with the selected variants. A later manual RESET
changes the boot identity and again yields State A's initial values plus
advancing state. D2 was removed after completion. This is a scoped pass for the
recorded experimental Nano/iPad combination; it supplies none of the separate
production or broader host gates above.

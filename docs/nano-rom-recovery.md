# Explicit Nano SDK ROM qualification

This is an opt-in macOS developer experiment for the user-selected recoverable
Nano. [Exact inputs and observations](nano-rom-recovery.json) currently record
successful read-only identity/volume inspection, candidate preflight, one SDK
transfer and fresh release hello/exact 256-byte echo. Independent ROM readback
matches all 144,128 payload bytes. The separately selected post-erase manual
power-cut case now also passes a new full SDK recovery with exact echo/readback.
First-page and partial SDK-transfer cases remain open.
The production library and its public API are unchanged.

`Validation/ROMHost` is a separate SwiftPM command-line host using public
`MacOSUF2ProgrammingBackend`, `FirmingoInstaller` and `FirmingoSession` APIs.
It is development-signed with hardened runtime, **unsandboxed**, on ARM64 macOS
27.0. macOS 14 is a build setting, not a qualified runtime. Direct iOS/iPadOS
ROM programming remains unavailable. Firmware-owned picotool identity/readback
checks are independent evidence; the actual transfer under test uses the SDK.

## Candidate and effects

Only the real 288,256-byte Nano application UF2 `2e2d6082…` and observed release
manifest `39b5fd64…` are admitted. Full hashes and historical provenance are in
the JSON ledger and existing lifecycle fixtures. Binaries are explicitly acquired
outside app resources and remain uncommitted. Nothing downloads/selects latest.
The build-report identity is checked, but its original bytes have not been
independently acquired. This is an unsigned observed 0.1.0 beta candidate, not an
authenticated publication or promotion of the experimental FMS2 firmware.

The image covers `0x10000000..<0x10023300` (erase sectors conservatively through
`0x10024000`). It replaces the experimental resident in overlapping regions.
Old tail/managed-slot bytes outside that image may remain; no continued FMS2
execution or sketch/settings preservation is promised. The final 4 KiB EEPROM
reservation is excluded and NINA radio firmware is outside the operation.

## Explicit procedure

Build from the SDK checkout:

```sh
swift build --package-path Validation/ROMHost --scratch-path .build/rom-host-build -c release
swift test --package-path Validation/ROMHost --scratch-path .build/rom-host-checks \
  --disable-xctest --enable-swift-testing -Xswiftc -warnings-as-errors
.build/rom-host-build/release/ROMQualification --help
```

Sign the resulting binary using an explicitly selected development identity and
verify `codesign --verify --strict`. Record its hash and signature metadata.
Every command requires a **new** local output directory. Records are bounded,
immutable per callback, synchronized before SDK execution can proceed, and never
written to a bootloader volume by the journal.

1. Keep D2 and REC disconnected. Match normal hello to the selected Nano when
   networking is available; this is not installed-image attestation.
2. Enter ROM physically: disconnect USB, connect REC to GND, reconnect to the Mac,
   and remove REC–GND after ROM appears. Use pinned `picotool info -a` read-only
   to match the exact previously selected flash ID. Generic `RPI-RP2` metadata
   alone cannot identify the physical model. Do not guess among multiple boards.
3. Run `inspect-volume --volume /Volumes/RPI-RP2 --output NEW_DIRECTORY` and
   `preflight --manifest FILE --image FILE --output NEW_DIRECTORY` independently.
4. After reviewing the exact candidate and data effects, explicitly run
   `install --manifest FILE --image FILE --output NEW_DIRECTORY --volume
   /Volumes/RPI-RP2 --confirm-board nano_rp2040_connect` once. Preparation binds
   the current attachment; execution rechecks it and consumes one process-local
   token. An exception or vanished mount never proves installation success.
5. Run `verify --record TRANSFER_DIRECTORY/record.json --output NEW_DIRECTORY
   --address 192.168.77.1 --device-id SELECTED_ID`. This opens fresh SDK sessions,
   checks expected release/capabilities/device identity and exact 256-byte echo.
   Hello is self-reported; independent ROM readback is a separate physical step
   needed to establish exact written image bytes. No automatic reconnect/retry.

## Interruption experiment, not yet executed

`paused-install` requires the same explicit image/volume/model selection. It
awaits a durable progress callback after the first accepted 65,536-byte UF2 prefix
and holds further host writes for up to 120 seconds. Expiry throws rather than
continuing automatically. Prepare the user before starting; manually unplug
only after the printed checkpoint. Preserve the record, terminate only this
owned process if required, and use `inspect-record` in a new process to restore
**context only**. There is no resume command or restored execution token.
Host file acceptance does not prove bytes programmed to flash. Re-enter ROM,
match identity again and independently read back the written regions. Recovery
requires a new full, explicitly requested SDK installation with newly acquired
attachment binding. Restored uncertain records remain uncertain even if hello
matches. Writing the same image over itself cannot demonstrate recovery from
unavailable firmware; a distinct reviewed prior image/checkpoint is required.

Managed-slot power-cut tests use separately reviewed Firmware instrumentation
and exact images. With manual USB unplugging, a deliberate hold after a completed
erase/program command can establish an unfinished installation and its recovery.
It cannot prove loss of power during the chip's internal command. Preparation alone does not qualify that experiment or automatic rollback.

The normal `node Tools/ManagedWASM/run-validation.mjs` entry point runs these
host admission/evidence tests without a board, real UF2, live mount, socket or
paused transfer. Manual CI uses the same entry point; remote runner execution
remains unverified. Hardware execution is always a separate explicit operation.

## First SDK transfer — 2026-10-16

Committed host `86a319e` executed one explicit transfer on the same checked ROM
attachment: nine durable callbacks, all 288,256 UF2 bytes accepted, final
`transferComplete`. A new process restored context and used fresh SDK sessions:
expected release hello matched, then all 256 binary values echoed exactly.
These observations are pinned in the JSON ledger. No retry or picotool write was
used. The prior image was Firmingo FMS2, so this is replacement of that selected
experimental resident, not first installation from non-Firmingo firmware.
Independent ROM verification and a separately decoded/read-back payload now
match all 563 UF2 blocks (144,128 payload bytes). At that baseline stage,
interrupted-write recovery was pending. Sandbox, minimum OS and other
board/platform claims remain open.

## Scoped post-erase recovery — 2026-10-16

The separately committed Firmware test resident `aa19f652…` held after completing
the real managed-sector erase. The operator observed slow checkpoint pulses and
removed USB power. Before any reboot/write, ROM readback found exactly 4096 erased
bytes and an unchanged 154,112-byte resident. Production FMS2 validation rejected
the erased slot. One explicit boot still answered the exact resident hello.

A newly selected ROM attachment and new SDK operation then installed the same
reviewed complete application through the same signed host. Nine durable
callbacks reached `transferComplete`; a new process matched release hello and
all 256 echo bytes. Separate ROM verification/save matches every UF2 payload
byte (144,128), digest `872bf96e…`. No offset resume or managed-commit replay was
used. The erased managed sector remains outside this release image; this recovers
the ordinary Firmingo application, not the previous FMS2 sketch or resident.
Full hashes, records and exact scope are in [the ledger](nano-rom-recovery.json).
This qualifies this between-command checkpoint/new full recovery combination;
it does not establish power loss inside a chip command, sandbox/minimum-OS
support, first-page interruption or initial installation from non-Firmingo.

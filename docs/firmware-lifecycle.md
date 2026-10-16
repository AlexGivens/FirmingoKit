# Complete Firmingo firmware lifecycle

## Implemented artifact preflight

The SDK locally acquires explicitly selected files, validates a complete Firmingo
UF2, and produces a reviewable artifact-bound installation plan without FMGO.
`FirmingoReleaseManifest`, `FirmingoFirmwareImage.load`, and
`FirmingoInstallationPlan` are reusable by other hosts. The demo exposes this
through **Prepare Firmingo Installation** while disconnected. It asks for an
unsigned release manifest, its image, explicit board/profile, and source trust.

Experimental macOS execution is implemented through `MacOSUF2ProgrammingBackend`
and `FirmingoInstaller`: explicit ROM selection, host-confirmed physical model,
attachment-bound process-local preparation, a separate one-shot execution request,
ordered durable records, session shutdown, bounded transfer and explicit fresh-hello
verification. No board/sandbox pair is hardware-qualified. There is no automatic
volume discovery, reset, reconnect, retry, rollback, offset resume, or qualified
update path. Direct iOS/iPadOS programming remains unavailable.

`canExecuteWithSDK` remains false for an artifact-only plan: it is not authority to
write. The separately prepared token supplies reviewed target binding for the
experimental executor. Manual instructions describe an external computer route.
The local WASM compiler and experimental managed uploader are separate workflows;
a UF2 is never a capsule. The demo exposes explicit macOS target selection and final
installation confirmation; its journal and verification are available independently
of a console. No demo/native writer has been exercised on hardware.

## Release contract and provenance

Policy is pinned to Firmingo `f17fdf0301256ba48270230cbf213126e70aa8d0`, schema 1,
product Firmingo, version `0.1.0`, beta channel, UF2 format. Application and UART
each have independent Nano and original Pico entries. Exact board/profile/version,
package path, full FQBN/options, file bytes/SHA-256, build-report SHA-256, positive
flash/static-RAM budgets, and `compile-tested` evidence are required. No artifact
is chosen by filename or shared family ID alone. Later releases, unknown fields,
and signature-bearing schemas require a reviewed policy/verifier update.

The pinned release generator has no signatures or authenticated download endpoint.
The host must establish a trusted source and retain the original index. HTTPS or
file provenance and checksums do not authenticate a publisher. This SDK does not
fetch a moving branch, invent a release URL, unpack archives, execute report text,
or fall back to another image. Build-report hashes are retained, not proof that
the report was acquired or independently verified.

`Tests/FirmingoKitTests/Fixtures/lifecycle/provenance.json` records consumed
committed release/board/tool hashes and the separate provisional observed index.
Its exact index SHA-256 is
`39b5fd642579137ae813ca00d498d4115fa532c3cda4718e5d4f925728861aa8`.
The index was an ignored local `dist/` output inspected read-only on 2026-09-29,
not a committed or authenticated published release. Four local copies of its
images passed the actual Swift validator; they remain under `.build/`, are not
bundled with the SDK/tests, and were never written to hardware. Their hashes
remain in the observed index. Synthetic UF2 fixtures have zero-filled,
non-executable payloads and must never be flashed.

Manifest parsing is bounded to 16 KiB, 1024 tokens, 16 nested containers, and four
files, rejecting duplicate decoded JSON keys and duplicate board/profile entries.
Local acquisition uses regular, explicitly selected files, bounded 64-KiB reads,
security-scoped access during each read, cancellation checks between reads, and a
concurrent executor. Inputs are checked again by immutable in-memory validation.
The image is limited to its manifest size, at most 2 MiB of UF2 (1 MiB payload).
Filesystem failures remain underlying errors. There is no download retry or write.

## Flash layout and effect

The validated release subset uses complete 512-byte little-endian UF2 blocks,
only family-present flags (`0x2000`), RP2040 family `0xe48bff56`, 256-byte payloads,
zero unused padding, unique complete block numbers, and contiguous addresses from
`0x10000000`. File order can differ from block order. Mixed families, metadata
blocks, gaps, overlays, RAM writes, reserved regions, unsupported flags, malformed
counts, and incomplete files are rejected even with a matching manifest checksum.
This is an explicit release subset, not a general UF2 editor or converter.

| Board | Pinned full FQBN flash selection | Permitted address end, exclusive | Reserved tail |
| --- | --- | --- | --- |
| Nano RP2040 Connect | `flash=16777216_0` | `0x10fff000` | 4 KiB EEPROM |
| Original Raspberry Pi Pico | `flash=2097152_0` | `0x101ff000` | 4 KiB EEPROM |

Both recipes have no filesystem and an engineering flash budget of 1 MiB/static
RAM budget of 196608 bytes. Reported flash usage is not the complete UF2 address
extent. The SDK measures actual payload and conservatively rounds the affected
extent to 4-KiB erase sectors. Erase behavior still needs backend/hardware
qualification; reporting this extent does not promise transactional replacement.

Complete-image transfer replaces existing RP2040 firmware, including a previous
sketch where sectors overlap. There is no preservation, backup, or rollback
guarantee for sketches/settings/filesystems. The validator excludes the reserved
EEPROM tail from writes; it does not guarantee what newly running firmware does
with settings afterward. Nano NINA auxiliary firmware is outside this operation.
No default-Arduino image, restoration API, or restoration recipe is provided.

## Physical procedures and versioned upstream references

References were checked on 2026-09-29. Only programming-mode entry and UF2
transfer mechanics are used; example application images in upstream tutorials
are not Firmingo installation artifacts.

- Nano: [Arduino recovery article](https://support.arduino.cc/hc/en-us/articles/4404168794514-Reset-the-firmware-on-Nano-RP2040-Connect), last edited 2024-09-25 09:48, and [Nano user manual](https://docs.arduino.cc/tutorials/nano-rp2040-connect/rp2040-01-technical-reference/). With USB connected, bridge REC to GND and press reset; remove the jumper after the ROM storage volume appears. Firmware-independent ROM entry is used instead of assuming double-reset works with every image. REC–GND is separate from experimental managed-upload D2–GND authorization.
- Pico: [Raspberry Pi Pico-series documentation](https://www.raspberrypi.com/documentation/microcontrollers/pico-series.html) and [Getting Started with Pico-series](https://datasheets.raspberrypi.com/pico/getting-started-with-pico.pdf), Release 24, build date `03/07/2026`, build version `d4e0f1799616`. Hold BOOTSEL while connecting USB; release it after the ROM volume appears. Copying a suitable UF2 normally triggers reboot, but this does not establish successful Firmingo startup.
- Format: [Microsoft UF2 specification](https://github.com/microsoft/uf2), inspected 2026-09-29, provides block constants, little-endian fields, family flags, and independent block ordering. The accepted recipe/layout is pinned separately above.

`RPI-RP2` identifies a generic RP2040 ROM storage interface. It cannot identify
the model, physical target, or installed image. The backend therefore requires a
user-selected volume root and a separate physical-model assertion. It rejects
ordinary directories, symlink roots, unsupported USB devices, and stale attachments.
Multiple devices are resolved by explicit user selection; the SDK does not choose
one by name. Discovery, file acquisition and preparation never trigger flashing.

The native adapter uses Disk Arbitration to match the selected volume root to its
IOMedia and IOKit USB ancestor. It requires ROM VID `2e8a` / PID `0003`, attachment
registry IDs, and bounded ASCII `INFO_UF2.TXT` with unique expected model/board fields.
These observations establish a current generic RP2040 ROM interface, not Nano/Pico
identity or cryptographic authentication. IDs are attachment-local and expire after
re-enumeration. The mount/info/IDs and pinned directory device/inode are rechecked
before and after the awaited write gate; a new attachment requires new preparation.

Additional upstream references checked 2026-09-29:

- [RP2040 datasheet](https://datasheets.raspberrypi.com/rp2040/rp2040-datasheet.pdf), build date `2025-02-20`, build version `3184e62-clean`: §2.8.5.1 Table 172 (USB VID/PID), §2.8.4.2 (virtual mass storage), and RP2040-E14 (contiguous 4-KiB erase implications). This is the basis for rejecting sparse/gapped complete images; it does not qualify the host writer.
- [Raspberry Pi B2 ROM info source](https://raw.githubusercontent.com/raspberrypi/pico-bootrom-rp2040/master/bootrom/info_uf2.txt), inspected 2026-09-29: `UF2 Bootloader v3.0`, `Model: Raspberry Pi RP2`, and `Board-ID: RPI-RP2`. This policy accepts the bounded bootloader-version prefix and requires exact unique model/board fields; it does not infer a hardware revision from them. No upstream code is bundled/adapted.
- [Apple Disk Arbitration programming guide](https://developer.apple.com/library/archive/documentation/DriversKernelHardware/Conceptual/DiskArbitrationProgGuide/ManipulatingDisks/ManipulatingDisks.html), archived guide inspected 2026-09-29, and local macOS 27 SDK headers for Disk Arbitration/IOKit: selected-volume lookup, descriptions and IOMedia association. Sandbox visibility and authorization remain real-host checks.

## Explicit execution, persistence and cancellation

`FirmingoInstaller.prepare` re-inspects a selected observation and requires the
host's physical-board confirmation. Tokens belong to that installer, only its
newest token is valid, and every execution attempt consumes it, even if writing
never starts. An explicit `execute` is necessary; restored records cannot produce
a token. SDK-wide attachment leases reject overlapping programming without queuing.
Different generic ROM devices remain separate selections.

Supply all relevant active `FirmingoSession` instances. The SDK closes/disconnects
idle consoles before programming. Pending control/serial writes and staged or
committing managed uploads block execution. Host apps own other processes/sessions
and must prevent new communication while programming. The demo blocks its window's
new communication, cancels inspection/connection attempts, and hands its current
session to this SDK boundary.

The required `recordChanged` callback is ordered and awaited. The host must save
updates atomically/durably before returning. In particular, `writeStarted` must
be persisted before the native backend can create or write any UF2. Failed storage
stops the gate or transfer. Accepted progress is retained before persistence can
fail, so an error still carries the latest known count. Callback/cleanup failures
retain underlying causes. A restored `writeStarted` is an unknown outcome.

The backend exclusively creates `FIRMINGO.UF2` using a pinned root descriptor,
without overwrite or symlink following. It writes bounded 64-KiB chunks, retains
partial unaccepted suffixes, awaits progress, synchronizes, and checks close.
Only interrupted syscalls without an accepted prefix retry locally; an ambiguous
or failed write is never replayed. It does not eject, reset, delete partial files,
resume at an offset, or automatically repeat a transfer. Cancellation is cooperative
between writes/callbacks; blocking filesystem calls cannot be preempted. Mount loss,
permissions, file creation, sync and close errors propagate.

Before write permission, errors/cancellation report `failedBeforeWrite` / `notStarted`.
After permission, every failure reports `outcomeUnknown` / `uncertain`, even with
zero known bytes. `transferComplete` means only that the host transfer/sync/close
completed. It does not prove reboot, successful installation, or sketch behavior.
The record's byte count is host filesystem acceptance, not flash readback.

`FirmwareInstallationRecord` schema 1 retains the operation ID, artifact/manifest/
build-report hashes, release source/version, board/profile, size, prior attachment,
state/count, optional hello observations and bounded failure context. Decoding
validates those fields; it does not authenticate context, select a device, acquire
an artifact, or authorize a write. Hosts must bound their journal input. Image bytes
are not persisted by the SDK; recovery requires explicit artifact reacquisition
and validation against saved provenance. Saved mount paths are context only.

The demo saves operation-specific and latest-context JSON journals in app-private
Application Support, atomically replaces them, synchronizes file contents and
containing-directory entries, and propagates failures through SDK callbacks.
The sheet restores latest context after restart without preparing a target or
connecting. Operation-specific files retain older contexts when a newer action is
saved. Users can share a journal after a durable update. Cross-process coordination,
signed-sandbox durability, app termination and physical-device behavior remain
unqualified. An unpersisted preparation creates no restart write authority.

## Verification, interruption, and platform boundaries

`verify` requests one fresh `FirmingoInspector` hello at a separately selected
numeric endpoint. It requires protocol one, selected board/profile, release
`0.1.0`, channel one and empty upload targets. Version is taken from pinned
`src/core/version.h`, used by both release examples, not the `session-dev-v1`
parser fixture. Reference file hashes are in lifecycle provenance. A supplied
previous device ID is checked; without it the host must establish association
between this endpoint and the selected USB board. No polling/retry occurs.

A completed transfer can become `helloMatched`. A restored/interrupted unknown
write remains `outcomeUnknown` even when hello matches. Save the verification
update, or the record accompanying `verificationFailed`. A failed hello does not
prove the write failed. Hello is self-reported and cannot attest the exact UF2/ELF
digest, a post-transfer boot, or useful behavior; check useful behavior separately.

Keep image/index provenance and follow the record's board-specific ROM recovery
instructions. Select the physical target again, reacquire/validate the image and
request a new full Firmingo reinstall. No automatic rollback, offset resume, or
blind retry is available. This implemented request/context boundary has fake-backend
evidence; physical recovery and update compatibility are still acceptance work.

| Operation | macOS, each board | iOS/iPadOS, each board |
| --- | --- | --- |
| Local artifact acquisition/validation | Implemented, deterministic tests | Implemented, simulator tests; physical file access unqualified |
| Artifact preflight/physical guidance | Implemented; explicit physical selection required | Implemented; external computer route |
| SDK ROM first installation | Experimental backend; selected Nano/macOS 27 replacement passes exact echo/readback; first installation from non-Firmingo and sandbox pending | Unavailable; no direct backend |
| Qualified updates | Pending compatibility and execution evidence | Pending |
| SDK interruption records / new full reinstall request | Selected post-erase checkpoint/new full Nano recovery passes exact echo/readback; other interruption/board/sandbox cases pending | Records/verification build; computer required for transfer |
| Fresh-hello verification | Selected Nano/macOS release hello and exact echo pass; no installed-image attestation | API/simulator tests; networking/file access unqualified |

Hardware qualification must start with a board not running Firmingo, install
through an actual signed SDK host, connect, and exchange exact bytes. Updates and
interrupted-operation recovery need dedicated evidence independently per board
and host. The selected replacement and post-erase recovery results below do not
close first installation from non-Firmingo firmware. Synthetic parser fixtures
remain memory-only; only the separately reviewed real candidate has reached the
native writer in this experiment.

## Selected Nano ROM qualification preparation — 2026-10-16

The separate [explicit developer host](nano-rom-recovery.md) now builds and
passes eight deterministic tests. Its development-signed, hardened, unsandboxed
ARM64 macOS 27.0 execution accepts the selected physical Nano ROM attachment
and preflights the exact historical real 0.1.0 application candidate. One explicit
SDK transfer now reaches `transferComplete`; fresh SDK sessions match release
hello and pass exact 256-byte echo. [Provenance](nano-rom-recovery.json) records
these scoped observations, including independent exact 144,128-byte ROM
readback after the transfer. A separate manual post-erase power-cut checkpoint
now passes a new full SDK recovery, fresh release hello/exact echo and exact
144,128-byte ROM readback. This replaces the test resident with the ordinary
application; it does not restore the old managed sketch. First-page/partial-SDK
interruption, first installation from non-Firmingo firmware, sandbox and
minimum-OS execution remain unqualified.

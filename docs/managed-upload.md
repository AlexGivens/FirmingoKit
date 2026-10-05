# Experimental Nano managed upload

FirmingoKit implements the FMGO-one managed transfer/reconciliation contract pinned
to Firmingo `f17fdf0301256ba48270230cbf213126e70aa8d0`. Deterministic tests use
packaged protocol vectors and fake peers. No physical SDK upload is qualified.
This operation replaces the managed sketch slot, not the complete resident
firmware. Initial Firmingo installation, updates, and bootloader recovery remain
separate work.

## Artifacts and resident binding

`ManagedCapsule` accepts complete FMS1 bytes and the independent module builder's
JSON report. It verifies the Nano tag, ABI one, exact API address, fixed code
address, code/whole-capsule digests, exact length, zero padding, and Thumb setup/loop
entries inside the linked code. It rejects conventional UF2, oversized or trailing
bytes, mismatched board/target/resident metadata, and unsafe report source paths.
Reports are bounded to 4096 bytes, with at most 64 source hash entries; compiler
text is retained as provenance and never executed. Source hashes are retained,
not re-read from a sibling checkout or treated as publisher authentication.

Before validation, the host supplies a `ManagedResidentBinding` for the selected
physical device, containing its exact resident ELF hash, known installed complete
firmware image hash, and aligned API symbol address. The host must establish that
association using verified build/install records. The SDK compares the module
report and header with this binding, but cannot attest to installed image bytes
from hello. Do not derive the ELF hash/API address from the firmware version or
hardcode a proof-build address. Constructing metadata is not proof that the
resident is installed. A shared chip/family ID is insufficient.

The current firmware proof uses constrained GCC-built modules and a tiny Arduino
facade. Writable globals, arbitrary Arduino libraries, and arbitrary `.ino` builds
are not established. Format validation cannot determine whether machine code is
safe or executable. Only trusted independently built, qualified capsules belong
on a physical board. Firmware parser fixtures have synthetic metadata and
non-executable code; they are used only with fake transports in package tests.

The accepted [catalogue design](compiler-catalogue.md) will separate bundled
firmware-build descriptors from physical-device associations and allow offline
builds without fabricated device IDs. That migration is not implemented. The
current API and example below still require `ManagedResidentBinding`; future
catalogue selection must preserve these exact binding, capability and one-commit
checks before any upload.

## Staging and explicit installation

The session requires the exact Nano application target: ID one,
`nano-managed-v1`, maximum size 4096, maximum chunk 1024, and
`physical-d2-gnd` authorization. Release profiles advertising no targets, Pico,
UART, and changed target recipes are unavailable for managed upload. Target and
device checks happen before closing a console or sending begin.

`stageManagedUpload` reserves the session, explicitly closes its owned console,
sends begin, transfers sequential capsule-relative chunks with an acknowledgement
for each, and requests finish. No chunk is retried. Every snapshot must match
transaction ID, size, digest, state, and cumulative offset. Completion means
verification in RAM. Progress callbacks run synchronously on SDK isolation and
must return promptly; there are at most four chunk callbacks with the current
target. Dispatch UI presentation to the main actor. Lossless serial data uses its
separate pull sequence.

Save the returned Codable `ManagedUploadRecord` and the host's commit intent
before explicitly calling `commitManagedUpload`. Only the originating connection's
verified record permits commit; a restored record on another connection can only
query status. Commit is attempted once, then that connection closes. A committing
reply means installation was queued. It does not prove flash readback, startup,
useful behavior, or reboot.

For example, after the host validates/selects its artifact and resident records:

```swift
import Foundation
import FirmingoKit

func stageAndCommit(bytes: Data, report: Data, binding: ManagedResidentBinding,
                    endpoint: FirmingoEndpoint, recordURL: URL) async throws -> ManagedUploadRecord {
    let capsule = try ManagedCapsule(bytes: bytes, reportJSON: report, resident: binding)
    let session = try await FirmingoSession.connect(
        to: endpoint, expectedBoard: .nanoRP2040Connect,
        expectedBackend: .application, expectedDeviceID: binding.deviceID
    )
    do {
        let record = try await session.stageManagedUpload(capsule)
        // This URL/storage decision belongs to the host. A save failure prevents commit.
        try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
        let acknowledgement = try await session.commitManagedUpload(record)
        print(acknowledgement.state, acknowledgement.errorCode)
        return record // Queue acknowledgement still requires read-only reconciliation.
    } catch {
        await session.disconnect()
        throw error
    }
}
```

Physical Nano D2/GPIO25–GND authorization is checked by firmware at begin, commit,
and before erase. The SDK reports its device rejection; it does not bypass or
infer physical authorization. `abortManagedUpload` disposes a verified pre-commit
stage and allows console acquisition again. Cancellation/disconnect before commit
disposes RAM staging without a slot write. After a commit attempt, abort is
unavailable. Keep ROM REC–GND recovery separate from this authorization jumper.

## Reconciliation and uncertainty

Missing, rejected, malformed, timed-out, or cancelled commit replies throw
`ManagedUploadError.uncertainCommit` with the record and underlying cause.
Installation may continue after disconnection. The SDK never resends commit,
reconnects automatically, or starts another upload. The host requests a new
read-only action and creates a fresh hello-validated session:

```swift
let observer = try await FirmingoSession.connect(
    to: endpoint, expectedBoard: .nanoRP2040Connect,
    expectedBackend: .application, expectedDeviceID: record.deviceID
)
do {
    let result = try await observer.reconcileManagedUpload(record)
    await observer.disconnect()
    switch result {
    case .snapshot(let snapshot):
        print(snapshot.state, snapshot.errorCode, snapshot.slotTouched)
    case .unknown(let reason):
        print("Outcome unknown:", reason)
    }
} catch {
    await observer.disconnect()
    throw error
}
```

The query verifies device, boot, target, transaction ID, whole-capsule size, and
digest. A changed device/boot, unavailable target, superseded RAM record, or
mismatched snapshot returns unknown. Record decoding checks its schema, bounds,
and identities, but persistence is not authentication. Each query is one bounded
request; hosts may explicitly poll observational status using their own bounded
wait policy. The reference harness's five-second startup polling is not a
firmware guarantee.

| State | What it establishes |
| --- | --- |
| accepted / verified | RAM transfer / validation; no slot write |
| committing | Queued or in progress; outcome remains pending |
| installed | Flash readback passed; startup unconfirmed |
| boot_confirmed | Managed setup and first loop returned; useful behavior unconfirmed |
| failed | Failed transaction even with `ok:true`; inspect machine error and slot_touched |
| aborted | Pre-commit RAM stage disposed; no slot write |

`slotTouched` is conservative after an erase attempt and can accompany failure.
The SDK promises no rollback or power-cut atomicity. A saved record cannot restore
RAM transaction history after reboot. New uploads require an explicit host action
after presenting prior uncertainty. To qualify hardware, record exact board,
resident/capsule hashes, compiler/recipe, host OS, authorization, observed status,
and useful sketch behavior on dedicated devices.

## Provenance

`Tests/FirmingoKitTests/Fixtures/provenance.json` records SHA-256 and byte counts
for the protocol, SDK handoff, image/ABI headers, image validator, stage/upload
implementation, and independent builder/harness inspected for this increment.
References were read from the pinned committed snapshot. The Firmingo working
tree's unrelated AGENTS.md edit remains provisional guidance. No reference code,
toolchain, executable capsule, or image was copied or modified, and no reference
build/tool was executed. Imported parser vectors retain their upstream license.

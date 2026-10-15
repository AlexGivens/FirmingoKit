# Experimental Nano Managed Uploads

Validate independently built FMS1 capsules, stage them in RAM, and reconcile an
explicit installation request without replaying commit.

ABI-two/FMS2 is also available through the explicit `.nanoManagedV2` profile and
``ManagedResidentState`` attached to ``ManagedResidentBinding``. It selects target
two, checks the exact RAM arena and both capsule digests, and preserves the same
one-shot commit/uncertain-outcome rules. Data/BSS are initialized for each
generation; hardware qualification for this new resident remains outstanding.
ABI-one upload behavior is preserved. See the repository's stateful adoption
guide for exact pinned assets and current evidence.

## Overview

This API implements the pinned experimental Nano `nano-managed-v1` FMGO-one
contract. Release profiles without targets, Pico, UART, conventional UF2 images,
and changed target recipes are unavailable for managed upload. It has deterministic
fixture/fake-peer tests and no SDK hardware qualification. The local WASM compiler
and initial Firmingo installation remain separate pending workflows.

Create ``ManagedResidentBinding`` from the host's verified exact resident
build/install record for the selected device. The record must identify the
resident ELF, installed complete firmware image, and aligned API symbol address.
Hello cannot attest to an exact image or supply that binding. ``ManagedCapsule``
checks the module report and complete bytes against the binding, validates header,
padding, sizes, digests and Thumb entry ranges, and retains source/compiler
provenance. Packaging validation does not prove executable behavior or authenticity;
parser-only firmware fixtures must never be uploaded to a physical board.

## Stage, persist, and explicitly commit

``FirmingoSession/stageManagedUpload(_:progress:)`` first checks the selected
device/target, closes its owned console, then sends begin, exact-offset chunks,
and finish. It returns a ``ManagedUploadRecord`` only after RAM verification.
Physical D2/GPIO25–GND authorization is enforced by the firmware. A stage sends no
commit and does not flash. Cancellation/failure closes the connection and disposes
staging; no bytes are automatically retried.

Save the returned record and the host's commit intent before requesting
``FirmingoSession/commitManagedUpload(_:)``. A restored record only permits status
queries; commit requires that same live connection's verified stage. The method
attempts commit once and closes the connection after its reply. Queue acceptance,
installation, managed startup confirmation, and useful sketch behavior are
distinct outcomes.

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
        try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
        let reply = try await session.commitManagedUpload(record)
        print(reply.state, reply.errorCode)
        return record
    } catch {
        await session.disconnect()
        throw error
    }
}
```

The host owns the user-selected persistence URL. A failed save prevents commit.
Before commit, ``FirmingoSession/abortManagedUpload(_:)`` explicitly discards the
verified RAM stage. After a commit attempt, abort cannot cancel installation.
The physical authorization jumper must remain present through the firmware's
pre-erase checks; Nano REC–GND ROM recovery is a separate procedure.

## Query outcomes without replay

Lost/rejected/malformed replies, timeouts, and cancellation after a commit attempt
throw ``ManagedUploadError/uncertainCommit(record:underlying:)`` with the record
and original cause. The SDK neither reconnects nor resends commit. The host
requests a new read-only action, creates a fresh connection, and calls
``FirmingoSession/reconcileManagedUpload(_:)``:

```swift
func readOutcome(record: ManagedUploadRecord,
                 endpoint: FirmingoEndpoint) async throws -> ManagedUploadReconciliation {
    let observer = try await FirmingoSession.connect(
        to: endpoint, expectedBoard: .nanoRP2040Connect,
        expectedBackend: .application, expectedDeviceID: record.deviceID
    )
    do {
        let result = try await observer.reconcileManagedUpload(record)
        await observer.disconnect()
        return result
    } catch {
        await observer.disconnect()
        throw error
    }
}
```

Each query checks device, boot, advertised target, transaction ID, whole-capsule
size, and digest. Changed/superseded evidence returns an unknown reason. A matching
snapshot can remain committing or installed, or report failed/aborted. Successful
response envelopes containing a failed transaction retain the firmware error and
conservative ``ManagedUploadSnapshot/slotTouched`` flag. Boot confirmation means
only that managed setup and the first loop returned; it does not attest to useful
behavior, a whole-device reboot, or future stability.

Queries have the session's five-second request deadline and do no implicit polling.
Hosts can explicitly poll with their own bounded policy. RAM records disappear
after reboot and cannot establish a prior outcome after transaction ID reuse.
The SDK provides no rollback or power-interruption atomicity. A new device-changing
action after uncertainty requires a new host request.

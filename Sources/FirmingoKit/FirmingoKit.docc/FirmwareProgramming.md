# Experimental Firmingo programming

Prepare an explicitly selected macOS ROM attachment, execute once, retain uncertainty,
and request a separate fresh hello.

## Overview

This backend is experimental and has no board/sandbox hardware qualification.
It supports the validated complete-image release subset, separately from managed
sketch upload. Direct programming on iOS/iPadOS is unavailable; the artifact plan
provides the external computer route. No compiler or Arduino restoration is involved.

First acquire a trusted complete image as described in <doc:FirmwarePreflight>.
The host presents the plan, asks the user to identify the physical Nano or original
Pico, enter its ROM mode, and explicitly select its mounted volume. Generic USB ROM
metadata cannot distinguish these models. Multiple attached boards must be resolved
by the host/user before confirmation. Selection does not write anything:

```swift
let backend = MacOSUF2ProgrammingBackend()
let installer = FirmingoInstaller(backend: backend)
let volume = try await backend.inspect(volumeURL: selectedROMRoot)
let prepared = try await installer.prepare(
    plan: reviewedPlan,
    volume: volume,
    confirmedPhysicalBoard: .nanoRP2040Connect
)
```

`selectedROMRoot` is a user-selected folder URL with appropriate filesystem access;
`reviewedPlan` is the immutable SDK artifact plan. macOS inspection verifies the
mount root, USB RP2040 ROM VID/PID, current IOKit attachment IDs, and bounded ROM
info. It does not scan all volumes or infer the physical model from a label.

## Explicit execution and persistence

After presenting the exact artifact, affected data, physical selection and recovery
route, obtain the end user's final installation action. Tokens are process-local,
belong to one installer, expire on newer preparation, and are consumed by any
execution attempt. A saved record is never an execution token.

The host supplies an ordered, awaited storage closure. It must persist each update
atomically and durably before acknowledging, especially `writeStarted` before the
backend may create or write a UF2. Returning before storage finishes invalidates
the restart-safety contract. The host also supplies all relevant active sessions;
the SDK releases an idle console and disconnects, and rejects unresolved control,
serial, or managed-upload operations. Other apps/connections remain the host's
responsibility. For example, wrap the explicit action with your storage boundary:

```swift
func executeReviewedInstallation(
    _ prepared: PreparedFirmwareInstallation,
    using installer: FirmingoInstaller,
    closing sessions: [FirmingoSession],
    saveDurably: @escaping @Sendable (FirmwareInstallationRecord) async throws -> Void
) async throws -> FirmwareInstallationRecord {
    try await installer.execute(prepared, closing: sessions, recordChanged: saveDurably)
}
```

Updates represent `prepared`, `writeStarted`, and accepted byte counts before
`transferComplete`. macOS uses exclusive `FIRMINGO.UF2` creation without overwrite,
bounded 64-KiB writes, partial-prefix retention, synchronization, and checked close.
The selected attachment is revalidated before and after the awaited write gate.
Overlapping SDK writes to that attachment fail rather than queue. Filesystem
permissions, IOKit visibility, durable storage, and real ROM behavior still need
qualification in a signed sandbox host.

Cancellation is cooperative between writes/callbacks; an in-flight kernel call
cannot be preempted. Before permission, failure reports `notStarted`; after
permission it reports `uncertain`, even with zero accepted bytes. Underlying causes
and the latest record are retained. No partial file is deleted, reset requested,
offset resumed, or failed write replayed. Transfer completion alone proves neither
flash contents nor startup. No state claims automatic rollback.

## Verification and restart

Save the returned record, or the record associated with a failure. Decode a bounded
host journal using `JSONDecoder` into ``FirmwareInstallationRecord``. Schema,
provenance, URL, hash, size, state and identity constraints are checked, but decoding
does not authenticate context or recreate target selection. A restored
`writeStarted` is an unknown outcome, irrespective of its accepted count.

After selecting the physical board's numeric endpoint, request one fresh hello:

```swift
let verified = try await installer.verify(
    savedRecord,
    at: FirmingoEndpoint(address: "192.168.77.1", port: 7420),
    expectedDeviceID: savedRecord.observedDeviceID
)
// Persist verified, and present its state and observations.
```

The inspector validates protocol, expected board/device identity, then the installer
requires release `0.1.0`, selected application/UART profile, and empty release upload
targets. There is no polling or retry. A completed transfer may become `helloMatched`;
an interrupted/unknown transfer remains `outcomeUnknown` even if hello matches.
Save verification updates and failures. Hello is self-reported and cannot attest
the selected UF2 digest or useful behavior. Without prior device identity, a
matching endpoint also cannot establish association with the selected USB board.

``FirmwareInstallationRecord/recoveryInstructions`` describes a separately requested
full Firmingo ROM reinstall. Reacquire/validate the artifact and select the physical
attachment again; the SDK does not persist the image bytes or retry automatically.
Qualified updates and physical interruption recovery remain acceptance work.

## Topics

- ``FirmingoInstaller``
- ``MacOSUF2ProgrammingBackend``
- ``FirmwareProgrammingBackend``
- ``FirmwareBootloaderVolume``
- ``PreparedFirmwareInstallation``
- ``FirmwareInstallationRecord``
- ``FirmwareInstallationError``

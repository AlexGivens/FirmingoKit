# ``FirmingoKit``

Inspect Firmingo identity and exchange exact serial bytes from a native host.

## Overview

This implementation supports short-lived FMGO protocol-one inspection and a
persistent channel-one serial session. Both connect to an explicitly selected
numeric endpoint and validate hello. Inspection closes without acquiring a
channel. A session requires an expected backend and explicit console ownership.
Experimental Nano managed upload is also available for independently built,
validated FMS1 capsules and exact host-known resident metadata. Offline source
preparation and independently linked ELF packaging are available; the SDK WASM
compiler is experimental and requires an explicitly supplied verified local service. Complete-firmware artifact validation and installation-plan review
are available, with experimental macOS ROM execution, saved operation context, and
separate fresh-hello verification. These have no SDK hardware qualification.

Device-independent compiler requests select exact verified catalogue metadata;
artifacts bind separately to reviewed physical-device associations. Production
descriptors and approved service packaging remain open. Default resource-loading
APIs verify an empty bundled catalogue and explicitly report pending service review.

```swift
import Foundation
import FirmingoKit

let endpoint = try FirmingoEndpoint(address: "192.168.77.1", port: 7420)
let device = try await FirmingoInspector.inspect(
    at: endpoint,
    expectedBoard: .nanoRP2040Connect
)
print(device.deviceID)
print(device.targets)

let session = try await FirmingoSession.connect(
    to: endpoint,
    expectedBoard: .nanoRP2040Connect,
    expectedBackend: .application
)
try await session.openConsole()
let consumer = Task {
    for try await bytes in session.serialBytes {
        print(bytes as NSData)
    }
}
try await session.sendSerial(Data("hello\n".utf8))
let status = try await session.serialStatus()
print(status.pendingToBackend)
try await session.closeConsole()
await session.disconnect()
_ = try await consumer.value
```

Cancellation closes pending network operations. Connection establishment, control
requests, and incomplete frames have five-second SDK deadlines. One pull consumer
receives exact chunks; the session buffers up to 4096 bytes and bounds a stalled
consumer to 30 seconds. `sendSerial` completion confirms local transport acceptance,
not sketch consumption. After a partial write failure, the result is uncertain;
the SDK never replays on reconnection. Inspection snapshots and live hello both
use self-reported, unauthenticated identity and do not prove exact installed images.
Network addresses are not device identities.

A host provides local-network permission text on iOS/iPadOS and macOS as required
by its OS, plus outgoing network entitlement when using the macOS App Sandbox.
No SDK board/platform pair has been hardware-qualified yet. Declared minimums
are macOS 14 and iOS/iPadOS 17; runtime qualification is tracked separately.

Approved compiler-service packaging, signed-host/physical-device compilation, qualified firmware updates, and hardware installation/recovery
qualification remain open work. See <doc:FirmwareProgramming> for experimental execution.
The managed uploader implements only the reviewed experimental Nano target, with
fixture/fake-peer validation and no SDK hardware qualification. See <doc:ManagedUploads>
for artifact binding, explicit commit, and read-only reconciliation.

## Topics

### Device inspection

- ``FirmingoInspector``
- ``FirmingoEndpoint``
- ``FirmingoBoard``
- ``FirmingoDevice``
- ``FirmingoError``

### Live console

- ``FirmingoSession``
- ``SerialBytes``
- ``SerialStatus``

### Experimental managed upload

- <doc:ManagedUploads>
- ``ManagedCapsule``
- ``ManagedResidentBinding``
- ``ManagedUploadRecord``
- ``ManagedUploadSnapshot``
- ``ManagedUploadProgress``
- ``ManagedUploadReconciliation``
- ``ManagedUploadError``

### Experimental local compilation

- <doc:ManagedCompilation>
- <doc:BundledCompilerResources>
- ``ManagedSketchCompiler``
- ``ManagedCompilationResult``
- ``ManagedCompilationPhase``
- ``ManagedCompilerError``
- ``ManagedCompilerResourceError``

### Experimental firmware catalogue metadata

- <doc:ManagedCatalogue>
- ``ManagedCompilerCatalogue``
- ``ManagedFirmwareBuildDescriptor``
- ``ManagedDeviceAssociation``
- ``ManagedCatalogueError``

### Device-independent experimental compilation

- <doc:OfflineManagedCompilation>
- ``ManagedOfflineBuildRequest``
- ``PreparedManagedOfflineSketch``
- ``ManagedOfflineSketchArtifact``
- ``ManagedOfflineCompilationResult``

### Offline managed source and ELF packaging

- <doc:ManagedBuildPreparation>
- ``SketchSourceSnapshot``
- ``ManagedSketchBuildRequest``
- ``ManagedSketchPreprocessor``
- ``PreparedManagedSketch``
- ``SketchDiagnostic``
- ``SketchBuildError``
- ``ManagedELFProvenance``
- ``ManagedELFConverter``
- ``ManagedSketchArtifact``

### Complete-firmware artifact preflight

- <doc:FirmwarePreflight>
- ``FirmingoReleaseManifest``
- ``FirmingoFirmwareImage``
- ``FirmingoInstallationPlan``
- ``FirmwareLifecycleError``

### Experimental complete-firmware programming

- <doc:FirmwareProgramming>

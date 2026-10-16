# Experimental FMS2 compiler and upload adoption

FirmingoKit now accepts explicit `nano-managed-v2`/ABI-two selections alongside
the unchanged ABI-one contract. The adoption increment below recorded local
SDK/WebKit execution and fake-peer deployment evidence without contacting a
board. Subsequent [exact-candidate qualification](nano-fms2-qualification.md)
now records signed macOS offline builds and physical Nano/iPad/iPhone
upload/state/echo/manual-reset passes; production gates remain separate.

## Pinned inputs

Compiler adoption source: commit `1ad0fa6` (versioned import, recipe, ELF/capsule validation and both-profile export).

Firmware `97be7bbbe29ef1d18ec886ae6eea1a2d41905869` exports schema three, anchor
`90911f7d3684dab4123d36b9a018805cc36ae58cb197c318fe720cb18d434a65`.
The explicit descriptor is
`dacbf259b96de0e050514764253403f3ef1ef51d0f9efaf1f43a10d8654c0e18`,
API `0x10023074`, volatile state `0x2000893c`/4096 bytes. Its resident UF2 is
`1ef766226ce6a2c51c668562cd51a71ed0bfbe1634b76b54d704c7e710ca1b2f`;
this is a candidate, not the earlier hardware-qualified resident.

The refreshed Compiler source package is
`2324bff2f0db46b5c640998a607df85066a3bb3ddcf90938499a1c858ba81639`
with 56 source/resource records and both explicit recipes. Consumer `.2` anchor
`1bbc0cc19d80490914799fbec5cb4bbc0a942a73fd3bbf6e09fff2c3856e660a`
retains the reviewed `a7648688…` service and the existing ABI-one catalogue.
FMS2 requires an explicitly selected, verified imported catalogue or resident
binding. No synthetic test device ID or automatic latest-build selection is added.
The source checkout remains service-free; binary provisioning still uses the
normal explicit prepared-package workflow.

SDK runtime manifest is
`b4c51684947f7f0fdfd6c86496b964cd9cd23af76b9ad8f482f78697420fe566`,
inventory `bed0aecb48fdfa7734be8785f1619f0cc397488b03ff35758f6629c621b8bd14`.
These new assets require fresh signed/physical host qualification; historical
ABI-one iPad/iPhone results retain their original input identities.

## API and compatibility

`ManagedFirmwareBuildDescriptor` accepts the closed ABI-two **schema 2**, with
`stateAddress`, `stateCapacityBytes`, and `compilerContractSHA256` in addition to
its existing fields, profile `nano-managed-v2`, resident ABI 2 and target ID 2.
The compiler contract hash and matching recipe hash are checked exactly. Its
canonical descriptor ID matches the Compiler implementation independently.

`ManagedResidentState(address:capacityBytes:)` represents bounded, aligned RP2040
RAM from reviewed resident build facts. Pass it as `state:` to
`ManagedResidentBinding`, or derive the binding from an exact descriptor and a
reviewed `ManagedDeviceAssociation`. Omitting state preserves ABI one. A
schema-two resident record requires the same three additional fields. Hello
cannot attest the RAM layout or exact installed ELF/UF2.

Choose `.nanoManagedV2` in `ManagedSketchBuildRequest`; a profile/binding mismatch
fails locally. Both public compiler overloads, shared preparation and supplied-ELF
conversion preserve the exact selection through their requests and receipts.
WebKit selects only that profile's pinned recipe bytes. The Swift boundary checks
returned correlation, source/descriptor/recipe identity and independent capsule
bytes; no native ELF compiler/producer is added.

`ManagedCapsule` independently verifies FMS2 magic/version/header, exact image
span, alignment, flags/padding, Thumb entry bounds, exact RAM/API binding and
both payload/header SHA-256 values, then checks the report's state/data/BSS/hash
fields. A valid digest cannot authorize a mismatched resident. State is reset
before setup for every generation/reboot and retained between loops; it is not
nonvolatile persistence. Constructors, TLS, heap, general Arduino libraries and
rollback remain unsupported.

`stageManagedUpload` rechecks the fresh hello for target 2, format
`nano-managed-v2`, exact 4096/1024 limits, application backend and physical
D2-to-GND authorization policy. FMS1 and FMS2 cannot be cross-staged. Every
begin/finish/commit/abort/status command uses the selected record's target ID;
type-four transaction ID/offset remain big-endian. Saved record schema 1 now
accepts the two exact target/format pairs, rejecting mixtures.

Commit remains one-shot. A lost reply is uncertain, never retried; fresh-session
reconciliation checks device/boot/target/record identity before read-only status.
An ABI-one advertisement cannot reconcile a target-two record. Firmware's
absolute 30-second staging lease can return `io_error`; callers must stage and
explicitly commit within it, retaining failures rather than treating an envelope
as success. `installed`, `boot_confirmed` and useful behavior remain distinct.

## Actual checks, 2026-10-15

- `node Tools/ManagedWASM/run-validation.mjs EXPLICIT_PINNED_SERVICE` passed:
  fixture inventories, package/host-tool checks, complete Swift suite and actual
  WebKit compilation. The new public legacy-binding and offline-descriptor FMS2
  builds, plus shared supplied-ELF conversion, produced the independently
  firmware-checked 380-byte capsule
  `e349a77d85958db1c4eba4f5c10f27e23dc9dd2ce03eb675c108d07bbfd93abb`
  (120 code, 4 initial data, 4 BSS). ABI-one runtime regressions also passed.
- Firmware's production host validator checked the same Compiler-produced bytes,
  guarded RAM initialization, generation replacement and host boot dispatch;
  ARM instructions were not executed.
- Independent firmware golden frames passed target-two staging/commit/status,
  lost-commit uncertainty/no replay, old-target rejection and 23 capsule-mutation
  cases. Imported fixture files are checked by `Tools/verify-fixtures.py`.
- Xcode 27.0 iOS and iOS Simulator builds passed through
  `Validation/FirmingoKit.xcworkspace`, scheme `FirmingoKit`, with signing disabled;
  macOS `docbuild` passed. These are build/documentation checks, not device runs.

The manual self-hosted workflow now names both profiles and uses the same suite.
No remote SDK CI success is claimed without a provisioned runner/run. The later
NanoStateful qualification explicitly replaces the selected recoverable Nano's
resident with user authorization and full ROM readback, then records both
physical hosts separately. The separate [NanoRecovery record](nano-fms2-interruption.md)
now covers pre-commit disconnect/power-cycle and real commit-reply loss with
query-only app-restart recovery, state/echo and a fresh upload on both hosts.
The iPhone record preserves an unidentified prerequisite rejection before its
successful final association. Default catalogue/production delivery, minimum OS,
broader host coverage, flash-write power loss/corruption and full SDK ROM recovery
remain open. Historical ABI-one results retain their original scope.

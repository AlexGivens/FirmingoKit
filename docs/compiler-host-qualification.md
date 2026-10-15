# Signed compiler host qualification

`Validation/CompilerHost` is a small public-API test app for macOS, iPad and iPhone.
It compiles bundled fixtures without a board, association or upload workflow. Run
starts six finite checks; Share results exports the journal. The app saves the
current stage before work and appends only completed checks. Running/failed or
interrupted journals never claim success.

```sh
python3 -I -S -B Tools/ManagedWASM/make-compiler-host.py \
  PREPARED_SDK TRUSTED_PREPARED_MANIFEST_SHA256 NEW_HOST_DIRECTORY
xcodebuild build -configuration Release \
  -project HOST_DIRECTORY/CompilerQualification.xcodeproj -scheme CompilerQualification \
  -destination 'generic/platform=macOS' -derivedDataPath NEW_MAC_BUILD_DIRECTORY \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES ENABLE_DEBUG_DYLIB=NO CODE_SIGNING_ALLOWED=NO
codesign --force --sign 'YOUR_APPLE_DEVELOPMENT_IDENTITY' --options runtime --timestamp=none \
  --entitlements HOST_DIRECTORY/CompilerQualification.entitlements APP_PATH
python3 -I -S -B Tools/ManagedWASM/run-compiler-host.py APP_PATH EXPECTED_TEAM_ID NEW_RESULTS_DIRECTORY
```

Generation verifies every independently anchored prepared SDK/source-delivery
record and the exact compiler/resource/source roles before creating a new project.
Its package reference points only to that SDK. No signing identity/team is baked
in. Generation performs no signing, installation, pairing or account/device change.
Signing is explicitly selected separately. The runner requires the selected
development team, signed bundle identifier, strict signature, hardened runtime
and exact sandbox/network-client entitlements before launch. No JIT, unsigned
executable-memory or broad filesystem entitlement is added.

The runner launches one fresh UUID with a 180-second outer bound, checks the
correlated journal, six steps, known capsules and bounded worker memory, then
writes completion last. Mac reports export through inherited stdout; neither
private app containers nor native UI are inspected. Failed output retains raw
stdout/stderr/signature and a failure record in its own new directory.

## Actual macOS result — 2026-10-14

The ARM64 Release app passes on macOS 27.0 (26A428), Xcode 27.0 (27A266a), Swift
6.4. Apple Development team `WGR9T9JH4L`, strict deep verification, runtime flag
`0x10000` and two finite entitlements are observed externally. Context is prepared
SDK commit `3927416…`, manifest `ba8d63b3…`, compiler package `d042dc7d…`, exact
experimental resident build `c44d25ef…`.

Two launches pass resources, first GPIO build, subsequent console build, frontend
rejection, busy/cancellation and fresh post-cancellation GPIO. First-run sketch
times are approximately 1.02/0.76 seconds. Both reproduce independent capsule
vectors `958b861b…` and `b372c00e…`. Observed WASM linear bytes are 27,983,872;
this is not total app/WebKit peak memory. [The machine-readable record](compiler-host-macos.json)
contains the second run's exact times, code-directory hash, journal and provenance.
The production 60-second SDK deadline remains; this app does not force its expiry.

Restricted signature inspection initially reported unavailable trust/entitlements;
normal Security access verifies the real certificate chain and entitlement data.
An external read of the app's journal was blocked by macOS container privacy.
The app now exports its own journal through stdout; trust/privacy settings and
filesystem permissions remain unchanged. A translated Python initially selected
Intel for type-checking; the check now uses the maintained ARM64 Apple CI target,
matching the built Swift module.

Six tiny tool fixtures pass, covering unsafe/duplicate/Boolean/missing inputs,
required compiler/source roles, special files, cleanup and stale/failed/oversized
journals. Normal adapter validation includes those fixtures and warnings-as-errors
source type-checking; 152 SDK test functions pass with nine unavailable-service
skips. This source-only CI path supplies no compiler binary and launches no app.
The iPad/iPhone device-target Release build passes with signing disabled.
AppIntents emits its standard no-framework metadata note; final Swift sources
have no warnings. Complete app CI is deliberately excluded until prepared assets
and signing/runner provisioning exist. Local execution is separate evidence.

## Physical iPad handoff

Connect the selected iPad to this Mac by USB, unlock it and handle any ordinary
Trust prompt. Xcode must see it before installing a development-signed app; a
valid profile/account and Developer Mode may require operator action. The current
inventory remembers a disconnected 11-inch iPad Pro (3rd generation), iPadOS
27.0.1. Cached inventory is not a physical test result.

Keep the app foregrounded, run checks and share the JSON journal. Record actual
model, OS/build, signing/profile, cold/repeated times, unexpected termination and
reported identities. No Nano/Pico is needed yet. Agent visual inspection remains
disabled; user observations and exported results are separate evidence.

Minimum-OS runtime, total app/child memory peaks, forced termination/deadline,
physical iPad/iPhone, installed-image evidence and Nano deployment remain open.
Pico managed compilation is unavailable. Hardware follows host checks with an
exact selected recoverable Nano resident and separately authorized SDK workflow.
No binary publication, physical-device installation or board operation occurred.

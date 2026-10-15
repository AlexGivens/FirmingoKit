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

## Actual physical iPad result — 2026-10-14

The development-signed ARM64 Release app was installed and executed on an iPad
Pro (11-inch, 3rd generation), iPad13,4, running iPadOS 27.0.1 (24A446). CoreDevice
confirmed a paired wired connection and enabled Developer Mode. The existing
Apple Development team/profile covered this device; strict deep signature,
application identifier and profile membership were checked before installation.
No provisioning updates or account changes were requested. iOS entitlements are
application/team identifiers and development debugging permission; no JIT or
unsigned executable-memory entitlement was added. The macOS hardened-runtime
configuration is separate from this iOS signature.

Both app launches pass all six checks. The first launch after installation takes
0.826 seconds for GPIO and 0.712 seconds for console. A fresh app process repeats
them in 0.655/0.693 seconds. These are first/subsequent builds within an app run;
OS caches were not cleared. All builds reproduce the desktop capsule identities
and report 27,983,872 WASM linear bytes. The sealed app contains the exact
101,194,565-byte compiler; its 22 files total 104,298,119 logical bytes, distinct
from an IPA download size, installed disk allocation or process memory.

CoreDevice copied only each qualification run's report and two generated
capsules. Fresh UUIDs, complete steps, exact prepared/package context, finite
times, memory bounds and the capsule bytes were checked. The independent native
firmware validator accepts both capsules at API `0x10022c9c` and rejects the
historical `0x10022ca0` address. This validates capsule structure/binding, without
executing Thumb code. [The machine-readable iPad record](compiler-host-ipad.json)
preserves both reports, signature/profile/source identities and validator results.
No visual inspection was performed or UI/accessibility result inferred.

To reproduce on iPad or iPhone with a generated host and a separately selected connected device,
use a new derived-data directory and an existing development team/profile:

```sh
xcodebuild build -configuration Release \
  -project HOST_DIRECTORY/CompilerQualification.xcodeproj -scheme CompilerQualification \
  -destination "id=$DEVICE_UDID" -derivedDataPath NEW_IPAD_BUILD_DIRECTORY \
  ENABLE_DEBUG_DYLIB=NO DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic
codesign --verify --deep --strict APP_PATH
xcrun devicectl device install app --device "$DEVICE_ID" APP_PATH --timeout 60
xcrun devicectl device process launch --device "$DEVICE_ID" --timeout 30 \
  com.firmingokit.compilerqualification --qualification-run "$RUN_ID"
xcrun devicectl device copy from --device "$DEVICE_ID" --timeout 30 \
  --domain-type appDataContainer --domain-identifier com.firmingokit.compilerqualification \
  --source "Documents/CompilerQualification-$RUN_ID" --destination NEW_RESULTS_DIRECTORY
```

`RUN_ID` must be a new uppercase UUID. Keep the app foregrounded until checks
finish; a copied running/failed journal is not a pass. A deliberate repeat uses
`--terminate-existing` on this app's launch and a new run ID/results directory.
The app also offers Share results. Keep raw device/profile metadata local; record
model/OS and selected identities without publishing device names, UDIDs or serials.
The macOS runner does not launch iOS apps.

## Actual physical iPhone result — 2026-10-14

The same signed ARM64 Release app was installed on an iPhone 15 Pro Max,
iPhone16,2, running iOS 27.0 (24A437). CoreDevice confirmed its paired wired
connection and enabled Developer Mode. Strict deep signature, exact application
identifier and this phone's membership in the existing profile were checked.
The executable, profile, compiler and generated host inputs match the iPad test;
no rebuild, provisioning update or account change was needed.

Both fresh app launches pass resources, GPIO/console builds, frontend diagnostics,
busy/cancellation and post-cancellation compilation. First-launch GPIO/console
times are 0.858/0.663 seconds; the second launch records 0.627/0.635 seconds.
OS caches were not cleared. All completed builds report 27,983,872 WASM linear
bytes; total app/WebKit peaks remain unmeasured.

Reports and capsule bytes were copied only from this app's two run directories.
UUIDs, complete steps, exact source/package context, durations, worker memory
bounds and hashes were verified. Both exported capsules match iPad/macOS output,
pass the independent firmware validator at `0x10022c9c` and are rejected at the
historical `0x10022ca0` address. [The machine-readable iPhone record](compiler-host-iphone.json)
preserves both reports and the same signing/provenance/validator identities.
These results cover this model/OS and constrained compiler fixtures; they do not
qualify arbitrary sketches, the demo or board deployment.

## Actual wireless deployment result — 2026-10-14

After the user disconnected both devices from the Mac, CoreDevice established
`connected`/`localNetwork` connections to the paired iPad and iPhone. The same
development-signed Release app was reinstalled on each through the network,
launched with a fresh UUID and its own report/capsules retrieved. Both devices
still reported `connected`/`localNetwork` after collection. Existing profile
membership, strict signature and exact entitlements were rechecked; no rebuild,
pairing configuration or provisioning update was required.

Each wireless run passes all six compiler checks and produces the exact wired
capsule vectors. GPIO/console times are 0.737/0.713 seconds on iPad and
0.760/0.639 seconds on iPhone. [The wireless record](compiler-host-wireless.json)
preserves both reports, transport checks, installation/launch/copy outcomes and
verified exported capsule hashes. The reinstall may reuse cached payloads; it is
not a cold full-transfer or Wi-Fi throughput measurement. Debugger attachment and
Instruments profiling were not exercised.

The existing `devicectl` install/launch/copy commands above select the paired
device; they need no separate Wi-Fi option when CoreDevice reaches it through
`localNetwork`. For later board checks, keep the Mac and Apple device on their
working local network and confirm that transport before launching. The Nano can
occupy the device's USB-C port while app deployment uses the network, but actual
simultaneous Nano USB Ethernet/Wi-Fi routing still needs a separate measured test.
This wireless increment performs no board operation or network configuration.

## Repeated builds and forced app interruption — 2026-10-14

The generator now copies an optional `QualificationStress.swift` host alongside
the original six-check mode. With a fresh uppercase run UUID, append
`--qualification-stress-count 20` to the existing device launch command. Counts
are restricted to 2–40. The host alternates the pinned GPIO/console sources,
checks every artifact/receipt, samples its own process footprint nominally every
50 ms and records a separate schema-2 journal in the same per-run directory.
It retains at most 4,096 samples and reports dropped samples. Kernel measurement
failures produce failed journals rather than zero-valued successes. Individual
builds retain the production deadline; new loop iterations stop being admitted
after 120 seconds. The sampler is canceled on every normal/error exit.

```sh
xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing --timeout 30 \
  com.firmingokit.compilerqualification --qualification-run "$RUN_ID" --qualification-stress-count 20
python3 -I -S -B Tools/ManagedWASM/check-compiler-stress.py REPORT_JSON "$RUN_ID" 20
```

Collection uses the preceding own-container copy command. The checker requires
the correlated UUID, complete count, pinned artifact identities, finite durations,
bounded worker memory and ordered nonzero footprint samples. Passing means those
checks completed and measurements were collected; no memory budget or absence of
leaks is asserted. `TASK_VM_INFO.phys_footprint` queries only this host process;
see [Apple's task VM information](https://developer.apple.com/documentation/kernel/task_vm_info_data_t).
It excludes WebKit children, and a periodic maximum can miss the true peak.

The signed ARM64 Release app, build 2, was updated wirelessly using the existing
profile. Each device completed 20 builds, then ran a separately selected 40-build
series. Before termination, its correlated journal showed completed builds and
an incomplete current stage. CoreDevice sent `--kill` only to the app PID from
that launch, cross-checked against the app's own PID and executable path. Both
post-kill journals remained `running`, with 11 completed builds and durable stage
`build-12-console`; the checker rejected them. This identifies an interrupted
build series, not an exact instruction/worker phase. Fresh app processes each
completed another 20 builds. Re-copying the interrupted journals after recovery
confirmed byte-identical content and no automatic replay/overwrite. In total,
80 baseline/recovery builds passed, plus 22 completed before interruption. The
updated iPhone app also passed the original six checks and exact capsule bytes.

For a separately selected interruption run, request 40 builds and save the
launch JSON with `--json-output RUN_LAUNCH_JSON` before the bundle identifier.
Copy its own journal and confirm it is still running/incomplete, has the expected
UUID/context, and reports the same PID as that app's launch/executable. Then:

```sh
xcrun devicectl device process terminate --device "$DEVICE_ID" --pid "$QUALIFICATION_PID" --kill --timeout 20
```

Collect that interrupted journal, verify the checker rejects it, and launch a new
UUID with 20 builds for recovery. After recovery, re-copy the old journal and
compare its bytes with the post-kill copy. This operation is confined to the
explicitly selected qualification app and is separate from a normal completed run.

| Host/run | Highest sampled host footprint | Last sampled host footprint |
| --- | ---: | ---: |
| iPad baseline | 790.4 MiB | 405.3 MiB |
| iPad fresh recovery | 698.1 MiB | 404.9 MiB |
| iPhone baseline | 789.7 MiB | 303.0 MiB |
| iPhone fresh recovery | 789.5 MiB | 206.3 MiB |

Every completed build reports 27,983,872 WASM linear bytes. These historical host
footprints prompted the resource-reader investigation below; neither a leak nor
a memory-budget pass follows from these runs.
The [reliability record](compiler-host-reliability.json) preserves checked summaries,
timings, observed peak samples, raw report hashes and source/signature identities.
Complete raw journals remain local under `.build/`.

An app-scoped ten-second `xctrace` Activity Monitor attempt exited 21 with
“Cannot find process for provided pid”; it yielded no memory result. No
all-processes capture or private WebKit PID API was used. Aggregate app/WebKit
memory remains open, along with real memory pressure, child-process termination,
background/foreground transitions and forced production-deadline expiry.

Seven tool fixtures and the maintained SDK validation pass (152 reported test
functions, nine expected unavailable-service skips). macOS warnings-as-errors
type-checking and a source-only iOS SDK build pass. Optimized iOS Release building
initially caught a nested recorder's missing explicit main-actor annotation that
macOS type-checking missed. The recorder is now explicitly isolated. The new CI
iOS step compiles optimized host objects against built source-only SDK modules,
without app linking, assets, signing or device access. A local negative control
rejects the original actor error; final optimized object compilation passes.
The physical Release build has no Swift warnings, only the standard AppIntents
no-framework metadata note. Runner provisioning/remote SDK CI remains open.
Workflow YAML and run-step shell syntax checks pass; the logging pipeline retains
the failing command's exit status. `actionlint` is not installed on this host.

## Resource-reader memory comparison — 2026-10-14

SDK commit `4edc6aa86040a86eb171c29eff9be0d82800c7b2` reduces resource-read
allocation growth without changing compiler inputs or public APIs. Both default
and explicit-service readers reserve the validated file size once and drain
Foundation chunk temporaries in a synchronous `autoreleasepool` after each append.
They retain owned byte snapshots, size limits, per-chunk cancellation, hashing and
their existing cleanup/error behavior. No mutable file mapping is introduced.
Apple documents [local autorelease pools](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmAutoreleasePools.html)
for controlling temporary-object lifetimes; the measurements here test the
combined capacity/pool change rather than assigning each an isolated contribution.

A native optimized Mac probe calls the actual internal production reader six
times, reading and SHA-checking the same 101,194,565-byte compiler on each call.
With identical probe source/flags and no WebKit, observations while the returned
bytes remain alive climb from 196 MiB to 1,164 MiB in the old reader; the candidate
stays at 100.3–100.4 MiB. Those are end-of-read observations, not continuous peaks.
The old native reader source is identical to the earlier physical baseline's.

The new clean prepared SDK contains 277 files and has manifest anchor
`f2ed2b6aed07e07c9fc4ffd43d4fd3e750f6e1f36d61dd405e6a38f5dab40fe4`.
Generate the host using the existing command with that anchor; sign a Release
iOS build with `CURRENT_PROJECT_VERSION=3` and `ENABLE_DEBUG_DYLIB=NO`. The three
host Swift sources, compiler module, consumer manifest, recipes, catalogue and
known capsules match the earlier baseline. The generated context now identifies
the tested SDK commit. The existing development profile covers both devices.
Install and launch through the paired `devicectl` network connection using the
same commands above; create a fresh UUID/process for each 20-build run.

| Host/run | Highest sampled host footprint | Last sampled host footprint |
| --- | ---: | ---: |
| iPad first | 213.7 MiB | 115.3 MiB |
| iPad second | 213.3 MiB | 115.4 MiB |
| iPhone first | 208.7 MiB | 110.1 MiB |
| iPhone second | 209.1 MiB | 109.9 MiB |

All 80 builds pass the existing strict journal/artifact checks: forty GPIO and
forty console capsules retain their known hashes; worker linear memory stays
27,983,872 bytes. No samples were dropped. Nominal sampling remains 50 ms; the
largest observed gap is 94.2 ms on iPad and 60.0 ms on iPhone. Compared with the
earlier maximum observations on each device, the new maxima are about 73% lower.
These are sequential observations on the same models/OS, not a randomized
benchmark. Host samples exclude WebKit children and missed peaks.

The original six-check mode also passes in a fresh process on each updated app,
including diagnostics, busy/cancellation and a successful subsequent build.
Both exported GPIO/console files match the previously independently validated
316/392-byte vectors. Device details show `localNetwork` before and after every
run. No board was contacted. The updated development app remains installed.

The full SDK validation passes with 154 reported test functions, all nine actual
macOS WebKit cases and seven host-tool fixtures. The prepared SDK separately
passes 154 reported test functions with one expected source-only absent-binary
test skipped. The iOS SDK build and optimized host-object check pass. New tests
cover multi-chunk/partial-tail exact bytes, excess-size rejection, independence
from in-place source-file changes, pre-cancellation and a fresh read. Existing CI
entry points cover these changes; remote CI remains unprovisioned/unrun.

The [memory record](compiler-resource-memory.json) preserves source/signature
identities, probe observations, checked device summaries, report hashes, timings
and exported capsule hashes. Raw journals remain local under `.build/`. The
earlier reliability record is unchanged. Aggregate memory, a memory-budget pass,
long-term stability and real lifecycle/pressure scenarios remain open.

## Opt-in idle background/return check

`--qualification-idle-lifecycle` selects a separate schema-3 journal. The harness
uses real [SwiftUI scene phases](https://developer.apple.com/documentation/swiftui/scenephase),
compiles/exports the known GPIO capsule, then waits while idle. Go Home, wait five
seconds and return to this app. It requires at least three seconds between an
observed background phase and a later active phase, then compiles/exports the
known console capsule using the same public compiler instance. No background
execution entitlement or task extension is added. The original six-check mode
remains the default; stress and lifecycle launch flags cannot be combined.

Generate/sign/install the host as above with the added lifecycle source. Launch
with a fresh UUID and save the CLI's JSON so its process ID is independently
available. All `devicectl` options precede the bundle identifier/app arguments:

```sh
xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing --timeout 30 \
  --json-output LAUNCH_JSON com.firmingokit.compilerqualification \
  --qualification-run "$RUN_ID" --qualification-idle-lifecycle
```

Wait for the exported journal's `waiting-for-background` stage before performing
the manual transition. The journal is atomically updated at each observed scene
change; inactive alone cannot pass. The manual observation window is ten minutes,
with the public compiler's existing build deadline unchanged. After returning,
copy this app's `Documents/CompilerQualification-RUN_ID` directory and require a
completed report with the same UUID, PID and generated context:

```sh
python3 -I -S -B Tools/ManagedWASM/check-compiler-lifecycle.py \
  REPORT_JSON "$RUN_ID" "$QUALIFICATION_PID" GENERATED_HOST/host-inputs.json
```

Also hash both exported `.fms` files against the known GPIO/console vectors.
A killed/relaunched process, missing/brief transition, running/failed journal,
wrong context or changed artifact is not a pass. The eight source-tool fixtures
cover these report boundaries; macOS type-checking and optimized iOS object
compilation include the new observer without executing an app. Physical evidence
must be recorded separately after actually performing the transition.

This checks an **idle scene transition**, not compilation while backgrounded,
OS suspension, memory pressure or interruption of an active build. Those remain
separate qualification gates. No SDK lifecycle policy or board operation is added.

The [lifecycle record](compiler-host-lifecycle.json) pins host source `7b1cb39…`,
the unchanged prepared SDK, generated inputs and development-signed Release build
4. Both device installations succeeded over Wi-Fi. The updated iPhone app passes
the original six-check mode and both exported capsule files match the known
vectors. Both physical manual idle transitions now pass:

| Host | Background-to-active observations | Before GPIO build | After console build |
| --- | ---: | ---: | ---: |
| iPad Pro (11-inch, 3rd generation), iPadOS 27.0.1 | 10.235 s | 0.722 s | 0.727 s |
| iPhone 15 Pro Max, iOS 27.0 | 20.166 s | 0.597 s | 0.710 s |

Each report matches its independently saved launch PID, UUID and prepared context.
All four exported files match the known 316-byte GPIO/392-byte console vectors;
worker linear memory remains 27,983,872 bytes. CoreDevice reports connected
`localNetwork` before and after both runs. The first post-return iPhone copy caught the final
build still running and was correctly rejected; its completed snapshot passes
without relaunching or changing the process. Both snapshots remain local and
their hashes/status are recorded. No OS suspension or background execution is
inferred from scene timestamps. Eight tool fixtures,
macOS/optimized iOS source checks, the Release app build, workflow YAML and shell
syntax checks pass. No remote CI run or additional full SDK test run is claimed
for this host-only change.

Minimum-OS runtime, total app/child memory peaks, forced WebKit-child termination/deadline expiry,
other physical model/OS combinations, installed-image evidence and Nano deployment remain open.
Pico managed compilation is unavailable. Hardware follows host checks with an
exact selected recoverable Nano resident and separately authorized SDK workflow.
No binary publication or board operation occurred. The development qualification
app remains installed on the selected iPad and iPhone.

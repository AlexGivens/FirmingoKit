# Firmingo Workbench consolidation

Started 2026-11-02. This is the app-owned integration-test surface over public
FirmingoKit APIs. Compiler execution/recipes stay in Firmingo-Compiler; device
contracts and independent validators stay in Firmingo. Historical qualification
hosts/results are retained until their scenarios have equivalent new evidence.

## First increment (locally validated)

- Shared `Demo/WorkbenchSupport` package: version-one requests, scenario registry,
  bounded durable reports, no-replay run identities, cancellation and retained history.
- Existing demo becomes Firmingo Workbench, retaining its bundle identity and
  normal documents, console, build/upload and installation guards. Test Lab uses
  the same engine as an explicit app launch command.
- Compiler catalogue/resource checks, pinned two-source smoke and diagnostic/fresh
  build cases migrate first. Hardware/recovery and lifecycle cases are visibly
  blocked until migrated; this command protocol has no device operation.
- `Tools/Workbench/workbench.py`: list/run through the same selected macOS app
  binary, validate correlated results and export evidence without private-container
  access, native UI inspection, sibling checkout lookup or runtime provisioning.

The initial CLI launches one owned app process per explicit offline command; it
is not a live connection to an already running window. The subsequent [paired controller](workbench-paired-controller.md) adds live
mobile commands and automatic report collection. MCP, external lifecycle control
and hardware scenario migration remain later increments. The manual Test Lab shares code on all three
Apple platforms. No network control listener is added in this increment.

## Completion checks

- Deterministic engine tests cover admission, stale/duplicate run rejection,
  failed journal gates, busy/cancel, blocked resources and preserved incomplete history.
- CLI fixtures reject stale/duplicate/malformed results and non-success test states.
- Build the existing app for macOS, iOS device and Simulator; exercise CLI discovery
  and an actual run using one development-signed sandboxed macOS app.
- Required resources unavailable means blocked, never a WASM pass. Real-runtime
  checks require explicitly provisioned reviewed assets and retain exact identities.
- No board is contacted, installed, reset or flashed by this increment.

## Follow-through

The [device scenario increment](workbench-device-scenarios.md) now implements
inspection and fixed binary console through the shared engine and MCP, with
explicit schema-two hardware selection. The version-one offline contract and
historical first-increment results below retain their original scope. Selected
Nano inspection/raw binary console now pass through native MCP on the physical
iPhone ([ledger](workbench-device-qualification.json)); iPad/FMS2 mode and guarded
upload/ROM migration remain separate steps.

Compiler busy/deadline/lifecycle/stress migration is tracked in
[the compiler-scenario work log](workbench-compiler-scenarios.md). Next migrate read-only device and
binary-console cases, then guarded upload/ROM recovery. The paired iPad/build-8 and iPhone/build-9 compiler, resume and revocation
qualification is recorded in the controller ledger. The [thin MCP adapter](workbench-mcp.md) now wraps the versioned controller API; Codex registration and two fresh native-host iPhone compiler scenarios now pass; see [the iPhone MCP ledger](workbench-mcp-iphone.json). Broader MCP/device qualification remains separate. Retire legacy generators
only after matching scenario evidence; preserve previous reports and unresolved
networking/qualification limits. Firmware fault images remain separate physical
inputs even when one app orchestrates every scenario.

## App and CLI usage

The canonical scheme is **FirmingoWorkbench** in the existing
`Demo/FirmingoDemo.xcodeproj`; the old `FirmingoDemo` scheme remains an alias to
that same target/product. Product/executable is `FirmingoWorkbench.app` /
`FirmingoWorkbench`. Bundle ID remains `com.firmingokit.demo`; test phases do not
create new app identities. The first increment used build 2; automatic compiler qualification used build 3,
and physical mobile lifecycle qualification uses build 4. No entitlement or listener
is added. The original editor, device actions and programming guards remain.

Build the app with your existing development signing configuration:

```sh
xcodebuild build -project Demo/FirmingoDemo.xcodeproj -scheme FirmingoWorkbench \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .build/workbench-app
python3 -I -S -B Tools/Workbench/workbench.py --help
python3 -I -S -B Tools/Workbench/workbench.py list \
  --app .build/workbench-app/Build/Products/Release/FirmingoWorkbench.app \
  --team YOUR_TEAM_ID --output .build/workbench-list-1
python3 -I -S -B Tools/Workbench/workbench.py run \
  --app .build/workbench-app/Build/Products/Release/FirmingoWorkbench.app \
  --team YOUR_TEAM_ID --output .build/workbench-catalogue-1 \
  --scenario compiler.catalogue
```

Each output directory must be new. `--team` must match an existing Apple Development
signature with hardened runtime, sandbox, outgoing networking and user-selected
read/write entitlements. The CLI never signs/builds/installs an app. It launches
only the selected app binary, with a fresh request ID by default, and kills only
that owned process if its 180-second/output bound expires. This is an offline test
invocation, not attachment to a preexisting editor process. UIKit/macOS may still
present normal document startup UI; the automation task is app-owned, independent
of view lifetime, and requests no document or device action.

For `compiler.smoke` / `compiler.diagnostics`, supply the explicit migrated vector
build ID with `--build-id`:

`c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f`.

The source checkout intentionally lacks `compiler.wasm`: catalogue verification
can pass, while compiler resource/execution cases report **blocked**, exit 3.
For actual compilation, first prepare a clean SDK copy using the existing
`Tools/ManagedWASM/prepare-sdk-package.mjs` with an explicitly supplied reviewed
consumer package and independent anchor. Build Workbench from that prepared copy.
No service override, sibling search, binary download or production asset promotion
is added. A package update may need a new build; selecting a different scenario
within one prepared app never does.

Manual access is the **Test Lab** toolbar button in a sketch window (and the macOS
Test Lab window). Load SDK Catalogue, explicitly select a descriptor for compile
cases, then run a case. Cases show scope, prerequisites and migration blockers;
current run events retain earlier observations. Cancel settles the owned SDK task.
Load Run History restores context only; incomplete snapshots display unknown
without rewriting the original. Export run report uses the app's own sharing path.
Layout, VoiceOver, keyboard/focus and physical mobile UI remain unqualified; no
agent screenshot/native-UI inspection is used.

## Version-one command and evidence contract

CLI `list` and `run` encode at most 4096 JSON bytes into the explicit
`--workbench-request BASE64` app launch argument. No filesystem path, service URL,
physical board ID or hardware permission is accepted in a request.

```json
{"schema":1,"requestID":"17C4EC61-36F3-4EEA-ACF8-4CF70E170194","operation":"run","scenarioID":"compiler.catalogue"}
```

`run` may additionally carry an exact lowercase `firmwareBuildID` digest.
`list` accepts neither selection. The app checks schema, allowed keys, operation,
scenario, bounds and selection before journal admission. At most one scenario or
metadata inspection runs in an engine. Run UUIDs reserve exclusive app-private
directories before SDK work; an existing UUID is rejected even after restart.
There is no resume operation, external execution token or device-changing command.

The app exports exactly one bounded `FIRMINGO_WORKBENCH_RESULT:` base64 JSON line
through inherited stdout. It contains schema, original request, actual PID,
scenario registry, verified catalogue when available, terminal report or bounded
command error. The CLI independently checks request/PID correlation, terminal
state, event ordering/time bounds, artifact paths/sizes/digests and app exit status.
Missing/duplicate/stale/malformed responses fail. Results retain the selected app
signature, executable hash, original stdout/stderr, launch PID, request, complete
response and any real exported capsules. No private-container access is required.

Reports use at most 64 ordered events, three bounded capsule artifacts and 64 KiB
serialized JSON. SDK offline receipts retain actual source/catalogue/descriptor,
recipe/toolchain, ELF and capsule identities. Worker linear-memory observations
are not aggregate app/WebKit peaks. `deviceOperations` is always false in this
protocol. Journal writes synchronize file/directory metadata before publication;
failed journal gates prevent later SDK work or a published success. History scans
at most 4096 entries and returns at most 32 recent snapshots; archive old evidence
explicitly rather than silently deleting it.

Exit codes: 0 = discovery completed / scenario passed; 1 = failed or unknown;
2 = invalid command, journal/transport/launch failure; 3 = blocked; 4 = cancelled.
Blocked is never a successful compiler check. Command failure records do not erase
app-private unfinished context. Durable device installation/upload journals remain
in their existing SDK/demo workflows and are not replaced by these compiler reports.

## Validation entry points

```sh
swift test --package-path Demo/WorkbenchSupport --scratch-path .build/workbench-support \
  --disable-xctest --enable-swift-testing -Xswiftc -warnings-as-errors
python3 -I -S -B Tools/Workbench/test-workbench.py
node Tools/ManagedWASM/run-validation.mjs
```

The ordinary entry point includes both new suites and preserves all legacy host
checks. Adapter CI also compiles the complete Workbench app for macOS, iOS and
Simulator on its explicitly provisioned Apple runner; no signed app execution,
compiler binary provisioning, test listener or hardware action runs implicitly.
Local validation is recorded separately from any remote CI execution.

## Recorded first-increment results — 2026-11-02

[Local evidence ledger](workbench-consolidation-local.json) retains the exact clean
SDK source revision, reviewed package anchor, prepared inventory, signed executable
identity, request/PID correlation, original response hashes and full terminal run
reports with capsule bytes/receipts. Initial source-only observations retain their
separate earlier binary identity.

The prepared app was built from clean SDK commit
`a28e3f044a92a1e52d9f467eb1e66d2ddaf92394`, with consumer manifest
`1bbc0cc19d80490914799fbec5cb4bbc0a942a73fd3bbf6e09fff2c3856e660a`.
One development-signed, sandboxed Workbench binary on macOS 27.0 (26A428) completed
CLI discovery, resource verification, cold/warm compilation and diagnostic/fresh
build checks. The GPIO capsule was 316 bytes, SHA-256
`958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d`;
the console capsule was 392 bytes, SHA-256
`b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0`.
The real frontend error mapped to `Workbench-invalid.ino`, line 1, column 16;
a subsequent known GPIO build passed using the same compiler instance.

Reusing the completed smoke UUID in a new app process returned command error
(exit 2), with no run report or catalogue load. Selecting the unmigrated hardware
case returned blocked (exit 3). These are expected rejections, not compiler passes.
All six invocations used the same executable digest. No board or external service
was contacted, no app was deployed to a device and no native UI was inspected.

Eight final engine tests and seven CLI fixtures passed. The ordinary SDK entry
point also passed 166 SDK tests, eight ROM-host tests, the seven initial engine
tests and existing source/tool checks; the added eighth parent-cancellation case
passed separately with warnings as errors. Complete Release app builds passed
for macOS, generic iOS and generic iOS Simulator; the Simulator check also built
the prepared-resource snapshot. These builds do not qualify physical mobile UI,
minimum OS, hardware or deployment behavior. Remote CI execution remains pending.

The first increment is complete at this scope. Next migrate compiler lifecycle,
deadline and stress cases, then pair a mobile controller before migrating device
and guarded recovery operations. Keep the existing specialized hosts available
until their replacements have equivalent evidence.

## Second increment — compiler scenarios

[Compiler lifetime/deadline/stress work log](workbench-compiler-scenarios.md)
tracks the extended shared registry, exact workloads, actual scene adapter,
independent CLI assertions and qualification limits. First-increment results above
remain scoped to their original source/binary identities.

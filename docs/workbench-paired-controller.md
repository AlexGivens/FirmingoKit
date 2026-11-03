# Paired Workbench mobile controller

Started 2026-11-02. This increment adds agent-driven scenario control/report export
through the same app-owned engine used by Test Lab. It does not add a compiler,
board-write API, UI inspector, general remote shell or public SDK dependency.
Build 5 preserves the Workbench product/bundle identity.

## Architecture and trust boundary

The Mac runs `Tools/Workbench/paired.py serve` on one explicitly selected private
IPv4 interface. The app initiates outbound HTTPS; it opens no listener and uses
no Bonjour discovery, cloud relay or background execution grant. TLS is pinned
to the exact controller leaf-certificate SHA-256 supplied out of band. Redirects
are refused. No system trust/route/privacy setting is changed.

A one-use 256-bit invitation expires after two minutes. Pairing consumes it and
rotates to a fresh in-memory session credential, bound to a per-process app UUID,
actual PID and bundle/build identity. Sessions expire after thirty minutes; app
or controller restart needs an explicit new pairing. Credentials are absent from
status/reports and held only in protected local controller files or app memory.
This is development-tool pairing, not signed installed-image attestation.

Local agent/operator commands use an owner-only Unix socket in a new 0700 state
directory. Only authenticated app pair/exchange requests reach the private TLS
listener. Eight sessions, eight TLS workers, four queued commands per session,
256 command tombstones and 32 full replies per session bound resource use.
JSON bodies are at most 96 KiB; scenario requests remain closed at 4 KiB and app
reports retain their existing 64 KiB bound. The server rejects browser origins,
chunked/ambiguous length headers, unknown paths and ambiguous JSON keys.

Every command has a UUID and ordered transport sequence. Lost delivery repeats
the same sequence; the app caches the last reply and acknowledges it without
executing the command again. The broker rejects changed or stale acknowledgements.
A lost local command response is uncertain: query its exact command ID rather
than resending an action. Durable engine run UUIDs independently reject replay
after process restart. Broker restart restores no credentials or queued actions.

## Agent usage

Provision/build/install the reviewed app through the existing Xcode and CoreDevice
workflow. The controller does not build/sign/install an app or search for devices.
Use one signed app binary across scenarios and devices, then explicitly bootstrap
the already installed selected app:

```sh
python3 -I -S -B Tools/Workbench/paired.py serve \
  --directory .build/workbench-controller-1 --bind PRIVATE_MAC_IPV4
python3 -I -S -B Tools/Workbench/paired.py pair-device \
  --directory .build/workbench-controller-1 --device SELECTED_APPLE_DEVICE_ID \
  --label iPad --output .build/workbench-pair-ipad-1
python3 -I -S -B Tools/Workbench/paired.py sessions \
  --directory .build/workbench-controller-1
python3 -I -S -B Tools/Workbench/paired.py command \
  --directory .build/workbench-controller-1 --session EXPLICIT_SESSION_UUID \
  --action list
python3 -I -S -B Tools/Workbench/paired.py command \
  --directory .build/workbench-controller-1 --session EXPLICIT_SESSION_UUID \
  --action run --scenario compiler.smoke \
  --build-id c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f \
  --wait --output .build/workbench-mobile-smoke-1
```

`serve` generates a local one-day certificate/key using the installed OpenSSL;
no certificate is installed into system trust. The state directory must be new.
`pair-device` explicitly restarts only the selected installed Workbench app with
one invitation argument. It independently compares CoreDevice's actual launch PID
with the paired producer and redacts invitation arguments from retained launch
metadata. Approve the app's normal local-network prompt when first required.
The invitation/file is sensitive and should stay outside committed source.

Without `--wait`, run acknowledges **durable admission**, not completion. `--wait`
observes terminal state, fetches and independently validates the report, exports
actual capsules, and uses scenario exit status (0 passed, 1 failed/unknown,
3 blocked, 4 cancelled). An existing output directory fails before enqueueing.
Status, cancellation, lifecycle start and report export require an exact run UUID:

```sh
python3 -I -S -B Tools/Workbench/paired.py command \
  --directory .build/workbench-controller-1 --session SESSION \
  --action status --run-id RUN_UUID
python3 -I -S -B Tools/Workbench/paired.py command \
  --directory .build/workbench-controller-1 --session SESSION \
  --action beginLifecycle --run-id RUN_UUID
python3 -I -S -B Tools/Workbench/paired.py command \
  --directory .build/workbench-controller-1 --session SESSION \
  --action report --run-id RUN_UUID --scenario host.lifecycle-worker \
  --build-id c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f \
  --output .build/workbench-mobile-report-1
```

Use `--action cancel` for selected-run cancellation. `revoke --session SESSION`
invalidates the controller capability; the app stops on its next exchange and
cancels only controller-owned work. Local **Disconnect controller** clears app
credentials immediately and stops its owned run; broker last-seen metadata may
remain until timeout/revocation. Manual Test Lab runs are not cancelled by unpair.

## Manual and lifecycle behavior

Test Lab displays pairing status/session and an explicit one-time invitation
field. `invite --label ... --output NEW_DIRECTORY` writes a private base64 file
for manual Connect. Normal app launch stays unpaired; invitation launch does not
start a scenario. The same registry, selected descriptors, durable journal,
busy/cancel rules and real SDK compiler serve UI and controller requests.

Real app scenes drive lifecycle policy. Polling pauses on background and resumes
with the saved sequence/reply after return. No controller action can inject a
scene event. Active lifecycle start is an explicit second action and now records
`startOrigin` (`manualUI` or `pairedController`) separately from the backward
compatible start timestamp. `--wait` returns the real waiting/ready state instead
of synthesizing the required Home action. The user may still need to approve
local-network access and perform actual Home/return transitions.

## Validation and work log

- Swift fixtures cover private pinned invitations, closed commands, durable
  admission before remote acknowledgement, selected-run cancellation, export and
  replay rejection. Existing engine/CLI/mobile-report corpus tests remain active.
- Broker fixtures cover consumed/expired invitations, credential rotation, lost
  delivery/ack deduplication, mismatched producer replies, revocation, queue bounds,
  unknown/device commands, ambiguous JSON and no restoration after restart.
- Ordinary validation starts no listener and contacts no device. Signed actual
  TLS pairing, real WASM scenario/export, wrong-pin/revocation and foreground
  pause/return checks are explicit local qualification, currently in progress.
- Live paired MCP wrapping, OS suspension/pressure, minimum OS and hardware/device
  scenario migration remain separate. This controller supports the closed offline
  scenario surface only; compiler support does not imply upload authorization.

Initial local validation passes: 21 shared-engine/control Swift tests, eight
socket-free broker fixtures, the existing fifteen CLI/report tests and the normal
SDK entry point. An explicit real TLS probe passed credential rotation, bad-token
rejection and revocation; an opt-in Foundation test passed the actual native
certificate-pin delegate against the same endpoint and rejected a wrong leaf pin.
The complete unsigned iOS app also builds. Actual signed paired mobile execution
remains in progress; the probes do not count as physical device/compiler evidence.

## Initial physical connection observations

Build 5 launched on both devices but neither paired. The user reported the iPhone
first local-network prompt followed by an offline error, and an invalid-server-
certificate error on iPad. Both failed invitations are preserved as failed trials,
not successful pairings. Build 6 adds URLSession connectivity waiting within the
existing transport bounds and a scoped `NSAllowsLocalNetworking` declaration.
Private HTTPS selection and exact TLS certificate pin remain enforced; no global
arbitrary-load or system trust exception is added. See Apple's
[local-network ATS documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
and [connectivity waiting](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/waitsforconnectivity).
A bounded, secret-free app-owned `controller.json` snapshot now makes pre-pair
failures visible to development automation; a timed-out pair-device operation
collects only that fixed file and checks its actual launch PID.

Build 6 reached TLS on both devices, but the safe snapshots still recorded
invalid-server-certificate failures; neither trial counts as pairing success.
Build 7 performs explicit SecTrust evaluation using only the already matched
pinned leaf as a connection-local anchor, retaining the existing TLS hostname
and certificate-validity policies. Nothing is added to system trust. Safe TLS
evaluation markers distinguish a pin mismatch from trust-policy failure.

The ephemeral controller certificate explicitly declares a non-CA TLS server
leaf, digital-signature/key-encipherment usage, serverAuth EKU and the selected
private-IP SAN. Connection-local anchor evaluation follows Apple's
[server trust guidance](https://developer.apple.com/library/archive/technotes/tn2232/_index.html).

The streamed-request native reproduction then exposed the missing delegate
route: `URLSession.bytes(for:)` did not invoke the session-level trust callback,
while the earlier `data(from:)` probe did. The production request and opt-in test
now explicitly supply the task-specific pin delegate and forward task trust
challenges through the same pin/anchor policy. Build 7 device failures are retained
as failures; the earlier data-request TLS pass was insufficient for this path.

## Actual paired iPad execution

Build 8 from clean source `0ad5d321634ab2f0d83d9be7ee02cb2a1d004002`
now pairs on the physical iPad and automatically passes catalogue, resource,
smoke, diagnostics, SDK busy/cancellation, actual sixty-second deadline/fresh
recovery and twenty-build stress scenarios. One app process handled all seven;
commands, terminal reports and actual capsule exports came through the pinned
controller, without Test Lab navigation or container scraping. The
[paired qualification ledger](workbench-paired-qualification.json) preserves
producer/run correlation, exported reports, receipts and separate RPC export/reply
hashes, including earlier failed trials. The iPad also passes an actual Home Screen/five-second/return transition: the
same paired connection automatically exports the passed idle-lifecycle report
after resuming. A separate remote `beginLifecycle`/exact-run `cancel` trial exports
`cancelled`, with `startOrigin: pairedController`. An earlier late cancellation
correctly rejects after the un-interrupted worker returned an artifact; that run
remains failed, never a lifecycle pass.

Explicitly revoking an iPad session during a waiting controller-owned run rejects
later commands, stops pairing and cancels that exact run. Only its selected
app-owned diagnostic and report were copied through CoreDevice after revocation;
the normal scenario results came through authenticated RPC. Invalid credentials,
reused completed run UUIDs and existing output directories also reject.

The identical app pairs on the iPhone and automatically passes catalogue,
resources, smoke, diagnostics and busy/cancellation. Its next deadline run was
admitted, but a later status reply was not observed after the device stopped
polling. Subsequent read-only CoreDevice checks could not obtain a connectivity
assertion. No run was replayed and no deadline pass is claimed. Unlock/reopen and
read-only reconciliation, then remaining deadline/stress/pause/revocation
qualification were pending at that checkpoint. Build 8 pauses transport on real
backgrounding and does not prevent auto-lock. The returned-phone follow-up below
retains this failed attempt and records the build-9 policy and fresh qualification.

Final source validation passes the normal SDK entry point, 15 CLI fixtures and
10 socket-free controller fixtures (including archived paired reports and full
CoreDevice metadata redaction). A separate opt-in test exercises the exact
streamed TLS API with the selected pin and a wrong pin. Release builds pass for
macOS, Simulator and the signed iOS device app. Remote CI and UI/accessibility
inspection remain unqualified; no board was contacted.

CoreDevice launch failure diagnostics now retain bounded failure reasons without
retrying or losing a device-locked error. Both repeated argument arrays and nested
error metadata redact base64 invitations and raw credentials before persistence;
only the explicit private invitation file contains bootstrap authority.


## Returned iPhone and foreground idle policy

The user later explained that the phone had left home and returned to Wi-Fi.
Before any restart, CoreDevice retrieved only its exact deadline journal and
safe controller diagnostic. The original journal is terminal **failed**: actual
inactivity at 41.026 seconds cancelled the foreground-only check. It is preserved
unchanged in the paired ledger; no deadline result was replayed or upgraded.
The old session had expired and the returned app correctly dropped authority.

Build 9 adds app-owned idle prevention only while an actual foreground test is
running, through the same engine for manual and paired runs. It captures the
previous UIKit idle setting once, restores it on completion/cancellation or real
backgrounding, and captures the current setting again on return. A visible Test
Lab caption explains this behavior. Ordinary editor use and an idle pairing do
not keep the display awake. Home/lock remain real device actions; this grants no
background execution and changes no SDK timeout. Deterministic policy tests cover
repeated updates, restoration, background release and an already-disabled timer.
Build and physical follow-up results are recorded below when completed.


Build 9 from clean source `8519d6beee40932710db0fe6caeab266d890fce3`
now passes all seven iPhone compiler scenarios through one authenticated session
and PID 30206. The actual public deadline expires in 60.125 seconds with only an
active scene recorded, typed timeout, and a known fresh console build. The stress
case completes twenty exact builds with 54 self-process footprint samples; the
largest is 221,513,760 bytes. These samples do not measure aggregate WebKit/app
peak memory or establish leak freedom. Normal SDK validation passes, including
24 non-network Workbench tests plus one opt-in TLS skip, eleven broker/report
fixtures and fifteen CLI fixtures. Release macOS, Simulator and signed-device
builds pass. The follow-up uses the same existing app product/bundle and reviewed
compiler assets; no new per-scenario app identity or hardware operation is added.


## Completed scoped follow-up

The iPhone build-9 Home/return check passes with the same PID/instance/session;
the controller receives the terminal report after real transport resumption.
The journal records 4.762 seconds from background to active after the requested
Home/five-second/reopen action. A new waiting controller-owned run is then
explicitly revoked: later commands reject, its selected original journal records
`cancelled`, and the safe diagnostic records `isPaired: false`. These revocation
files alone use exact app-owned CoreDevice reads because network authority was
intentionally removed; ordinary compiler/lifecycle reports use authenticated RPC.

The [paired ledger](workbench-paired-qualification.json) and archived exports
retain both app identities: iPad build 8 and iPhone build 9 each have seven
compiler passes plus actual connection resumption and live revocation. Build 9
is not claimed physically tested on iPad. Earlier failed attempts, the original
foreground-interrupted deadline and its stale status command remain historical
facts. The controller is stopped after revocation; no listener or reusable paired
credential is left active. Future runs require a new explicit controller/pairing.

Next work is a thin MCP adapter and migration of guarded read-only device,
console, upload and recovery scenarios. UI/accessibility, minimum OS, real pressure
and hardware qualification remain separate; this increment contacts no Nano.

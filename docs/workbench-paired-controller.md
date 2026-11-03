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

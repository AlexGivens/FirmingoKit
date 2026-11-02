# Workbench compiler lifetime, deadline and stress consolidation

Started 2026-11-02. This increment extends the existing shared Workbench engine,
manual Test Lab and version-one launch CLI; it creates no new app identity,
listener, shortened SDK deadline, compiler implementation or device operation.
Historical qualification hosts/results remain until replacement scenarios have
matching signed/physical evidence.

| Scenario | Assertions | Host actions |
| --- | --- | --- |
| `compiler.cancellation` | Known baseline; first source-compilation callback; overlapping public SDK verification returns typed busy; that exact request settles cancelled; fresh known console artifact | Automatic, same signed macOS CLI or manual Test Lab |
| `compiler.deadline` | Pinned 227,646-byte frontend workload; unchanged public 60-second runtime limit; typed timeout within 60–75 seconds, one compiling callback; fresh known console artifact after settlement | Automatic CLI has process-only scope; interactive mobile additionally requires observed foreground |
| `compiler.stress` | Twenty alternating exact GPIO/console builds; receipts identified per call; bounded self-process footprint samples and post-build worker linear bytes | Automatic, same signed macOS CLI or manual Test Lab |
| `host.lifecycle` | Known artifacts around actual active/background/active observations, at least three seconds away, same app process | Interactive iOS/iPadOS; go Home for five seconds and return when prompted |
| `host.lifecycle-active` | Baseline, explicit second Start action, inactivity while a pinned long SDK call is pending, typed cancellation settlement, actual background/return, fresh artifact | Interactive iOS/iPadOS; observed phase is recorded without a source-phase claim |
| `host.lifecycle-worker` | Same active check with exact 227,505-byte workload and a completed 4–55-second source-calibration interval first | Interactive iOS/iPadOS; no synthetic scene control |

Use the exact migrated build ID
`c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f`.
Source-checkout resource absence remains **blocked**, not compiler success.
Prepare reviewed compiler assets explicitly using the existing package workflow;
see [Workbench usage](workbench-consolidation.md). Choose any automatic scenario
with the same signed app, for example:

```sh
python3 -I -S -B Tools/Workbench/workbench.py run \
  --app .build/workbench-app/Build/Products/Release/FirmingoWorkbench.app \
  --team YOUR_TEAM_ID --output .build/workbench-deadline-1 \
  --scenario compiler.deadline \
  --build-id c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f
```

The CLI retains its 180-second owned-process bound. Lifecycle requests in this
launch-only mode are blocked before SDK work; no request can inject scene events.
Test Lab obtains aggregate SwiftUI app scenes rather than sheet/document dismissal.
On mobile, select the exact build, start the scenario, and follow its retained
Status events. Active cases expose **Start lifecycle interruption** only after
baseline/calibration; cancelling or dismissing a prompt never proves background.

The worker source is deterministically generated as test input and checked against
the original fixture hash `9a17105b5d17f732435ab81c6bf1083386e5cb5ae8b36569259bac8cf479ec3f`.
The sixteen-repetition deadline derivation must match
`bde5df426deb79fd8277abfd5b406cf1288b28b307646b62bc5ee1028cce26eb`.
Both preserve the existing recipes/assets and source caps. First compiling
notifications are synchronous bounded SDK observations, not CPU instruction traces.
A bounded one-shot signal admits the SDK busy/cancel check without polling past a
short source-compilation interval; observer tasks are joined on every exit.

Schema-one reports gain an optional `exercise` object. Older reports remain
readable. It retains up to forty completed-build observations, eight interrupted
request progress notifications, thirty-two actual scenes and 128 self-process
footprint samples, with explicit omitted-sample count. Reports and terminal
responses still have the 64 KiB cap. Unique known capsule bytes/receipts are
exported once; repeated calls retain individual receipt hashes. The CLI checks
known hashes, build order/count, callback order, typed outcomes, timeout interval,
settlement-before-fresh ordering, sample bounds and exit-code agreement.

Stress samples TASK_VM_INFO `phys_footprint` at requested 250 ms intervals and at
the final idle boundary. Scheduling can delay observations. The 120-second stress
observation limit and one-second idle sample are harness bounds, separate from
each unchanged SDK deadline. Samples exclude WebKit children and missed peaks;
these results cannot establish aggregate peak memory, leak freedom, memory
pressure recovery or survival of OS suspension/termination.

## Work log and validation

- Implemented shared app-owned scenarios, bounded evidence and probe/monitor cleanup.
- Added aggregate mobile scene forwarding, explicit post-calibration start, manual
  prerequisites, progress/outcome and sample presentation to the existing Test Lab.
- Added deterministic orchestration and independent CLI rejection tests to the
  existing validation entry point; retained legacy qualification checks.
- Sixteen final deterministic Workbench tests and eleven CLI fixtures pass. The
  full SDK entry point passed 166 SDK tests, eight ROM-host tests, the fifteen
  initial Workbench tests and retained legacy host/tool checks. Runtime-unavailable ordinary tests remain explicitly skipped.
- One development-signed sandboxed Workbench build 3 passes actual SDK busy and
  first-source cancellation followed by fresh compilation; the actual deadline
  settles after **60.633 seconds** from request admission with typed timedOut and
  one compiling notification, then a known fresh console build passes.
- The same executable passes twenty alternating exact builds in **21.617 seconds**
  overall, with 74 self-process footprint samples and zero omissions. Sampled
  self-process maximum is 240,426,032 bytes; post-build WASM linear memory is
  27,983,872 bytes for all twenty builds. These are distinct scoped observations.
- That same binary returns blocked (exit 3) for all three lifecycle scenarios
  through the launch-only CLI, before any catalogue/SDK work.
- Release app builds pass for macOS, iOS device target and Simulator.
  Strict development signature, YAML and shell syntax checks pass. Actionlint is
  unavailable and remote CI has not run.
- [Exact source/package/binary identities and terminal reports](workbench-compiler-scenarios-local.json)
  retain these results. Physical Workbench mobile lifecycle, minimum-OS,
  layout/accessibility, actual suspension/termination and pressure remain pending.
  The previously selected iPad was not reachable during this increment; no mobile
  app was installed and no board interaction occurred.

Final source review found and fixed an interactive admission error: a failed save
of the explicit manual Start must leave the attempt unarmed. Calibration is also
saved before exposing Start. A sixteenth focused regression test proves the failed
gate prevents a second SDK call; all focused tests and macOS/iOS rebuilds passed.
This follow-up affects only interactive lifecycle admission; automatic runtime
reports retain the exact preceding clean `5d9c151` source/binary identity. No
physical scene qualification is inferred from the synthetic regression test.

## Physical Workbench iPad qualification — in progress

The previously selected iPad is now available over paired Wi-Fi. The deployment
uses one Workbench app identity and reviewed prepared compiler package. Build 4
separates generic pending-call cancellation from the stricter calibrated first
source-compilation case: the generic attempt uses the same pinned long workload
to provide a practical manual interruption window, and records the actual SDK
phase. It does not require or claim a source-phase interruption. Workload
calibration and strict first-source assertions remain mandatory in the worker case.
The native callback timestamps now use a fixed monotonic origin.

`Tools/Workbench/check-mobile-report.py --help` validates only an explicitly
exported local report with an independently selected run UUID, actual launch PID,
scenario and app build number. It checks real scene sequence/interval, durable
manual admission, typed cancellation/settlement, workload/calibration where
required, fresh known capsules and SDK receipt bindings. It performs no device or
UI operation. Launch-only CLI continues to reject lifecycle passes. CoreDevice
may retrieve only Workbench's own selected run reports, matching the established
iOS qualification workflow; the controller never scans another app's data.

The corrected build 4 is now installed and launched on the selected physical
11-inch iPad Pro (3rd generation), iPadOS 27.0.1 (24A446), through paired
`localNetwork`. Its clean source is `78001f551bab3907b94020bd6ce4798e309152fa`.
[Deployment and physical qualification ledger](workbench-ipad-qualification.json)
keeps the prepared inventory, signed executable identity, independently launched
PID and actual reports as checks proceed. Seventeen Workbench tests, fourteen
CLI/report fixtures and the full SDK entry point pass. Development signing needs
`DEVELOPMENT_TEAM=WGR9T9JH4L` applied to the resource bundle as well as the app.
The user has been asked to run the idle scenario from Test Lab; no mobile lifecycle
pass is claimed yet.

The first physical Workbench idle check now passes independent validation in
PID 2085. Run `D2277232-1AA1-4153-86DD-9BE0F4A2A504` records actual aggregate
active/inactive/background/return events with a 6.113-second background-to-active
interval, the exact known baseline GPIO capsule and fresh console capsule in the
same process. Full report/receipts and validator result are in the iPad ledger.
Active-call and calibrated worker scenarios remain pending; no suspension claim
follows from the idle transition.

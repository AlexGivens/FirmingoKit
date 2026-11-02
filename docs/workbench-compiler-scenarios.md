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
| `host.lifecycle-active` | Baseline, explicit second Start action, inactivity during first observed source compilation, typed cancellation settlement, actual background/return, fresh artifact | Interactive iOS/iPadOS; a missed interval fails and needs a new explicit run |
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
- Signed real-runtime checks and final platform builds are in progress. Physical
  mobile lifecycle, minimum-OS/UI/accessibility and remote CI remain unqualified.

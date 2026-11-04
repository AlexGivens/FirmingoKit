# Workbench MCP adapter

The tools-only stdio server at `Tools/Workbench/mcp-server.py` wraps the existing
paired controller's local operator API. The shared Workbench app still owns all
scenario execution. Compiler/SDK/device responsibilities and mobile app identities
remain unchanged. The server uses Python's standard library; it starts no
controller, listener, Apple process, compiler, or device operation on launch.

## Connect a client

Start an explicitly selected controller and pair the installed Workbench app
using [the existing CLI workflow](workbench-paired-controller.md). Pairing remains
outside the MCP tool surface, so invitation credentials never enter MCP results.
The former qualification controller was stopped; its expired/revoked sessions
cannot be reused.

Create an optional evidence directory with mode 0700. Register the following
command/arguments in your MCP client's server settings, replacing all placeholder
paths with absolute paths. This is a client-neutral launch specification, not a
change to any user's Codex or Claude configuration:

```json
{
  "command": "/absolute/path/to/python3",
  "args": [
    "-I", "-S", "-B",
    "/absolute/path/to/FirmingoKit/Tools/Workbench/mcp-server.py",
    "--directory", "/absolute/path/to/controller-state",
    "--evidence-directory", "/absolute/path/to/private-evidence"
  ]
}
```

Both directories must already exist, belong to the operator and have no group or
other permissions. A symlink in place of either selected directory is rejected.
Omit `--evidence-directory` for inline-only results. The controller path is fixed
at startup; tool arguments cannot switch sockets, paths, app binaries or devices.
Do not run this stdio command in a terminal expecting a textual prompt: the MCP
client owns its standard input/output. `--help` is available for manual use.

The adapter supports the [2026-07-28 per-request metadata protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning)
and the [initialization handshake](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
for 2025-11-25, 2025-06-18, 2025-03-26 and 2024-11-05. It advertises only tools;
there are no resources, prompts, tasks, subscriptions, sampling or elicitation.
Modern discovery is `server/discover`; legacy clients initialize and notify
readiness. Protocol versions and client capabilities are checked before tools
are admitted. There is no HTTP/SSE MCP endpoint.

## Tools and run flow

| Tool | Behavior |
| --- | --- |
| `workbench_sessions` | List safe session, app-version, PID, instance and expiry metadata. Does not discover or select a device. |
| `workbench_submit` | Queue one existing `list`, `run`, `status`, `cancel`, `beginLifecycle` or `report` command. Requires caller-chosen session/command UUIDs; actions select exact run UUIDs. |
| `workbench_result` | Read that command's queued/delivered/completed/archived state. Validate any returned report and optionally save its bytes. Does not enqueue a command. |
| `workbench_revoke` | Explicitly revoke one pairing. The app cancels only controller-owned work on its next exchange. Does not terminate the app or controller. |

1. Read sessions and select the intended paired app explicitly. Submit a `list`
   action with a fresh `command_id`, then read its result to obtain the app's
   actual registry and SDK catalogue. No local duplicate registry is maintained.
2. Choose fresh command and run UUIDs **before** submitting a scenario. A `run`
   takes `run_id`, `scenario_id` and an exact `firmware_build_id` when required.
   Submission returns transport admission with `scenarioCompletion: not_observed`.
   It never claims a scenario pass.
3. Read `workbench_result` with that command ID to obtain the app's durable
   admission response. While the scenario executes, submit `status` commands with
   fresh command UUIDs and the same exact run UUID. Poll at a sensible interval
   (for example two seconds); the existing 256-command session limit still applies.
4. When the run is terminal, submit `report` with a fresh command ID and exact
   run UUID. Collect it using `workbench_result`, supplying the expected
   `scenario_id` and `firmware_build_id`. These expectations are checked against
   the actual report; they never change or re-execute the run.
5. For lifecycle cases, `beginLifecycle` explicitly starts a prepared attempt;
   real Home/return actions still happen on the device. For cancellation, submit
   `cancel` against the exact active run. Revoke the session when finished.

Example submission arguments, after choosing UUIDs and a compatible descriptor:

```json
{
  "session_id": "EXPLICIT_SESSION_UUID",
  "command_id": "FRESH_COMMAND_UUID",
  "action": "run",
  "run_id": "FRESH_RUN_UUID",
  "scenario_id": "compiler.smoke",
  "firmware_build_id": "EXACT_DESCRIPTOR_SHA256"
}
```

The placeholders are explanatory; runtime UUID and digest validation is strict.
Unknown fields, nested request overrides, arbitrary source/service URLs, shell,
file paths, scene injection and arbitrary reset/ROM commands reject before controller
access. Explicit fixed managed stage/one-shot commit now use schema three, with
separate authorizations and the existing deployment guards; see
[managed phases](workbench-managed-scenarios.md). [Selected device inspection and fixed binary console](workbench-device-scenarios.md)
now accept explicit device fields through request/report schema two. Console bytes
require a separately inspected boot and explicit fixed-probe selection. The app
remains the authority for scenario availability and prerequisites.

## Uncertainty, cancellation and evidence

Submission is one local broker call. Lost delivery/response never causes an
automatic resend. Recover with `workbench_result` using the **original command
ID**; do not create a second run because an MCP request timed out. Identical
command reuse retains the broker's deduplication, while changed reuse rejects.
An unknown or archived result is not successful execution.

MCP request IDs, controller command UUIDs and durable scenario run UUIDs are
different identities. [Stdio cancellation and EOF](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio)
stop MCP observation and suppress its reply. They do not silently cancel, replay
or revoke an already admitted app action. Use the explicit exact-run controller
controls to change that action. Four bounded workers keep cancellation/EOF
responsive during a local RPC; the existing RPC timeout remains fifteen seconds.
Incoming lines are bounded at 16 KiB, outgoing responses at 512 KiB. No JSON-RPC
batches are accepted. Oversized or unterminated frames close the adapter after an
error, preventing their remaining bytes from becoming a second request.

Reports pass through `paired.export_report` and the existing independent CLI
checker, including run/scenario/build selection, producer, timeline and capsule
byte checks. The current paired PID/instance/app version must also match. A
validated report retains its real `passed`, `failed`, `blocked`, `cancelled` or
`outcomeUnknown` state. Non-passes and controller/validation failures use
`isError: true`; transport success cannot upgrade them. Results contain both
structured data and a JSON text block as described by the [MCP tools contract](https://modelcontextprotocol.io/specification/2025-11-25/server/tools).

With evidence enabled, checked replies/reports/capsules are saved under
`EVIDENCE/SESSION_UUID/COMMAND_UUID/`, with file paths, byte counts and SHA-256s
returned to the client. Files are mode 0600 in owned 0700 directories. Repeated
queries verify identical existing files. Differing, unsafe or partially written
evidence rejects without overwriting it; preserve it for review and select a
fresh evidence root outside tool calls if necessary. These are RPC exports, not
byte-identical copies of original app journals. The tool is conservatively
annotated as potentially writing evidence, even for an otherwise read-only query.

## Reproduce validation

The normal SDK entry point runs nineteen MCP fixtures without sockets or devices:

```sh
python3 -I -S -B Tools/Workbench/test-mcp.py
node Tools/ManagedWASM/run-validation.mjs
```

They exercise the production broker in memory, both protocol families, closed
arguments, uncertain submission, explicit producer/report binding, non-pass
outcomes, conflict/symlink rejection, bounded concurrent calls, cancellation,
framing and real stdio subprocess startup/EOF. Archived reports are parser data;
replaying them does not constitute another compiler or hardware qualification.

An optional check uses pinned official clients over a real **local Unix socket**.
Its dependencies/lockfile are isolated from the server and normal SDK/CI checks:

```sh
mkdir .build/workbench-mcp-clients
cp Tools/Workbench/MCPClient/package*.json .build/workbench-mcp-clients/
npm --prefix .build/workbench-mcp-clients ci --ignore-scripts --no-audit --no-fund
node Tools/Workbench/check-mcp-interop.mjs \
  .build/workbench-mcp-clients .build/workbench-mcp-interop-new
```

Use a new, short output path suitable for a Unix socket. The runner requires
`@modelcontextprotocol/client` 2.4.0, `@modelcontextprotocol/sdk` 1.32.2 and the
reviewed lockfile. It loads archived bytes into the production broker, validates
both clients' tool/session/result/export behavior and stops its fixture. It
starts no TLS/mobile listener, Apple app, compiler or board. `results.json`
records scope, source/package-lock hashes and export hashes. Dependency upgrades
are explicit; the adapter itself needs neither client package.

## Work log — 2026-11-02

The thin adapter and offline/official-client checks are implemented. Product
Swift, app binaries, compiler assets and firmware contracts are unchanged. The
existing [paired physical qualification](workbench-paired-qualification.json)
remains underlying controller evidence; this increment does not claim a fresh
MCP-to-physical-device run or actual Codex/Claude host registration. No client
settings have been edited. Hardware scenario migration, client-host registration
and broader platform/UI qualification remain separately scoped work.

## Codex registration and physical iPhone — 2026-11-03

Codex is now registered with the `firmingo-workbench` stdio entry in the user's
configuration. A fresh native Codex host discovers all four tools. Codex's
[shared MCP configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)
supports the CLI registration form below, or an explicitly edited
`[mcp_servers.firmingo-workbench]` table in `config.toml`:

```sh
/path/to/current/codex mcp add firmingo-workbench -- \
  /path/to/python3 -I -S -B /absolute/checkout/Tools/Workbench/mcp-server.py \
  --directory /absolute/private/controller-state \
  --evidence-directory /absolute/private/evidence
/path/to/current/codex mcp get firmingo-workbench --json
```

On this machine, the working app-bundled CLI is `0.166.0-alpha.6`; the older
standalone `0.92.0` process was killed on launch. Registration was verified
against all original configuration values and text. This CLI build normalized an
unrelated `node_repl.args` field; the original configuration was restored around
the single new Workbench table. Future edits must preserve unrelated settings.
No invitation token is in the Codex entry.

The [fresh iPhone ledger](workbench-mcp-iphone.json) records native
`mcpServer/tool/call` requests through that registered server, pinned TLS and the
physical iPhone 15 Pro Max on iOS 27.0.1 (24A446). Build 9, PID 34038, passes
`compiler.smoke` and `compiler.diagnostics`: real SDK/WASM execution returns the
known GPIO/console capsules and recovers from a frontend diagnostic with a fresh
successful build. Native MCP responses and exact RPC exports are retained with
SHA-256s. The app's separate safe diagnostic confirms the later MCP revocation.
No manual app interaction was needed.

`Tools/Workbench/check-codex-device.py` makes this check repeatable with Python
3.11+ and an explicitly selected working Codex executable. It starts a short-lived
native app-server, uses an **ephemeral host context**, and sends no model turn.
It does not create a saved chat or bind a second writer to the active desktop
chat. Existing writer ownership was respected when probed. All scenario actions
and report collection use the native Codex MCP tool API, not an alternate client
or a direct broker call. Unrelated configured MCP servers are disabled only in
that test host's configuration overrides. Its native host and MCP child close
after collection.

After explicitly starting a controller and pairing the selected installed app:

```sh
python3 -I -S -B Tools/Workbench/check-codex-device.py \
  --codex /path/to/current/codex \
  --pairing .build/explicit-phone-pair/pairing.json \
  --build-id c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f \
  --output .build/codex-phone-check-new --revoke
```

The helper captures caller command/run IDs before submission, polls only saved
commands, and fails on uncertainty without replaying a run. Its compiler mode runs two fixed compiler cases. Explicit device mode runs
inspection and, when a fixed probe is selected, binary console through the same
engine. It has no arbitrary payload, upload, app deployment or pairing command.
It is an opt-in physical check, excluded from ordinary CI execution. Ordinary
CI revalidates the archived native envelopes and report hashes and parses the
helper's source without requiring a Codex installation or Python's `tomllib`.

The registered controller remains running for developer MCP access; the tested
iPhone pairing is revoked. The controller is not installed as an auto-starting
service. Future tests explicitly pair again. If it is stopped or its ignored
state directory is removed, start a new controller and update only the
Workbench registration's directory argument. The active desktop chat's tool
catalogue was not forcibly rebound; the persisted entry was loaded and tested
in a fresh native host. These results cover the two recorded compiler cases;
iPad MCP, broader MCP lifecycle/stress, hardware and minimum-OS claims remain
separate.


## Selected Nano through iPhone — 2026-11-04

[Device scenario guide](workbench-device-scenarios.md) documents the new closed
hardware selection. Adapter 0.2.0 carries explicit request/report schema two,
without changing compiler schema one. [Exact ledger](workbench-device-qualification.json)
retains build-10 native Codex admission/report envelopes, the actual SDK hello,
all 256 echo bytes and confirmed MCP revocation. Both compiler regressions also
pass on that same signed app/PID. No manual app test buttons, installation, reset
or firmware write were used. The user confirmed the prior recovered 0.1.0
application was unchanged; hello is not fresh image attestation.

The registered entry now selects the fresh r2 controller/evidence directories;
all unrelated settings were preserved. Work is paused at the user's request and
the owned controller is stopped. A future test needs a fresh controller certificate,
scoped registration-path update and new pairing; no service auto-start is installed.
The active desktop tool catalogue was not rebound. Eighteen socket-free fixtures
include the new versioned scope checks and original build-10 native corpus replay;
replaying those bytes is not another physical run. iPad/Pico, command-2 FMS2 mode,
upload/ROM recovery and broader hardware qualification remain separate work.


## iPad device follow-up — 2026-11-04

[The iPad ledger](workbench-device-ipad-qualification.json) now records fresh
native Codex MCP inspection and exact raw binary console through the identical
signed build 10 on iPad Pro (11-inch, 3rd generation)/iPadOS 27.0.1. The Nano
remained on its unchanged 0.1.0 application. The fresh inspected boot was required
before sending the one 256-byte probe; every reply byte matched, and console close,
disconnect and native MCP revocation passed. Original request/report envelopes
are retained and replayed as parser data in the same 18-test offline suite.
This adds no fresh compiler, upload/ROM, FMS2-probe mode, minimum-OS or Pico claim.

Registration now selects the r3 controller/evidence paths with unrelated Codex
settings preserved. The owned controller is stopped after qualification; a future
run requires explicit fresh controller startup and pairing. No automatic service
or active-desktop tool-catalogue rebinding was added. The shared configuration
procedure remains the [official OpenAI MCP configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).


## Managed phase extension — 2026-11-04

Adapter 0.3.0 adds the closed schema-three managed selection to the same four
tools. The [managed guide](workbench-managed-scenarios.md) specifies each field,
separate stage/commit authorization, saved record hash, restore/reconciliation,
no replay and pending-owner guards. Schema 1/2 authority is unchanged. Normal
fixtures and official-client checks do not execute a board workflow; fresh
physical managed qualification is tracked separately. No ROM writer, arbitrary
artifact/source or automatic recovery is added.

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
file paths, scene injection and device-writing commands reject before controller
access. The app remains the authority for scenario availability and prerequisites.

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

The normal SDK entry point runs fifteen MCP fixtures without sockets or devices:

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

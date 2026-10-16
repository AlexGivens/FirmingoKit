# Nano FMS2 interruption and recovery qualification

This explicitly selected experiment uses **NanoRecovery**,
`com.firmingokit.nanorecovery`, with its own container. It keeps the same FMS2
resident, compiler assets, catalogue and State A/B sources as
[the completed functional qualification](nano-fms2-qualification.md). Firmware's
versioned contract remains authoritative; no resident or public SDK API change
is required for this harness. The scoped iPad sequence now passes: baseline,
pre-commit connection close and USB power cycle, a real withheld commit reply,
actual app restart, query-only reconciliation and a fresh ordinary upload.
[The iPad evidence](nano-fms2-interruption-ipad.json) pins both runs and captures.
The identical signed app now passes the iPhone read-only baseline, pre-commit
connection close and USB power cycle in [its separate evidence](nano-fms2-interruption-iphone.json);
real commit-reply loss and restart recovery remain pending there.
Normal launch starts no device operation or proxy.
[Preparation evidence](nano-fms2-interruption-preparation.json) pins the signed
apps, exact generated sources, offline outputs and local check results.

The first iPad stage of B was verified in RAM and explicitly disconnected without
abort or commit. Fresh SDK reconciliation returned `aborted`, `disconnected`,
`slot_touched=false`. Two retained-A observations independently decode to seed 7,
zero startup BSS and advancing counters; the later observation continues from the
earlier one in the same boot. The user observed D13 off. Both actual capsules
match the fixed hashes and pass Firmware's production native validator. The
RAM-only checkpoint and immutable journal captures are pinned in the evidence;
this connection-close result remains separate from later recovery observations.

A second B stage was verified in RAM, then the operator unplugged USB, waited
five seconds and reconnected it. The operator reported that scene inactivity
closed the stage and removed its disconnect control. The durable checkpoint
still records RAM-only intent, and the journal contains no commit attempt.
A fresh SDK query correctly returned `unknown(bootChanged)`. State A replies
have a different boot identity, seed 7, zero startup BSS and advancing counters;
D13 was observed off. The original transaction stays unknown. The operator then
explicitly retired this RAM-only host context and started a new operation with
fresh inspection and reviewed association. Lost commit reply and process-restart
recovery are recorded separately below. This was power loss before any flash writer started.

The subsequent B upload used the explicit loopback proxy. The journal records
one host commit attempt and one observed complete commit frame. Independent
decoding of the captured real response confirms a correlated `committing`
response for the exact 548-byte B capsule, `error=none`, `slot_touched=false`.
The proxy withheld that reply, and the SDK reported `uncertainCommit` with the
matching record and underlying disconnect. The durable checkpoint contains
commit intent. D13 was observed on, which alone does not prove installation or
state correctness. CoreDevice then successfully sent SIGKILL to the verified
original app process and normally launched the same executable with a different
PID and no arguments. No Nano reset or commit replay was requested during this
process restart.

The new app run now recompiles the same exact capsules, restores the unchanged
commit-intent checkpoint linked to the original run and admits only status
queries. Its fresh SDK reconciliation returns `boot_confirmed`, `error=none`,
`slot_touched=true`. The actual B snapshots match the saved Nano boot, seed 23,
zero startup BSS and advancing counters; the exact 256-byte binary echo passes.
The operator observes D13 on. The new run contains no stage or commit attempt.
Both newly exported capsules also pass the independent production native
validator.

After explicit completion of recovered B, the operator starts a new operation,
inspects and records reviewed resident evidence, then stages A through the
ordinary SDK connection and commits it once. Fresh reconciliation reports
`boot_confirmed`, no error and a touched slot. A has seed 7, zero startup BSS,
advancing counters and an exact 256-byte echo; D13 is observed off. Its distinct
transaction shares the recovered B boot. The original pre-restart journal is
unchanged, and the recovery-only capture is an unchanged prefix of the final
21-event second-run journal. The operator confirms D2 removed afterward, with
REC disconnected. iPhone interruption checks remain pending; this result does
not qualify a flash-write power cut or rollback.

The iPhone 15 Pro Max/iOS 27.0 baseline produces the same two capsule hashes,
both independently accepted by the production native validator. The first
inspection succeeds in 1.483484375 seconds with one inactive-overlay event.
The operator reports a local-network prompt and quick approval; exact approval
timing is not independently measured. Retained A has seed 7, zero startup BSS
and advancing counters, with D13 observed off. This read-only result does not
close the broader authorization/cold-attachment gates. A later B RAM stage is
explicitly disconnected without abort or commit. Retained A counters continue
from the baseline in the same boot, and the subsequent fresh status query reports
`aborted`, `disconnected`, `slot_touched=false`. The RAM-only checkpoint and both
capture prefixes are preserved. No installation is attempted in this check.

The next iPhone B stage is RAM-verified before an operator USB unplug/five-second
wait/reconnect. The journal then records explicit connection close without
abort/commit, a fresh SDK `unknown(bootChanged)` result and retained A replies
from the new boot. The checkpoint remains RAM-only; A has seed 7, zero startup
BSS and advancing counters, with D13 observed off. No commit attempt is present.
The original transaction remains unknown, with host-context retirement and the
separate lost-reply/restart sequence still pending. This power cycle occurs
before any flash writer starts.

## Preparation and local checks

Generate from the existing independently anchored prepared SDK and FMS2 inputs:

```sh
python3 -I -S -B Tools/Hardware/make-nano-host.py \
  PREPARED_SDK PREPARED_MANIFEST_SHA256 FMS2_TEST_INPUTS TEST_PLAN_SHA256 NEW_HOST \
  --stateful-contract --recovery-check-bundle
python3 -I -S -B Tools/Hardware/run-nano-offline.py \
  SIGNED_MACOS_APP TEAM_ID NEW_HOST NEW_RESULTS \
  --stateful-contract --recovery-check-bundle
python3 -I -S -B Tools/Hardware/check-nano-proxy.py --loopback
```

The last command explicitly starts ephemeral local fake-peer/proxy sockets. Its
binary/fragmented/coalesced vectors and withheld reply validate relay I/O, not a
device or SDK recovery result. Ordinary SDK validation runs only `--compile-only`
for that helper, nine Nano tool fixtures and the pure admission/state/recovery
executables; it opens no listener. Both host variants receive warnings-as-errors
macOS checks and optimized iOS source compilation. Complete signed apps, actual
SDK compilation, local relay execution and physical operations stay separate.
The macOS offline runner retains its existing two sandbox entitlements; no
server capability is needed because offline execution never starts the proxy.
The reply-loss hardware path is initially qualified on physical Apple mobile
hosts. Sandboxed macOS relay listening remains outside this experiment.

## Expected checkpoints

Start from the previously installed State A with D2/REC disconnected. Compile
both fixed sources on the selected host, inspect the actual Nano identity and
check retained A through the binary snapshot protocol before staging State B.
Every later stage needs explicit fresh inspection and reviewed resident evidence.

| Operation | Expected observation | Recovery action |
| --- | --- | --- |
| Verified B stage, then explicit connection close before commit | Same boot, `aborted`, `disconnected`, `slot_touched=false`; retained A counters advance without reinitialization | New explicit operation after recorded aborted status |
| Verified B stage, immediate USB power cycle before commit | Changed boot; saved SDK transaction is `unknown(bootChanged)`; retained A starts with seed 7 / zero startup loop counter | Explicitly retire only the RAM-only host context; keep the device result unknown |
| Real B commit with one actual response withheld | One observed commit frame; validated real firmware `committing` response withheld; SDK throws `uncertainCommit` with the saved record | Terminate/relaunch this app, prepare offline, then explicitly reconcile on a fresh connection; never resend commit |
| Restored commit-intent checkpoint | Query-only gate; no restored session/proxy/commit capability | Matching boot-confirmed B result, then state/echo checks |
| Fresh ordinary A upload after recovered B | New explicit stage/one commit/startup, A state/echo | Remove D2 upload arm after completion |

The harness saves the SDK record plus originating app run and separate RAM-only/
commit-intent state. Commit intent is synchronized before calling the SDK.
Restoration never opens a connection or starts a proxy. A pre-commit checkpoint
can be retired after an observed boot change because this host admitted no
commit; this does **not** turn the SDK's unknown device outcome into an aborted
transaction. A restored commit intent cannot use that retirement path.

The reply-loss test uses one loopback client and one connection to the selected
numeric Nano endpoint. Public SDK connection/staging/commit APIs still run;
the SDK performs real hello/identity checks through the relay. Frames have bounded
16-byte headers / 4096-byte payloads, one outstanding read/write per direction
and backpressure. There is no reconnect or replay. After RAM verification, the
gate is armed with that exact record. It forwards one matching commit and
consumes one actual correlated queued-commit response, then closes both sockets
without delivering that response to the SDK. Raw withheld bytes are journaled;
an unrelated, malformed or synthetic response cannot pass this hardware check.

User actions are requested one checkpoint at a time. Staging has a 30-second
absolute lease: disconnect or power-cycle immediately at the RAM-verified
status, and commit immediately for the separately selected reply-loss case.
Keep D2 present through any intended installation and REC disconnected throughout
normal network checks. A failure stops the affected workflow; uncertain commit
is queried without retry. Raw device/boot identities remain in ignored local
evidence; app journals and per-transaction/checkpoint files are retrieved only
from this app's own container over paired Wi-Fi.

## Scope remaining after these checks

Pre-commit power loss leaves the flash writer unstarted. Withholding a response
is an intentional application-level network fault after firmware accepted the
real commit. Neither case proves interruption during erase/program, arbitrary
packet-loss behavior, rollback, complete SDK ROM installation/recovery, cold
attachment, minimum OS or general Arduino support. Flash-corruption/power-cut
qualification needs its own selected recoverable-board procedure and concrete
recovery image. The existing known ROM composite remains available independently.

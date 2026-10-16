# Nano FMS2 interruption and recovery qualification

This explicitly selected experiment uses **NanoRecovery**,
`com.firmingokit.nanorecovery`, with its own container. It keeps the same FMS2
resident, compiler assets, catalogue and State A/B sources as
[the completed functional qualification](nano-fms2-qualification.md). Firmware's
versioned contract remains authoritative; no resident or public SDK API change
is required for this harness. The iPad baseline, pre-commit connection-close
and pre-commit USB power-cycle checks now pass; the remaining physical checks are pending in
[the incremental iPad evidence](nano-fms2-interruption-ipad.json).
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
D13 was observed off. The original transaction stays unknown. Retirement of
this RAM-only host context, lost commit reply and process-restart recovery are
separate subsequent checks. This was power loss before any flash writer started.

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

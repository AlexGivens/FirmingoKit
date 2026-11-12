# Next Nano USB and routing checks

Use these separately selected manual checks after the scoped two-sketch results.
They do not authorize flashing or destructive interruption. Keep D2 and REC
disconnected. Select the same physical Nano by its recorded identity and exact
resident evidence; an address or generic RP2040 bootloader name is insufficient.
Keep development deployment/report collection over the already paired network.

Use the separately identified NanoPermission host for first-app-access and denial
checks. Follow [connection readiness](connection-readiness.md) to prepare it offline,
select the numeric endpoint and device ID, and inspect explicitly. Record actual
user actions, displayed result, own-run journal, app/SDK/resident identities, host
model and OS, and cable or hub details. Record prompt approval and hello separately.

## Cold attachment with Workbench

The previously authorized iPhone can use the installed Workbench app for an
attachment baseline on the pinned FMS2 resident. Pair over Wi-Fi before the
physical trial. Use the same cable, direct connection, and unlocked host for each
trial in a series. Note the OS build and any change from the incident under review.

1. Disconnect USB power for five seconds with D2 and REC disconnected. Attach
   once and observe Ethernet in Settings for about 15 seconds. Record the address
   if visible, any prompt and approval, and approximate time to visible Ethernet.
   Collect subnet, router, DNS and assignment mode when those fields are available.
2. Return Workbench to the foreground with the Nano still connected. Submit one
   `device.inspect` run for the selected endpoint, board and device ID. Archive
   the terminal report, including a timeout or other failure. A failed inspection
   ends that trial. A later reconnect gets a new trial and run ID.
3. After successful inspection, run `device.console-binary` once using that boot
   ID and `fms2-command-2-v1` on the known compatible sketch. Save the exact report
   and check that the boot differs from the prior trial's boot when both were
   observed. Record any RESET, replug or address edit as part of the outcome.

The Settings window measures operator-observed readiness. Report event times
measure the SDK operations after Workbench returns to the foreground. Exact USB
configuration and lease timing require instrumentation at those layers.

The 2026-11-11 iOS 27.2 baseline passed three attachments on three distinct
boots. The first two used Settings before inspection. The third left Workbench
in the foreground during the reconnect, as in the earlier incident. The second
trial showed `192.168.77.16/24`, an empty Router field, and Automatic DNS
configuration. DNS server values were unreported. The earlier iOS 27.0.1
timeouts remain unresolved. See the [attachment ledger](workbench-iphone-attachment-qualification.json).

| Check | Procedure and required observation |
| --- | --- |
| Fresh app access prompt | On its first explicit inspection, record the exact prompt and choice, and whether hello completes on that attempt within the original deadline. A timeout and successful second explicit attempt are two separate outcomes |
| Denied app permission | Deny only this test app's prompt when separately selected; verify bounded failure and no successful hello. After explicitly allowing this app in Settings, use a new explicit inspection; never infer denial from a generic network error alone |
| Previously approved reconnect | Physically reattach, allow automatic addressing, then inspect. Record elapsed time, result and whether any reset/manual address change was needed; do not hide a failure with reset/retry |
| Locked attachment | When separately selected, attach while locked, unlock normally and record actual authorization/network behavior; do not reset privacy settings |
| Cold connections | For each selected host, aim for 20 separately counted cold connections. Retain actual pass/fail counts and first-attempt failures; a retry is not a cold-cycle pass |
| Internet coexistence | While Nano is connected, manually load a fresh uncached Internet resource and record the URL/test nonce and observed result. A Wi-Fi icon or successful development tunnel alone is insufficient; record whether the Internet interface was actually identified |
| DHCP fields | Read the board-interface address/subnet/router/DNS fields without editing them. Firmware's local-only DHCP omits router/DNS options; user-visible fields and real Internet behavior need their own observations |

Do not automatically change network settings, disconnect USB, reset the board,
repeat inspection or continue into staging. Keep denial, locked attachment and
cellular-specific checks opt-in. A desktop packet capture is not an iPhone USB
trace. Exclude power cuts during flash, corruption and rollback claims from
this read-only sequence. The original board-free tests and initial Nano results
remain separate evidence; this procedure supplies no new hardware pass by itself.

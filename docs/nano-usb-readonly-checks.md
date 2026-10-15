# Next Nano USB and routing checks

Use these separately selected manual checks after the scoped two-sketch results.
They do not authorize flashing or destructive interruption. Keep D2 and REC
disconnected. Select the same physical Nano by its recorded identity and exact
resident evidence; an address or generic RP2040 bootloader name is insufficient.
Keep development deployment/report collection over the already paired network.

For connection-only checks, use the separately identified NanoPermission host
from [connection readiness](connection-readiness.md). Prepare once offline, select
the real numeric endpoint/device ID, then inspect explicitly. Record actual user
actions, displayed result, own-run journal, app/SDK/resident identities, host model/
OS and cable/hub details. A prompt approval is separate from successful hello.

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

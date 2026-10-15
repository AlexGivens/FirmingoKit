# Initial TCP readiness and local-network permission

The original Nano checks recorded a Network-is-down failure on the first
inspection of each Apple device, followed by a successful explicit retry. The
iPhone user also reported an access prompt during that first attempt. Those
records remain unchanged in `nano-hardware-ipad.json` and
`nano-hardware-iphone.json`; they do not establish the exact platform-state cause.

Source review found that `TCPInspectionTransport` treated every Network.framework
`waiting` event as terminal, including before the first `ready`. Apple documents
that [initial connections can wait for local-network permission](https://developer.apple.com/videos/play/wwdc2020/10110/)
and describes [the privacy/path behavior](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
The transport now distinguishes initial readiness from an established session:

| Event | SDK behavior |
| --- | --- |
| Waiting before initial ready | Keep the same connection pending; send no hello yet |
| Ready before the absolute deadline | Continue the original one-shot hello |
| Waiting after ready | Terminate and report the platform error; no reconnect/replay |
| Failed/cancelled, SDK deadline or caller cancellation | Close and resolve pending work; late callbacks cannot restart it |

The public five-second deadline still includes initial waiting, TCP establishment
and hello. No timer is extended, `restart` called, new connection created, command
resent, discovery added or permission inferred from an error number. A person who
takes longer to approve permission must explicitly inspect again after timeout.
An existing upload commit is never replayed.

The Nano host also previously cancelled all work on scene inactivity. It now
permits only pending **read-only inspection** to continue under an inactive
overlay within that original deadline. Actual background and the Cancel button
still cancel it. Other work and staged-session inactivity retain their previous
policy. Inspection shows the deadline/prompt guidance and a useful timeout action,
and journals start, inactive overlay, duration and successful hello separately.

`--nano-permission-check` is an explicit qualification mode: association, staging
and installation are hidden and guarded. It still requires manual offline
preparation, actual selected device identity and the Inspect action. Normal launch
does nothing. A separately signed bundle identifier can exercise a fresh prompt
without resetting privacy settings or changing the existing Nano test app.

Generate that namespace with `make-nano-host.py --permission-check-bundle` and
the same explicit SDK/test-plan arguments. This changes only app bundle identity
and display name; its identity also enforces read-only mode when opened manually.
Keep the target's normal product name and SwiftPM resource naming. A global
`PRODUCT_NAME` override also renames SDK products and breaks resource lookup.

Five deterministic Swift Testing cases inject finite platform callbacks into the
**production TCP actor and hello exchange**: initial waiting-to-ready with one
hello, deadline during waiting with no hello, cancellation with no hello, terminal
failure, and established path loss without reconnect. No sockets or OS permission
changes are involved. They are included in the ordinary SDK entry point and CI;
the suite has a one-minute failure bound. Source tests and builds do not establish
physical first-prompt recovery; signed-device results are recorded separately below.

## Physical results on 2026-10-15

The separately identified, development-signed NanoPermission build 4 uses SDK/host
`14f7e0c…` and the unchanged experimental compiler/resident inputs. Both devices
compile the known 316/392-byte capsules offline, then perform only explicit
read-only inspection with D2 and REC disconnected. Installation and own-run
retrieval use the paired network while the Nano occupies the Apple device's USB
port. [The evidence record](connection-readiness-qualification.json) pins the exact
package, generated host, signature, launches, reports and capsule bytes.

| Host | Observed result |
| --- | --- |
| iPhone 15 Pro Max, iOS 27.0 (24A437) | User approved the fresh local-network prompt; the first inspection completed in 2.580 seconds. The journal records an inactive overlay and one successful hello |
| 11-inch iPad Pro (3rd generation), iPadOS 27.0.1 (24A446) | First inspection reported the original five-second timeout during prompt handling. Its journal was saved before requesting a retry. With permission already approved, a separately requested second inspection succeeded in 15.4 ms |

The iPad's exact approval time relative to timeout was not measured. Its first
attempt remains a timeout, not a successful first-prompt qualification. Neither
journal exposes private Network.framework path states or establishes the exact
cause of the older Network-is-down failures. Earlier build-3 upload evidence
retains its own SDK/app provenance; this updated app exercises only inspection.

The first complete app-build attempt failed because of a global product-name
override. It was not deployed. The corrected generator changes only app identity
and display name; the complete signed build and its normal SDK resource bundle
were checked before either physical run.

Broader permission denial, locked attachment, repeated cold connections and
Internet coexistence remain open. [The read-only follow-up procedure](nano-usb-readonly-checks.md)
keeps their actual counts and observations separate from these scoped results.

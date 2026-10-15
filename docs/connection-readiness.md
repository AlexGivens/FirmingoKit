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

Five deterministic Swift Testing cases inject finite platform callbacks into the
**production TCP actor and hello exchange**: initial waiting-to-ready with one
hello, deadline during waiting with no hello, cancellation with no hello, terminal
failure, and established path loss without reconnect. No sockets or OS permission
changes are involved. They are included in the ordinary SDK entry point and CI;
the suite has a one-minute failure bound. Source tests and builds do not establish
physical first-prompt recovery; that requires separate signed-device evidence.

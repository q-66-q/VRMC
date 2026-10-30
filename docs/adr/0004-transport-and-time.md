# ADR-0004 — Separate control and media transport, with clock sync, prediction, and late latching

- **Status:** Accepted
- **Date:** 2026-10-29
- **Related:** ADR-0001, `protocol/PROTOCOL.md`, `docs/architecture/STREAMING.md`
- **Verification:** AT-TIME-*, AT-NET-*, AT-TRANSPORT-* (NOT IMPLEMENTED)

## Context

The session carries two very different traffic classes:

- **Control:** pairing, authentication, stream configuration, state transitions, keyframe
  requests, telemetry. Must be reliable and ordered; occasional latency is acceptable.
- **Media and input:** video fragments and hand/head samples. Must be low-latency;
  retransmitting an old frame is usually worse than dropping it. Some loss is acceptable if
  recovery is fast.

Running both over TCP would create head-of-line blocking and latency spikes. Running
everything over UDP without reliability would lose control state. Clocks on the headset and PC
are independent; hand poses and video frames must be compared on a common timeline for
prediction and latency accounting.

## Decision

Use two transports:

1. **Control channel:** TCP with TLS 1.3 (Network.framework on visionOS; Schannel/OpenSSL on
   Windows) or an equivalent authenticated, encrypted stream. Length-prefixed VRMC control
   messages. Used for pairing, session config, input-channel keying, IDR requests, state, and
   low-rate telemetry.
2. **Media/input:** UDP datagrams encrypted with ChaCha20-Poly1305 using keys derived during
   session setup. Sequence numbers, replay windows, MTU-safe fragmentation, NACKs for missing
   video fragments, and IDR requests. Input is unreliable but duplicated for the newest state
   (last-value wins) so a lost sample does not stall control.

**Clock sync:** four-timestamp exchanges over the control channel (client t0, host t1/t2,
client t3), robust median filtering and drift estimation, refreshed at least every second and
after any reconnect. Report offset, RTT, and uncertainty; reject samples with excessive
asymmetry. All pose/frame messages carry the sender's monotonic timestamp; the receiver maps
to its own clock and records the raw values for audit.

**Prediction:** hand/head samples are filtered (one-euro) and extrapolated with bounded
constant-velocity/angular-velocity models to the estimated driver/render presentation time.
Prediction horizon is clamped (≤50 ms default) and confidence-weighted; on loss, prediction
decays to zero instead of running away.

**Late latching:** the client renders the newest decoded frame with the head pose captured at
frame capture time, then applies a rotation-only reprojection to the predicted present pose.
Gesture intent is timestamped at the sensor sample and mapped on the client; button edges are
latched for at least one host frame and released deterministically. The driver extrapolates
the latest snapshot by at most 30 ms.

**Jitter buffer:** target one frame, maximum three; drop oldest video frames under pressure;
never block the decode thread; request IDR after unrecoverable loss. Media packets older than
the current playout window are discarded.

## Consequences

### Positive

- Control state is reliable without head-of-line blocking media.
- Media latency is bounded; loss recovery is explicit.
- Clock sync makes latency measurable and prediction defensible.
- Input state survives short loss via last-value redundancy and local latching.
- Security is uniform: both channels are authenticated/encrypted.

### Negative

- More implementation complexity: two sockets, two state machines, key management.
- NAT/firewall must allow both TCP and UDP; documented.
- Clock sync can be biased by asymmetric Wi‑Fi delay; we report uncertainty and clamp
  prediction.
- Encryption adds CPU overhead and nonce-management risk; must be tested.
- TLS on control plus custom AEAD on media means two crypto stacks; keep them small and
  audited.

### Neutral

- TCP control is not used for video; congestion control on media is sender-side ABR, not TCP.
- A future QUIC transport could unify both channels, but Network.framework/Windows support
  and maturity are not assumed for v1.
- Audio (v1.1) will use the media channel with its own stream ID and jitter buffer.

## Protocol requirements

- Magic `VRMC`, version major/minor, message type, flags, payload length, sequence/session ID.
- Max control message 1 MiB; max media datagram 1200 bytes including AEAD tag.
- Never trust lengths; validate before allocation; reject unknown critical flags.
- Nonce uniqueness per key/direction; key rotation on reconnect; replay window ≥1024 packets.
- Pairing code rate-limited (5 attempts/minute, lockout), never logged.
- Telemetry may report timestamps and sizes, never raw hand joints or frame pixels.

## Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| All TCP | Head-of-line blocking causes latency spikes and stale frames; unacceptable for VR. |
| All UDP with application reliability | Reimplementing reliable control is more complex and error-prone than TCP. |
| WebRTC | Large dependency, congestion-control/ABR complexity, visionOS integration uncertain, harder to audit. |
| QUIC | Attractive long-term, but custom AEAD over UDP is smaller and testable now; revisit when platform APIs mature. |
| Unencrypted LAN | Fails privacy/security and App Review expectations; hand and video data are sensitive. |
| No clock sync, use local "now" | Makes prediction and latency measurements meaningless; jitter causes pose/frame mismatch. |

## Verification

- Clock sync soak under N1/N2/N4 (S-11), offset/uncertainty recorded.
- Packet loss/reorder/duplicate/replay tests (AT-NET-02/03, NF-02..05).
- Prediction replay against recorded poses (AT-HAND-03).
- Latency telemetry cross-checked by camera (MT-09).

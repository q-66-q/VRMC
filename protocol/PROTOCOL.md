# VRMC Wire Protocol v1.0

**Status:** Draft for implementation (M0/M1). Wire format is frozen only after conformance
vectors and both codecs pass.
**Transport:** TCP control channel; UDP media/input channel. Both are little-endian.
**Authority:** this document; changes require a protocol major/minor decision and new vectors.

---

## 1. Design rules

- Integers are little-endian unless stated. `u8/u16/u32/u64` are unsigned; `f32` is IEEE-754
  binary32 little-endian.
- Strings are `u16` byte length followed by UTF-8 bytes. Maximum 255 bytes in control
  messages, 64 bytes in discovery.
- Vectors are fixed-size; counts are validated before reading. No implicit padding.
- Control messages are reliable and ordered. Media/input datagrams are unreliable and may be
  reordered, duplicated, or lost.
- Unknown **critical** flags/types must be rejected. Unknown non-critical fields may be skipped
  only if the message has an explicit length and the spec says so.
- Timestamps are `u64` nanoseconds from a monotonic clock (`CLOCK_MONOTONIC_RAW` /
  `mach_continuous_time` / `QueryPerformanceCounter` converted to ns). Wall clock is never
  used on the wire except in diagnostic text.
- Positions are metres; quaternions are `(x,y,z,w)`, right-handed, normalised. A zero/invalid
  quaternion is a protocol error.
- All encrypted messages have an AEAD tag. Never log keys, pairing codes, or raw skeletons.

---

## 2. Ports and discovery

| Purpose | Default | Notes |
| --- | --- | --- |
| TCP control | 48625 | Pairing, auth, config, state, clock sync, telemetry |
| UDP media | 48626 | Video/meta/NACK/IDR (host → client; NACK client → host) |
| UDP input | 48627 | Head/hand/intent + keepalive (client → host) |
| Bonjour | `_vrmc._tcp` | Optional discovery; TXT: `v=1`, `name`, `proto=1`, `pairing=0/1` |

The host binds to a selected interface in release mode. The client connects by discovered
service or manual host/IP. Ports are configurable; the values above are defaults.

---

## 3. Control channel

### 3.1 Frame

```
offset size field
0      4    magic = "VRMC" (0x56 0x52 0x4D 0x43)
4      1    versionMajor = 1
5      1    versionMinor = 0
6      1    type
7      1    flags        bit0 = plaintext, bit1 = auth-required, others reserved
8      4    sessionId    (0 before WELCOME)
12     4    sequence     per direction; 0 for handshake
16     4    payloadLength (ciphertext length including AEAD tag, or plaintext length)
20     4    reserved = 0
24     ...  payload
```

Total header = 24 bytes. Maximum payload = 1,048,576 bytes. The connection is closed on a
malformed/oversized frame.

**Encryption:** after `AUTH_OK` (secure mode), every control message is AEAD-sealed:

- `aad` = the 24-byte header (with `payloadLength` set to ciphertext length).
- `nonce` = `direction u32 || sequence u64` (12 bytes), where direction is 3 for
  client→host and 4 for host→client; sequence is the header sequence. Keys are separate per
  direction.
- `ciphertext` = ChaCha20-Poly1305(key, nonce, plaintext, aad); tag appended (16 bytes).
- Sequence starts at 1 after the handshake, increments by 1, and is checked with a replay
  window. Handshake frames use sequence 0 and `flags.plaintext=1`.
- In insecure development mode, `flags.plaintext=1` for all control frames and payloads are
  not encrypted. This mode is refused unless both sides explicitly enable it.

### 3.2 Message types

| Value | Name | Direction | Purpose |
| --- | --- | --- | --- |
| 0x01 | HELLO | C→H | Version, nonces, auth request, capabilities |
| 0x02 | WELCOME | H→C | Version, session ID, auth mode, salt, host info |
| 0x03 | AUTH_CHALLENGE | H→C | Server proof over transcript |
| 0x04 | AUTH_RESPONSE | C→H | Client proof |
| 0x05 | AUTH_OK | H→C | Auth success/failure; first encrypted message in secure mode |
| 0x06 | STREAM_CONFIG | H→C | Video geometry, projections, codec, mapping profile |
| 0x07 | START_STREAM | H→C | Stream start time and initial frame |
| 0x08 | STOP_STREAM | both | Stop reason |
| 0x09 | KEYFRAME_REQUEST | C→H | Request IDR |
| 0x0A | SESSION_STATE | both | State transition/diagnostic |
| 0x0B | CLOCK_PING | C→H | t0, ping ID |
| 0x0C | CLOCK_PONG | H→C | t0,t1,t2, ping ID |
| 0x0D | TELEMETRY_CLIENT | C→H | Client counters/latency |
| 0x0E | TELEMETRY_HOST | H→C | Host counters/latency |
| 0x0F | SET_QUALITY | C→H | Request bitrate/fps/scale |
| 0x10 | INPUT_CONFIG | H→C | Mapping profile, prediction horizon |
| 0x11 | HAPTIC | H→C | Visual/audio haptic cue (future hardware) |
| 0x12 | HEARTBEAT | both | Liveness/state |
| 0x13 | DISCONNECT | both | Graceful close |
| 0x14 | ERROR | both | Typed error |
| 0x15 | AUDIO_CONFIG | H→C | Reserved for v1.1 (must be rejected by v1 client if critical flag set) |

Unknown types are rejected with `ERROR` code 1 (unsupported) and the session is closed.

### 3.3 Payloads

#### HELLO (0x01, plaintext)

| Field | Type | Notes |
| --- | --- | --- |
| minMajor, maxMajor | u16,u16 | protocol range |
| minMinor, maxMinor | u16,u16 | minor range |
| clientNonce | 16 bytes | random |
| clientVersion | string | e.g. `0.1.0` |
| clientPlatform | string | e.g. `visionOS 27.0` |
| requestedAuthMode | u8 | 1=pairing code, 2=token (reserved), 3=insecure dev |
| capabilities | u32 | bit0 hand skeleton, bit1 head pose, bit2 reprojection, bit3 audio, bit4 haptics, bit5 telemetry |

#### WELCOME (0x02, plaintext)

| Field | Type | Notes |
| --- | --- | --- |
| major, minor | u16,u16 | selected protocol |
| sessionId | u32 | also in frame header |
| serverNonce | 16 bytes | random |
| authMode | u8 | selected |
| serverVersion | string | |
| hostName | string | user-visible, may be PC name |
| salt | 16 bytes | pairing KDF salt; zero in insecure |
| capabilities | u32 | intersection semantics |

#### AUTH_CHALLENGE (0x03, plaintext)

| Field | Type | Notes |
| --- | --- | --- |
| transcriptHash | 32 bytes | SHA-256 of concatenated HELLO and WELCOME **payloads** |
| serverProof | 32 bytes | HMAC-SHA256(pairKey, "VRMC-SERVER" || transcriptHash) |

The client verifies the proof before sending its own. A failure closes the session and
increments the host rate limiter.

#### AUTH_RESPONSE (0x04, plaintext)

| Field | Type | Notes |
| --- | --- | --- |
| clientProof | 32 bytes | HMAC-SHA256(pairKey, "VRMC-CLIENT" || transcriptHash) |

#### AUTH_OK (0x05, encrypted in secure mode)

| Field | Type | Notes |
| --- | --- | --- |
| status | u8 | 0=ok, 1=bad proof, 2=unsupported auth, 3=rate-limited |
| detail | string | user-safe; empty on success |

#### Pairing / session keys (secure mode)

- `pairKey = PBKDF2-HMAC-SHA256(normalize(code), salt, 120000, 32)`. The code is 12 Crockford
  base32 characters (60 bits), grouped `XXXX-XXXX-XXXX`, case-insensitive; ambiguous
  characters are normalised.
- `transcriptHash = SHA-256(HELLO payload || WELCOME payload)`.
- `sessionKeys = HKDF-SHA256(ikm=pairKey, salt=clientNonce||serverNonce,
  info="VRMC-SESSION"||transcriptHash, L=64)` → c2s (32), s2c (32).
- Reconnect uses a new nonce pair and new session keys. Codes are single-use per session and
  host-rate-limited (5 failures/min, exponential lockout). A future token mode reuses a
  high-entropy secret stored in Keychain; it must not weaken the code path.
- Insecure dev mode skips AUTH_CHALLENGE/RESPONSE; AUTH_OK is plaintext; keys are zero and
  never used. The UI must show a red warning.

#### STREAM_CONFIG (0x06, encrypted)

| Field | Type | Notes |
| --- | --- | --- |
| configVersion | u16 | 1 |
| videoWidth, videoHeight | u16,u16 | full SBS frame |
| eyeWidth, eyeHeight | u16,u16 | per-eye dimensions |
| eyeOrder | u8 | 0=left,right; 1=right,left |
| colorSpace | u8 | 0=sRGB, 1=linear |
| codec | u8 | 1=H.264 Annex-B, 2=HEVC Annex-B |
| reserved | u8 | 0 |
| fps | u16 | target capture/display rate |
| displayHz | u16 | virtual HMD display frequency |
| bitrateKbps | u32 | initial target |
| keyframeIntervalMs | u16 | |
| maxPacketBytes | u16 | ≤ 1200 |
| ipdMeters | f32 | nominal |
| leftProjection | 4×f32 | left, right, top, bottom tangents |
| rightProjection | 4×f32 | same |
| leftEyeOffset | 3×f32 | metres, head space |
| rightEyeOffset | 3×f32 | metres, head space |
| flags | u32 | bit0 = reprojection enabled, bit1 = DUAL mirror verified, bit2 = audio enabled (v1.1), bit3 = vertical flip on sampling |
| source | string | e.g. `Vivecraft DUAL 3840x1080` |
| mappingProfile | string | e.g. `handmap-v1` |

The client rejects unsupported codec/eye order/geometry and requests a new config. The host
must not start media until the client sends `SESSION_STATE(state=ready)`.

#### START_STREAM (0x07)

`startHostTimeNs u64`, `firstFrameId u32`, `flags u32`. Sent after config is accepted.

#### STOP_STREAM (0x08)

`reason u8`, `detail string`.

#### KEYFRAME_REQUEST (0x09)

`lastFrameId u32`, `reason u8`, `reserved u8[3]`, `clientTimeNs u64`.

#### SESSION_STATE (0x0A)

`state u8`, `reason u16`, `flags u32` (session degradation flags), `detail string`. States:
0=idle, 1=connecting, 2=auth, 3=ready, 4=streaming, 5=degraded, 6=reconnecting, 7=stopping,
8=error. Reason codes are implementation-defined but stable for telemetry (see
`docs/diagnostics`). Session flags: bit0 capture degraded, bit1 encoder degraded, bit2 network
degraded, bit3 tracking degraded.

#### CLOCK_PING/PONG (0x0B/0x0C)

- PING: `t0 u64` (client send), `pingId u32`.
- PONG: `t0 u64`, `t1 u64` (host receive), `t2 u64` (host send), `pingId u32`.
- Client computes `offset = ((t1-t0)+(t2-t3))/2`, `rtt = (t3-t0)-(t2-t1)`; host offset is
  `-offset`. Samples are median-filtered; drift is estimated over ≥8 samples. Uncertainty is
  reported in telemetry. Pings every 1 s (or 250 ms during recovery).

#### TELEMETRY_CLIENT (0x0D)

`framesReceived u32, framesDecoded u32, framesPresented u32, framesDropped u32,
decodeAvgUs u32, decodeP95Us u32, renderAvgUs u32, renderP95Us u32, inputSent u32,
inputLost u32, lastFrameId u32, latencyP50Us u32, latencyP95Us u32, queueDepth u16,
flags u16` (44 bytes).

#### TELEMETRY_HOST (0x0E)

`captured u32, encoded u32, packetsSent u64, packetsLost u32, nacks u32, idrRequests u32,
captureAvgUs u32, encodeAvgUs u32, encodeP95Us u32, queueDepth u16, reserved u16,
bitrateKbps u32, fpsX100 u32` (48 bytes).

#### SET_QUALITY (0x0F)

`maxBitrateKbps u32, targetFps u16, scalePercent u16, flags u32`.

#### INPUT_CONFIG (0x10)

`mappingProfile string, predictionMs u16, flags u32`.

#### HAPTIC (0x11)

`hand u8 (0=left,1=right,2=both), amplitude f32, durationMs u16, frequencyHz u16`. Vision Pro
has no haptic actuator; the client renders a visual pulse and may play a sound.

#### HEARTBEAT (0x12)

`hostTimeNs u64, state u8, reserved u8[3]`. Sent every 500 ms on the control channel; missing
3 in a row (1.5 s) triggers the degraded state.

#### DISCONNECT (0x13)

`reason u8`, `detail string`.

#### ERROR (0x14)

`code u16`, `detail string`. Codes: 1 unsupported, 2 bad version, 3 bad packet, 4 auth,
5 rate-limited, 6 busy, 7 internal, 8 capture unavailable, 9 encoder unavailable, 10 timeout.

---

## 4. Media datagrams (UDP 48626)

### 4.1 Header (40 bytes)

```
offset size field
0      2    magic = bytes 0x56 0x4D ("VM")
2      1    version = 1
3      1    type
4      1    flags
5      1    reserved = 0
6      2    fragmentIndex
8      2    fragmentCount
10     2    payloadLength (ciphertext length including tag, or plaintext length)
12     4    sessionId
16     4    frameId
20     4    reserved2 = 0
24     8    packetSequence (monotonic per session; nonce component)
32     8    timestampNs (host monotonic capture time)
40     ...  payload
```

Types: 1=VIDEO, 2=INPUT, 3=AUDIO (v1.1), 4=FRAME_META, 5=NACK, 6=IDR_REQUEST,
7=KEEPALIVE.

Flags: bit0=keyframe, bit1=config, bit2=retransmit, bit3=meta-duplicate, bit4=plaintext,
others reserved.

Encryption: same AEAD/key schedule as control, with direction 1 (client→host) or 2
(host→client); nonce = direction u32 || packetSequence u64; AAD = the 40-byte header.
`payloadLength` is ciphertext length including the 16-byte tag. Max datagram = 1200 bytes
(IPv6-safe), so max payload = 1200 − 40 − 16 = 1144 bytes in secure mode; plaintext dev mode
also uses 1144 to keep fragmentation identical.

### 4.2 VIDEO (type 1)

Payload is a fragment of one encoded access unit (Annex-B byte stream). The first fragment of
a frame SHOULD contain the access-unit delimiter/parameter sets; the host may repeat
parameter sets on keyframes. `fragmentCount` is 1..1024; `fragmentIndex` is 0-based.
`frameId` is monotonic, starts at `START_STREAM.firstFrameId`, and identifies the access unit.
`timestampNs` is the capture time of the frame. The host sends `FRAME_META` before the first
fragment (twice, with meta-duplicate flag). If metadata is lost, the client uses the last
known capture head pose and flags the frame as `meta-missing` (reprojection degrades but
display continues).

Reassembly:

- Buffer per frame up to 1024 fragments / 8 MiB; reject larger.
- A frame is complete when all fragments arrive. Deliver once, in order.
- If incomplete after 50 ms, send one NACK listing missing fragments; if still incomplete
  after 150 ms, drop and request IDR. Never stall the decoder indefinitely.
- On a discontinuity (frameId gap > 2 or keyframe), reset the frame buffer and request IDR.
- Duplicate fragments are ignored. Retransmitted fragments have bit2 set.

### 4.3 FRAME_META (type 4)

| Field | Type | Notes |
| --- | --- | --- |
| frameId | u32 | duplicate of header |
| captureHeadPosition | 3×f32 | host/SteamVR tracking space |
| captureHeadOrientation | 4×f32 | quaternion |
| flags | u32 | bit0=keyframe, bit1=left-right verified, bit2=meta-missing marker |
| sourceFrameNumber | u64 | host capture counter (diagnostics) |
| clientHeadTimestampNs | u64 | client timestamp of the head pose the host used for this frame (0 if unavailable); used by the client to find the matching local pose for reprojection |

Sent twice; the client deduplicates by `frameId` and keeps the first. If both copies are lost,
the client still displays with last pose and records `meta_missing`.

### 4.4 NACK (type 5, client→host)

`startFrameId u32, count u16`, then `count` entries of `frameId u32, fragmentIndex u16,
reserved u16`. Max 160 entries per datagram. The host retransmits only fragments still in its
ring (default 250 ms / 8 frames); otherwise it sends an IDR.

### 4.5 IDR_REQUEST (type 6, client→host)

`lastFrameId u32, reason u8, reserved u8[3], clientTimeNs u64`.

### 4.6 KEEPALIVE (type 7)

`clientTimeNs u64`, optional `inputSequence u64`. Sent every 1 s when no input; the host marks
the input link dead after 3 s.

---

## 5. Input datagrams (UDP 48627)

Type 2. Payload begins with `subType u8`:

### 5.1 HEAD (subType 1)

`trackingState u8 (0=invalid,1=degraded,2=tracked), flags u16, sampleId u32,
position 3×f32, orientation 4×f32, linearVelocity 3×f32, angularVelocity 3×f32` = 60 bytes.
`timestampNs` in the header is the sample time on the client clock. The host maps it with the
latest clock offset; stale samples (>250 ms) are dropped. A trackingState of invalid causes
the host to mark the HMD pose invalid; it must not reuse the last pose as valid indefinitely
(hold ≤120 ms, then invalid).

### 5.2 HAND (subType 2)

`chirality u8 (0=left,1=right), trackingState u8, flags u16, sampleId u32, jointCount u8
(must be 27), reserved u8, palmPosition 3×f32, palmOrientation 4×f32`, then 27 joints:
`jointId u8, position 3×f32, orientation 4×f32, radius f32` = 33 bytes each.

Joint IDs match `HandJointName` (0=wrist, 1=thumbKnuckle, 2=thumbIntermediateBase,
3=thumbIntermediateTip, 4=thumbTip, 5=indexMetacarpal, 6=indexKnuckle,
7=indexIntermediateBase, 8=indexIntermediateTip, 9=indexTip, 10=middleMetacarpal,
11=middleKnuckle, 12=middleIntermediateBase, 13=middleIntermediateTip, 14=middleTip,
15=ringMetacarpal, 16=ringKnuckle, 17=ringIntermediateBase, 18=ringIntermediateTip,
19=ringTip, 20=littleMetacarpal, 21=littleKnuckle, 22=littleIntermediateBase,
23=littleIntermediateTip, 24=littleTip, 25=forearmWrist, 26=forearmArm). If ARKit exposes a
different set, the adapter maps by name and marks missing joints with zero transform+radius 0;
jointCount remains 27 and the receiver treats zero radius as unavailable.

Payload size ≈ 931 bytes, under the max. The host forwards the skeleton to the driver skeleton
component (if enabled) and to diagnostics; gameplay uses INTENT.

### 5.3 INTENT (subType 3)

`hand u8, flags u16, sampleId u32, pose position 3×f32, pose orientation 4×f32,
linearVelocity 3×f32, angularVelocity 3×f32, trigger f32 [0,1], grip f32 [0,1],
stickX f32 [-1,1], stickY f32 [-1,1], trackpadX f32 [-1,1], trackpadY f32 [-1,1],
buttons u32, reserved u32`.

Buttons bitmask: bit0=triggerClick, bit1=gripClick, bit2=A, bit3=B, bit4=system/menu,
bit5=stickClick, bit6=trackpadClick, bit7=trackpadTouch, bit8=triggerTouch, bit9=gripTouch.

INTENT is authoritative for SteamVR input. The host clamps values, applies the latest sample
by timestamp (not arrival order), and latches button edges for at least one driver frame.
`pose` is the controller grip pose in the client's calibrated SteamVR space; the driver uses
it directly (after calibration transform). Aim pose is derived from orientation (−Z forward).

### 5.4 Input rules

- Send at sensor rate (target 90 Hz), immediately after the ARKit update; do not coalesce
  across frames unless the link is congested.
- On tracking loss, send one INTENT with all buttons/axes released and trackingState=invalid,
  then stop; the host must not keep stale buttons.
- Keepalive every 1 s; no input for 3 s marks the input link dead, releases all inputs, and
  transitions the session to degraded.
- Replay: reject packets with timestamps older than the newest accepted by >250 ms or duplicate
  `(sessionId, packetSequence)`; keep a 1024-entry window.
- Clock sync uncertainty >15 ms triggers degraded telemetry and reduced prediction.

---

## 6. Session sequence

```text
client                                      host
  TCP connect
  HELLO (plain) ─────────────────────────▶
                                           validate version/auth
  ◀───────────────────────── WELCOME (plain)
  ◀────────────────────── AUTH_CHALLENGE (plain)
  verify proof; derive keys
  AUTH_RESPONSE (plain) ──────────────────▶
                                           verify; derive keys
  ◀──────────────────────── AUTH_OK (enc)
  ◀──────────────────────── STREAM_CONFIG (enc)
  SESSION_STATE(ready) ───────────────────▶
                                           start capture/encode
  ◀──────────────────────── START_STREAM (enc)
  ◀════════════════════ VIDEO/META (UDP) ══════════════
  INTENT/HEAD/HAND (UDP) ═════════════════════════════▶
  CLOCK_PING/PONG, HEARTBEAT, TELEMETRY     both ways
  on failure: SESSION_STATE(degraded)       both ways
  on quit: STOP_STREAM / DISCONNECT
```

Insecure development mode omits the AUTH_CHALLENGE/RESPONSE and sets plaintext flags. Both
sides must opt in; production builds reject it.

---

## 7. Compatibility and versioning

- Major version mismatch: close with `ERROR(unsupported)` and a human-readable message.
- Minor version is backward-compatible; unknown non-critical fields may be ignored.
- New message types must not reuse IDs; deprecate, never delete within a major.
- Every accepted change updates `protocol/vectors/` and both Swift/C++ codecs. The Python
  reference implementation is authoritative for byte layout.
- `configVersion` in STREAM_CONFIG allows geometry changes; clients reject unknown config
  versions.

---

## 8. Limits and validation

| Item | Limit |
| --- | --- |
| Control payload | 1,048,576 bytes |
| Media datagram | 1,200 bytes total |
| Video frame | 8 MiB, 1,024 fragments |
| Strings | 255 bytes control, 64 discovery |
| Joints | 27, IDs 0..26 |
| NACK entries | 160 |
| Replay window | 1,024 packets |
| Session idle | 10 s → disconnect; recoverable |
| Clock samples | 64 ring, median + drift |

Any allocation is bounded by these limits. Parsers reject counts before allocating and return
typed errors. Fuzz targets cover every field boundary.

---

## 9. Security notes

- The pairing code has 60 bits of entropy and is single-use per session; PBKDF2 slows offline
  guessing. The host rate-limits and locks out after repeated failures.
- AEAD nonces never repeat within a key: session keys are unique per nonce pair and directions
  are separated; packet/control sequences are monotonic and the connection is torn down before
  a u64 sequence can wrap in any realistic session.
- The host must verify the client proof before sending any stream/session data.
- TLS on the control channel may replace the custom AEAD framing in a later version; the
  current design keeps media encryption uniform and testable.
- No plaintext mode in production builds; `--insecure-dev` is compiled only in development
  configurations and shows a red UI warning.

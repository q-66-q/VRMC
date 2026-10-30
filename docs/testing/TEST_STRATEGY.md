# Test Strategy

**Status:** Active; M0/M1 local tests run, hardware tests blocked.
**Authoritative acceptance mapping:** [`VERIFY.md`](../../VERIFY.md).

---

## 1. Principles

- Test the **actual boundary** you ship, not a mock of it. The mock host is valid for
  transport/renderer integration, never for Vivecraft, device hand tracking, or latency.
- Every acceptance criterion maps to a concrete test or manual procedure.
- Prefer deterministic, seeded, virtual-clock tests for time/gesture logic.
- Hardware evidence is recorded with build hash, device, procedure, expected/actual, and
  attached logs. A missing device is `BLOCKED`, not a pass.
- A failure is a deliverable: record it, file it, and do not hide it behind retries.

---

## 2. Test levels

| Level | What | Where | Evidence |
| --- | --- | --- | --- |
| Unit | Protocol bytes, clock math, prediction, gestures, mapping, session state, reassembly, IPC seqlock, projection math | `client/Tests`, `bridge/tests` | command output, commit |
| Conformance | Python reference ↔ Swift ↔ C++ on shared vectors | `protocol/vectors`, `scripts/test_protocol.sh` | byte-identical vectors |
| Integration | Mock host ↔ simulator: handshake, config, video, input, reconnect | `scripts/demo_simulator.sh`, app | logs/screenshots; simulator label |
| Device | ARKit hands, immersive rendering, tracking loss, gestures | D1 | MT-04..MT-07, hands-on video |
| Runtime | SteamVR driver + Vivecraft + mirror capture + input | P1/D1 | MT-01..MT-03, logs |
| System | End-to-end gameplay, latency, failure campaign, soak | D1+P1+N1 | MT-05..MT-11, telemetry/CSV |
| Acceptance | AC-1..AC-6 | D1/P1 | VERIFY §9/§10 |

---

## 3. Automated coverage plan

### Protocol / transport
- Frame round-trip and exact vector bytes; malformed magic/version/type/length; max sizes;
  truncation at every field boundary (property/fuzz); UTF-8/length validation; non-finite
  floats; quaternion normalization; unknown critical types.
- Reassembly: reorder, duplicate, loss, late fragments, frame gap, keyframe/config flags,
  NACK generation, drop timeout, serial wrap.
- Crypto (when implemented): RFC test vectors, nonce uniqueness, replay window, key rotation,
  wrong pairing code, rate limiting. Do not mark security release-ready until these exist.
- Clock: known offset/RTT, asymmetric delay, outlier rejection, drift, re-sync, wrap.
- Prediction: constant velocity, clamped horizon, confidence scaling, loss decay.
- IPC: seqlock torn-write stress, version/magic mismatch, writer restart.

### Hands / gestures / mapping
- Synthetic 27-joint open/pinch/fist/palm-up/palm-to-face/palm-down poses for both hands and
  left-handed mode.
- Threshold hysteresis/debounce; no chatter at boundary; press/release timing.
- Locomotion engage/exit, deadzone/saturation, turn, jump edge; no drift.
- Menu short/long dwell, suppression during attack/use, no double action.
- Tracking loss/stale/occlusion releases all buttons; 3-sample reacquire; no reacquisition
  false trigger.
- Two-hand independence; bow/shield sequences.
- Property tests with random joint noise/scale; no NaNs, no stuck states.

### Video / render math
- Annex-B parsing (3/4-byte codes, emulation prevention, AUD/SEI/parameter sets).
- VideoToolbox decode of a committed H.264 fixture; dimensions/colour; repeated frames;
  decoder reset; malformed input returns typed error.
- Projection/reprojection identity, extremes, clamp/no-NaN; eye order/UV rectangles.
- Packet loss → hold/IDR behavior.

### Session / app
- Connect/handshake/auth/config/start/stop state machine.
- Media timeout, link loss, retry/backoff, IDR request on recovery.
- Clock re-sync without pose jump.
- Bounded queues under synthetic overload; counters.
- Mock host E2E: stream decoded, input datagrams received, screenshot non-black.

---

## 4. Device and hardware testing

Manual procedures and pass conditions live in `VERIFY.md` §2/§4 and
`MANUAL_DEVICE_TESTS.md`. Requirements:

- D1 Vision Pro with a development-signed build, hand tracking + local network permissions.
- P1 Windows PC with SteamVR, pinned Minecraft/Fabric/Vivecraft, VRMC driver/host; DUAL
  mirror, borderless 3840×1080 game window.
- N1 Wi‑Fi 6E/dedicated AP with PC wired; N4 impairment tooling for failure tests.
- 240 fps camera or equivalent for M2P; telemetry CSV for stage latency.
- Test operator records raw numbers; a second reviewer checks evidence.

---

## 5. CI and local commands

```bash
./scripts/test_all.sh        # Swift + C++ core + vectors + docs
cd client && swift test
./scripts/build_bridge.sh --core
./scripts/test_protocol.sh
./scripts/demo_simulator.sh  # mock host + simulator (not acceptance)
```

CI: `.github/workflows/ci.yml` (macOS Swift/simulator, C++ core, Windows compile smoke, docs).
Hardware jobs are separate/self-hosted and not claimed by CI.

---

## 6. Flake and failure policy

- Unit/integration tests must be deterministic; virtual time, fixed seeds, no sleeps where a
  clock can be injected.
- A flaky test is quarantined with an issue and evidence; it is not retried to green.
- Hardware tests that fail are recorded with logs; the release cannot pass unless the failing
  row is fixed or an explicit, signed limitation is accepted in `VERIFY.md`.
- Test code is reviewed like product code; no test-only bypasses in production paths.

---

## 7. Evidence workflow

1. Build from a clean commit; record SHA and dirty state.
2. Run automated tests; save full output.
3. Execute manual procedure; capture logs/screenshots/video/CSV.
4. Add an entry to `VERIFY.md` §9 using the template, link paths/hashes, and set verdict.
5. Update the AC status only for the covered scope. Simulator evidence never advances device
   or latency ACs.
6. At a phase gate, run `./scripts/verify_release.sh` (or the gate checklist) and post a
   handoff per `AGENT.md` §8.4.

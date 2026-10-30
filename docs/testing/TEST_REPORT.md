# Test Report (Current)

**Date:** 2026-10-30.
**Build:** commit `660ad30` (Swift/C++ sources); simulator app bundle hash recorded in EV-0003.
**Verdict:** local/simulator scope PASS; hardware acceptance NOT RUN/BLOCKED.

## 1. Automated results

| Suite | Result | Evidence |
| --- | --- | --- |
| Swift `VRMCoreTests` | 34 passed, 0 failed | `evidence/EV-0002-local-suite/test_all.log` |
| Swift `VRMCVideoTests` (Annex-B + VideoToolbox H.264 fixture) | 3 passed, 0 failed | same |
| C++ core (`vrmc_core_tests`: protocol/vectors/clock/pose/IPC) | passed | same |
| Protocol vectors (Python reference ↔ committed vectors) | passed | `scripts/test_protocol.sh` |
| Docs/link checks | passed | same log |
| Driver source syntax (OpenVR v2.15.6, clang) | passed | EV-0008 |
| Simulator E2E | streaming, 154/155 frames decoded, 0 dropped, synthetic intents received | EV-0003 |

The simulator run used a 1280×720 30 fps H.264 loopback stream and synthetic hands. It is not
evidence for Vivecraft, device hand tracking, 90 Hz, or motion-to-photon latency.

## 2. Manual/hardware results

| Area | Status | Reason |
| --- | --- | --- |
| Pair/connect on Vision Pro | BLOCKED | no D1 |
| Vivecraft/SteamVR session | BLOCKED | no Windows/SteamVR; host/driver unbuilt |
| Both hands 27 joints | BLOCKED | no D1; synthetic/unit only |
| Core interactions | BLOCKED | depends on D1+P1 |
| Latency/camera | BLOCKED | depends on D1+P1+N1 |
| Failure campaign | BLOCKED | depends on D1+P1+N1 |
| New-user reproducibility | BLOCKED | requires hardware and independent tester |

## 3. Defects/limitations observed

- Development transport is insecure (no pairing/AEAD) — release blocker (EV-0007).
- The simulator window remains visible over the immersive test pattern; close it manually or
  use the future auto-hide UX.
- Mock clock domains differ, so the UI clock-offset number is large and not user-friendly;
  it does not affect frame decoding/rendering.
- Simulator dropped 0 frames in the final run; earlier runs dropped frames before the mock host
  honored IDR requests, which was fixed. This does not establish real-network stability.
- C++ Windows host/driver have not been compiled/run on Windows; only driver syntax was checked.

## 4. Next tests

Follow `VERIFY.md` MT-01..MT-12 and `MANUAL_DEVICE_TESTS.md`. Acceptance is withheld until every
AC row is PASS with evidence.

# Acceptance Guide

**Authority:** [`VERIFY.md`](../../VERIFY.md) is the single source of truth for acceptance and
evidence. This file explains how to use it; it does not override it.

## What "accepted" means

The MVP is accepted only when AC-1…AC-6 (`VERIFY.md` §1) and budgets K1–K6 (`VERIFY.md` §3) are
demonstrated on device with recorded evidence. A milestone passes only with:

1. green automated tests for its scope;
2. no open P0 defects;
3. evidence entries in `VERIFY.md` §6 for every claimed result;
4. status propagation per `AGENT.md` §4.7.

## Environments

| ID | Role | Notes |
|---|---|---|
| D1 | Paired Apple Vision Pro, visionOS 27.2 | Primary acceptance device; chip recorded at first run |
| D2 | Second headset (optional) | Compatibility only |
| D3 | visionOS 27.0 simulator | Build/UI/plumbing only; never evidence for hands, optics, thermals, latency |
| M1 | MacBook Pro M16,7 / M4 Pro, Xcode 27.2 | Build host; environment facts in EV-0001 |

## Test families

| Prefix | Meaning | Where defined |
|---|---|---|
| `AT-###` | Automated host-side tests | `VERIFY.md` §4.1 |
| `ST-S#` | Spike gates | `VERIFY.md` §4.2, procedures in [`SPIKES.md`](SPIKES.md) |
| `DT-##` | Device tests | `VERIFY.md` §4.3 |
| `HT-##` | Hand-input tests | `VERIFY.md` §4.4 |
| `CT-##` | Controller tests | `VERIFY.md` §4.5 |
| `LT-##` | Soak/thermal tests | `VERIFY.md` §4.6 |

## Budgets

K1 boot/launch timing · K2 frame rate · K3 motion-to-photon · K4 stability · K5 thermals · K6
footprint. Measurement methods and thresholds are in `VERIFY.md` §3. The K3 latency rig protocol is
an M0/M1 deliverable; without it M6 cannot produce evidence.

## Evidence workflow

```bash
# 1. Run the test, keep logs/screenshots in a scratch path.
# 2. Create the bundle (allocates the next EV ID, hashes artifacts):
scripts/log_evidence.sh --title "DT-07 immersive stereo" --status PASS \
  --device "D1 Apple Vision Pro visionOS 27.2" \
  --procedure "..." --expected "..." --actual "..." \
  --artifact /tmp/run.log --artifact /tmp/shot.png
# 3. Paste evidence/EV-####/entry.md into VERIFY.md §6; update the next-ID header,
#    dashboard §7, and change log §9 in the same commit.
```

Rules that are easy to get wrong:

- A re-run gets a **new** ID; never edit a past entry.
- A `PASS` with no artifacts is invalid.
- The simulator cannot satisfy AC-2…AC-5.
- If a run is aborted, record `FAIL` or `BLOCKED` with the reason.

## Device test preconditions

- App installed on D1 with the recorded build hash.
- Hand-tracking permission granted/denied scenarios both exercised.
- JIT launch path operating (S1).
- Controller and hands-only modes tested separately.
- Comfort settings tested (vignette, snap turn, teleport, seated).

## Release gate

`VERIFY.md` §1 all `PASS`; no `FAIL`/`BLOCKED` without a written waiver; notices and source
publication complete (AC-6); `versions.env` pins recorded in the release manifest; sign-off in
`VERIFY.md` §10.

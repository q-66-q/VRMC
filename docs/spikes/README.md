# Spike Records

A spike is a time-boxed, evidence-producing investigation. It ends with a decision and links
to `VERIFY.md` evidence. Spikes are not acceptance tests; they de-risk the plan.

| ID | Question | Status | Record |
| --- | --- | --- | --- |
| S-01 | Does SteamVR accept the VRMC HMD/controllers and does Vivecraft render? | BLOCKED | [S-01](S-01-driver.md) |
| S-02 | Is Vivecraft DUAL mirror capture complete/correct at target rate? | PARTIAL (source) | [S-02](S-02-dual-mirror.md) |
| S-03 | Does Vision Pro hand tracking meet rate/accuracy/recovery targets? | BLOCKED | [S-03](S-03-device-hand-tracking.md) |
| S-04 | Can the client decode/render 90 Hz at target resolution? | BLOCKED | pending device |
| S-05 | Is view M2P within target with rotation-only reprojection? | BLOCKED | [S-05](S-05-latency.md) |
| S-06 | Is the gesture/controller mapping usable? | PARTIAL (logic) | pending device |
| S-07 | Does WGC capture at 90 fps without corruption? | BLOCKED | pending Windows |
| S-08 | Do synthetic inputs drive Vivecraft's default bindings? | BLOCKED | pending SteamVR |
| S-09 | Does pairing/AEAD fit budget and satisfy privacy? | BLOCKED | not implemented |
| S-10 | Is a 3840×1080 DUAL window stable? | BLOCKED | pending Windows |
| S-11 | Can clocks synchronise within ±2 ms? | PARTIAL (logic) | pending network |
| S-12 | Are FOV/IPD matched closely enough for comfort? | BLOCKED | pending device |

## Spike protocol

1. Write the question, method, environment, and success criterion here before running.
2. Run it; capture raw logs/measurements.
3. Record the result, decision, and follow-up. Update `AGENT.md` §11 and `VERIFY.md`.
4. If the result disproves an assumption, stop implementation and follow the escalation rule
   in `AGENT.md` §12.5.

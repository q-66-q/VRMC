# S-03 — Vision Pro hand tracking quality

**Question:** Does ARKit `HandTrackingProvider` in an immersive CompositorServices app deliver
both hands, 27 joints, at ≥72 Hz with usable accuracy and recovery?

**Status:** BLOCKED — no physical Vision Pro in this workspace. Adapter code exists
(`client/Sources/VRMCApp/HandTrackingService.swift`), simulator tests use synthetic hands.

**Go criterion:** both hands tracked; 27 joints with position/orientation; ≥72 Hz; no chirality
swaps; pinch/fist thresholds reachable; occlusion→release and reacquire ≤1 s; 30-minute session
without thermal failure.

**No-go:** rate/accuracy/occlusion cannot support the mapping. Fallback: controller-backed v1
for actions, with hand tracking as an additional path (does not satisfy hand acceptance) or
redesign gestures; update ADR/plan.

**Method:** MT-04/HT-01..HT-20; log anchor timestamps, per-joint jitter, tracking flags, and
reacquisition; record video of ghost-hand/overlay behavior; test low light/reflections.

**Evidence:** pending; see `VERIFY.md` EV-0004.

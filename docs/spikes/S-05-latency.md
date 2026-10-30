# S-05 — Motion-to-photon latency

**Question:** Can VRMC achieve view M2P P50 ≤50 ms/P95 ≤70 ms and action feedback P50 ≤150 ms
with rotation-only reprojection on N1/D1/P1?

**Status:** BLOCKED — requires D1/P1/N1. Simulator loopback UI latency (~2–5 ms) is not M2P and
does not count.

**Go criterion:** instrumented stage timestamps plus a 240 fps camera measurement; percentiles
over 10 minutes; targets met or a quantified limitation with an accepted mitigation.

**No-go:** p95 misses budget after capture/encode/decode/reprojection optimization. Mitigate via
resolution/bitrate/72 Hz; if still unacceptable, document a limitation and waiver; consider
direct-mode capture or depth reprojection (new ADR).

**Method:** MT-09. Record t0..t8, camera frames, network topology, and thermal state; run 3×
N1, N2, N4; include action feedback with a visible marker.

**Evidence:** pending; see `VERIFY.md` EV-0006/MT-09.

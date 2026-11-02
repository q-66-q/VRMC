#!/usr/bin/env python3
"""Assert the simulator provider-sampling test result (see run.sh).

Verifies the drawn-drawable readback (64x64 RGBA8 dump of the presented drawable) matches the fake
provider texture as sampled through the compositor's flat path:
  row 0      : flat-mode badge (green)
  rows 1..6  : black top strip of the fake eye texture (orientation marker)
  rows 8..31 : TL red / TR green
  rows 32..63: BL blue / BR white
With --require-sync it additionally requires the compositor log to show the MTLSharedEvent wait path
(syncValid=1 + "eye frame sync: waiting on shared event").
"""
import os, sys

def load_rgba64(path):
    data = open(path, "rb").read()
    if len(data) != 64 * 64 * 4:
        raise SystemExit(f"unexpected raw size {len(data)} (want 64*64*4) in {path}")
    return [[tuple(data[((y*64+x)*4):((y*64+x)*4)+4]) for x in range(64)] for y in range(64)]

def kind(rgb):
    r, g, b = rgb[0], rgb[1], rgb[2]
    if r > 120 and g < 100 and b < 100: return "red"
    if g > 120 and r < 120 and b < 120: return "green"
    if b > 120 and r < 120 and g < 120: return "blue"
    if r > 150 and g > 150 and b > 150: return "white"
    if r < 90 and g < 90 and b < 90: return "black"
    return f"rgb({r},{g},{b})"

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/vrmc-provider-sim"
    require_sync = "--require-sync" in sys.argv[2:]
    raw = os.path.join(out, "drawable-L.raw")
    if not os.path.exists(raw):
        print(f"FAIL: {raw} missing (no presented drawable readback)"); return 1
    px = load_rgba64(raw)
    checks = [
        ("top badge (row 0)",    px[0][32],  "green"),
        ("top strip (row 4)",    px[4][32],  "black"),
        ("upper-left quadrant",  px[20][16], "red"),
        ("upper-right quadrant", px[20][48], "green"),
        ("lower-left quadrant",  px[48][16], "blue"),
        ("lower-right quadrant", px[48][48], "white"),
    ]
    failures = 0
    print(f"{'check':32s} {'got':22s} {'want':8s} result")
    for name, rgb, want in checks:
        got = kind(rgb); ok = got == want
        failures += 0 if ok else 1
        print(f"{name:32s} {got:22s} {want:8s} {'PASS' if ok else 'FAIL'}")
    if require_sync:
        log = ""
        p = os.path.join(out, "compositor.log")
        if os.path.exists(p): log = open(p, "r", errors="replace").read()
        sync_ok = ("syncValid=1" in log) and ("eye frame sync: waiting on shared event" in log)
        print(f"{'GPU sync wait path':32s} {('seen' if sync_ok else 'missing'):22s} {'seen':8s} {'PASS' if sync_ok else 'FAIL'}")
        if not sync_ok: failures += 1
    if failures:
        print(f"[provider-sim] FAIL: {failures} assertion(s) failed"); return 1
    print("[provider-sim] PASS: provider texture sampled through the compositor flat path with expected "
          "orientation/layout" + (" + GPU timeline sync wait exercised" if require_sync else ""))
    return 0

if __name__ == "__main__":
    sys.exit(main())

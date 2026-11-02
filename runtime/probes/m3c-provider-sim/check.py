#!/usr/bin/env python3
"""Assert the simulator provider-sampling test results (see run.sh).

Scenarios:
  provider (default) : fake provider `MTLTexture` sampled through the compositor flat path.
      Expected drawable readback (64x64 top->bottom): green flat badge, black top strip,
      TL red / TR green, BL blue / BR white; depth-clear fix active (depthZero=0).
  --require-sync     : additionally require the compositor log to show the MTLSharedEvent wait path.
  --pattern          : eye-distinct stereo/alignment test pattern (manual Enter VR path):
      white/cyan proof border, warm left-eye tint, white centre fusion cross, red left-eye marker.

Every scenario also requires the shell log to show the immersive scene foreground-active.

Exit 0 = PASS, 1 = FAIL.
"""
import os, sys

def load_rgba64(path):
    data = open(path, "rb").read()
    if len(data) != 64 * 64 * 4:
        raise SystemExit(f"unexpected raw size {len(data)} (want 64*64*4) in {path}")
    return [[tuple(data[((y * 64 + x) * 4):((y * 64 + x) * 4) + 4]) for x in range(64)] for y in range(64)]

def is_red(p):   return p[0] > 120 and p[1] < 100 and p[2] < 100
def is_green(p): return p[1] > 120 and p[0] < 120 and p[2] < 120
def is_blue(p):  return p[2] > 120 and p[0] < 120 and p[1] < 120
def is_white(p): return p[0] > 150 and p[1] > 150 and p[2] > 150
def is_black(p): return p[0] < 90 and p[1] < 90 and p[2] < 90
def is_warm(p):  return p[0] > 140 and p[0] > p[1] + 40 and p[0] > p[2] + 40
def is_colour(p):return max(p[0], p[1], p[2]) > 120

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/vrmc-provider-sim"
    args = sys.argv[2:]
    require_sync = "--require-sync" in args
    pattern = "--pattern" in args

    raw = os.path.join(out, "drawable-L.raw")
    if not os.path.exists(raw):
        print(f"FAIL: {raw} missing (no presented drawable readback)"); return 1
    px = load_rgba64(raw)

    if pattern:
        checks = [
            ("proof border (0,0)",       px[0][0],   is_white,  "white"),
            ("left-eye warm tint",       px[20][16], is_warm,   "warm"),
            ("centre fusion cross",      px[32][32], is_white,  "white"),
            ("left-eye corner marker",   px[60][4],  is_red,    "red"),
        ]
    else:
        checks = [
            ("top badge (row 0)",        px[0][32],  is_green,  "green"),
            ("top strip (row 4)",        px[4][32],  is_black,  "black"),
            ("upper-left quadrant",      px[20][16], is_red,    "red"),
            ("upper-right quadrant",     px[20][48], is_green,  "green"),
            ("lower-left quadrant",      px[48][16], is_blue,   "blue"),
            ("lower-right quadrant",     px[48][48], is_white,  "white"),
        ]

    failures = 0
    print(f"{'check':32s} {'got':24s} {'want':8s} result")
    for name, rgb, pred, want in checks:
        got = f"rgb({rgb[0]},{rgb[1]},{rgb[2]})"
        ok = bool(pred(rgb))
        failures += 0 if ok else 1
        print(f"{name:32s} {got:24s} {want:8s} {'PASS' if ok else 'FAIL'}")

    log = os.path.join(out, "compositor.log")
    text = open(log, "r", errors="replace").read() if os.path.exists(log) else ""
    if not pattern:
        depth_ok = "depthZero=0" in text
        print(f"{'depth-clear fix active':32s} {('yes' if depth_ok else 'no'):24s} {'yes':8s} {'PASS' if depth_ok else 'FAIL'}")
        if not depth_ok: failures += 1
    if require_sync:
        sync_ok = ("syncValid=1" in text) and ("eye frame sync: waiting on shared event" in text)
        print(f"{'GPU sync wait path':32s} {('seen' if sync_ok else 'missing'):24s} {'seen':8s} {'PASS' if sync_ok else 'FAIL'}")
        if not sync_ok: failures += 1

    shelllog = os.path.join(out, "shell.log")
    stext = open(shelllog, "r", errors="replace").read() if os.path.exists(shelllog) else ""
    active_ok = "CPSceneSessionRoleImmersiveSpaceApplication:fgActive" in stext
    print(f"{'immersive scene fgActive':32s} {('seen' if active_ok else 'missing'):24s} {'seen':8s} {'PASS' if active_ok else 'FAIL'}")
    if not active_ok: failures += 1

    if failures:
        print(f"[provider-sim] FAIL: {failures} assertion(s) failed"); return 1
    print("[provider-sim] PASS: " + ("stereo/alignment test pattern" if pattern else "provider texture sampled "
          "through the compositor flat path with expected orientation/layout")
          + ((" + GPU timeline sync wait exercised") if require_sync else ""))
    return 0

if __name__ == "__main__":
    sys.exit(main())

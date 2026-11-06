#!/usr/bin/env python3
"""Assert the simulator provider-sampling test results (see run.sh).

Scenarios:
  provider (default) : fake provider `MTLTexture` sampled through the compositor flat path.
      Expected drawable readback (64x64 top->bottom): green flat badge, black top strip,
      TL red / TR green, BL blue / BR white; depth-clear fix active (depthZero=0).
  --require-sync     : additionally require the compositor log to show the MTLSharedEvent wait path.
  --pattern          : eye-distinct stereo/alignment test pattern (manual Enter VR path):
      white/cyan proof border, warm left-eye tint, white centre fusion cross, red left-eye marker.
  --require-input    : M4-W1 input scenario. The real compositor published synthetic 27-joint hand
      snapshots through the fake bridge; input-capture.txt must show >=30 snapshots with valid_mask
      framing, right-pinch threshold crossings (below pinchOn / above pinchOff), left-fist ratio
      crossings (below fistOn / above fistOff), and a final zeroed release frame (valid_mask=0), with
      no compositor input errors. Plumbing evidence only - NOT hands evidence.
  --require-render   : M8 render-feedback scenario. The real compositor must publish display geometry
      + cadence through the native-shared channel (render-capture.txt: >=3 valid payloads with sane
      logical/physical sizes, quality, cadence) and log the layer configuration, foveation state,
      fixed runtime quality, minimumFrameRepeatCount=0 and the render-feedback summary lines.
      Plumbing evidence only - simulator display sizes/rates are NOT device optics/refresh evidence.

Every scenario also requires the shell log to show the immersive scene foreground-active.

Exit 0 = PASS, 1 = FAIL.
"""
import os, sys

# M4-W1 gesture thresholds (docs/analysis/immersive-input.md §5.3 provider defaults). The capture
# records the provider's metrics computed from the published joints; the synthetic cycle must cross
# both sides of each hysteresis band.
PINCH_ON = 0.030      # press when pinch distance < pinchOn
PINCH_OFF = 0.045     # release when pinch distance > pinchOff
FIST_ON = 1.25        # press when fist ratio < fistOn
FIST_OFF = 1.55       # release when fist ratio > fistOff
INPUT_MIN_SNAPSHOTS = 30

def parse_input_capture(path):
    """Return the capture records as tuples; '#' header/comment lines are skipped."""
    records = []
    with open(path, "r", errors="replace") as handle:
        for line_no, line in enumerate(handle, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(",")
            if len(parts) != 8:
                raise SystemExit(f"malformed input capture line {line_no} ({len(parts)} fields): {line}")
            try:
                records.append((int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]),
                                float(parts[4]), float(parts[5]), float(parts[6]), float(parts[7])))
            except ValueError:
                raise SystemExit(f"malformed input capture line {line_no}: {line}")
    return records

def parse_render_capture(path):
    """Return render-feedback payloads as tuples; raises SystemExit on malformed lines."""
    records = []
    with open(path, "r", errors="replace") as handle:
        for line_no, line in enumerate(handle, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(",")
            if len(parts) != 15:
                raise SystemExit(f"malformed render capture line {line_no} ({len(parts)} fields): {line}")
            try:
                records.append((int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]),
                                int(parts[4]), int(parts[5]), int(parts[6]), int(parts[7]),
                                int(parts[8]), int(parts[9]), int(parts[10]),
                                float(parts[11]), float(parts[12]), float(parts[13]),
                                float(parts[14])))
            except ValueError:
                raise SystemExit(f"malformed render capture line {line_no}: {line}")
    return records

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
    require_parking = "--require-parking" in args
    require_hidden = "--require-hidden" in args
    require_noparking = "--require-noparking" in args
    reentry = "--reentry" in args
    pattern = "--pattern" in args
    require_input = "--require-input" in args
    require_render = "--require-render" in args
    require_eyedrop = "--require-eyedrop" in args

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
    if require_parking:
        parking_ok = ("window parked after first presented frame" in stext) and ("alpha=0.00" in stext)
        print(f"{'window parking':32s} {('seen' if parking_ok else 'missing'):24s} {'seen':8s} {'PASS' if parking_ok else 'FAIL'}")
        if not parking_ok: failures += 1
    if require_hidden:
        hidden_ok = "hidden=true" in stext
        print(f"{'isHidden parking mode':32s} {('seen' if hidden_ok else 'missing'):24s} {'seen':8s} {'PASS' if hidden_ok else 'FAIL'}")
        if not hidden_ok: failures += 1
    if require_noparking:
        nopark_ok = ("parking disabled by vrmc-no-parking.flag" in stext) and ("window parked after first presented frame" not in stext)
        print(f"{'no-parking mode respected':32s} {('seen' if nopark_ok else 'missing'):24s} {'seen':8s} {'PASS' if nopark_ok else 'FAIL'}")
        if not nopark_ok: failures += 1
    if reentry:
        bg_ok = "didEnterBackground" in stext
        fg_ok = "reason=foreground" in stext
        runs = stext.count("VRMCCompositorRunning generation=")
        reentry_ok = bg_ok and fg_ok and runs >= 2
        print(f"{'re-entry (bg->fg reopen)':32s} {(f'bg={bg_ok} fg={fg_ok} runs={runs}'):24s} {'>=2':8s} {'PASS' if reentry_ok else 'FAIL'}")
        if not reentry_ok: failures += 1
    if require_input:
        # M4-W1: every snapshot the REAL compositor published through the fake bridge. The cycle must
        # exercise both sides of the pinch/fist hysteresis bands, then a zeroed release on stop.
        capture_path = os.path.join(out, "input-capture.txt")
        records = parse_input_capture(capture_path) if os.path.exists(capture_path) else []
        if not records:
            print(f"{'input capture present':32s} {'missing/empty':24s} {'>=1':8s} FAIL")
            failures += 1
        else:
            tracked = [r for r in records if r[2] == 3]
            count_ok = len(records) >= INPUT_MIN_SNAPSHOTS
            print(f"{'input published snapshots':32s} {str(len(records)):24s} {f'>={INPUT_MIN_SNAPSHOTS}':8s} {'PASS' if count_ok else 'FAIL'}")
            if not count_ok: failures += 1

            # valid_mask framing: both hands tracked (3) for every scripted frame, then exactly the
            # final stop/release snapshot has no valid hands (0).
            framing_ok = (records[0][2] == 3 and records[-1][2] == 0 and
                          all(r[2] == 3 for r in records[:-1]) and
                          len(tracked) >= INPUT_MIN_SNAPSHOTS)
            print(f"{'valid_mask framing (3..3,0)':32s} {f'tracked={len(tracked)} last={records[-1][2]}':24s} {'3..,0':8s} {'PASS' if framing_ok else 'FAIL'}")
            if not framing_ok: failures += 1

            seq_ok = all(r[0] == i + 1 for i, r in enumerate(records))
            frames_ok = all(records[i][1] <= records[i + 1][1] for i in range(len(records) - 1))
            ts_ok = all(r[3] > 0 for r in tracked)
            meta_ok = seq_ok and frames_ok and ts_ok
            print(f"{'seq/frame/timestamp framing':32s} {(f'seq={seq_ok} frame={frames_ok} ts={ts_ok}'):24s} {'all':8s} {'PASS' if meta_ok else 'FAIL'}")
            if not meta_ok: failures += 1

            # Right pinch: the cycle must cross below pinchOn (press) and above pinchOff (release).
            right_pinches = [r[4] for r in tracked]
            pinch_low = min(right_pinches) if right_pinches else 1.0
            pinch_high = max(right_pinches) if right_pinches else 0.0
            pinch_ok = pinch_low < PINCH_ON and pinch_high > PINCH_OFF
            print(f"{'right pinch hysteresis crossings':32s} {(f'min={pinch_low:.4f} max={pinch_high:.4f}'):24s} {'<' + str(PINCH_ON) + ' & >' + str(PINCH_OFF):8s} {'PASS' if pinch_ok else 'FAIL'}")
            if not pinch_ok: failures += 1

            # Left fist: the cycle must cross below fistOn (press) and above fistOff (release).
            left_fists = [r[7] for r in tracked]
            fist_low = min(left_fists) if left_fists else 9.0
            fist_high = max(left_fists) if left_fists else 0.0
            fist_ok = fist_low < FIST_ON and fist_high > FIST_OFF
            print(f"{'left fist ratio crossings':32s} {(f'min={fist_low:.3f} max={fist_high:.3f}'):24s} {'<' + str(FIST_ON) + ' & >' + str(FIST_OFF):8s} {'PASS' if fist_ok else 'FAIL'}")
            if not fist_ok: failures += 1

            # Compositor evidence: synthetic lines are labelled; one publication + one release logged;
            # no input errors at all.
            log_ok = ("INPUT-SIM SYNTHETIC" in text and "input publish seq=" in text and
                      "input release" in text and "input script=cycle" in text)
            print(f"{'compositor input log lines':32s} {('seen' if log_ok else 'missing'):24s} {'seen':8s} {'PASS' if log_ok else 'FAIL'}")
            if not log_ok: failures += 1
            error_markers = ("input publish error", "input publication disabled",
                             "input hand query failed", "input: bridge dylib has no")
            errors_seen = [marker for marker in error_markers if marker in text]
            err_ok = not errors_seen
            print(f"{'no compositor input errors':32s} {(str(errors_seen) if errors_seen else 'none'):24s} {'none':8s} {'PASS' if err_ok else 'FAIL'}")
            if not err_ok: failures += 1
    if require_render:
        # M8: the REAL compositor published display geometry + cadence to the provider channel. The
        # fake provider captured every payload; assert the wire shape and the compositor log evidence.
        capture_path = os.path.join(out, "render-capture.txt")
        rows = parse_render_capture(capture_path) if os.path.exists(capture_path) else []
        if not rows:
            print(f"{'render feedback capture':32s} {'missing/empty':24s} {'>=3':8s} FAIL")
            failures += 1
        else:
            count_ok = len(rows) >= 3
            print(f"{'render feedback publishes':32s} {str(len(rows)):24s} {'>=3':8s} {'PASS' if count_ok else 'FAIL'}")
            if not count_ok: failures += 1
            shape_ok = all(
                r[2] == 1 and r[3] >= 64 and r[4] >= 64 and r[5] >= 64 and r[6] >= 64
                and 0.0 <= r[11] <= 1.0 and 0.0 <= r[12] <= 1.0 and r[12] >= r[11] - 1e-3
                and r[13] >= 0.0 and r[14] >= 0.0 and r[9] in (0, 1)
                for r in rows)
            print(f"{'render payload shape/quality':32s} {('sane' if shape_ok else 'bad'):24s} {'sane':8s} {'PASS' if shape_ok else 'FAIL'}")
            if not shape_ok: failures += 1
            monotonic = all(rows[i][0] < rows[i + 1][0] for i in range(len(rows) - 1))
            print(f"{'publish counter monotonic':32s} {('yes' if monotonic else 'no'):24s} {'yes':8s} {'PASS' if monotonic else 'FAIL'}")
            if not monotonic: failures += 1
            last = rows[-1]
            print(f"  render feedback: logical L={last[3]}x{last[4]} R={last[5]}x{last[6]} "
                  f"drawable={last[7]}x{last[8]} foveation={last[9]} rateMaps={last[10]} "
                  f"quality={last[11]:.2f}/{last[12]:.2f} displayHz={last[13]:.1f} frame={last[14]:.2f}ms")
            log_ok = ("render feedback published:" in text and "display geometry: logical L=" in text
                      and "render quality:" in text and "frame pacing: minimumFrameRepeatCount=0" in text
                      and "foveation:" in text and "layer configuration colorFormat=" in text
                      and "sharpen=" in text)
            print(f"{'compositor render log lines':32s} {('seen' if log_ok else 'missing'):24s} {'seen':8s} {'PASS' if log_ok else 'FAIL'}")
            if not log_ok: failures += 1
            no_errors = "render feedback publish FAILED" not in text
            print(f"{'no render-feedback errors':32s} {('none' if no_errors else 'seen'):24s} {'none':8s} {'PASS' if no_errors else 'FAIL'}")
            if not no_errors: failures += 1
    if require_eyedrop:
        # M8 resize grace: the fake provider withheld its eye frame for 60 acquires (mimicking the real
        # provider clearing the shared frame before an eye-target rebuild). The compositor must reuse
        # its last sampled pair, log the grace expiry, then recover when eyes return - in that order -
        # and the shell must have survived the whole drop.
        reuse_marker = "eyes absent: reusing the last sampled eye frame"
        expired_marker = "last-frame grace expired"
        resumed_marker = "eye frame resumed after"
        reuse_ok = reuse_marker in text
        print(f"{'grace: last-frame reuse logged':32s} {('seen' if reuse_ok else 'missing'):24s} {'seen':8s} {'PASS' if reuse_ok else 'FAIL'}")
        if not reuse_ok: failures += 1
        expired_ok = expired_marker in text
        print(f"{'grace: expiry logged':32s} {('seen' if expired_ok else 'missing'):24s} {'seen':8s} {'PASS' if expired_ok else 'FAIL'}")
        if not expired_ok: failures += 1
        resumed_ok = resumed_marker in text
        print(f"{'grace: recovery logged':32s} {('seen' if resumed_ok else 'missing'):24s} {'seen':8s} {'PASS' if resumed_ok else 'FAIL'}")
        if not resumed_ok: failures += 1
        order_ok = (reuse_ok and expired_ok and resumed_ok and
                    text.index(reuse_marker) < text.index(expired_marker) < text.index(resumed_marker))
        print(f"{'grace: reuse -> expiry -> resume':32s} {('ordered' if order_ok else 'out of order'):24s} {'ordered':8s} {'PASS' if order_ok else 'FAIL'}")
        if not order_ok: failures += 1
        crash_ok = (("FATAL" not in stext) and ("SIGSEGV" not in stext)
                    and "VRMCCompositorRunning generation=" in stext)
        print(f"{'grace: compositor survived drop':32s} {('yes' if crash_ok else 'no'):24s} {'yes':8s} {'PASS' if crash_ok else 'FAIL'}")
        if not crash_ok: failures += 1
    active_ok = "CPSceneSessionRoleImmersiveSpaceApplication:fgActive" in stext
    print(f"{'immersive scene fgActive':32s} {('seen' if active_ok else 'missing'):24s} {'seen':8s} {'PASS' if active_ok else 'FAIL'}")
    if not active_ok: failures += 1

    if failures:
        print(f"[provider-sim] FAIL: {failures} assertion(s) failed"); return 1
    detail = "stereo/alignment test pattern" if pattern else ("provider texture sampled through the compositor flat path with expected orientation/layout")
    if require_sync: detail += " + GPU timeline sync wait exercised"
    if require_parking: detail += " + window parking"
    if reentry: detail += " + background/foreground re-entry"
    if require_input: detail += " + synthetic-hand input publication/release (plumbing only, NOT hands evidence)"
    if require_render: detail += " + M8 render feedback display-geometry/cadence publication (plumbing only)"
    if require_eyedrop: detail += " + M8 resize-grace last-frame reuse/expiry/recovery (simulated provider clear)"
    print("[provider-sim] PASS: " + detail)
    return 0

if __name__ == "__main__":
    sys.exit(main())
#!/usr/bin/env python3
"""Summarize Gesture Lab JSONL recordings into per-label feature statistics + threshold suggestions.

Reads:  <dir>/gesturelab-*.jsonl
Writes: <dir>/gesturelab-analysis.md  (stdout also prints a short summary)
These are host analysis hints only; thresholds must still be validated on device.
"""
import json, math, statistics, sys
from collections import defaultdict
from pathlib import Path


def fnum(x, default=0.0):
    try:
        v = float(x)
        return v if math.isfinite(v) else default
    except Exception:
        return default


def pct(values, p):
    if not values:
        return 0.0
    s = sorted(values)
    k = min(len(s) - 1, max(0, int(round((len(s) - 1) * p))))
    return s[k]


def joint_map(hand):
    return {j.get("name"): j for j in hand.get("joints", []) if isinstance(j, dict)}


def joint_pos(j):
    m = j.get("m", [])
    if len(m) < 15:
        return None
    return (m[12], m[13], m[14])


def joint_dist(a, b):
    if a is None or b is None:
        return None
    return math.dist(a, b)


def fist_ratio(hand):
    """Same curl ratio as the app: mean(tip→knuckle / wrist→knuckle)."""
    j = joint_map(hand)
    wrist = j.get("wrist")
    ws = joint_pos(wrist) if wrist else None
    if ws is None:
        return None
    vals = []
    for finger in ("index", "middle", "ring", "little"):
        kn = j.get(finger + "FingerKnuckle")
        tip = j.get(finger + "FingerTip")
        a, b = joint_pos(kn) if kn else None, joint_pos(tip) if tip else None
        if a is None or b is None:
            return None
        vals.append(joint_dist(b, a) / max(0.02, joint_dist(ws, a)))
    return sum(vals) / len(vals)


def main():
    if len(sys.argv) < 2:
        print("usage: m7_analyze_lab_data.py <recording-dir>", file=sys.stderr); return 2
    d = Path(sys.argv[1])
    files = sorted(d.glob("gesturelab-*.jsonl"))
    if not files:
        print(f"[m7-analysis] no gesturelab-*.jsonl in {d}")
        return 0
    by_label = defaultdict(list)
    bad = 0
    total = 0
    for path in files:
        for line in path.read_text(errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                s = json.loads(line)
            except Exception:
                bad += 1
                continue
            label = str(s.get("label", "?"))
            by_label[label].append(s)
            total += 1
    out = ["# Gesture Lab analysis", ""]
    out.append(f"files={len(files)} samples={total} unparsed={bad} labels={len(by_label)}")
    out.append("")
    out.append("| label | samples | L tracked | R tracked | L pinch p05/p50/p95 | L events | R pinch p05/p50/p95 | R events | L fist p50 | R fist p50 | R speed p95 | R wrist→head p50 | head y range |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    suggestions = []
    for label in sorted(by_label):
        rows = by_label[label]
        left = sum(1 for s in rows if s.get("left", {}).get("tracked"))
        right = sum(1 for s in rows if s.get("right", {}).get("tracked"))
        pinches, left_pinches, right_fists, left_fists, speeds, head_dists, head_ys = [], [], [], [], [], [], []
        for s in rows:
            rf = s.get("rightFeatures", {})
            lf = s.get("leftFeatures", {})
            if s.get("left", {}).get("tracked"):
                left_pinches.append(fnum(lf.get("pinch"), 1.0))
                v = fist_ratio(s["left"])
                if v is not None:
                    left_fists.append(v)
            if s.get("right", {}).get("tracked"):
                v = fist_ratio(s["right"])
                if v is not None:
                    right_fists.append(v)
            pinches.append(fnum(rf.get("pinch"), 1.0))
            if not right_fists:
                pass
            speeds.append(abs(fnum(rf.get("speed"), 0.0)))
            if s.get("headTracked") and s.get("right", {}).get("tracked"):
                head = s.get("head", [0, 0, 0])
                wr = None
                for j in s["right"].get("joints", []):
                    if j.get("name", "").endswith("wrist"):
                        m = j.get("m", [])
                        if len(m) >= 16:
                            wr = (m[12], m[13], m[14])
                        break
                if wr and len(head) == 3:
                    head_dists.append(math.dist(wr, head))
                    head_ys.append(fnum(head[1]))
        rng = (max(head_ys) - min(head_ys)) if head_ys else 0.0
        def pinch_events(vals):
            on = False
            count = 0
            for p in vals:
                if not on and p < 0.030:
                    on = True
                elif on and p > 0.045:
                    on = False
                    count += 1
            return count
        closed = [p for p in pinches if p < 0.030]
        events = pinch_events(pinches)
        left_events = pinch_events(left_pinches)
        out.append(f"| {label} | {len(rows)} | {left} | {right} | "
                   f"{pct(left_pinches,0.05):.3f}/{pct(left_pinches,0.5):.3f}/{pct(left_pinches,0.95):.3f} | "
                   f"{left_events} | {pct(pinches,0.05):.3f}/{pct(pinches,0.5):.3f}/{pct(pinches,0.95):.3f} | "
                   f"{events} | {pct(left_fists,0.5):.2f} | {pct(right_fists,0.5):.2f} | "
                   f"{pct(speeds,0.95):.2f} | {pct(head_dists,0.5):.3f} | {rng:.3f} |")
        if label in ("MENU_RIGHT_PINCH", "PLACE_RIGHT_PINCH") and pinches:
            suggestions.append(f"- {label}: {len(closed)} closed frames (<0.030 m), {events} pinch events; "
                               f"p05={pct(pinches,0.05):.3f} p25={pct(pinches,0.25):.3f} "
                               f"p50={pct(pinches,0.5):.3f} p95={pct(pinches,0.95):.3f} m. "
                               f"Current 0.030 on / 0.045 off is consistent if the open-hand p25 stays above 0.045.")
        if label in ("ESCAPE_LEFT_FIST", "WALK_BOTH_FISTS", "BOW_BOTH_FISTS", "INVENTORY_BOTH_FISTS", "CLIMB_ALTERNATE"):
            closed_l = sum(1 for v in left_fists if v < 0.55)
            closed_r = sum(1 for v in right_fists if v < 0.55)
            suggestions.append(f"- {label}: left fist frames <0.55={closed_l}/{len(left_fists)}; "
                               f"right fist frames <0.55={closed_r}/{len(right_fists)}; "
                               f"left p50={pct(left_fists,0.5):.2f}, right p50={pct(right_fists,0.5):.2f}. "
                               f"Use closed frames with both-hands-visible to set fist on/off hysteresis.")
        if label == "TELEPORT_LEFT_PINCH":
            suggestions.append(f"- TELEPORT_LEFT_PINCH: left pinch events={left_events}; "
                               f"p05={pct(left_pinches,0.05):.3f} p50={pct(left_pinches,0.5):.3f} "
                               f"p95={pct(left_pinches,0.95):.3f} m. Left pinch hold should start teleport-aim; "
                               f"release commits.")
        if label in ("WALK_BOTH_FISTS", "BOW_BOTH_FISTS", "ATTACK_RIGHT_SWING") and speeds:
            suggestions.append(f"- {label}: right wrist speed p95={pct(speeds,0.95):.2f} m/s; "
                               f"use for attack/walk separation after checking falsing.")
        if label == "EAT_RIGHT_HAND_HEAD" and head_dists:
            suggestions.append(f"- eat proximity: right wrist→head p50={pct(head_dists,0.5):.3f} m, "
                               f"p95={pct(head_dists,0.95):.3f} m; start latch ~0.28 m and require food context.")
        if label in ("JUMP_HEAD", "SNEAK_HEAD") and head_ys:
            suggestions.append(f"- {label}: head y range={rng:.3f} m; compare idle baseline before latching.")
    out += ["", "## Suggested starting thresholds (host hints only)", ""]
    out += suggestions or ["- Not enough action-labelled data yet."]
    out += ["", "Device validation is still required; do not treat these as accepted thresholds.", ""]
    text = "\n".join(out)
    (d / "gesturelab-analysis.md").write_text(text)
    print(f"[m7-analysis] labels={len(by_label)} samples={total} -> {d / 'gesturelab-analysis.md'}")
    print(text)


if __name__ == "__main__":
    raise SystemExit(main())

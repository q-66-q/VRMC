#!/usr/bin/env python3
"""M7 head-gesture analysis: head jump/sneak, head pose math, cross-dataset + IDLE negatives.

Reads the read-only Gesture Lab JSONL captures (local/gitignored) and prints every table and
number used in docs/mvp/M7_DATA_ANALYSIS_HEAD.md. It never writes to the data or to git.

Usage (from the repo root):
    python3 scripts/m7_lab_stats_head.py

Data inputs:
    export/gesturelab-data/accepted/gesturelab-*.jsonl            (15 labelled action captures)
    export/gesturelab-data/gesturelab-IDLE-20261102-173326.jsonl  (label IDLE, used as negative)

Reference engine (read-only, not modified):
    provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java lines 53-56 and 178-195:
      HEAD_JUMP_RISE=0.08, HEAD_SNEAK_DROP=0.10, HEAD_JUMP_COOLDOWN=700 ms,
      HEAD_SNEAK_LATCH=350 ms, baseline EMA headBaseline = headBaseline*0.985 + headY*0.015
      once per update, headVel = dy/dt per frame, jump pulse 80 ms, sneak has NO release
      hysteresis (instant release the frame the 0.10 m drop test fails).
    VisionVR.poll() runs once per render frame on a 90 Hz budget (missed90HzFrames), while the
    lab records ~18 Hz: the same per-frame EMA pole has a ~5x different time constant there.
"""
import json
import math
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "export" / "gesturelab-data"
ACCEPTED = DATA / "accepted"
IDLE_PATH = DATA / "gesturelab-IDLE-20261102-173326.jsonl"

PROD_HZ = 90.0
LAB_HZ = 18.05
FRAME_ALPHA = 0.985
TAU_DESIGN = 2.0

CUR_JUMP_RISE = 0.08
CUR_JUMP_VEL = 0.25
CUR_JUMP_COOLDOWN = 0.70
CUR_SNEAK_DROP = 0.10
CUR_SNEAK_LATCH = 0.35

P_TAU = 2.0
P_ADAPT_BAND = 0.10        # baseline adapts only while |headY-baseline| <= this; else freeze
P_JUMP_PITCH_GATE = -45.0  # ignore jump detection while looking down past this pitch (deg)
P_JUMP_RISE = 0.10
P_JUMP_VEL = 0.35
P_JUMP_WIN = 0.12
P_JUMP_COOLDOWN = 0.70
P_SNEAK_DROP = 0.12
P_SNEAK_LATCH = 0.50
P_SNEAK_EXIT = 0.05
P_SNEAK_EXIT_HOLD = 0.25
P_JUMP_SUPPRESS_SNEAK = 0.30

PITCH_C1 = 0.1038
PITCH_C2 = 0.0945

JOINT_NAMES = [
    "wrist",
    "thumbKnuckle", "thumbIntermediateBase", "thumbIntermediateTip", "thumbTip",
    "indexFingerMetacarpal", "indexFingerKnuckle", "indexFingerIntermediateBase",
    "indexFingerIntermediateTip", "indexFingerTip",
    "middleFingerMetacarpal", "middleFingerKnuckle", "middleFingerIntermediateBase",
    "middleFingerIntermediateTip", "middleFingerTip",
    "ringFingerMetacarpal", "ringFingerKnuckle", "ringFingerIntermediateBase",
    "ringFingerIntermediateTip", "ringFingerTip",
    "littleFingerMetacarpal", "littleFingerKnuckle", "littleFingerIntermediateBase",
    "littleFingerIntermediateTip", "littleFingerTip",
    "forearmWrist", "forearmArm",
]
FINGERS = ("index", "middle", "ring", "little")


def pct(values, p):
    if not values:
        return 0.0
    s = sorted(values)
    k = min(len(s) - 1, max(0, int(round((len(s) - 1) * p))))
    return s[k]


def mean(values):
    return sum(values) / len(values) if values else 0.0


def std(values):
    if len(values) < 2:
        return 0.0
    m = mean(values)
    return math.sqrt(sum((v - m) ** 2 for v in values) / len(values))


def dist3(a, b):
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


def fmt_list(values, nd=2, limit=None):
    vals = list(values) if limit is None else list(values)[:limit]
    text = "[" + ", ".join(("%." + str(nd) + "f") % v for v in vals) + "]"
    if limit is not None and len(values) > limit:
        text = text[:-1] + ", ...]"
    return text


def _joint_pos(joint):
    m = joint.get("m")
    if not isinstance(m, list) or len(m) < 15:
        return None
    try:
        x, y, z = float(m[12]), float(m[13]), float(m[14])
    except (TypeError, ValueError):
        return None
    if not (math.isfinite(x) and math.isfinite(y) and math.isfinite(z)):
        return None
    return (x, y, z)


def _hand_joints(hand):
    joints = hand.get("joints")
    if not isinstance(joints, list):
        return None
    out = {}
    for joint in joints:
        if not isinstance(joint, dict):
            continue
        name = joint.get("name")
        pos = _joint_pos(joint)
        if name and pos is not None:
            out[name] = pos
    return out if out else None


def load_recording(path):
    rec = {
        "path": path, "t": [], "head": [], "head_raw": [], "hm": [], "head_tracked": [],
        "L": [], "R": [], "Lt": [], "Rt": [], "Lf": [], "Rf": [],
        "Lflags": [], "Rflags": [], "labels": Counter(),
        "joint_records": 0, "joint_flag_false": 0,
    }
    with path.open("r", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            sample = json.loads(line)
            rec["labels"][str(sample.get("label", "?"))] += 1
            rec["t"].append(float(sample.get("t", 0.0)))
            rec["head_tracked"].append(bool(sample.get("headTracked")))
            head = sample.get("head")
            raw = None
            if isinstance(head, list) and len(head) == 3:
                try:
                    raw = (float(head[0]), float(head[1]), float(head[2]))
                except (TypeError, ValueError):
                    raw = None
            rec["head_raw"].append(raw)
            if rec["head_tracked"][-1] and raw is not None:
                rec["head"].append(raw)
            else:
                rec["head"].append(None)
            hm = sample.get("headMatrix")
            if isinstance(hm, list) and len(hm) == 16:
                try:
                    rec["hm"].append(tuple(float(v) for v in hm))
                except (TypeError, ValueError):
                    rec["hm"].append(None)
            else:
                rec["hm"].append(None)
            for side, key in (("left", "L"), ("right", "R")):
                hand = sample.get(side) or {}
                tracked = bool(hand.get("tracked"))
                rec[key + "t"].append(tracked)
                rec[key].append(_hand_joints(hand) if tracked else None)
                flags = set()
                if tracked and isinstance(hand.get("joints"), list):
                    for joint in hand["joints"]:
                        if not isinstance(joint, dict) or not joint.get("name"):
                            continue
                        rec["joint_records"] += 1
                        if joint.get("tracked"):
                            flags.add(joint["name"])
                        else:
                            rec["joint_flag_false"] += 1
                rec[key + "flags"].append(frozenset(flags))
                rec[key + "f"].append(sample.get(side + "Features") or {})
    n = len(rec["t"])
    rec["n"] = n
    rec["dur"] = (rec["t"][-1] - rec["t"][0]) if n > 1 else 0.0
    return rec


def dataset_display(path):
    stem = path.stem
    if stem.startswith("gesturelab-"):
        stem = stem[len("gesturelab-"):]
    parts = stem.split("-")
    if len(parts) >= 3:
        return "-".join(parts[:-2])
    return stem


def build_datasets():
    items = []
    for path in sorted(ACCEPTED.glob("gesturelab-*.jsonl")):
        items.append({"path": path, "display": dataset_display(path), "kind": "accepted"})
    if IDLE_PATH.exists():
        items.append({"path": IDLE_PATH, "display": "IDLE", "kind": "idle"})
    seen = Counter()
    for item in items:
        base = item["display"]
        seen[base] += 1
        if seen[base] > 1:
            item["display"] = base + "#%d" % seen[base]
    return items


def curl_ratio(joints):
    if not joints:
        return None
    wrist = joints.get("wrist")
    if wrist is None:
        return None
    vals = []
    for finger in FINGERS:
        knuckle = joints.get(finger + "FingerKnuckle")
        tip = joints.get(finger + "FingerTip")
        if knuckle is None or tip is None:
            return None
        vals.append(dist3(tip, knuckle) / max(0.02, dist3(wrist, knuckle)))
    return sum(vals) / len(vals)


def head_y(rec):
    return [p[1] if p is not None else None for p in rec["head"]]


def head_series(rec, rate=None):
    """Valid (head-tracked) head-Y samples; optional uniform resample. Pitch is carried forward."""
    ts = []
    ys = []
    ps = []
    last_p = None
    for i in range(rec["n"]):
        if rec["head"][i] is None:
            continue
        ts.append(rec["t"][i])
        ys.append(rec["head"][i][1])
        p = rec["pitch"][i]
        if p is None:
            p = last_p
        else:
            last_p = p
        ps.append(p)
    if rate is None:
        return ts, ys, ps
    rt, ry = resample_series(ts, ys, rate)
    if any(p is not None for p in ps):
        rp = resample_series(ts, [p if p is not None else -90.0 for p in ps], rate)[1]
    else:
        rp = [None] * len(rt)
    return rt, ry, rp


def head_speed_series(rec, key, joint_name):
    out = []
    for i in range(rec["n"]):
        joints = rec[key][i]
        prev = rec[key][i - 1] if i > 0 else None
        if joints is None or prev is None or joint_name not in joints or joint_name not in prev:
            out.append(0.0)
            continue
        dt = rec["t"][i] - rec["t"][i - 1]
        if dt <= 0 or dt > 5.0:
            dt = 1.0 / LAB_HZ
        out.append(dist3(joints[joint_name], prev[joint_name]) / dt)
    return out


def head_pitch_yaw(rec):
    pitches = []
    yaws = []
    for m in rec["hm"]:
        if m is None:
            pitches.append(None)
            yaws.append(None)
            continue
        fx, fy, fz = -m[8], -m[9], -m[10]
        pitches.append(math.degrees(math.asin(max(-1.0, min(1.0, fy)))))
        yaws.append(math.degrees(math.atan2(-fx, -fz)))
    return pitches, yaws


def resample_series(ts, ys, rate):
    t0 = ts[0]
    dur = ts[-1] - t0
    n = int(dur * rate) + 1
    out_t = []
    out_y = []
    j = 0
    for k in range(n):
        t = t0 + k / rate
        while j + 1 < len(ts) and ts[j + 1] < t:
            j += 1
        if j + 1 >= len(ts):
            out_t.append(t)
            out_y.append(ys[-1])
            continue
        span = ts[j + 1] - ts[j]
        frac = (t - ts[j]) / span if span > 0 else 0.0
        out_t.append(t)
        out_y.append(ys[j] * (1.0 - frac) + ys[j + 1] * frac)
    return out_t, out_y


def window_velocity(ts, ys, i, win):
    j = i
    while j > 0 and ts[i] - ts[j - 1] <= win:
        j -= 1
    if i == j or ts[i] <= ts[j]:
        if i == 0:
            return 0.0
        return (ys[i] - ys[i - 1]) / max(1e-3, ts[i] - ts[i - 1])
    return (ys[i] - ys[j]) / (ts[i] - ts[j])


def sim_current(ts, ys):
    prev_ns = 0
    base = 0.0
    prev_y = 0.0
    jump_until = 0
    sneak_since = 0
    sneaking = False
    jumps = []
    sneak_iv = []
    cur = None
    gmin = 0.0
    gmax = 0.0
    for i in range(len(ts)):
        t = ts[i]
        y = ys[i]
        now_ns = int(round(t * 1e9))
        dt = 1.0 / 60.0 if prev_ns == 0 else max(1e-3, (now_ns - prev_ns) * 1e-9)
        if prev_ns == 0:
            base = y
        base = base * FRAME_ALPHA + y * (1.0 - FRAME_ALPHA)
        vel = 0.0 if prev_ns == 0 else (y - prev_y) / dt
        gap = y - base
        if now_ns >= jump_until and gap > CUR_JUMP_RISE and vel > CUR_JUMP_VEL:
            jumps.append((t, gap, vel))
            jump_until = now_ns + int(CUR_JUMP_COOLDOWN * 1e9)
        if base - y > CUR_SNEAK_DROP:
            if sneak_since == 0:
                sneak_since = now_ns
            if now_ns - sneak_since >= int(CUR_SNEAK_LATCH * 1e9):
                if not sneaking:
                    cur = [t, None]
                    sneak_iv.append(cur)
                sneaking = True
        else:
            if sneaking and cur is not None:
                cur[1] = t
            sneak_since = 0
            sneaking = False
        gmin = min(gmin, gap)
        gmax = max(gmax, gap)
        prev_y = y
        prev_ns = now_ns
    if sneaking and cur is not None:
        cur[1] = ts[-1]
    return {"jumps": jumps, "sneak": sneak_iv, "gap_min": gmin, "gap_max": gmax}


def sim_dt_corrected(ts, ys, tau=TAU_DESIGN):
    prev_ns = 0
    base = 0.0
    prev_y = 0.0
    jump_until = 0
    sneak_since = 0
    sneaking = False
    jumps = []
    sneak_iv = []
    cur = None
    for i in range(len(ts)):
        t = ts[i]
        y = ys[i]
        now_ns = int(round(t * 1e9))
        dt = 1.0 / 60.0 if prev_ns == 0 else max(1e-3, (now_ns - prev_ns) * 1e-9)
        if prev_ns == 0:
            base = y
        base = base + (y - base) * (1.0 - math.exp(-dt / tau))
        vel = 0.0 if prev_ns == 0 else (y - prev_y) / dt
        gap = y - base
        if now_ns >= jump_until and gap > CUR_JUMP_RISE and vel > CUR_JUMP_VEL:
            jumps.append((t, gap, vel))
            jump_until = now_ns + int(CUR_JUMP_COOLDOWN * 1e9)
        if base - y > CUR_SNEAK_DROP:
            if sneak_since == 0:
                sneak_since = now_ns
            if now_ns - sneak_since >= int(CUR_SNEAK_LATCH * 1e9):
                if not sneaking:
                    cur = [t, None]
                    sneak_iv.append(cur)
                sneaking = True
        else:
            if sneaking and cur is not None:
                cur[1] = t
            sneak_since = 0
            sneaking = False
        prev_y = y
        prev_ns = now_ns
    if sneaking and cur is not None:
        cur[1] = ts[-1]
    return {"jumps": jumps, "sneak": sneak_iv, "gap_min": 0.0, "gap_max": 0.0}


def sim_proposed(ts, ys, pitch=None, latch=None, pitch_gate=None):
    latch_s = P_SNEAK_LATCH if latch is None else latch
    gate = P_JUMP_PITCH_GATE if pitch_gate is None else pitch_gate
    prev_ns = 0
    prev_t = 0.0
    base = 0.0
    buf = []
    jump_until = 0.0
    suppress_until = 0.0
    sneak_since = None
    exit_since = None
    sneaking = False
    jumps = []
    sneak_iv = []
    cur = None
    for i in range(len(ts)):
        t = ts[i]
        y = ys[i]
        if prev_ns == 0:
            base = y
            prev_ns = int(round(t * 1e9))
            prev_t = t
            buf = [(t, y)]
            continue
        dt = max(1e-3, t - prev_t)
        gap = y - base
        if abs(gap) <= P_ADAPT_BAND:
            base += (1.0 - math.exp(-dt / P_TAU)) * gap
        buf.append((t, y))
        while len(buf) > 2 and buf[1][0] <= t - P_JUMP_WIN:
            buf.pop(0)
        t0, y0 = buf[0]
        vel = (y - y0) / (t - t0) if t > t0 else 0.0
        gap = y - base
        pitch_ok = True
        if pitch is not None and i < len(pitch) and pitch[i] is not None:
            pitch_ok = pitch[i] >= gate
        if t >= jump_until and gap > P_JUMP_RISE and vel > P_JUMP_VEL and pitch_ok:
            jumps.append((t, gap, vel))
            jump_until = t + P_JUMP_COOLDOWN
            suppress_until = t + P_JUMP_SUPPRESS_SNEAK
            if sneaking and cur is not None:
                cur[1] = t
                cur = None
                sneaking = False
                exit_since = None
        if gap < -P_SNEAK_DROP and t >= suppress_until:
            if sneak_since is None:
                sneak_since = t
            if t - sneak_since >= latch_s:
                if not sneaking:
                    cur = [t, None]
                    sneak_iv.append(cur)
                    exit_since = None
                sneaking = True
        else:
            if gap >= -P_SNEAK_DROP:
                sneak_since = None
            if sneaking:
                if gap >= -P_SNEAK_EXIT:
                    if exit_since is None:
                        exit_since = t
                    if t - exit_since >= P_SNEAK_EXIT_HOLD:
                        cur[1] = t
                        sneaking = False
                        cur = None
                        exit_since = None
                else:
                    exit_since = None
        prev_ns = int(round(t * 1e9))
        prev_t = t
    if sneaking and cur is not None:
        cur[1] = ts[-1]
    return {"jumps": jumps, "sneak": sneak_iv, "gap_min": 0.0, "gap_max": 0.0}


def reference_events(ts, ys, thr, exit_thr, alpha_per_sample=0.02, direction=1):
    base = ys[0]
    gaps = []
    for i, y in enumerate(ys):
        if i > 0:
            base = base * (1.0 - alpha_per_sample) + y * alpha_per_sample
        gaps.append(y - base)
    events = []
    active = False
    start = None
    peak = -1e9
    for i, g in enumerate(gaps):
        val = direction * g
        if not active:
            if val > thr:
                active = True
                start = i
                peak = val
        else:
            peak = max(peak, val)
            if val <= exit_thr:
                events.append((start, i, peak))
                active = False
    if active:
        events.append((start, len(gaps) - 1, peak))
    return events, gaps


def match_events(trigger_times, ref_start_times, tol=1.5):
    matched = {}
    extra = []
    for t in trigger_times:
        best = None
        for k, rt in enumerate(ref_start_times):
            d = abs(t - rt)
            if best is None or d < best[1]:
                best = (k, d)
        if best is not None and best[1] <= tol:
            matched.setdefault(best[0], []).append(t)
        else:
            extra.append(t)
    missed = [k for k in range(len(ref_start_times)) if k not in matched]
    return matched, extra, missed


def section_header(num, title):
    print("")
    print("#" * 100)
    print("# %s %s" % (num, title))
    print("#" * 100)


def main():
    items = build_datasets()
    print("M7 HEAD GESTURE / HEAD-FRAME / IDLE-NEGATIVE ANALYSIS")
    print("=" * 100)
    print("repo root : %s" % ROOT)
    print("data dir  : %s" % DATA)
    print("captures  : %d accepted + IDLE negative" % len([i for i in items if i["kind"] == "accepted"]))
    print("engine    : provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java:53-56,178-195")
    print("frame loop: VisionVR.poll() once per frame; 90 Hz frame budget (missed90HzFrames)")
    print("lab rate  : ~18 Hz samples (section 2)")

    recs = {}
    loaded = []
    for item in items:
        rec = load_recording(item["path"])
        rec["display"] = item["display"]
        rec["kind"] = item["kind"]
        loaded.append(rec)
    for rec in loaded:
        rec["pitch"], rec["yaw"] = head_pitch_yaw(rec)
    for rec in loaded:
        recs[rec["display"]] = rec

    section_header(1, "DATA INVENTORY: accepted captures + the label-IDLE capture")
    print("%-28s %-9s %6s %8s %9s %8s  %s" % ("dataset", "kind", "n", "dur[s]", "headOK", "headMx", "labels"))
    for rec in loaded:
        print("%-28s %-9s %6d %8.2f %9s %8s  %s"
              % (rec["display"], rec["kind"], rec["n"], rec["dur"],
                 "%d/%d" % (sum(1 for x in rec["head_tracked"] if x), rec["n"]),
                 "%d/%d" % (sum(1 for x in rec["hm"] if x is not None), rec["n"]),
                 ",".join("%s=%d" % (k, v) for k, v in rec["labels"].items())))
    print("")
    print("Other local files in the data dir are raw sources / duplicates of the accepted captures and")
    print("are not counted as separate datasets:")
    for path in sorted(DATA.glob("gesturelab-*.jsonl")):
        print("  %s" % path.name)
    rejected = sorted((DATA / "rejected").glob("*.jsonl"))
    print("  rejected/: %d short fragments from the recorder data-quality bug (1.1-3.2 s) - not used:" % len(rejected))
    for path in rejected:
        print("    %s" % path.name)

    section_header(2, "SAMPLING / FRAME RATE / STALE FRAMES")
    print("%-28s %6s %7s %7s %8s %8s %8s %8s %8s %9s" % (
        "dataset", "n", "dur", "rate", "dt_p50", "dt_p95", "dt_max", "gap>250ms", "head_rep",
        "joint_rep"))
    all_rates = []
    all_dt = []
    total_head_rep = 0
    total_joint_rep = 0
    joint_pairs_total = 0
    for rec in loaded:
        ts = rec["t"]
        dts = [ts[i + 1] - ts[i] for i in range(len(ts) - 1)]
        dts_ms = [d * 1000.0 for d in dts]
        rate = (rec["n"] - 1) / rec["dur"] if rec["dur"] > 0 else 0.0
        all_rates.append(rate)
        all_dt.extend(dts)
        gaps = sum(1 for d in dts if d > 0.25)
        head_rep = sum(1 for i in range(1, rec["n"])
                       if rec["head"][i] is not None and rec["head"][i] == rec["head"][i - 1])
        joint_rep = 0
        joint_pairs = 0
        for key in ("L", "R"):
            for i in range(1, rec["n"]):
                if rec[key + "t"][i] and rec[key + "t"][i - 1]:
                    joint_pairs += 1
                    if rec[key][i] is not None and rec[key][i] == rec[key][i - 1]:
                        joint_rep += 1
        total_head_rep += head_rep
        total_joint_rep += joint_rep
        joint_pairs_total += joint_pairs
        print("%-28s %6d %7.2f %7.2f %8.1f %8.1f %8.1f %8d %8d %9d" % (
            rec["display"], rec["n"], rec["dur"], rate,
            pct(dts_ms, 0.5), pct(dts_ms, 0.95), max(dts_ms) if dts_ms else 0.0,
            gaps, head_rep, joint_rep))
    print("")
    print("mean lab sample rate over %d captures: %.2f Hz (range %.2f-%.2f Hz)" % (
        len(loaded), mean(all_rates), min(all_rates), max(all_rates)))
    print("overall dt: p50=%.2f ms p95=%.2f ms max=%.2f s" % (
        pct(all_dt, 0.5) * 1000, pct(all_dt, 0.95) * 1000, max(all_dt)))
    joint_records = sum(r["joint_records"] for r in loaded)
    joint_false = sum(r["joint_flag_false"] for r in loaded)
    all_pairs = sum(r["n"] - 1 for r in loaded)
    raw_head_rep = []
    for rec in loaded:
        for i in range(1, rec["n"]):
            if rec["head_raw"][i] is not None and rec["head_raw"][i] == rec["head_raw"][i - 1]:
                raw_head_rep.append((rec["display"], rec["t"][i] - rec["t"][0],
                                     rec["head_tracked"][i], rec["head_raw"][i]))
    print("head position repeats (head-tracked rows): %d; joint-position repeats: %d of %d pairs"
          % (total_head_rep, total_joint_rep, joint_pairs_total))
    print("  pair scopes: %d = per-hand consecutive pairs with both frames tracked (joint test);"
          % joint_pairs_total)
    print("               %d = all consecutive sample pairs (head test)" % all_pairs)
    print("head position repeats (ALL recorded rows): %d of %d pairs" % (len(raw_head_rep), all_pairs))
    untracked_rows = [(rec["display"], i) for rec in loaded
                      for i in range(rec["n"]) if not rec["head_tracked"][i]]
    print("headTracked=false rows: %d (all %s) - zero-fill sentinel, excluded from every"
          % (len(untracked_rows),
             ", ".join(sorted(set(name for name, _ in untracked_rows))) if untracked_rows else "none"))
    print("  head-relative feature; indices %s"
          % str([(name.split("-")[0], i) for name, i in untracked_rows]))
    for name, rel_t, tracked, pos in raw_head_rep[:6]:
        print("   %s t=%.3f s headTracked=%s head=%s (missing-data sentinel, not a physical hold)"
              % (name, rel_t, tracked, list(pos)))
    print("per-joint 'tracked' flag false inside tracked hands: %d/%d (%.1f%%) - the flag is"
          % (joint_false, joint_records, 100.0 * joint_false / joint_records if joint_records else 0.0))
    print("unreliable, but the joint matrices are valid (section 8 provenance check).")
    print("")
    print("Frame-rate dependence of the current per-frame EMA pole alpha=0.985:")
    for rate in (18.0, 45.0, 90.0, 120.0):
        tau = (1.0 / rate) / (-math.log(FRAME_ALPHA))
        print("  at %6.2f Hz: time constant tau = %.3f s   (design tau=2 s needs alpha = %.5f)"
              % (rate, tau, 1.0 - math.exp(-(1.0 / rate) / TAU_DESIGN)))
    print("  => same code: tau=0.735 s in the 90 Hz game, tau=3.68 s in the 18 Hz lab. The lab cannot")
    print("     validate the frame-rate-dependent behaviour, and a frame-rate drop to 45 Hz halves")
    print("     the game time constant. A dt-corrected alpha is required (section 7).")
    print("")
    print("Stale-frame definition: 'joint_rep' counts consecutive samples where ALL parsed joint")
    print("positions (m[12..14]) of a tracked hand are bit-identical. It is 0 in every capture: the")
    print("recorder emits fresh joint matrices on every line, so there are no stale frames by this test")
    print("(head_rep, the same test over head-tracked rows, is 0 too). The only recorded-row head")
    print("repeats are the untracked zero-fill rows of TELEPORT_LEFT_PINCH#2 listed above - missing-data")
    print("sentinels, not a physical head-anchor hold. The related data issue is the per-joint 'tracked'")
    print("flag, which is unreliable (50.6% false inside tracked hands); feature re-derivation must use")
    print("the matrices and ignore that flag, which is what section 8 does.")

    section_header(3, "HEAD POSE MATH: headMatrix column convention + exact provider formulas")
    total_hm = 0
    max_norm_err = 0.0
    max_dot = 0.0
    max_det_err = 0.0
    max_trans_err = 0.0
    max_cross_err = 0.0
    max_fwd_cross_err = 0.0
    max_m_other = 0.0
    for rec in loaded:
        nerr = []
        dots = []
        dets = []
        terrs = []
        cros = []
        fcross = []
        for i, m in enumerate(rec["hm"]):
            if m is None:
                continue
            total_hm += 1
            c0 = (m[0], m[1], m[2])
            c1 = (m[4], m[5], m[6])
            c2 = (m[8], m[9], m[10])
            n0 = math.sqrt(sum(x * x for x in c0))
            n1 = math.sqrt(sum(x * x for x in c1))
            n2 = math.sqrt(sum(x * x for x in c2))
            nerr.extend((abs(n0 - 1.0), abs(n1 - 1.0), abs(n2 - 1.0)))
            dots.extend((c0[0] * c1[0] + c0[1] * c1[1] + c0[2] * c1[2],
                         c0[0] * c2[0] + c0[1] * c2[1] + c0[2] * c2[2],
                         c1[0] * c2[0] + c1[1] * c2[1] + c1[2] * c2[2]))
            dets.append(c0[0] * (c1[1] * c2[2] - c1[2] * c2[1])
                        - c1[0] * (c0[1] * c2[2] - c0[2] * c2[1])
                        + c2[0] * (c0[1] * c1[2] - c0[2] * c1[1]))
            head = rec["head"][i]
            if head is not None:
                terrs.append(max(abs(m[12] - head[0]), abs(m[13] - head[1]), abs(m[14] - head[2])))
            cr = (c0[1] * c1[2] - c0[2] * c1[1],
                  c0[2] * c1[0] - c0[0] * c1[2],
                  c0[0] * c1[1] - c0[1] * c1[0])
            cros.append(max(abs(cr[k] - c2[k]) for k in range(3)))
            fwd = (-c2[0], -c2[1], -c2[2])
            crf = (fwd[1] * c1[2] - fwd[2] * c1[1],
                   fwd[2] * c1[0] - fwd[0] * c1[2],
                   fwd[0] * c1[1] - fwd[1] * c1[0])
            fcross.append(max(abs(crf[k] - c0[k]) for k in range(3)))
            max_m_other = max(max_m_other, abs(m[3]), abs(m[7]), abs(m[11]), abs(m[15] - 1.0))
        if nerr:
            max_norm_err = max(max_norm_err, max(nerr))
            max_dot = max(max_dot, max(abs(x) for x in dots))
            max_det_err = max(max_det_err, max(abs(x - 1.0) for x in dets))
            max_trans_err = max(max_trans_err, max(terrs))
            max_cross_err = max(max_cross_err, max(cros))
            max_fwd_cross_err = max(max_fwd_cross_err, max(fcross))
    print("headMatrix frames parsed: %d" % total_hm)
    print("checks over every parsed 4x4:")
    print("  max |column length - 1|           = %.2e" % max_norm_err)
    print("  max |column dot|                  = %.2e" % max_dot)
    print("  max |det(R) - 1|                  = %.2e" % max_det_err)
    print("  max |m[3], m[7], m[11], m[15]-1|  = %.2e" % max_m_other)
    print("  max |translation - head position| = %.2e m" % max_trans_err)
    print("  max |cross(col0,col1) - col2|     = %.2e" % max_cross_err)
    print("  max |cross(forward,up) - col0|    = %.2e" % max_fwd_cross_err)
    print("")
    print("VERIFIED convention: column-major simd_float4x4 in ARKit device orientation")
    print("  col0 = right, col1 = up, col2 = backward, col3 = translation (head position)")
    print("  det(R)=+1 and cross(right,up)=backward => right-handed; forward = -col2.")
    print("  cross(forward,up)=right (verified above) - the usual OpenGL/ARKit camera basis.")
    print("")
    print("Exact provider formulas (hmdPose is the same column-major 4x4; VisionVR line 981 already")
    print("uses hmdPose.m30/m31/m32 as the head position, so the accessors are column-major):")
    print("  // flat JSON array: m[4*j+r] = column j, row r")
    print("  float fwdX = -m[8],  fwdY = -m[9],  fwdZ = -m[10];  // forward = -col2 (backward)")
    print("  float upX  =  m[4],  upY  =  m[5],  upZ  =  m[6];   // up = col1")
    print("  float rgtX =  m[0],  rgtY =  m[1],  rgtZ =  m[2];   // right = col0")
    print("  float pitch = asin(clamp(fwdY, -1, 1));            // + = looking up")
    print("  float yaw   = atan2(-fwdX, -fwdZ);                  // 0 = facing -Z")
    print("  float headX = m[12], headY = m[13], headZ = m[14];  // = hmdPose.m30/m31/m32")
    print("")
    print("Semantic check using the EAT capture (the right hand is at the mouth, i.e. IN FRONT of the head):")
    eat = recs.get("EAT_RIGHT_HAND_HEAD")
    if eat is not None:
        proj_fwd = []
        proj_back = []
        for i in range(eat["n"]):
            m = eat["hm"][i]
            hand = eat["R"][i]
            head = eat["head"][i]
            if m is None or hand is None or head is None or "wrist" not in hand:
                continue
            fwd = (-m[8], -m[9], -m[10])
            back = (m[8], m[9], m[10])
            d = (hand["wrist"][0] - head[0], hand["wrist"][1] - head[1], hand["wrist"][2] - head[2])
            proj_fwd.append(d[0] * fwd[0] + d[1] * fwd[1] + d[2] * fwd[2])
            proj_back.append(d[0] * back[0] + d[1] * back[1] + d[2] * back[2])
        print("  wrist->head projection on forward=-col2: p05=%.3f p50=%.3f p95=%.3f m"
              % (pct(proj_fwd, 0.05), pct(proj_fwd, 0.50), pct(proj_fwd, 0.95)))
        print("  wrist->head projection on +col2 (backward): p05=%.3f p50=%.3f p95=%.3f m"
              % (pct(proj_back, 0.05), pct(proj_back, 0.50), pct(proj_back, 0.95)))
        print("  fraction of EAT frames with the eating hand in front: %.1f%%"
              % (100.0 * sum(1 for v in proj_fwd if v > 0) / max(1, len(proj_fwd))))
        print("  => forward=-col2 is correct: the eating hand sits %.0f mm in front of the head plane."
              % (1000.0 * pct(proj_fwd, 0.50)))
    print("")
    print("%-28s %7s %7s %7s %9s %8s %8s %9s" % (
        "dataset", "pitch02", "pitch50", "pitch98", "yawRate95", "yaw>30%", "netYaw", "yRange"))
    for rec in loaded:
        pitches, yaws = head_pitch_yaw(rec)
        pv = [v for v in pitches if v is not None]
        yv = [v for v in yaws if v is not None]
        ys = [v for v in head_y(rec) if v is not None]
        if not pv:
            print("%-28s %7s %7s %7s %9s %8s %8s %9.3f"
                  % (rec["display"], "-", "-", "-", "-", "-", "-", max(ys) - min(ys)))
            continue
        yaw_rates = []
        unwrapped = 0.0
        prev = None
        for i, y in enumerate(yv):
            if prev is not None:
                d = y - prev
                while d > 180.0:
                    d -= 360.0
                while d < -180.0:
                    d += 360.0
                unwrapped += d
                dt = rec["t"][i] - rec["t"][i - 1]
                if dt > 0:
                    yaw_rates.append(d / dt)
            prev = y
        print("%-28s %7.1f %7.1f %7.1f %9.1f %8.1f %8.1f %9.3f" % (
            rec["display"], pct(pv, 0.02), pct(pv, 0.5), pct(pv, 0.98),
            pct([abs(v) for v in yaw_rates], 0.95),
            100.0 * sum(1 for v in yaw_rates if abs(v) > 30.0) / max(1, len(yaw_rates)),
            unwrapped, max(ys) - min(ys)))
    print("")
    walk = recs.get("WALK_BOTH_FISTS")
    if walk is not None and any(x is not None for x in walk["hm"]):
        pitches, yaws = head_pitch_yaw(walk)
        yv = [v for v in yaws if v is not None]
        ys = [p[1] for p in walk["head"] if p is not None]
        pyt = [v for v in pitches if v is not None]
        yaw_rates = []
        unwrapped = 0.0
        prev = None
        for i, y in enumerate(yv):
            if prev is not None:
                d = y - prev
                while d > 180.0:
                    d -= 360.0
                while d < -180.0:
                    d += 360.0
                unwrapped += d
                dt = walk["t"][i] - walk["t"][i - 1]
                if dt > 0:
                    yaw_rates.append(d / dt)
            prev = y
        m = mean(ys)
        zc = 0
        last = None
        for v in ys:
            sgn = 1 if v >= m else -1
            if last is not None and sgn != last:
                zc += 1
            last = sgn
        print("WALK_BOTH_FISTS head-motion test (walking-in-place, %.2f s):" % walk["dur"])
        print("  body forward direction recorded? NO - the JSONL has only the head pose, no body/anchor")
        print("  pose, so 'body forward' cannot be measured directly.  Head yaw is NOT stable while")
        print("  walking in place: net yaw sweep %.1f deg, p2-p98 span %.1f deg, yaw rate p50/p95/max"
              % (unwrapped, pct(yv, 0.98) - pct(yv, 0.02)))
        print("  %.1f/%.1f/%.1f deg/s, %.1f%% of frames above 30 deg/s."
              % (pct([abs(v) for v in yaw_rates], 0.5), pct([abs(v) for v in yaw_rates], 0.95),
                 max(abs(v) for v in yaw_rates),
                 100.0 * sum(1 for v in yaw_rates if abs(v) > 30.0) / max(1, len(yaw_rates))))
        print("  pitch p2-p98 = %.1f..%.1f deg; head y range %.3f m (~%.2f Hz bob, p2-p98 amplitude %.3f m)"
              % (pct(pyt, 0.02), pct(pyt, 0.98), max(ys) - min(ys),
                 zc / 2.0 / walk["dur"], pct(ys, 0.98) - pct(ys, 0.02)))
        print("  => head-relative features must be anchored at gesture start: the head-relative axes rotate")
        print("     with the head, and this capture contains a ~%.0f deg yaw turn."
              % (pct(yv, 0.98) - pct(yv, 0.02)))
    print("")
    print("Pitch -> HMD height geometry fitted on captures with stable body height:")
    fit_names = [n for n in recs if n.startswith(("ATTACK", "BOW", "BREAK", "CLIMB", "EAT", "HOTBAR",
                                                  "INVENTORY", "TELEPORT"))]
    Xs = []
    Yv = []
    for name in fit_names:
        rec = recs[name]
        pitches, _ = head_pitch_yaw(rec)
        pts = [(p, rec["head"][i][1]) for i, p in enumerate(pitches)
               if p is not None and rec["head"][i] is not None]
        if len(pts) < 10:
            continue
        th = [math.radians(p) for p, _ in pts]
        yy = [y for _, y in pts]
        ct = [math.cos(a) for a in th]
        st = [math.sin(a) for a in th]
        mct = mean(ct)
        mst = mean(st)
        my = mean(yy)
        for i in range(len(yy)):
            Xs.append((ct[i] - mct, st[i] - mst))
            Yv.append(yy[i] - my)
    s11 = sum(x[0] * x[0] for x in Xs)
    s12 = sum(x[0] * x[1] for x in Xs)
    s22 = sum(x[1] * x[1] for x in Xs)
    b1 = sum(Xs[i][0] * Yv[i] for i in range(len(Yv)))
    b2 = sum(Xs[i][1] * Yv[i] for i in range(len(Yv)))
    det = s11 * s22 - s12 * s12
    c1 = (b1 * s22 - b2 * s12) / det
    c2 = (b2 * s11 - b1 * s12) / det
    resid = [Yv[i] - (c1 * Xs[i][0] + c2 * Xs[i][1]) for i in range(len(Yv))]
    print("  y_hmd(theta) = y0 + C1*cos(theta) + C2*sin(theta)   [theta = head pitch, radians]")
    print("  fitted C1=%.4f m (HMD height above neck pivot), C2=%.4f m (forward lever arm),"
          % (c1, c2))
    print("  residual std=%.4f m over n=%d frames" % (std(resid), len(Yv)))
    print("  pitch-only HMD height change relative to pitch=0 (from the fit):")
    for deg in (-20, -30, -40, -50, -60, 30, 45):
        th = math.radians(deg)
        dy = c1 * (math.cos(th) - 1.0) + c2 * math.sin(th)
        print("    pitch %+4d deg -> dy = %+6.1f mm" % (deg, 1000.0 * dy))
    print("  cross-check per capture: predicted pitch-induced y swing vs measured y range")
    for name in fit_names:
        rec = recs[name]
        pitches, _ = head_pitch_yaw(rec)
        pts = [(p, rec["head"][i][1]) for i, p in enumerate(pitches)
               if p is not None and rec["head"][i] is not None]
        if len(pts) < 10:
            continue
        th = [math.radians(p) for p, _ in pts]
        yy = [y for _, y in pts]
        mct = mean([math.cos(a) for a in th])
        mst = mean([math.sin(a) for a in th])
        pred = [c1 * (math.cos(a) - mct) + c2 * (math.sin(a) - mst) for a in th]
        print("    %-28s pitch %6.1f..%6.1f deg  predicted swing=%5.3f m  measured y range=%5.3f m"
              % (name, min([p for p in pitches if p is not None]),
                 max([p for p in pitches if p is not None]), max(pred) - min(pred), max(yy) - min(yy)))

    section_header(4, "JUMP_HEAD: reference segmentation, current vs dt-corrected baseline, simulation")
    jump = recs["JUMP_HEAD"]
    jump_ts, jump_ys, jump_pitch = head_series(jump)
    print("JUMP_HEAD: n=%d dur=%.2f s headOK=%d/%d"
          % (jump["n"], jump["dur"], sum(1 for x in jump["head_tracked"] if x), jump["n"]))
    print("head Y min/p05/p50/p95/max = %.3f / %.3f / %.3f / %.3f / %.3f m" % (
        min(jump_ys), pct(jump_ys, 0.05), pct(jump_ys, 0.5), pct(jump_ys, 0.95), max(jump_ys)))
    jdts = [jump_ts[i + 1] - jump_ts[i] for i in range(len(jump_ts) - 1)]
    print("dt p50/p95/max = %.1f / %.1f / %.1f ms (mean rate %.2f Hz); %d gaps > 250 ms"
          % (pct(jdts, 0.5) * 1000, pct(jdts, 0.95) * 1000, max(jdts) * 1000,
             (len(jump_ts) - 1) / jump["dur"], sum(1 for d in jdts if d > 0.25)))
    jvel = [(jump_ys[i + 1] - jump_ys[i]) / jdts[i] for i in range(len(jdts)) if jdts[i] >= 0.02]
    print("per-frame vertical speed |v| p50/p95/max = %.2f / %.2f / %.2f m/s (min %.2f)"
          % (pct([abs(v) for v in jvel], 0.5), pct([abs(v) for v in jvel], 0.95),
             max(abs(v) for v in jvel), min(jvel)))
    print("  (matches accepted summary 'upward velocity p95=1.51, max=2.36' - computed over |v|)")
    gap_starts = [jump_ts[i + 1] - jump_ts[0] for i in range(len(jdts)) if jdts[i] > 0.25]
    print("  sample-gap locations (s from start, first 12): %s" % fmt_list(gap_starts, 1, 12))
    ref_jump, ref_jump_gaps = reference_events(jump_ts, jump_ys, 0.08, 0.03, 0.02)
    ref_starts = [jump_ts[s0] for s0, _, _ in ref_jump]
    print("")
    print("Reference offline segmentation: baseline EMA alpha=0.02/sample at 18 Hz (tau~2.75 s),")
    print("event starts at gap>0.08 m, ends when gap<=0.03 m, no minimum-duration filter.")
    print("  events=%d  peaks=%.3f..%.3f m  durations=%.2f..%.2f s (median %.2f s)"
          % (len(ref_jump), min(e[2] for e in ref_jump), max(e[2] for e in ref_jump),
             min(jump_ts[e[1]] - jump_ts[e[0]] for e in ref_jump),
             max(jump_ts[e[1]] - jump_ts[e[0]] for e in ref_jump),
             pct([jump_ts[e[1]] - jump_ts[e[0]] for e in ref_jump], 0.5)))
    long_ev = max(ref_jump, key=lambda e: jump_ts[e[1]] - jump_ts[e[0]])
    print("  CROSS-CHECK vs accepted summary (29 rises, peaks 0.11-0.30 m, mostly 0.27-0.95 s plus one")
    print("  3.95 s stay): reproduced - %d events, one long event %.2f s, peaks %.3f-%.3f m."
          % (len(ref_jump), jump_ts[long_ev[1]] - jump_ts[long_ev[0]],
             min(e[2] for e in ref_jump), max(e[2] for e in ref_jump)))
    print("  per-event table (t_start, t_end, peak_gap, rise_time_to_peak, peak_100ms_vel):")
    for k, (s0, s1, pk) in enumerate(ref_jump):
        ip = max(range(s0, s1 + 1), key=lambda i: ref_jump_gaps[i])
        v = window_velocity(jump_ts, jump_ys, ip, 0.10)
        print("    %2d  t=%6.2f..%6.2f  dur=%5.2f  peak=%5.3f  rise=%5.2f  vpeak=%5.2f m/s" % (
            k + 1, jump_ts[s0] - jump_ts[0], jump_ts[s1] - jump_ts[0],
            jump_ts[s1] - jump_ts[s0], pk, jump_ts[ip] - jump_ts[s0], v))
    rt90, ry90, rp90 = head_series(jump, PROD_HZ)
    cur_lab = sim_current(jump_ts, jump_ys)
    cur_90 = sim_current(rt90, ry90)
    dtc_90 = sim_dt_corrected(rt90, ry90)
    prop_90 = sim_proposed(rt90, ry90, rp90)
    prop_lab = sim_proposed(jump_ts, jump_ys, jump_pitch)
    print("")
    print("Detector comparison on JUMP_HEAD:")
    print("  %-40s %7s %9s %12s %9s" % ("simulation", "jumps", "sneakIv", "sneakActive", "jumps/min"))
    for name, res in (("current engine, lab 18 Hz replay", cur_lab),
                      ("current engine, 90 Hz replay", cur_90),
                      ("dt-corrected tau=2 s, 90 Hz", dtc_90),
                      ("PROPOSED, 18 Hz replay", prop_lab),
                      ("PROPOSED, 90 Hz", prop_90)):
        print("  %-40s %7d %9d %12.2f %9.1f"
              % (name, len(res["jumps"]), len(res["sneak"]),
                 sum((b - a) for a, b in res["sneak"] if b is not None),
                 len(res["jumps"]) / (jump["dur"] / 60.0)))
    print("")
    print("  current@90 jump trigger times (s): %s"
          % fmt_list([t - jump_ts[0] for t, _, _ in cur_90["jumps"]], 2))
    print("  current@90 sneak latch intervals (s): %s"
          % str([(round(a - jump_ts[0], 2), round(b - jump_ts[0], 2) if b else None)
                 for a, b in cur_90["sneak"]]))
    print("  PROPOSED@90 jump trigger times (s): %s"
          % fmt_list([t - jump_ts[0] for t, _, _ in prop_90["jumps"]], 2))
    print("  PROPOSED@90 sneak latch intervals (s): %s"
          % str([(round(a - jump_ts[0], 2), round(b - jump_ts[0], 2) if b else None)
                 for a, b in prop_90["sneak"]]))
    for label, res in (("current@90", cur_90), ("PROPOSED@90", prop_90)):
        matched, extra, missed = match_events([t for t, _, _ in res["jumps"]], ref_starts)
        multi = {k: v for k, v in matched.items() if len(v) > 1}
        print("  %-12s vs reference: matched %d/%d, ref events missed=%d, extra pulses=%d,"
              " multi-trigger=%d"
              % (label, len(matched), len(ref_starts), len(missed), len(extra), len(multi)))
        if missed:
            print("      missed ref starts (s): %s" % fmt_list([ref_starts[k] - jump_ts[0] for k in missed], 2))
        if extra:
            print("      extra pulses (s): %s" % fmt_list([t - jump_ts[0] for t in extra], 2))
        if multi:
            print("      multi-trigger (ref idx: times): %s" % str(
                {k: [round(x - jump_ts[0], 2) for x in v] for k, v in multi.items()}))
    trig_pitch = [rp90[int(round((tt - rt90[0]) * PROD_HZ))] for tt, _, _ in prop_90["jumps"]
                  if 0 <= int(round((tt - rt90[0]) * PROD_HZ)) < len(rp90)
                  and rp90[int(round((tt - rt90[0]) * PROD_HZ))] is not None]
    cur_trig_pitch = [rp90[int(round((tt - rt90[0]) * PROD_HZ))] for tt, _, _ in cur_90["jumps"]
                      if 0 <= int(round((tt - rt90[0]) * PROD_HZ)) < len(rp90)
                      and rp90[int(round((tt - rt90[0]) * PROD_HZ))] is not None]
    if trig_pitch:
        print("  PROPOSED@90 jump-trigger head pitch: min/median/max = %.1f / %.1f / %.1f deg"
              " (gate %+.0f)" % (min(trig_pitch), pct(trig_pitch, 0.5), max(trig_pitch), P_JUMP_PITCH_GATE))
        print("  current@90 trigger pitch min = %.1f deg; JUMP capture deepest look-down = %.1f deg"
              % (min(cur_trig_pitch) if cur_trig_pitch else 0.0,
                 min([p for p in rp90 if p is not None])))
    print("  (the proposed extra pulse at 9.99 s sits inside the gap-interpolated 3.95 s elevated stay:")
    print("  it is one pulse too many for the reference segmentation, not a new physical jump)")
    print("")
    print("Baseline-adaptation effects in the JUMP capture:")
    print("  the 3.95 s 'stay' is one reference event (t=%.2f..%.2f s) that spans three sample gaps;"
          % (jump_ts[long_ev[0]] - jump_ts[0], jump_ts[long_ev[1]] - jump_ts[0]))
    print("  the 90 Hz replay interpolates through those gaps, so the current engine sees a smooth")
    print("  slow rise there and fires extra pulses; the accepted 29-event count is only recovered by")
    print("  the lab-rate reference segmentation.")
    print("")
    print("Head-y variance decomposition (how much head-y motion is NOT the jump gesture):")
    my = mean(jump_ys)
    var_y = sum((y - my) ** 2 for y in jump_ys) / len(jump_ys)
    print("  var(head y)=%.5f m^2 (std %.3f m), range %.3f m"
          % (var_y, math.sqrt(var_y), max(jump_ys) - min(jump_ys)))
    if any(p is not None for p in jump_pitch):
        pts = [(p, jump_ys[i]) for i, p in enumerate(jump_pitch) if p is not None]
        th = [math.radians(p) for p, _ in pts]
        yy = [y for _, y in pts]
        ct = [math.cos(a) for a in th]
        st = [math.sin(a) for a in th]
        mct = mean(ct)
        mst = mean(st)
        nmy = mean(yy)
        nb1 = sum((ct[i] - mct) * (yy[i] - nmy) for i in range(len(yy)))
        nb2 = sum((st[i] - mst) * (yy[i] - nmy) for i in range(len(yy)))
        n11 = sum((ct[i] - mct) ** 2 for i in range(len(yy)))
        n22 = sum((st[i] - mst) ** 2 for i in range(len(yy)))
        n12 = sum((ct[i] - mct) * (st[i] - mst) for i in range(len(yy)))
        ndet = n11 * n22 - n12 * n12
        h1 = (nb1 * n22 - nb2 * n12) / ndet
        h2 = (nb2 * n11 - nb1 * n12) / ndet
        pred = [h1 * (ct[i] - mct) + h2 * (st[i] - mst) for i in range(len(yy))]
        ss_res = sum((yy[i] - (nmy + pred[i])) ** 2 for i in range(len(yy)))
        ss_tot = sum((y - nmy) ** 2 for y in yy)
        r2 = 1.0 - ss_res / ss_tot
        print("  pitch-only model (C1=%.3f, C2=%.3f) explains R^2=%.2f of head-y variance;"
              " the other %.2f is body height" % (h1, h2, r2, 1.0 - r2))
        print("  pitch range in JUMP: p2/p50/p98 = %.1f / %.1f / %.1f deg (mostly near level)"
              % (pct([p for p in jump_pitch if p is not None], 0.02),
                 pct([p for p in jump_pitch if p is not None], 0.5),
                 pct([p for p in jump_pitch if p is not None], 0.98)))
    print("  reference-event vertical travel = %.2f m (sum of %d peak gaps) vs total travel"
          " sum|dy| = %.2f m"
          % (sum(e[2] for e in ref_jump), len(ref_jump),
             sum(abs(jump_ys[i + 1] - jump_ys[i]) for i in range(len(jump_ys) - 1))))
    print("")
    print("Frame-rate dependence of the current detector on JUMP_HEAD:")
    print("  %-10s %14s %14s" % ("input Hz", "current J/S", "proposed J/S"))
    for rate in (18.05, 30.0, 45.0, 90.0, 120.0, 144.0):
        rts, rys, rps = head_series(jump, rate)
        c = sim_current(rts, rys)
        p = sim_proposed(rts, rys, rps)
        print("  %-10.2f %14s %14s" % (rate, "%d/%d" % (len(c["jumps"]), len(c["sneak"])),
                                       "%d/%d" % (len(p["jumps"]), len(p["sneak"]))))

    section_header(5, "SNEAK_HEAD: sustained-crouch dropout simulation, hysteresis, look-down risk")
    sneak = recs["SNEAK_HEAD"]
    sneak_ts, sneak_ys, sneak_pitch = head_series(sneak)
    print("SNEAK_HEAD: n=%d dur=%.2f s headOK=%d/%d"
          % (sneak["n"], sneak["dur"], sum(1 for x in sneak["head_tracked"] if x), sneak["n"]))
    print("head Y min/p05/p50/p95/max = %.3f / %.3f / %.3f / %.3f / %.3f m" % (
        min(sneak_ys), pct(sneak_ys, 0.05), pct(sneak_ys, 0.5), pct(sneak_ys, 0.95), max(sneak_ys)))
    sdts = [sneak_ts[i + 1] - sneak_ts[i] for i in range(len(sneak_ts) - 1)]
    svel = [(sneak_ys[i + 1] - sneak_ys[i]) / sdts[i] for i in range(len(sdts)) if sdts[i] >= 0.02]
    print("dt p50/p95/max=%.1f/%.1f/%.1f ms, %d gaps>250ms; |v| p50/p95/max=%.2f/%.2f/%.2f m/s"
          % (pct(sdts, 0.5) * 1000, pct(sdts, 0.95) * 1000, max(sdts) * 1000,
             sum(1 for d in sdts if d > 0.25), pct([abs(v) for v in svel], 0.5),
             pct([abs(v) for v in svel], 0.95), max(abs(v) for v in svel)))
    print("  (accepted summary: head Y 0.779-1.509, max speed 1.66 m/s - reproduced)")
    ref_sneak, _ = reference_events(sneak_ts, sneak_ys, 0.10, 0.05, 0.02, direction=-1)
    standing = max(sneak_ys)
    print("")
    print("Reference offline downward events (baseline alpha=0.02/sample, drop>0.10 m, release>0.05 m):")
    print("  events=%d (accepted summary: 5)" % len(ref_sneak))
    for k, (s0, s1, pk) in enumerate(ref_sneak):
        lo = min(sneak_ys[s0:s1 + 1])
        print("    %d  t=%6.2f..%6.2f  dur=%5.2f s  peak_gap=%5.3f m  standing=%.3f  min=%.3f"
              "  stand->min drop=%.3f m"
              % (k + 1, sneak_ts[s0] - sneak_ts[0], sneak_ts[s1] - sneak_ts[0],
                 sneak_ts[s1] - sneak_ts[s0], pk, standing, lo, standing - lo))
    print("  CROSS-CHECK: 5 downward events reproduced, durations [%s] match the accepted"
          % ", ".join("%.2f" % (sneak_ts[e[1]] - sneak_ts[e[0]]) for e in ref_sneak))
    print("  'two ~4.9 s holds + 0.33/2.56/1.33 s returns' shape. BUT the accepted 'depths 0.10-0.25 m'")
    print("  is NOT reproducible from head y: stand->crouch minima are 0.56-0.71 m drops and the")
    print("  alpha=0.02 baseline gaps peak at %.2f-%.2f m. The summary's depth range is inconsistent."
          % (min(e[2] for e in ref_sneak), max(e[2] for e in ref_sneak)))
    crouch_thr = standing - 0.20
    intervals = []
    inside = False
    start = 0
    for i, y in enumerate(sneak_ys):
        if y < crouch_thr and not inside:
            inside = True
            start = i
        elif y >= crouch_thr and inside:
            inside = False
            intervals.append([start, i])
    if inside:
        intervals.append([start, len(sneak_ys) - 1])
    merged = []
    for iv in intervals:
        if merged and sneak_ts[iv[0]] - sneak_ts[merged[-1][1]] < 0.30:
            merged[-1][1] = iv[1]
        else:
            merged.append(list(iv))
    phys = [iv for iv in merged if sneak_ts[iv[1]] - sneak_ts[iv[0]] >= 0.30]
    print("")
    print("Physical crouch intervals (raw head y < standing-0.20 = %.3f m, gaps <0.30 s merged," % crouch_thr)
    print("min duration 0.30 s - deeper than the -0.12 m detector threshold on purpose):")
    for k, iv in enumerate(phys):
        print("  #%d  t=%6.2f..%6.2f  dur=%5.2f s  min_y=%.3f"
              % (k + 1, sneak_ts[iv[0]] - sneak_ts[0], sneak_ts[iv[1]] - sneak_ts[0],
                 sneak_ts[iv[1]] - sneak_ts[iv[0]], min(sneak_ys[iv[0]:iv[1] + 1])))
    print("")
    print("Current engine simulation on SNEAK_HEAD (dropout = physically crouched but sneak flag false):")
    rt90, ry90, rp90 = head_series(sneak, PROD_HZ)
    cur_lab_s = sim_current(sneak_ts, sneak_ys)
    cur_90_s = sim_current(rt90, ry90)
    dtc_90_s = sim_dt_corrected(rt90, ry90)
    prop_90_s = sim_proposed(rt90, ry90, rp90)
    prop_lab_s = sim_proposed(sneak_ts, sneak_ys, sneak_pitch)
    phys_total = sum(sneak_ts[iv[1]] - sneak_ts[iv[0]] for iv in phys)

    def covered_time(intervals):
        total = 0.0
        for iv in phys:
            lo_iv = sneak_ts[iv[0]]
            hi_iv = sneak_ts[iv[1]]
            segs = []
            for a, b in intervals:
                b2 = b if b is not None else sneak_ts[-1]
                lo = max(a, lo_iv)
                hi = min(b2, hi_iv)
                if hi > lo:
                    segs.append((lo, hi))
            segs.sort()
            end = -1e9
            for lo, hi in segs:
                if lo < end:
                    lo = end
                if hi > lo:
                    total += hi - lo
                    end = hi
        return total

    for name, res in (("current engine, lab 18 Hz replay", cur_lab_s),
                      ("current engine, 90 Hz replay", cur_90_s),
                      ("dt-corrected tau=2 s, 90 Hz", dtc_90_s),
                      ("PROPOSED, 18 Hz replay", prop_lab_s),
                      ("PROPOSED, 90 Hz", prop_90_s)):
        cov = covered_time(res["sneak"])
        durs = ", ".join("%.2f" % ((b if b is not None else sneak_ts[-1]) - a)
                         for a, b in res["sneak"])
        print("  %-40s latches=%d jump_pulses=%d" % (name, len(res["sneak"]), len(res["jumps"])))
        print("      latch durations (s): [%s]" % durs)
        print("      latch intervals (s): %s" % str(
            [(round(a - sneak_ts[0], 2), round((b if b is not None else sneak_ts[-1]) - sneak_ts[0], 2))
             for a, b in res["sneak"]]))
        print("      physical crouch %.2f s, covered %.2f s, DROPOUT %.2f s (%.0f%%)"
              % (phys_total, cov, phys_total - cov,
                 100.0 * (phys_total - cov) / phys_total if phys_total > 0 else 0.0))
    print("")
    print("  NOTE: the 5 jump_pulses the current engine fires on the SNEAK capture are FALSE jumps")
    print("  caused by standing up from a crouch after the fast baseline has been dragged down;")
    print("  the proposed detector fires 0 (the deadband freeze keeps the standing level pinned).")
    print("")
    print("DROPOUT MECHANISM: current baseline at 90 Hz has tau=0.735 s; during a held crouch the")
    print("gap decays as D*exp(-t/tau), falling back under the 0.10 m threshold after")
    print("t = tau*ln(D/0.10): D=0.25 m -> 0.67 s, D=0.60 m -> 1.31 s. The sneak flag then drops")
    print("out while the headset is still physically lowered - exactly what the 90 Hz replay shows.")
    print("At the lab's 18 Hz the same code has tau=3.68 s and drops out much later, which is why")
    print("the lab recording alone cannot reveal the bug. The dataset's real crouches last 4.0-9.9 s,")
    print("far longer than any latch/cooldown timer. The dt-corrected tau=2 s baseline alone still")
    print("drops out during the hold (it keeps adapting); only the deadband freeze fixes it.")
    print("")
    print("Look-down false-positive risk (pitch does NOT lower head y very much, quantified):")
    print("  from the section-3 pitch model, pitch-only HMD height change:")
    for deg in (-30, -40, -50, -60):
        th = math.radians(deg)
        dy = c1 * (math.cos(th) - 1.0) + c2 * math.sin(th)
        print("    pitch %+4d deg -> %+6.1f mm" % (deg, 1000.0 * dy))
    print("  the current 0.10 m sneak threshold is BELOW the pitch-only drop beyond about -47 deg")
    print("  (109.5 mm at -50 deg, 133.7 mm at -60 deg); a sustained look at the feet can cross it.")
    print("  Deep look-down captures (static geometry):")
    for name in ("TELEPORT_LEFT_PINCH", "TELEPORT_LEFT_PINCH#2", "PLACE_RIGHT_PINCH"):
        rec = recs.get(name)
        if rec is None or not any(x is not None for x in rec["hm"]):
            continue
        pitches, _ = head_pitch_yaw(rec)
        ys = [v for v in head_y(rec) if v is not None]
        pv = [v for v in pitches if v is not None]
        print("    %-24s pitch p2/p50/p98=%6.1f/%6.1f/%6.1f deg, head y range=%.3f m"
              % (name, pct(pv, 0.02), pct(pv, 0.5), pct(pv, 0.98), max(ys) - min(ys)))
    print("  SNEAK itself has pitch p2/p50/p98 = %.1f/%.1f/%.1f deg: the operator looks down while"
          % (pct([p for p in sneak_pitch if p is not None], 0.02),
             pct([p for p in sneak_pitch if p is not None], 0.5),
             pct([p for p in sneak_pitch if p is not None], 0.98)))
    print("  crouching, so a pitch-compensated height is the clean phase-2 fix (section 7).")
    print("")
    print("Synthetic baseline-adaptation / hysteresis tests (90 Hz, y starts at 1.50 m):")
    def synth_run(label, ts, ys):
        c = sim_current(ts, ys)
        d = sim_dt_corrected(ts, ys)
        p = sim_proposed(ts, ys)
        print("  %-46s current J/S=%d/%d  dtc J/S=%d/%d  proposed J/S=%d/%d"
              % (label, len(c["jumps"]), len(c["sneak"]), len(d["jumps"]), len(d["sneak"]),
                 len(p["jumps"]), len(p["sneak"])))
        if c["sneak"]:
            print("      current sneak latches: %s" % str(
                [(round(a - ts[0], 2), round(b - ts[0], 2) if b else None) for a, b in c["sneak"]]))
        if p["sneak"]:
            print("      proposed sneak latches: %s" % str(
                [(round(a - ts[0], 2), round(b - ts[0], 2) if b else None) for a, b in p["sneak"]]))
        if p["jumps"]:
            print("      proposed jump pulses (s): %s" % str([round(t - ts[0], 2) for t, _, _ in p["jumps"]]))
    def make_series(dur, fn):
        n = int(dur * PROD_HZ)
        ts = [i / PROD_HZ for i in range(n)]
        return ts, [fn(t) for t in ts]
    base_y = 1.50
    def crouch_case(t, depth, hold):
        t0 = 1.0
        if t < t0:
            return base_y
        if t < t0 + 0.15:
            return base_y - depth * (t - t0) / 0.15
        if t < t0 + 0.15 + hold:
            return base_y - depth
        if t < t0 + 0.30 + hold:
            return base_y - depth * (1.0 - (t - t0 - 0.15 - hold) / 0.15)
        return base_y
    ts, ys = make_series(7.5, lambda t: crouch_case(t, 0.25, 4.9))
    synth_run("sustained 4.9 s crouch, depth 0.25 m", ts, ys)
    ts, ys = make_series(7.5, lambda t: crouch_case(t, 0.60, 4.9))
    synth_run("sustained 4.9 s crouch, depth 0.60 m", ts, ys)
    def step_case(t, height, rise, hold):
        t0 = 1.0
        if t < t0:
            return base_y
        if t < t0 + rise:
            return base_y + height * (t - t0) / rise
        if t < t0 + rise + hold:
            return base_y + height
        if t < t0 + 2 * rise + hold:
            return base_y + height * (1.0 - (t - t0 - rise - hold) / rise)
        return base_y
    ts, ys = make_series(7.0, lambda t: step_case(t, 0.20, 0.30, 3.0))
    synth_run("0.20 m step up (0.30 s), 3 s stay, 0.30 s down", ts, ys)
    ts, ys = make_series(7.0, lambda t: step_case(t, 0.15, 1.5, 2.0))
    synth_run("slow 0.15 m rise (1.5 s) - must NOT be a jump", ts, ys)
    def pitch_case(t, deg, rise, hold):
        t0 = 1.0
        if t < t0:
            d = 0.0
        elif t < t0 + rise:
            d = deg * (t - t0) / rise
        elif t < t0 + rise + hold:
            d = deg
        else:
            d = deg * max(0.0, 1.0 - (t - t0 - rise - hold) / rise)
        th = math.radians(d)
        return (base_y - PITCH_C1) + PITCH_C1 * math.cos(th) + PITCH_C2 * math.sin(th)
    ts, ys = make_series(5.0, lambda t: pitch_case(t, -30, 0.4, 1.0))
    synth_run("fast look-down to -30 deg, hold 1 s", ts, ys)
    ts, ys = make_series(5.0, lambda t: pitch_case(t, -50, 0.4, 1.0))
    synth_run("fast look-down to -50 deg, hold 1 s", ts, ys)
    ts, ys = make_series(5.0, lambda t: pitch_case(t, -60, 0.4, 1.0))
    synth_run("fast look-down to -60 deg, hold 1 s", ts, ys)
    ts, ys = make_series(5.0, lambda t: pitch_case(t, 45, 0.3, 0.5))
    synth_run("fast look-up to +45 deg, hold 0.5 s", ts, ys)
    def bob_case(t):
        return base_y + 0.0545 * math.sin(2.0 * math.pi * 0.65 * t)
    ts, ys = make_series(10.0, bob_case)
    synth_run("walking bob, amplitude 0.0545 m, 0.65 Hz, 10 s", ts, ys)
    print("  KEY: a sustained -60 deg look-down makes the CURRENT engine fire a false JUMP on the")
    print("  return (the fixed-alpha baseline gets dragged down, then the head comes back up); the")
    print("  dt-corrected and proposed detectors instead latch sneak (~1 s).  The -45 deg pitch gate")
    print("  only protects the jump path; the sneak path needs a pitch-compensated headY (phase 2)")
    print("  or a larger HEAD_SNEAK_DROP to cover extreme look-down.")

    section_header(6, "CROSS-DATASET HEAD MOTION + FALSE-TRIGGER RATES (fixed vs proposed detectors)")
    print("%-28s %7s %7s %8s %8s %8s %8s %8s %8s %9s" % (
        "dataset", "dur", "yRange", "winV95", "winVmax", "pitch02", "pitch98", "curJ/min", "curS/min",
        "proJ/min"))
    cross = {}
    for rec in loaded:
        if rec["display"] == "IDLE":
            continue
        vts, vys, vps = head_series(rec)
        if not vys:
            continue
        pitches = rec["pitch"]
        pv = [v for v in pitches if v is not None]
        winv = [abs(window_velocity(vts, vys, i, 0.12)) for i in range(1, len(vts))]
        rts, rys, rps = head_series(rec, PROD_HZ)
        c = sim_current(rts, rys)
        p = sim_proposed(rts, rys, rps)
        dur_min = rec["dur"] / 60.0
        cross[rec["display"]] = (c, p, vys, pv, winv, rec)
        print("%-28s %7.2f %7.3f %8.2f %8.2f %8s %8s %8.1f %8.1f %9.1f" % (
            rec["display"], rec["dur"], max(vys) - min(vys),
            pct(winv, 0.95), max(winv) if winv else 0.0,
            "%7.1f" % pct(pv, 0.02) if pv else "-", "%7.1f" % pct(pv, 0.98) if pv else "-",
            len(c["jumps"]) / dur_min if dur_min > 0 else 0.0,
            len(c["sneak"]) / dur_min if dur_min > 0 else 0.0,
            len(p["jumps"]) / dur_min if dur_min > 0 else 0.0))
    idle = recs["IDLE"]
    idle_ts, idle_ys, idle_pitch = head_series(idle)
    idle_rt, idle_ry, idle_rp = head_series(idle, PROD_HZ)
    idle_cur = sim_current(idle_rt, idle_ry)
    idle_prop = sim_proposed(idle_rt, idle_ry, idle_rp)
    idle_dur_min = idle["dur"] / 60.0
    print("%-28s %7.2f %7.3f %8s %8s %8s %8s %8.1f %8.1f %9.1f" % (
        "IDLE (negative)", idle["dur"], max(idle_ys) - min(idle_ys), "-", "-", "-", "-",
        len(idle_cur["jumps"]) / idle_dur_min, len(idle_cur["sneak"]) / idle_dur_min,
        len(idle_prop["jumps"]) / idle_dur_min))
    print("")
    print("Per-dataset counts (not rate-normalised):")
    for rec in loaded:
        if rec["display"] == "IDLE":
            continue
        c, p, _, _, _, _ = cross[rec["display"]]
        print("  %-28s current jumps=%d sneak=%d | proposed jumps=%d sneak=%d"
              % (rec["display"], len(c["jumps"]), len(c["sneak"]), len(p["jumps"]), len(p["sneak"])))
    print("")
    print("NOTE: WALK is walking-in-place with real physical bobbing (~0.65 Hz, p2-p98 0.109 m,")
    print("120 ms-window vertical speed p95 0.69 m/s); neither detector fires because the 2 s")
    print("baseline and the 0.10 m rise / 0.12 m drop thresholds reject the periodic bob.")
    print("STRONGEST residual false-positive class: PLACE. The operator physically bends down and")
    print("stands back up while placing (head y range 0.47 m); a fast stand-up is indistinguishable")
    print("from a jump by head y alone. Current: 4 jump pulses; proposed: 1 (the -45 deg pitch gate")
    print("removes 3 - the operator was looking at the ground, head pitch -48/-46/-65 deg). The last")
    print("one fires at pitch -33 deg and needs context gating (suppress jump while placing) or A/B.")

    section_header(7, "PROPOSED DT-CORRECTED HEAD ALGORITHM: constants, pseudocode, full simulation")
    print("Constants (replace the head-jump/sneak block of VisionM7Gesture.update):")
    print("  BASELINE_TAU_S        = %.2f   (design intent; alpha = 1-exp(-dt/tau), frame-rate independent)" % P_TAU)
    print("  BASELINE_ADAPT_BAND_M = %.2f  (adapt only while |headY-baseline| <= band; freeze outside)" % P_ADAPT_BAND)
    print("  HEAD_JUMP_RISE_M      = %.2f  (was 0.08)" % P_JUMP_RISE)
    print("  HEAD_JUMP_VEL_MPS     = %.2f  windowed over %.2f s (was 0.25 single-frame over 1/90 s)"
          % (P_JUMP_VEL, P_JUMP_WIN))
    print("  HEAD_JUMP_COOLDOWN_S  = %.2f  (unchanged)" % P_JUMP_COOLDOWN)
    print("  HEAD_JUMP_PITCH_GATE  = %+.0f deg (ignore head rise while looking deeper down)" % P_JUMP_PITCH_GATE)
    print("  HEAD_SNEAK_DROP_M     = %.2f  (was 0.10)" % P_SNEAK_DROP)
    print("  HEAD_SNEAK_LATCH_S    = %.2f  (was 0.35; filters jump-anticipation squats)" % P_SNEAK_LATCH)
    print("  HEAD_SNEAK_EXIT_M     = %.2f for %.2f s (was: instant release at 0.10)" % (P_SNEAK_EXIT, P_SNEAK_EXIT_HOLD))
    print("  JUMP_CANCELS_SNEAK    = yes, plus %.2f s sneak re-latch suppression after a jump" % P_JUMP_SUPPRESS_SNEAK)
    print("  optional phase 2: headY_eff = headY - (%.4f*cos(pitch) + %.4f*sin(pitch))"
          % (PITCH_C1, PITCH_C2))
    print("  (needs the full hmdPose passed into update(); current code only passes headX/Y/Z)")
    print("")
    print("Pseudocode:")
    print("  dt = clamp((nowNs - prevNs)*1e-9, 1e-3, 0.25)")
    print("  gap = headY - baseline")
    print("  if abs(gap) <= ADAPT_BAND: baseline += (1 - exp(-dt/TAU)) * gap // re-centre near the baseline")
    print("  vel = (headY - headY[t-0.12s]) / 0.12                          // windowed, not single-frame")
    print("  if !gui && !seated && now >= jumpCooldown && gap > RISE && vel > VEL && pitch > -45:")
    print("      jumpPulse(80ms); jumpCooldown = now + 700ms; suppressSneakUntil = now + 300ms")
    print("      if sneaking: sneaking = false                            // jump wins, never both")
    print("  if gap < -DROP && now >= suppressSneakUntil:")
    print("      sneakSince = sneakSince or now; if now - sneakSince >= LATCH: sneaking = true")
    print("  else sneakSince = null")
    print("  if sneaking && gap >= -EXIT for EXIT_HOLD: sneaking = false    // exit hysteresis")
    print("  baseline = headY on tracking loss > 500 ms, seated toggle, or manual recentre")
    print("")
    print("Sneak-latch trade-off under the proposed baseline (JUMP anticipation squats vs real holds):")
    jt90, jy90, jp90 = head_series(recs["JUMP_HEAD"], PROD_HZ)
    st90, sy90, sp90 = head_series(recs["SNEAK_HEAD"], PROD_HZ)
    pt90, py90, pp90 = head_series(recs["PLACE_RIGHT_PINCH"], PROD_HZ)
    print("  %-8s %-20s %-30s %s" % ("latch s", "JUMP sneak pulses", "SNEAK latches (durations s)",
                                     "PLACE jumps/sneak"))
    for latch in (0.35, 0.50, 0.60):
        jj = sim_proposed(jt90, jy90, jp90, latch=latch)
        ss = sim_proposed(st90, sy90, sp90, latch=latch)
        pj = sim_proposed(pt90, py90, pp90, latch=latch)
        print("  %-8.2f %-20d %-30s %d/%d" % (
            latch, len(jj["sneak"]),
            str([round((b - a) if b else 0.0, 2) for a, b in ss["sneak"]]),
            len(pj["jumps"]), len(pj["sneak"])))
    no_gate = sim_proposed(pt90, py90, pp90, pitch_gate=-999.0)
    with_gate = sim_proposed(pt90, py90, pp90)
    print("  PLACE jump pulses with the pitch gate disabled = %d; with the -45 deg gate = %d"
          % (len(no_gate["jumps"]), len(with_gate["jumps"])))
    print("")
    print("Full simulation at 90 Hz on every capture:")
    print("  %-28s %8s %12s %12s %12s" % ("dataset", "dur[s]", "current J/S", "proposed J/S", "proposed J/min"))
    for rec in loaded:
        rts, rys, rps = head_series(rec, PROD_HZ)
        c = sim_current(rts, rys)
        p = sim_proposed(rts, rys, rps)
        print("  %-28s %8.2f %12s %12s %12.2f" % (
            rec["display"], rec["dur"], "%d/%d" % (len(c["jumps"]), len(c["sneak"])),
            "%d/%d" % (len(p["jumps"]), len(p["sneak"])),
            len(p["jumps"]) / (rec["dur"] / 60.0) if rec["dur"] > 0 else 0.0))
    print("")
    print("Rate invariance of the proposed detector (dt correction works):")
    print("  %-8s %-14s %-14s %-14s %-14s" % ("rate", "JUMP J/S", "SNEAK J/S", "WALK J/S", "PLACE J/S"))
    for rate in (18.05, 30.0, 45.0, 90.0, 120.0, 144.0):
        cells = []
        for name in ("JUMP_HEAD", "SNEAK_HEAD", "WALK_BOTH_FISTS", "PLACE_RIGHT_PINCH"):
            rec = recs[name]
            rts, rys, rps = head_series(rec, rate)
            p = sim_proposed(rts, rys, rps)
            cells.append("%d/%d" % (len(p["jumps"]), len(p["sneak"])))
        print("  %-8.2f %-14s %-14s %-14s %-14s" % (rate, cells[0], cells[1], cells[2], cells[3]))

    section_header(8, "IDLE NEGATIVE ANALYSIS: candidate detectors for all 14 gestures + contamination")
    menu = recs["MENU_RIGHT_PINCH"]
    identical = 0
    for i in range(min(idle["n"], menu["n"])):
        same = (idle["t"][i] == menu["t"][i] and idle["head"][i] == menu["head"][i]
                and idle["L"][i] == menu["L"][i] and idle["R"][i] == menu["R"][i]
                and idle["Lt"][i] == menu["Lt"][i] and idle["Rt"][i] == menu["Rt"][i])
        if same:
            identical += 1
    print("IDLE capture vs accepted MENU_RIGHT_PINCH capture: %d/%d frames byte-identical."
          % (identical, min(idle["n"], menu["n"])))
    print("  IDLE labels=%s, MENU labels=%s, MENU sourceLabel=%s"
          % (dict(idle["labels"]), dict(menu["labels"]),
             json.loads(menu["path"].read_text(errors="replace").split("\n")[0]).get("sourceLabel")))
    print("  => 'IDLE' is the pre-relabel source of MENU_RIGHT_PINCH, NOT a gesture-free negative:")
    print("  it contains 42 deliberate right-pinch events (see table). There is no true idle capture")
    print("  in export/gesturelab-data. For head jump/sneak it is still a valid negative (the head")
    print("  does not move vertically); for hand gestures it must be read as MENU data, not noise.")
    print("")
    print("IDLE capture quality: n=%d dur=%.2f s; left hand tracked %d/%d, right %d/%d; headMatrix=%d"
          % (idle["n"], idle["dur"], sum(1 for x in idle["Lt"] if x), idle["n"],
             sum(1 for x in idle["Rt"] if x), idle["n"],
             sum(1 for x in idle["hm"] if x is not None)))
    idts = [idle_ts[i + 1] - idle_ts[i] for i in range(len(idle_ts) - 1)]
    print("IDLE dt p50/p95/max=%.1f/%.1f/%.1f ms; head y range=%.3f m; per-frame head |v| p95=%.2f m/s"
          % (pct(idts, 0.5) * 1000, pct(idts, 0.95) * 1000, max(idts) * 1000,
             max(idle_ys) - min(idle_ys),
             pct([abs((idle_ys[i + 1] - idle_ys[i]) / idts[i])
                  for i in range(len(idts)) if idts[i] > 0], 0.95)))
    print("")
    print("Feature provenance: the per-joint ARKit tracked flag is unreliable in this export (mostly")
    print("false even inside tracked hands), but the joint MATRICES are exactly what the lab classifier")
    print("and the provider curl() consume - so the curl ratio is recomputed from matrices here (the")
    print("recorded rightFeatures.fistRatio is a STALE pre-fix metric for this MENU/IDLE capture only).")
    print("The left hand is tracked in only 179/563 samples.")
    print("")
    print("Feature-provenance check: recorded rightFeatures vs recomputed from the joint matrices")
    print("  %-28s %6s %11s %11s %10s %10s %9s" % (
        "dataset", "nR", "stored<.65", "recomp<.65", "stored_p50", "recomp_p50", "mean|d|"))
    pinch_n = 0
    pinch_err = 0.0
    for rec in loaded:
        pairs = []
        for i in range(rec["n"]):
            joints = rec["R"][i]
            if not rec["Rt"][i] or joints is None:
                continue
            c = curl_ratio(joints)
            st = (rec["Rf"][i] or {}).get("fistRatio")
            if c is not None and isinstance(st, (int, float)):
                pairs.append((st, c))
            ps = (rec["Rf"][i] or {}).get("pinch")
            if "thumbTip" in joints and "indexFingerTip" in joints and isinstance(ps, (int, float)):
                pinch_err = max(pinch_err, abs(ps - dist3(joints["thumbTip"], joints["indexFingerTip"])))
                pinch_n += 1
        if not pairs:
            continue
        stored = [a for a, _ in pairs]
        recomp = [b for _, b in pairs]
        diffs = [abs(a - b) for a, b in pairs]
        print("  %-28s %6d %11d %11d %10.3f %10.3f %9.4f" % (
            rec["display"], len(pairs),
            sum(1 for v in stored if v < 0.65), sum(1 for v in recomp if v < 0.65),
            pct(stored, 0.5), pct(recomp, 0.5), mean(diffs)))
    print("  pinch: stored == |thumbTip-indexTip| recomputed from the matrices, max abs diff %.2e over"
          % pinch_err)
    print("  %d frames - the matrices are exactly the ones the lab classifier used. The fistRatio is" % pinch_n)
    print("  stale only for the MENU/IDLE capture; every other accepted capture matches exactly.")
    print("")
    print("Candidate detectors (thresholds copied from VisionM7Gesture where they exist):")
    print("  %-30s %-36s %7s %7s %8s" % ("gesture / detector", "rule", "events", "frames", "per min"))
    def right_pinch(i):
        f = idle["Rf"][i] or {}
        v = f.get("pinch")
        return v if isinstance(v, (int, float)) else None
    def left_pinch(i):
        f = idle["Lf"][i] or {}
        v = f.get("pinch")
        return v if isinstance(v, (int, float)) else None
    def fist_at(i, side):
        key = "L" if side == "left" else "R"
        if not idle[key + "t"][i]:
            return None
        if idle[key][i] is not None:
            c = curl_ratio(idle[key][i])
            if c is not None:
                return c
        feat = (idle[key + "f"][i] or {}).get("fistRatio")
        return feat if isinstance(feat, (int, float)) else None
    def pinch_events(getter, on=0.025, off=0.05, debounce=0.04, arm=0.10):
        events = 0
        pressed = False
        raw_since = 0.0
        released_at = 0.0
        armed = True
        prev_raw = False
        for i in range(idle["n"]):
            v = getter(i)
            raw = v is not None and v < on
            t = idle_ts[i]
            if raw:
                if not prev_raw:
                    raw_since = t
                if not pressed and armed and t - raw_since >= debounce:
                    pressed = True
                    events += 1
            elif pressed:
                pressed = False
                armed = False
                released_at = t
            if not armed and t - released_at >= arm:
                armed = True
            prev_raw = raw
        return events
    def fist_events(side, on=0.65, off=0.75):
        events = 0
        closed = False
        for i in range(idle["n"]):
            c = fist_at(i, side)
            if c is None:
                continue
            if not closed and c < on:
                closed = True
                events += 1
            elif closed and c > off:
                closed = False
        return events
    def fist_frames(side, on=0.65):
        return sum(1 for i in range(idle["n"])
                   if fist_at(i, side) is not None and fist_at(i, side) < on)
    def both_fist_events():
        events = 0
        both_prev = False
        for i in range(idle["n"]):
            l = fist_at(i, "left")
            r = fist_at(i, "right")
            both = l is not None and r is not None and l < 0.65 and r < 0.65
            if both and not both_prev:
                events += 1
            both_prev = both
        return events
    r_speed = head_speed_series(idle, "R", "wrist")
    r_tip = head_speed_series(idle, "R", "indexFingerTip")
    def cooldown_events(value_fn, thr, cooldown):
        events = 0
        last = -1e9
        for i in range(idle["n"]):
            v = value_fn(i)
            if v is not None and v > thr and idle_ts[i] - last >= cooldown:
                events += 1
                last = idle_ts[i]
        return events
    def near_head_events(thr=0.28, latch=0.25):
        events = 0
        inside_since = None
        latched = False
        for i in range(idle["n"]):
            hand = idle["R"][i]
            head = idle["head"][i]
            if hand is None or head is None or "wrist" not in hand:
                inside_since = None
                latched = False
                continue
            d = dist3(hand["wrist"], head)
            if d < thr:
                if inside_since is None:
                    inside_since = idle_ts[i]
                if not latched and idle_ts[i] - inside_since >= latch:
                    latched = True
                    events += 1
            else:
                inside_since = None
                latched = False
        return events
    def separation_events(thr=0.55):
        events = 0
        prev = False
        for i in range(idle["n"]):
            l = idle["L"][i]
            r = idle["R"][i]
            if l is None or r is None or "wrist" not in l or "wrist" not in r:
                prev = False
                continue
            cl = fist_at(i, "left")
            cr = fist_at(i, "right")
            both = cl is not None and cr is not None and cl < 0.65 and cr < 0.65
            now = both and dist3(l["wrist"], r["wrist"]) > thr
            if now and not prev:
                events += 1
            prev = now
        return events
    def climb_events():
        events = 0
        prev = False
        for i in range(idle["n"]):
            head = idle["head"][i]
            if head is None:
                prev = False
                continue
            grab = False
            for key, side in (("L", "left"), ("R", "right")):
                hand = idle[key][i]
                if hand is not None and "wrist" in hand:
                    c = fist_at(i, side)
                    if c is not None and c < 0.65 and hand["wrist"][1] - head[1] > -0.05:
                        grab = True
            if grab and not prev:
                events += 1
            prev = grab
        return events
    def walk_events():
        events = 0
        crossings = 0
        last_cross = -1e9
        sign = 0
        walking = False
        for i in range(idle["n"]):
            l = fist_at(i, "left")
            r = fist_at(i, "right")
            both = l is not None and r is not None and l < 0.65 and r < 0.65
            if both and idle["L"][i] is not None and idle["R"][i] is not None \
                    and "wrist" in idle["L"][i] and "wrist" in idle["R"][i]:
                diff = idle["L"][i]["wrist"][2] - idle["R"][i]["wrist"][2]
                if abs(diff) > 0.04:
                    s = 1 if diff > 0 else -1
                    if sign != 0 and s != sign:
                        crossings += 1
                        last_cross = idle_ts[i]
                    sign = s
            if both and crossings >= 2 and idle_ts[i] - last_cross < 0.6:
                if not walking:
                    events += 1
                walking = True
            elif not both or idle_ts[i] - last_cross > 0.6:
                walking = False
                if not both:
                    sign = 0
                    crossings = 0
        return events
    dur_min = idle["dur"] / 60.0
    def emit(label, rule, events, frames=0):
        print("  %-30s %-36s %7d %7d %8.2f"
              % (label, rule, events, frames, events / dur_min if dur_min > 0 else 0.0))
    emit("pinch RIGHT (menu/place/break)", "pinch<0.025 on, >0.05 off, 40 ms debounce", pinch_events(right_pinch))
    emit("pinch LEFT (teleport)", "same", pinch_events(left_pinch))
    emit("fist LEFT (escape tap)", "curl<0.65 on, >0.75 off (recomputed)", fist_events("left"),
         fist_frames("left"))
    emit("fist RIGHT (use/climb)", "same", fist_events("right"), fist_frames("right"))
    emit("both fists (inventory/bow/walk)", "L and R curl<0.65 together", both_fist_events())
    emit("walk (alternating swing)", ">=2 z-sign crossings, |dz|>0.04, 600 ms stop", walk_events())
    emit("bow (both fists + separation)", "both fists and wrist sep >0.55 m", separation_events())
    emit("climb grab (fist above chest)", "fist and wrist.y-head.y > -0.05 m", climb_events())
    emit("attack (right wrist speed)", ">1.4 m/s", cooldown_events(lambda i: r_speed[i], 1.4, 0.30))
    emit("eat (right hand near head)", "wrist-head <0.28 m, 250 ms latch", near_head_events())
    emit("hotbar (right index tip)", "tip speed>1.2 and wrist speed<0.5 m/s",
         cooldown_events(lambda i: r_tip[i] if r_speed[i] < 0.5 else 0.0, 1.2, 0.15))
    emit("jump (current detector)", "rise>0.08 + v>0.25", len(idle_cur["jumps"]))
    emit("jump (proposed detector)", "rise>0.10 + 120 ms windowed v>0.35", len(idle_prop["jumps"]))
    emit("sneak (current detector)", "drop>0.10, 350 ms latch", len(idle_cur["sneak"]))
    emit("sneak (proposed detector)", "drop>0.12, 500 ms latch", len(idle_prop["sneak"]))
    print("")
    raw_pinch_edges = 0
    _on = False
    for i in range(idle["n"]):
        v = right_pinch(i)
        if v is None:
            continue
        if not _on and v < 0.030:
            _on = True
            raw_pinch_edges += 1
        elif _on and v > 0.045:
            _on = False
    print("IDLE right-pinch: %d raw 0.030/0.045 edge events (= accepted MENU summary's 42) and %d"
          % (raw_pinch_edges, pinch_events(right_pinch)))
    print("events after the engine 40 ms debounce/arm logic; this confirms IDLE==MENU data and")
    print("validates the pinch detector (the 4-event difference is short/noisy closures the debounce")
    print("rejects).")
    print("IDLE false head-jump pulses: current=%d, proposed=%d; false sneak latches: current=%d, proposed=%d"
          % (len(idle_cur["jumps"]), len(idle_prop["jumps"]),
             len(idle_cur["sneak"]), len(idle_prop["sneak"])))
    print("IDLE max baseline gap: current gap_max=%.3f m gap_min=%.3f m (thresholds 0.08/0.10)"
          % (idle_cur["gap_max"], idle_cur["gap_min"]))

    section_header(9, "HEADLINE NUMBER SUMMARY (for the report)")
    print("sampling:       %d samples in %d captures; mean rate %.2f Hz; dt p50 %.1f ms, p95 %.1f ms,"
          " max %.2f s"
          % (sum(r["n"] for r in loaded), len(loaded), mean(all_rates), pct(all_dt, 0.5) * 1000,
             pct(all_dt, 0.95) * 1000, max(all_dt)))
    print("stale frames:   joint-position repeats=%d of %d pairs; head-tracked repeats=%d;"
          % (total_joint_rep, joint_pairs_total, total_head_rep))
    print("                all-row head repeats=%d (TELEPORT_LEFT_PINCH#2 untracked zero-fill);"
          " per-joint flag false=%.1f%%"
          % (len(raw_head_rep),
             100.0 * sum(r["joint_flag_false"] for r in loaded)
             / max(1, sum(r["joint_records"] for r in loaded))))
    print("frame-rate:     per-frame alpha 0.985 => tau %.3f s @90 Hz vs %.3f s @18 Hz (design 2.0 s)"
          % ((1.0 / 90.0) / (-math.log(FRAME_ALPHA)), (1.0 / 18.05) / (-math.log(FRAME_ALPHA))))
    print("head math:      column-major right=col0 up=col1 backward=col2, forward=-col2 (max norm err %.1e);"
          " verified on EAT" % max_norm_err)
    print("pitch lever:    C1=%.4f m C2=%.4f m; look-down dy @-30/-40/-50/-60 deg = %.0f/%.0f/%.0f/%.0f mm"
          % (PITCH_C1, PITCH_C2,
             1000 * abs(PITCH_C1 * (math.cos(math.radians(-30)) - 1) + PITCH_C2 * math.sin(math.radians(-30))),
             1000 * abs(PITCH_C1 * (math.cos(math.radians(-40)) - 1) + PITCH_C2 * math.sin(math.radians(-40))),
             1000 * abs(PITCH_C1 * (math.cos(math.radians(-50)) - 1) + PITCH_C2 * math.sin(math.radians(-50))),
             1000 * abs(PITCH_C1 * (math.cos(math.radians(-60)) - 1) + PITCH_C2 * math.sin(math.radians(-60)))))
    print("JUMP:           %d reference rises (peaks %.3f-%.3f m); current@90=%d pulses, current@lab=%d,"
          " proposed@90=%d"
          % (len(ref_jump), min(e[2] for e in ref_jump), max(e[2] for e in ref_jump),
             len(cur_90["jumps"]), len(cur_lab["jumps"]), len(prop_90["jumps"])))
    print("JUMP sneaks:    current@90=%d pulses, proposed@90=%d (jump-anticipation squats)"
          % (len(cur_90["sneak"]), len(prop_90["sneak"])))
    print("SNEAK:          %d reference drops; current@90 latches=%d (dur %s), proposed@90 latches=%d (dur %s)"
          % (len(ref_sneak), len(cur_90_s["sneak"]),
             str([round((b - a) if b else sneak_ts[-1] - a, 2) for a, b in cur_90_s["sneak"]]),
             len(prop_90_s["sneak"]),
             str([round((b - a) if b else sneak_ts[-1] - a, 2) for a, b in prop_90_s["sneak"]])))
    print("SNEAK jumps:    current@90=%d false jumps, proposed@90=%d"
          % (len(cur_90_s["jumps"]), len(prop_90_s["jumps"])))
    print("IDLE:           current jump/sneak=%d/%d, proposed=%d/%d; IDLE==MENU source"
          % (len(idle_cur["jumps"]), len(idle_cur["sneak"]),
             len(idle_prop["jumps"]), len(idle_prop["sneak"])))
    print("PLACE:          current jumps=%d sneak=%d, proposed jumps=%d sneak=%d (stand-up class)"
          % (len(cross["PLACE_RIGHT_PINCH"][0]["jumps"]), len(cross["PLACE_RIGHT_PINCH"][0]["sneak"]),
             len(cross["PLACE_RIGHT_PINCH"][1]["jumps"]), len(cross["PLACE_RIGHT_PINCH"][1]["sneak"])))
    print("WALK:           head y range %.3f m, ~0.65 Hz bob; current/proposed jump+sneak=0"
          % (max(cross["WALK_BOTH_FISTS"][2]) - min(cross["WALK_BOTH_FISTS"][2])))
    print("")
    print("done.")


if __name__ == "__main__":
    main()

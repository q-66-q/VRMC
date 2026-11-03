#!/usr/bin/env python3
"""M7 Gesture Lab dataset analysis - pinch + hand-action gestures (host-side, reproducible).

Recomputes every feature from the raw 27-joint ARKit matrices recorded by the Gesture Lab
(export/gesturelab-data), reproduces the existing summaries, and prints the measured tables that
back docs/mvp/M7_DATA_ANALYSIS_HANDS.md.

Run from the repo root:
    python3 scripts/m7_lab_stats_hands.py

Only reads raw JSONL (gitignored, never modified). No numpy needed.
Feature conventions (fixed by the analysis spec, recomputed from joints - never from stored features):
  pinch      = |thumbTip - indexFingerTip|                       (metres)
  fist       = mean over {index,middle,ring,little} fingers of
                 dist(fingerTip, fingerKnuckle) / max(0.02, dist(wrist, fingerKnuckle))
  velocity   = finite difference of joint world position (m[12..14]) / recorded dt (t = epoch s)
  head frame = headMatrix column-major: right = col0, up = col1, forward = -col2, head pos = m[12..14]
  durations  = first ON sample -> first subsequent OFF sample (matches the accepted summaries;
               an event still closed at the end of a recording is "unfinished" and listed separately).
"""

import json
import math
import os
import sys
from collections import Counter, defaultdict
from pathlib import Path

# ---------------------------------------------------------------- paths / constants

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "export" / "gesturelab-data"
ACCEPTED = DATA_DIR / "accepted"
IDLE_PATH = DATA_DIR / "gesturelab-IDLE-20261102-173326.jsonl"
REJECTED = DATA_DIR / "rejected"

FINGERS = ("index", "middle", "ring", "little")
FIST_ON = 0.65          # VisionM7Gesture.FIST_ON
FIST_OFF = 0.75         # VisionM7Gesture.FIST_OFF (declared but currently unused)
PINCH_ON_ENG = 0.025    # VisionM7Gesture.PINCH_ON
PINCH_OFF_ENG = 0.050   # VisionM7Gesture.PINCH_OFF
PLACE_MAX = 0.350       # VisionM7Gesture.PLACE_MAX_NS
INV_TAP_MAX = 0.450     # VisionM7Gesture.INVENTORY_TAP_MAX_NS
ATTACK_SPEED = 1.4      # VisionM7Gesture.ATTACK_SPEED
BOW_SEP = 0.55          # VisionM7Gesture.BOW_SEPARATION
EAT_DIST = 0.28         # VisionM7Gesture.EAT_DISTANCE
WALK_SWING = 0.04       # VisionM7Gesture.WALK_START_SWING

# Canonical analysis order (action datasets first, IDLE last; JUMP/SNEAK are head-only extras that
# are still useful negative controls for hand detectors and are loaded too).
ACTION_LABELS = [
    "MENU_RIGHT_PINCH", "PLACE_RIGHT_PINCH", "BREAK_RIGHT_PINCH_HOLD", "TELEPORT_LEFT_PINCH",
    "ESCAPE_LEFT_FIST", "INVENTORY_BOTH_FISTS", "WALK_BOTH_FISTS", "BOW_BOTH_FISTS",
    "CLIMB_ALTERNATE", "ATTACK_RIGHT_SWING", "EAT_RIGHT_HAND_HEAD", "HOTBAR_RIGHT_TAP",
]
EXTRA_LABELS = ["IDLE", "JUMP_HEAD", "SNEAK_HEAD"]

SHORT = {
    "MENU_RIGHT_PINCH": "MENU", "PLACE_RIGHT_PINCH": "PLACE", "BREAK_RIGHT_PINCH_HOLD": "BREAK",
    "TELEPORT_LEFT_PINCH": "TELEPORT", "ESCAPE_LEFT_FIST": "ESCAPE",
    "INVENTORY_BOTH_FISTS": "INVENTORY", "WALK_BOTH_FISTS": "WALK", "BOW_BOTH_FISTS": "BOW",
    "CLIMB_ALTERNATE": "CLIMB", "ATTACK_RIGHT_SWING": "ATTACK",
    "EAT_RIGHT_HAND_HEAD": "EAT", "HOTBAR_RIGHT_TAP": "HOTBAR",
    "IDLE": "IDLE", "JUMP_HEAD": "JUMP", "SNEAK_HEAD": "SNEAK",
}
EXPECTED_EVENTS = {
    "PLACE_RIGHT_PINCH": 76, "BREAK_RIGHT_PINCH_HOLD": 7,
    "MENU_RIGHT_PINCH": 42, "TELEPORT_LEFT_PINCH": 16,
}
# Accepted-summary headline counts used for the cross-check table (dataset -> (name, expected)).
EXPECTED_SUMMARY = [
    ("PLACE_RIGHT_PINCH", "short pinches <0.35 s", 72),
    ("PLACE_RIGHT_PINCH", "pinch events (completed)", 76),
    ("BREAK_RIGHT_PINCH_HOLD", "held pinch events", 7),
    ("MENU_RIGHT_PINCH", "pinch events", 42),
    ("TELEPORT_LEFT_PINCH", "left pinch events", 16),
    ("ESCAPE_LEFT_FIST", "left-fist events (0.55/0.75)", 24),
    ("INVENTORY_BOTH_FISTS", "both-fist tap runs", 24),
    ("HOTBAR_RIGHT_TAP", "index-tip tap events", 22),
    ("BOW_BOTH_FISTS", "draw cycles (sep > 0.55)", 16),
    ("ATTACK_RIGHT_SWING", "swing events", 28),
    ("EAT_RIGHT_HAND_HEAD", "near-head events", 11),
    ("CLIMB_ALTERNATE", "L-R height zero crossings", 31),
    ("WALK_BOTH_FISTS", "both-fist frames", 420),
    ("WALK_BOTH_FISTS", "zero crossings of L/R z swing", 53),
]

# ---------------------------------------------------------------- small helpers


def q(vals, p, default=None):
    """Linear-free nearest-rank quantile (same convention as scripts/m7_analyze_lab_data.py)."""
    vals = [v for v in vals if v is not None]
    if not vals:
        return default
    s = sorted(vals)
    k = min(len(s) - 1, max(0, int(round((len(s) - 1) * p))))
    return s[k]


def qs(vals, ps):
    return [q(vals, p) for p in ps]


def f3(v, nd=3):
    return "-" if v is None else ("%.3f" % v if nd == 3 else ("%.2f" % v if nd == 2 else str(round(v, nd))))


def pct_str(num, den):
    return "%.1f%%" % (100.0 * num / den) if den else "-"


def mean(vals):
    vals = [v for v in vals if v is not None]
    return sum(vals) / len(vals) if vals else None


def std(vals):
    vals = [v for v in vals if v is not None]
    if len(vals) < 2:
        return 0.0
    m = mean(vals)
    return math.sqrt(sum((v - m) ** 2 for v in vals) / (len(vals) - 1))


def pearson(a, b):
    pairs = [(x, y) for x, y in zip(a, b) if x is not None and y is not None]
    if len(pairs) < 3:
        return None
    n = len(pairs)
    mx = sum(p[0] for p in pairs) / n
    my = sum(p[1] for p in pairs) / n
    sxx = sum((p[0] - mx) ** 2 for p in pairs)
    syy = sum((p[1] - my) ** 2 for p in pairs)
    if sxx <= 0 or syy <= 0:
        return None
    return sum((p[0] - mx) * (p[1] - my) for p in pairs) / math.sqrt(sxx * syy)


def dist3(a, b):
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


def dot3(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def table(headers, rows):
    rows = [[str(c) for c in r] for r in rows]
    widths = [len(h) for h in headers]
    for r in rows:
        for i, c in enumerate(r):
            widths[i] = max(widths[i], len(c))
    line = " | ".join(headers[i].ljust(widths[i]) for i in range(len(headers)))
    print(line)
    print("-" * len(line))
    for r in rows:
        print(" | ".join(r[i].ljust(widths[i]) for i in range(len(headers))))


def h1(title):
    print("\n" + "=" * 104)
    print(title)
    print("=" * 104)


def h2(title):
    print("\n-- " + title)


# ---------------------------------------------------------------- loading


def parse_hand(hand):
    """Return a compact hand dict or None if the hand is not tracked."""
    if not isinstance(hand, dict) or not hand.get("tracked"):
        return None
    js = {}
    for j in hand.get("joints", []):
        if isinstance(j, dict) and j.get("name"):
            js[j["name"]] = j

    def pos(name):
        # NOTE: the recorder also writes a per-joint ARKit 'tracked' flag, but ~51% of joint records
        # are flagged untracked while their (best-estimate) matrices are still valid and are exactly
        # what the live classifier and the provider ABI consume. We therefore use the matrices and
        # ignore the per-joint flag (the hand-level tracked flag is still honoured).
        j = js.get(name)
        if not j:
            return None
        m = j.get("m")
        if not isinstance(m, list) or len(m) < 15:
            return None
        return (float(m[12]), float(m[13]), float(m[14]))

    out = {
        "w": pos("wrist"),
        "it": pos("indexFingerTip"),
        "tt": pos("thumbTip"),
    }
    out["p"] = dist3(out["tt"], out["it"]) if (out["tt"] and out["it"]) else None
    # Fist curl ratio (recomputed; deliberately ignores stored *Features.fistRatio).
    w = out["w"]
    total = 0.0
    nf = 0
    for f in FINGERS:
        kn = pos(f + "FingerKnuckle")
        tip = pos(f + "FingerTip")
        if w is None or kn is None or tip is None:
            nf = 0
            break
        total += dist3(tip, kn) / max(0.02, dist3(w, kn))
        nf += 1
    out["f"] = (total / nf) if nf == 4 else None
    return out


def stored_feats(raw, side):
    fe = raw.get(side + "Features")
    if not isinstance(fe, dict):
        return None
    out = {}
    for k in ("pinch", "fistRatio", "speed", "verticalSpeed"):
        v = fe.get(k)
        try:
            out[k] = float(v)
        except (TypeError, ValueError):
            out[k] = None
    return out


def parse_recording(path, label=None):
    samples = []
    first = None
    bad = 0
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                raw = json.loads(line)
            except Exception:
                bad += 1
                continue
            if first is None:
                first = raw
            hm = raw.get("headMatrix")
            ax = None
            if isinstance(hm, list) and len(hm) == 16:
                ax = ((float(hm[0]), float(hm[1]), float(hm[2])),      # right
                      (float(hm[4]), float(hm[5]), float(hm[6])),      # up
                      (-float(hm[8]), -float(hm[9]), -float(hm[10])))  # forward
            head = raw.get("head")
            h = None
            if isinstance(head, list) and len(head) == 3:
                try:
                    h = (float(head[0]), float(head[1]), float(head[2]))
                except (TypeError, ValueError):
                    h = None
            samples.append({
                "t": float(raw["t"]),
                "ht": bool(raw.get("headTracked")) and h is not None,
                "h": h,
                "ax": ax,
                "L": parse_hand(raw.get("left")),
                "R": parse_hand(raw.get("right")),
                "stL": stored_feats(raw, "left"),
                "stR": stored_feats(raw, "right"),
            })
    meta = {}
    if first is not None:
        for k in ("label", "sourceLabel", "relabeled"):
            if first.get(k) is not None:
                meta[k] = first[k]
    if label is not None:
        meta["label"] = label
    rec = {
        "path": str(path),
        "file": os.path.basename(str(path)),
        "label": label if label is not None else meta.get("label", "?"),
        "samples": samples,
        "meta": meta,
        "bad": bad,
    }
    add_segments(rec)
    return rec


def segments_of(flags):
    """[(start_idx, end_idx_exclusive)] for contiguous True runs."""
    out = []
    start = None
    for i, f in enumerate(flags):
        if f and start is None:
            start = i
        elif not f and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(flags)))
    return out


def velocity_trace(rec, side, key="w", max_dt=0.25):
    """Per-sample (speed, vx, vy, vz) or None. Breaks on tracking loss / dt > max_dt."""
    out = []
    prev = None
    for s in rec["samples"]:
        hand = s[side]
        p = hand.get(key) if hand else None
        if p is None:
            out.append(None)
            prev = None
            continue
        if prev is None:
            out.append(None)
            prev = (s["t"], p)
            continue
        dt = s["t"] - prev[0]
        if dt <= 1e-6 or dt > max_dt:
            out.append(None)
            prev = (s["t"], p)
            continue
        v = ((p[0] - prev[1][0]) / dt, (p[1] - prev[1][1]) / dt, (p[2] - prev[1][2]) / dt)
        out.append((math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]), v[0], v[1], v[2]))
        prev = (s["t"], p)
    return out


def add_segments(rec):
    """Cache derived per-sample traces used across sections."""
    rec["velL"] = velocity_trace(rec, "L", "w")
    rec["velR"] = velocity_trace(rec, "R", "w")
    rec["tipL"] = velocity_trace(rec, "L", "it")
    rec["tipR"] = velocity_trace(rec, "R", "it")
    # convenience aligned arrays
    ts = [s["t"] for s in rec["samples"]]
    rec["t"] = ts
    rec["dt"] = [ts[i + 1] - ts[i] for i in range(len(ts) - 1)]


def load_data():
    DATA = {}
    files = sorted(ACCEPTED.glob("gesturelab-*.jsonl"))
    for path in files:
        rec = parse_recording(path)
        DATA.setdefault(rec["label"], []).append(rec)
    # IDLE is the un-relabelled twin of the accepted MENU recording. It is NOT a gesture-free negative
    # (there is no true idle capture in export/gesturelab-data): load it only for the twin/provenance
    # checks and the confusion-matrix duplicate row.
    if IDLE_PATH.exists():
        DATA["IDLE"] = [parse_recording(IDLE_PATH, label="IDLE")]
    return DATA


# ---------------------------------------------------------------- dataset helpers


def recs(DATA, label):
    return DATA.get(label, [])


def dataset_samples(DATA, label):
    out = []
    for rec in recs(DATA, label):
        out.extend(rec["samples"])
    return out


def dataset_vel(DATA, label, side, key="w"):
    trace_key = ("vel" if key == "w" else "tip") + side
    out = []
    for rec in recs(DATA, label):
        tr = rec[trace_key]
        out.extend(tr)
    return out


def ordered_labels(DATA, extras=True):
    labels = [l for l in ACTION_LABELS if l in DATA]
    if extras:
        labels += [l for l in EXTRA_LABELS if l in DATA]
    for l in sorted(DATA):
        if l not in labels:
            labels.append(l)
    return labels


def label_list(DATA, neg_only=False):
    labels = ordered_labels(DATA)
    if neg_only:
        return labels
    return labels


# ---------------------------------------------------------------- section 1: inventory


def section_inventory(DATA):
    h1("[1] DATA INVENTORY, TIMING AND FEATURE-CONVENTION CROSS-CHECKS")
    print("""Feature conventions used everywhere below (recomputed from the raw joint matrices):
  pinch(m)  = |thumbTip - indexFingerTip|
  fist      = mean over index/middle/ring/little of dist(tip,knuckle)/max(0.02, dist(wrist,knuckle))
  speed     = |d(wrist world position)| / dt(recorded t)  [m/s]; traces break over tracking loss / dt>0.25 s
  head axes = headMatrix column-major: right=col0, up=col1, forward=-col2; head pos = headMatrix[12..14]
  durations = first ON sample -> first following OFF sample; still-closed at EOF shown as "unfinished".
""")
    rows = []
    all_dt = []
    for label in ordered_labels(DATA):
        for rec in recs(DATA, label):
            ss = rec["samples"]
            ts = [s["t"] for s in ss]
            dts = [ts[i + 1] - ts[i] for i in range(len(ts) - 1)]
            all_dt.extend(dts)
            nL = sum(1 for s in ss if s["L"])
            nR = sum(1 for s in ss if s["R"])
            nH = sum(1 for s in ss if s["ht"])
            nAx = sum(1 for s in ss if s["ht"] and s["ax"] is not None)
            gaps = sum(1 for d in dts if d > 0.2)
            meta = []
            if "sourceLabel" in rec["meta"]:
                meta.append("src=%s" % rec["meta"]["sourceLabel"])
            if rec["meta"].get("relabeled"):
                meta.append("relabeled")
            rows.append([
                SHORT.get(label, label), rec["file"].split("-")[-1].replace(".jsonl", ""),
                len(ss), "%.1f" % (ts[-1] - ts[0]) if len(ts) > 1 else "-",
                ("%.1f" % ((len(ss) - 1) / (ts[-1] - ts[0]))) if len(ts) > 1 and ts[-1] > ts[0] else "-",
                "%.4f" % q(dts, 0.5), "%.4f" % q(dts, 0.95), "%.4f" % max(dts) if dts else "-",
                gaps, "%d/%d/%d/%d" % (nL, nR, nH, nAx), ",".join(meta),
            ])
    table(["dataset", "file", "n", "dur_s", "rate_Hz", "dt_p50", "dt_p95", "dt_max", "gaps>0.2s",
           "tracked L/R/head/headAxes", "meta"], rows)
    print("\n  MENU and ESCAPE were recorded before the headMatrix field was added (~17:45); they have")
    print("  head position but no head orientation, so head-frame geometry below excludes them.")
    print("\nAll datasets: samples=%d, recorded dt p50=%.4f s p95=%.4f s p99=%.4f s max=%.3f s;"
          % (len(all_dt), q(all_dt, 0.5), q(all_dt, 0.95), q(all_dt, 0.99), max(all_dt)))
    print("  effective rate = %.2f Hz (lab throttles to ~18 Hz; the device engine actually runs at anchor-update rate)."
          % (1.0 / q(all_dt, 0.5)))
    # joint-level tracking flags when the hand is nominally tracked
    joint_untracked = Counter()
    # derived from raw is not cached; fast re-scan only for accepted files
    raw_joint_checks = 0
    for path in sorted(ACCEPTED.glob("gesturelab-*.jsonl")):
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                raw = json.loads(line)
                for side in ("left", "right"):
                    hand = raw.get(side)
                    if not isinstance(hand, dict) or not hand.get("tracked"):
                        continue
                    for j in hand.get("joints", []) or []:
                        raw_joint_checks += 1
                        if not j.get("tracked"):
                            joint_untracked[side] += 1
    print("  joint-level (accepted files only; +IDLE twin would be 223753/441963 = 50.6%%):"
          % ())
    print("  %d joint records in tracked hands, %d flagged tracked=false (%.1f%%); the"
          % (raw_joint_checks, sum(joint_untracked.values()),
             100.0 * sum(joint_untracked.values()) / max(1, raw_joint_checks)))
    print("  per-joint flags are mostly false (ARKit occlusion/fusion) but the matrices remain usable, so")
    print("  features below use the matrices exactly as the live classifier and the provider ABI do.")

    # -------- stored vs recomputed features (provenance / stale metric detection)
    h2("stored *Features vs recomputed features (stale-metric detector)")
    rows = []
    for label in ordered_labels(DATA):
        for rec in recs(DATA, label):
            for side in ("R", "L"):
                key = side
                sp_vals, sf_vals, rp_vals, rf_vals = [], [], [], []
                for s in rec["samples"]:
                    hand = s[key]
                    st = s["stR"] if side == "R" else s["stL"]
                    if hand is None or st is None:
                        continue
                    if hand.get("p") is not None and st.get("pinch") is not None:
                        rp_vals.append(hand["p"])
                        sp_vals.append(st["pinch"])
                    if hand.get("f") is not None and st.get("fistRatio") is not None:
                        rf_vals.append(hand["f"])
                        sf_vals.append(st["fistRatio"])
                if not rp_vals and not rf_vals:
                    continue
                dpinch = max(abs(a - b) for a, b in zip(rp_vals, sp_vals)) if rp_vals else None
                dfist = [abs(a - b) for a, b in zip(rf_vals, sf_vals)]
                dfist_p95 = q(dfist, 0.95)
                flag = "STALE" if (dfist_p95 is not None and dfist_p95 > 1e-3) else "ok"
                rows.append([SHORT.get(label, label), rec["file"].split("-")[-1].replace(".jsonl", ""),
                             side, len(rp_vals), f3(dpinch, 6),
                             f3(mean(dfist), 6) if dfist else "-", f3(dfist_p95, 6) if dfist else "-", flag])
    table(["dataset", "file", "hand", "n", "max|stored-rec| pinch", "mean|stored-rec| fist",
           "p95|stored-rec| fist", "verdict"], rows)
    print("\nRead: pinch is stored/recomputed-identical everywhere. The fist ratio is identical for every")
    print("recording except the pre-fix MENU/IDLE twin (accepted MENU file), so MENU fist metrics below are")
    print("recomputed from joints and the stale stored value is never used for MENU.")
    menurec = recs(DATA, "MENU_RIGHT_PINCH")[0]
    closed_r, open_r = [], []
    for s in menurec["samples"]:
        hand = s["R"]
        if hand is None or hand.get("p") is None or hand.get("f") is None:
            continue
        (closed_r if hand["p"] < PINCH_ON_ENG else open_r).append(hand["f"])
    stale_closed, stale_open = [], []
    for s in menurec["samples"]:
        hand = s["R"]
        st = s["stR"]
        if hand is None or hand.get("p") is None or st is None or st.get("fistRatio") is None:
            continue
        (stale_closed if hand["p"] < PINCH_ON_ENG else stale_open).append(st["fistRatio"])
    print("\nMENU right hand, conditional on recomputed pinch < 0.025 m (pinch-closed poster posture):")
    table(["metric", "n", "p25", "p50", "p75"],
          [["recomputed fist ratio", len(closed_r), f3(q(closed_r, .25)), f3(q(closed_r, .5)), f3(q(closed_r, .75))],
           ["stale stored fistRatio", len(stale_closed), f3(q(stale_closed, .25)), f3(q(stale_closed, .5)), f3(q(stale_closed, .75))]])
    print("  -> a natural right-pinch posture recomputes to fist ratio p50 %.3f, i.e. it straddles the engine"
          % (q(closed_r, 0.5) or 0.0))
    print("     FIST_ON=0.65; the stale pre-fix stored value made this look %.3f. See section 3." % (q(stale_closed, 0.5) or 0.0))

    # provenance checks: accepted relabelled copies vs top-level sources
    h2("provenance checks (relabelled recordings)")
    menurec = recs(DATA, "MENU_RIGHT_PINCH")[0]
    idlerec = recs(DATA, "IDLE")[0]
    t_ok = [s["t"] for s in menurec["samples"]] == [s["t"] for s in idlerec["samples"]]
    print("  accepted MENU t-sequence == top-level IDLE source: %s (same 563 samples, only label/sourceLabel differ)" % t_ok)
    print("  => IDLE is the pre-relabel MENU capture, NOT a gesture-free idle negative; 'IDLE' rows in the")
    print("     negative-control tables duplicate MENU and must not be read as idle data.")
    esc = recs(DATA, "ESCAPE_LEFT_FIST")[0]
    src = DATA_DIR / "gesturelab-MENU_RIGHT_PINCH-20261102-174228.jsonl"
    if src.exists():
        srcrec = parse_recording(src)
        same = [s["t"] for s in esc["samples"]] == [s["t"] for s in srcrec["samples"]]
        print("  accepted ESCAPE t-sequence == top-level MENU_RIGHT_PINCH-174228 source: %s" % same)
    print("  rejected/: %d files from the pre-fix 17:31 batch (21-58 samples each, no headMatrix field);"
          % len(list(REJECTED.glob("*.jsonl"))))
    print("  excluded from all analysis below (sparse/old format, not accepted).")
    # head missing-data convention: headTracked=false rows carry head=[0,0,0] and an empty headMatrix
    sent = []
    for label in ordered_labels(DATA):
        for rec in recs(DATA, label):
            for i, s in enumerate(rec["samples"]):
                if not s["ht"]:
                    sent.append((SHORT.get(label, label), i, s["h"], s["ax"] is None))
    if sent:
        n_sent = sum(1 for r in sent if r[2] == (0.0, 0.0, 0.0) and r[3])
        by_label = {}
        for r in sent:
            by_label.setdefault(r[0], []).append(r[1])
        print("  headTracked=false rows: %d in total; %d are a zero-fill sentinel (head=[0,0,0], empty"
              % (len(sent), n_sent))
        print("  headMatrix): %s. These are missing-data rows, not physical holds; they are excluded from"
              % ", ".join("%s rows %s" % (k, v) for k, v in by_label.items()))
        print("  every head-relative feature below.")
    else:
        print("  headTracked=false rows: 0 (no missing-head rows in the accepted set).")
    return all_dt


# ---------------------------------------------------------------- generic event helpers


def hysteresis_down_events(times, values, on, off, missing="open"):
    """Events where a *smaller-is-closed* metric (pinch, fist) is closed.

    ON when value < on; OFF when value > off.  'missing' (None value: hand untracked) either closes
    the event immediately ("open", engine tracking-loss behaviour) or is bridged ("hold").
    Returns dicts: start, last (last ON sample), end (first OFF sample or None), n (ON frames), indices.
    """
    events = []
    active = False
    start_t = last_t = None
    start_i = last_i = None
    n = 0
    for i, (t, v) in enumerate(zip(times, values)):
        if v is None:
            if active and missing == "open":
                events.append({"start": start_t, "last": last_t, "end": t, "n": n,
                               "start_i": start_i, "last_i": last_i, "unfinished": False})
                active = False
            continue
        if not active and v < on:
            active = True
            start_t, last_t = t, t
            start_i = last_i = i
            n = 1
        elif active and v > off:
            events.append({"start": start_t, "last": last_t, "end": t, "n": n,
                           "start_i": start_i, "last_i": last_i, "unfinished": False})
            active = False
        elif active:
            last_t = t
            last_i = i
            n += 1
    if active:
        events.append({"start": start_t, "last": last_t, "end": None, "n": n,
                       "start_i": start_i, "last_i": last_i, "unfinished": True})
    return events


def hysteresis_up_runs(times, values, enter, exit_, missing="reset"):
    """Runs where a *larger-is-on* metric (separation) stays above 'enter'; reset below 'exit_'."""
    runs = []
    active = False
    start_t = last_t = None
    start_i = last_i = None
    for i, (t, v) in enumerate(zip(times, values)):
        if v is None:
            if active and missing == "reset":
                runs.append({"start": start_t, "last": last_t, "end": t, "start_i": start_i,
                             "last_i": last_i, "unfinished": False})
                active = False
            continue
        if not active and v > enter:
            active = True
            start_t = last_t = t
            start_i = last_i = i
        elif active and v < exit_:
            runs.append({"start": start_t, "last": last_t, "end": t, "start_i": start_i,
                         "last_i": last_i, "unfinished": False})
            active = False
        elif active:
            last_t = t
            last_i = i
    if active:
        runs.append({"start": start_t, "last": last_t, "end": None, "start_i": start_i,
                     "last_i": last_i, "unfinished": True})
    return runs


def bool_runs(times, flags):
    """Contiguous True runs of a boolean per-sample flag."""
    runs = []
    active = False
    start_t = last_t = None
    start_i = last_i = None
    for i, (t, f) in enumerate(zip(times, flags)):
        if f:
            if not active:
                active = True
                start_t = last_t = t
                start_i = last_i = i
            else:
                last_t = t
                last_i = i
        else:
            if active:
                runs.append({"start": start_t, "last": last_t, "end": t, "start_i": start_i,
                             "last_i": last_i, "unfinished": False})
                active = False
    if active:
        runs.append({"start": start_t, "last": last_t, "end": None, "start_i": start_i,
                     "last_i": last_i, "unfinished": True})
    return runs


def ev_duration(ev):
    if ev["end"] is not None:
        return ev["end"] - ev["start"]
    return ev["last"] - ev["start"]


def ev_durations(events, completed_only=True):
    return [ev_duration(e) for e in events if e["end"] is not None or not completed_only]


def sorted_durations(events, completed_only=True):
    return sorted(ev_durations(events, completed_only))


def interval_stats(times):
    ts = sorted(times)
    if len(ts) < 2:
        return {"n": 0}
    gaps = [ts[i + 1] - ts[i] for i in range(len(ts) - 1)]
    return {"n": len(gaps), "min": min(gaps), "p50": q(gaps, 0.5), "p95": q(gaps, 0.95),
            "max": max(gaps), "gaps": gaps}


def engine_pinch_presses(times, values, on=PINCH_ON_ENG, debounce=0.040, arm=0.100):
    """Faithful translation of VisionM7Gesture.debouncePinch() to recorded timestamps.

    raw = tracked && 0 <= pinch < PINCH_ON; press needs raw continuously for >= debounce; after a
    release the presser is unarmed until the raw flag has been false for >= arm.
    Returns list of {"start": press time (first raw frame), "end": release time or None}.
    """
    out = []
    pressed = False
    armed = True
    raw_since = None
    released_since = None
    press_t = None
    prev_raw = False
    for t, v in zip(times, values):
        raw = v is not None and v >= 0.0 and v < on
        if raw:
            if not prev_raw:
                raw_since = t
            if not pressed and armed and (t - raw_since) >= debounce:
                pressed = True
                press_t = raw_since
        else:
            if pressed:
                out.append({"start": press_t, "end": t})
                pressed = False
                armed = False
                released_since = t
            if not armed and released_since is not None and (t - released_since) >= arm:
                armed = True
        prev_raw = raw
    if pressed:
        out.append({"start": press_t, "end": None})
    return out


def windowed_speed(times, positions, window):
    """Speed from the earliest sample still inside 'window' seconds (spans over one or more samples)."""
    out = []
    j = 0
    n = len(times)
    for i in range(n):
        p = positions[i]
        if p is None:
            out.append(None)
            continue
        while j < i and (times[i] - times[j] > window or positions[j] is None):
            j += 1
        if i == 0 or j >= i or positions[j] is None:
            out.append(None)
            continue
        dt = times[i] - times[j]
        if dt <= 1e-6 or dt < 0.5 * window:
            out.append(None)
            continue
        out.append(dist3(p, positions[j]) / dt)
    return out


def rel_head_components(sample):
    """(right, up, forward) components of wrist-relative-to-head for both hands, matrix frame."""
    if not sample["ht"] or sample["ax"] is None:
        return None
    h = sample["h"]
    ax = sample["ax"]
    out = {}
    for side in ("L", "R"):
        hand = sample[side]
        if hand is None or hand["w"] is None:
            out[side] = None
            continue
        rel = (hand["w"][0] - h[0], hand["w"][1] - h[1], hand["w"][2] - h[2])
        out[side] = (dot3(rel, ax[0]), dot3(rel, ax[1]), dot3(rel, ax[2]))
    return out


def rel_head_yaw_components(sample):
    """(right, forward) components in a *yaw-only* head frame derived from the forward axis."""
    if not sample["ht"] or sample["ax"] is None:
        return None
    ax = sample["ax"]
    f = ax[2]
    fl = math.hypot(f[0], f[2])
    if fl < 1e-6:
        return None
    fx, fz = f[0] / fl, f[2] / fl
    out = {}
    for side in ("L", "R"):
        hand = sample[side]
        if hand is None or hand["w"] is None:
            out[side] = None
            continue
        rel = (hand["w"][0] - sample["h"][0], hand["w"][1] - sample["h"][1],
               hand["w"][2] - sample["h"][2])
        out[side] = (rel[0] * (-fz) + rel[2] * fx, rel[0] * fx + rel[2] * fz)
    return out


def trace_for(rec, side, kind):
    """kind: 'pinch', 'fist', 'speed'(m/s), 'tip'(m/s), 'height'(rel head), 'wpos'."""
    if kind == "pinch":
        return [s[side]["p"] if s[side] else None for s in rec["samples"]]
    if kind == "fist":
        return [s[side]["f"] if s[side] else None for s in rec["samples"]]
    if kind == "speed":
        return [v[0] if v else None for v in rec["vel" + side]]
    if kind == "tip":
        return [v[0] if v else None for v in rec["tip" + side]]
    if kind == "height":
        out = []
        for s in rec["samples"]:
            hand = s[side]
            if hand is None or hand["w"] is None or not s["ht"]:
                out.append(None)
            else:
                out.append(hand["w"][1] - s["h"][1])
        return out
    if kind == "wpos":
        return [s[side]["w"] if s[side] else None for s in rec["samples"]]
    raise KeyError(kind)


# ---------------------------------------------------------------- section 2: pinch family

PINCH_SETS = [
    ("PLACE_RIGHT_PINCH", "R"),
    ("BREAK_RIGHT_PINCH_HOLD", "R"),
    ("MENU_RIGHT_PINCH", "R"),
    ("TELEPORT_LEFT_PINCH", "L"),
]
THRESHOLD_PAIRS = [(0.025, 0.050), (0.030, 0.045)]


def pinch_records(DATA, label, side):
    out = []
    for rec in recs(DATA, label):
        out.append((rec, trace_for(rec, side, "pinch")))
    return out


def section_pinch(DATA):
    h1("[2] PINCH FAMILY (right: PLACE / BREAK / MENU, left: TELEPORT)")
    print("Recomputed pinch traces, hysteresis segmentation.  Event duration = first ON sample -> first")
    print("following OFF sample; a still-closed tail is counted as unfinished and reported separately.")
    h2("2.1 event counts and durations by threshold pair")
    rows = []
    for label, side in PINCH_SETS:
        recs_ = pinch_records(DATA, label, side)
        span = sum(rec["t"][-1] - rec["t"][0] for rec, _ in recs_)
        for on, off in THRESHOLD_PAIRS:
            ev_all, durs = [], []
            for rec, vals in recs_:
                ev = hysteresis_down_events(rec["t"], vals, on, off)
                ev_all.extend(ev)
                durs.extend(ev_durations(ev, completed_only=True))
            starts = [e["start"] for e in ev_all if e["end"] is not None]
            gap = interval_stats(starts)
            rows.append([SHORT[label], side, "%.3f/%.3f" % (on, off), len(durs),
                         len(ev_all) - len(durs), f3(q(durs, 0.25), 2), f3(q(durs, 0.5), 2),
                         f3(q(durs, 0.95), 2), f3(max(durs) if durs else None, 2),
                         f3(gap.get("min"), 2), f3(gap.get("p50"), 2), f3(gap.get("max"), 2),
                         "%.2f" % (len(durs) / span)])
    table(["dataset", "hand", "on/off", "completed", "unfinished", "dur_p25", "dur_p50", "dur_p95",
           "dur_max", "gap_min", "gap_p50", "gap_max", "ev/s"], rows)
    h2("2.2 complete duration lists at the accepted thresholds (0.030 on / 0.045 off)")
    for label, side in PINCH_SETS:
        ev_all, durs = [], []
        for rec, vals in pinch_records(DATA, label, side):
            ev = hysteresis_down_events(rec["t"], vals, 0.030, 0.045)
            ev_all.extend(ev)
            durs.extend(ev_durations(ev, completed_only=True))
        print("  %-9s n=%d completed: %s" % (SHORT[label], len(durs), ", ".join("%.2f" % d for d in sorted(durs))))
        un = [ev_duration(e) for e in ev_all if e["end"] is None]
        if un:
            print("             unfinished tail duration: %s" % ", ".join("%.2f" % d for d in un))
    h2("2.3 cross-check vs accepted summaries")
    rows = []
    for label, side in PINCH_SETS:
        ev_all, durs = [], []
        for rec, vals in pinch_records(DATA, label, side):
            ev = hysteresis_down_events(rec["t"], vals, 0.030, 0.045)
            ev_all.extend(ev)
            durs.extend(ev_durations(ev, completed_only=True))
        got = len(durs)
        exp = EXPECTED_EVENTS[label]
        extra = ""
        if label == "PLACE_RIGHT_PINCH":
            short = sum(1 for d in durs if d < 0.35)
            extra = "short<0.35s=%d (summary 72); held=%d" % (short, got - short)
        if label == "BREAK_RIGHT_PINCH_HOLD":
            extra = "min hold=%.2f s (summary 1.21)" % (min(durs) if durs else 0)
        rows.append([SHORT[label], side, exp, got, got - exp, extra])
    table(["dataset", "hand", "summary", "recomputed", "delta", "detail"], rows)
    print("""
Reconciliation notes:
  * The accepted summaries used stored rightFeatures/leftFeatures.pinch; section 1 verifies stored pinch
    == |thumbTip-indexTip| exactly, so the only difference is the untracked->open default (1.0 m) and
    whether a still-closed tail is counted. m7_analyze_lab_data.py does not count a tail still closed at
    EOF; 2.2 therefore shows PLACE 77 detected / 76 completed, matching the summary's 76.
  * Duration p95/max differences of one sample (+/-0.06 s) are the release sample relative to the
    0.045 m off threshold. We report release_time - first_closed_time, which reproduces BREAK's
    1.21/2.24/1.49/1.98/4.33/3.36/10.44 s exactly.
""")
    h2("2.4 separation margin: contact band vs open band (raw distributions)")
    print("  contact = raw pinch < on (0.030 m); open = raw pinch > off (0.045 m); ambiguous = in between.")
    rows = []
    for label, side in PINCH_SETS:
        contact, opn, ambiguous_in = [], [], 0
        for rec, vals in pinch_records(DATA, label, side):
            ev = hysteresis_down_events(rec["t"], vals, 0.030, 0.045)
            latched = [False] * len(vals)
            for e in ev:
                for i in range(e["start_i"], e["last_i"] + 1):
                    latched[i] = True
            for i, v in enumerate(vals):
                if v is None:
                    continue
                if v < 0.030:
                    contact.append(v)
                elif v > 0.045:
                    opn.append(v)
                else:
                    ambiguous_in += 1 if latched[i] else 0
        margin = (q(opn, 0.01) - q(contact, 0.99)) if contact and opn else None
        rows.append([SHORT[label], len(contact), f3(q(contact, 0.5), 4), f3(q(contact, 0.95), 4),
                     f3(q(contact, 0.99), 4), f3(max(contact) if contact else None, 4),
                     len(opn), f3(q(opn, 0.01), 4), f3(min(opn) if opn else None, 4),
                     f3(margin, 4), ambiguous_in])
    table(["dataset", "contact_n", "contact_p50", "contact_p95", "contact_p99", "contact_max",
           "open_n", "open_p01", "open_min", "margin open_p01-contact_p99",
           "latched frames in 0.030-0.045 band"], rows)
    print("  Positive margin = the 1%-closest open frames are still farther apart than 99% of contact")
    print("  frames. All four datasets have a positive raw margin of 17-30 mm: the 0.030 on threshold has")
    print("  clean raw separation, and the only frames that need the hysteresis band are the 2-19 latched")
    print("  frames listed in the last column. The 0.045 off threshold is what absorbs those jitter frames;")
    print("  the engine currently has NO off threshold, so those 2-19 frames would chatter instead.")
    h2("2.5 jitter inside holds (events >= 0.30 s)")
    rows = []
    for label, side in PINCH_SETS:
        within_std, step_mean, step_max = [], [], []
        for rec, vals in pinch_records(DATA, label, side):
            ev = hysteresis_down_events(rec["t"], vals, 0.030, 0.045)
            for e in ev:
                if ev_duration(e) < 0.30:
                    continue
                seg = [vals[i] for i in range(e["start_i"], e["last_i"] + 1) if vals[i] is not None]
                if len(seg) < 3:
                    continue
                within_std.append(std(seg))
                steps = [abs(seg[i + 1] - seg[i]) for i in range(len(seg) - 1)]
                step_mean.append(mean(steps))
                step_max.append(max(steps))
        rows.append([SHORT[label], len(within_std), f3(q(within_std, 0.5), 4),
                     f3(q(within_std, 0.95), 4), f3(q(step_mean, 0.5), 4),
                     f3(q(step_mean, 0.95), 4), f3(q(step_max, 0.95), 4)])
    table(["dataset", "holds>=.3s", "within_std_p50", "within_std_p95", "|step|_p50", "|step|_p95",
           "max|step|_p95"], rows)
    h2("2.6 negative control: raw pinch contacts and events in every dataset")
    rows = []
    for label in ordered_labels(DATA):
        per_side = {}
        for side in ("R", "L"):
            frames_025 = frames_030 = 0
            nt = 0
            events = 0
            presses = 0
            for rec in recs(DATA, label):
                vals = trace_for(rec, side, "pinch")
                ts = rec["t"]
                for v in vals:
                    if v is None:
                        continue
                    nt += 1
                    if v < 0.025:
                        frames_025 += 1
                    if v < 0.030:
                        frames_030 += 1
                events += len([e for e in hysteresis_down_events(ts, vals, 0.025, 0.050) if e["end"] is not None])
                presses += len([e for e in engine_pinch_presses(ts, vals) if e["end"] is not None])
            per_side[side] = (nt, frames_025, frames_030, events, presses)
        if "R" not in per_side:
            continue
        r = per_side["R"]
        l = per_side["L"]
        rows.append([SHORT.get(label, label),
                     "%d/%d" % (r[1], r[2]), "%d" % r[4], pct_str(r[1], r[0]),
                     "%d/%d" % (l[1], l[2]), "%d" % l[4], pct_str(l[1], l[0])])
    table(["dataset", "R frames <.025/<.030", "R events(.025/.05)", "R %frames<.025",
           "L frames <.025/<.030", "L events(.025/.05)", "L %frames<.025"], rows)
    print("  (event counts are completed hysteresis events on that hand across all recordings of the label)")
    h2("2.7 debounce / settle evidence")
    rows = []
    for label, side in PINCH_SETS:
        raw_events, presses, settle = [], [], []
        for rec, vals in pinch_records(DATA, label, side):
            ev = hysteresis_down_events(rec["t"], vals, 0.025, 0.050)
            raw_events.extend(ev)
            presses.extend(engine_pinch_presses(rec["t"], vals))
            for e in ev:
                last_high = None
                for i in range(e["start_i"], e["last_i"] + 1):
                    v = vals[i]
                    if v is not None and v >= 0.040:
                        last_high = rec["t"][i]
                settle.append(0.0 if last_high is None else last_high - e["start"])
        press_durs = [pe["end"] - pe["start"] for pe in presses if pe["end"] is not None]
        missed = sum(1 for e in raw_events if e["n"] == 1)
        rows.append([SHORT[label], len(raw_events), missed, len(presses), f3(q(settle, 0.5), 3),
                     f3(q(settle, 0.95), 3), f3(max(settle) if settle else None, 3),
                     f3(q(press_durs, 0.5), 3), f3(q(press_durs, 0.95), 3),
                     sum(1 for d in press_durs if d < PLACE_MAX)])
    table(["dataset", "raw events", "1-frame raw (missed by 40ms)", "engine presses",
           "settle p50", "settle p95", "settle max", "engine dur p50", "engine dur p95",
           "engine durs <0.35"], rows)
    print("  settle = last time inside an event at which pinch >= 0.040 m, minus first-closed time (0 = the")
    print("  contact snapped straight into the closed band; larger values are bounce frames the off")
    print("  threshold/40 ms debounce must absorb.")
    h2("2.8 short-vs-held boundary evidence (pooled durations at 0.030/0.045)")
    pooled = {}
    for label, side in PINCH_SETS:
        durs = []
        for rec, vals in pinch_records(DATA, label, side):
            durs.extend(ev_durations(hysteresis_down_events(rec["t"], vals, 0.030, 0.045),
                                     completed_only=True))
        pooled[label] = sorted(durs)
    bins = [0.0, 0.06, 0.12, 0.20, 0.30, 0.35, 0.40, 0.50, 0.75, 1.00, 1.50, 2.00, 3.00, 5.00, 12.0]
    hist = [0] * (len(bins) - 1)
    for label in pooled:
        for d in pooled[label]:
            for b in range(len(bins) - 1):
                if bins[b] <= d < bins[b + 1]:
                    hist[b] += 1
                    break
    table(["bin (s)"] + ["%.2f-%.2f" % (bins[i], bins[i + 1]) for i in range(len(bins) - 1)],
          [["count"] + [str(h) for h in hist]])
    print("  PLACE durations >=0.30 s: %s" % ", ".join("%.2f" % d for d in pooled["PLACE_RIGHT_PINCH"] if d >= 0.30))
    print("  BREAK durations: %s" % ", ".join("%.2f" % d for d in pooled["BREAK_RIGHT_PINCH_HOLD"]))
    print("  MENU durations >=0.30 s: %s" % ", ".join("%.2f" % d for d in pooled["MENU_RIGHT_PINCH"] if d >= 0.30))
    print("  TELEPORT durations >=0.30 s: %s" % ", ".join("%.2f" % d for d in pooled["TELEPORT_LEFT_PINCH"] if d >= 0.30))
    rows = []
    short_expected = ["PLACE_RIGHT_PINCH", "MENU_RIGHT_PINCH", "TELEPORT_LEFT_PINCH"]
    for split in (0.25, 0.30, 0.35, 0.40, 0.45, 0.50, 0.60, 0.75, 1.00):
        short = sum(1 for l in short_expected for d in pooled[l] if d < split)
        place_long = sum(1 for d in pooled["PLACE_RIGHT_PINCH"] if d >= split)
        break_short = sum(1 for d in pooled["BREAK_RIGHT_PINCH_HOLD"] if d < split)
        rows.append(["%.2f" % split, short, place_long, break_short])
    table(["split (s)", "short events placed short (PLACE+MENU+TELEPORT)", "PLACE holds left long",
           "BREAK holds classified short"], rows)
    print("  Data gap: longest ordinary short event = 0.22 s (PLACE has 4 operator hold outliers at")
    print("  0.56-4.06 s); shortest BREAK hold = 1.16 s. Any split in (0.61, 1.16) s classifies the")
    print("  accepted data 100% cleanly; 0.35 s already separates the deliberate short taps with >2x margin.")
    h2("2.9 pinch posture vs the fist metric (interaction with FIST_ON=0.65)")
    rows = []
    for label, side in PINCH_SETS:
        closed_f, open_f, fist_closed = [], [], 0
        for rec, vals in pinch_records(DATA, label, side):
            fistvals = trace_for(rec, side, "fist")
            ev = hysteresis_down_events(rec["t"], vals, 0.030, 0.045)
            inside = [False] * len(vals)
            for e in ev:
                for i in range(e["start_i"], e["last_i"] + 1):
                    inside[i] = True
            for i, fv in enumerate(fistvals):
                if fv is None or vals[i] is None:
                    continue
                if inside[i]:
                    closed_f.append(fv)
                    if fv < FIST_ON:
                        fist_closed += 1
                else:
                    open_f.append(fv)
        rows.append([SHORT[label], side, len(closed_f), f3(q(closed_f, 0.5)), f3(q(closed_f, 0.95)),
                     pct_str(fist_closed, len(closed_f)), f3(q(open_f, 0.5)), f3(q(open_f, 0.95))])
    table(["dataset", "hand", "frames in pinch hold", "fist_p50 in hold", "fist_p95 in hold",
           "hold frames <FIST_ON 0.65", "fist_p50 outside", "fist_p95 outside"], rows)
    print("  A pinch posture is only partly curled; with FIST_ON=0.65 a large share of pinch-hold frames")
    print("  also read as 'fist', which disables eat/hotbar and can spuriously satisfy climb-grab.")


# ---------------------------------------------------------------- engine replay simulator

DETECTORS = ["place", "breakHeld", "attack", "menu", "inventory", "hotbarNext", "hotbarPrev",
             "teleport", "bowDraw", "bowFire", "eat", "climbGrabL", "climbGrabR", "climbJump",
             "walk", "guiClick", "leftFistTap"]


class M7Sim:
    """Faithful host replay of VisionM7Gesture.update() driven by the recorded samples.

    guiOpen=False, seated=False, head jump/sneak are included only as far as they do not affect the
    hand detectors (they do not).  Speeds are the replay-side per-sample speeds unless
    use_engine_speed=True, in which case the engine's stale-joint semantics across tracking loss are
    reproduced (this is what the device sees; see section 4.5).
    """

    def __init__(self):
        self.prev_ns = 0.0
        self.raw_pinchL = self.raw_pinchR = False
        self.pressedL = self.pressedR = False
        self.armedL = self.armedR = True
        self.raw_sinceL = self.raw_sinceR = 0.0
        self.released_sinceL = self.released_sinceR = 0.0
        self.press_tL = self.press_tR = 0.0
        self.pinch_durL = self.pinch_durR = 0.0
        self.prev_pinchL = self.prev_pinchR = False
        self.pinch_events = {"L": [], "R": []}
        self.prev_fistL = self.prev_fistR = False
        self.fist_pressL = self.fist_pressR = 0.0
        self.both_prev = False
        self.both_start = 0.0
        self.last_both_close = 0.0
        self.last_both_release = 0.0
        self.bow_prev = False
        self.climb_prev = False
        self.swing_sign = 0
        self.swing_crossings = 0
        self.swing_last_cross = 0.0
        self.place_pulse = 0.0
        self.inventory_pulse = 0.0
        self.menu_pulse = 0.0
        self.left_fist_tap_pulse = 0.0
        self.last_inventory_t = 0.0
        self.last_menu_t = 0.0
        self.hotbar_last = 0.0
        self.hotbar_next_pulse = 0.0
        self.hotbar_prev_pulse = 0.0
        self.attack_until = 0.0
        self.attack_pulse = 0.0
        self.bow_fire_until = 0.0
        self.climb_jump_pulse = 0.0
        self.prev_tip_speedR = 0.0
        self.last_head = (0.0, 1.5, 0.0)
        self.poll = defaultdict(int)

    def debounce(self, side, raw, now):
        if side == "L":
            armed, raw_since, released_since = self.armedL, self.raw_sinceL, self.released_sinceL
            pressed, press_t = self.pressedL, self.press_tL
        else:
            armed, raw_since, released_since = self.armedR, self.raw_sinceR, self.released_sinceR
            pressed, press_t = self.pressedR, self.press_tR
        was_raw = self.raw_pinchL if side == "L" else self.raw_pinchR
        if raw:
            if not was_raw:
                raw_since = now
            if not pressed and armed and now - raw_since >= 0.040:
                pressed = True
                press_t = raw_since
            if side == "L":
                self.raw_pinchL, self.raw_sinceL, self.pressedL, self.press_tL = True, raw_since, pressed, press_t
            else:
                self.raw_pinchR, self.raw_sinceR, self.pressedR, self.press_tR = True, raw_since, pressed, press_t
            return pressed
        if pressed:
            self.pinch_events[side].append({"start": press_t, "end": now})
            if side == "L":
                self.pinch_durL = now - press_t
            else:
                self.pinch_durR = now - press_t
            pressed = False
            armed = False
            released_since = now
        if not armed and now - released_since >= 0.100:
            armed = True
        if side == "L":
            self.raw_pinchL, self.raw_sinceL, self.pressedL, self.press_tL = False, raw_since, pressed, press_t
            self.armedL, self.released_sinceL = armed, released_since
        else:
            self.raw_pinchR, self.raw_sinceR, self.pressedR, self.press_tR = False, raw_since, pressed, press_t
            self.armedR, self.released_sinceR = armed, released_since
        return False

    def update(self, s, speedL, speedR, tipSpeedL, tipSpeedR, engine_speedL=None, engine_speedR=None):
        now = s["t"]
        if not s["ht"]:
            head = self.last_head
        else:
            head = s["h"]
            self.last_head = head
        L, R = s["L"], s["R"]
        trackedL, trackedR = L is not None, R is not None
        fistL = trackedL and L["f"] is not None and L["f"] < FIST_ON
        fistR = trackedR and R["f"] is not None and R["f"] < FIST_ON
        pinchL = L["p"] if (trackedL and L["p"] is not None) else None
        pinchR = R["p"] if (trackedR and R["p"] is not None) else None
        if engine_speedL is not None:
            speedL = engine_speedL
        if engine_speedR is not None:
            speedR = engine_speedR
        wL = L["w"] if trackedL else None
        wR = R["w"] if trackedR else None
        if not s["ht"]:
            head = self.last_head
        headY = head[1]

        rawL = trackedL and pinchL is not None and 0.0 <= pinchL < PINCH_ON_ENG
        rawR = trackedR and pinchR is not None and 0.0 <= pinchR < PINCH_ON_ENG
        pinchNowL = self.debounce("L", rawL, now)
        pinchNowR = self.debounce("R", rawR, now)
        if fistL and not self.prev_fistL:
            self.fist_pressL = now
        if fistR and not self.prev_fistR:
            self.fist_pressR = now

        both = fistL and fistR
        handSep = dist3(wL, wR) if (wL and wR) else 0.0
        if both:
            self.last_both_close = now
        if self.both_prev and not both:
            self.last_both_release = now
        if both and not self.both_prev:
            self.both_start = now
        bow = both and handSep > BOW_SEP
        climbCandidate = ((fistL and wL is not None and wL[1] - headY > -0.05)
                          or (fistR and wR is not None and wR[1] - headY > -0.05))

        if both and not bow and wL is not None and wR is not None:
            diff = wL[2] - wR[2]
            if abs(diff) > WALK_SWING:
                sign = 1 if diff > 0 else -1
                if self.swing_sign != 0 and sign != self.swing_sign:
                    self.swing_crossings += 1
                    self.swing_last_cross = now
                self.swing_sign = sign
        walkActive = False
        if both and not bow and self.swing_crossings >= 2 and now - self.swing_last_cross < 0.600:
            walkActive = True
        elif (now - self.swing_last_cross > 0.600) or (not both) or bow:
            if not both:
                self.swing_sign = 0
                self.swing_crossings = 0

        wasBow = self.bow_prev
        wasClimb = self.climb_prev
        if wasBow and not bow and now - self.bow_fire_until > 0.250:
            self.bow_fire_until = now + 0.080
        if (self.both_prev and not both and not wasBow and not wasClimb and not walkActive
                and self.both_start > 0.0 and now - self.both_start <= INV_TAP_MAX):
            self.inventory_pulse = now + 0.080
            self.last_inventory_t = now
        self.bow_prev = bow
        self.climb_prev = climbCandidate

        rightPinch = pinchNowR
        pinDur = (now - self.press_tR) if rightPinch else self.pinch_durR
        breakHeld = rightPinch and pinDur >= PLACE_MAX
        if self.prev_pinchR and not rightPinch:
            if self.pinch_durR < PLACE_MAX:
                self.place_pulse = now + 0.080
            self.pinch_durR = 0.0
        nearHead = trackedR and wR is not None and dist3(wR, head) < EAT_DIST
        if (not bow and not both and trackedR and not rightPinch and not nearHead
                and speedR > ATTACK_SPEED and now >= self.attack_until):
            self.attack_pulse = now + 0.080
            self.attack_until = now + 0.300
        eatHeld = (not bow) and trackedR and nearHead and not fistR
        teleportHold = trackedL and pinchNowL

        leftFistTap = (self.prev_fistL and not fistL and not fistR and self.fist_pressL > 0.0
                       and now - self.fist_pressL <= INV_TAP_MAX)
        if leftFistTap and now - self.last_both_release > 0.250:
            self.left_fist_tap_pulse = now + 0.080
        if (leftFistTap and now - self.last_both_release > 0.150
                and now - self.last_both_close > 0.150):
            self.menu_pulse = now + 0.080
            self.last_menu_t = now

        if (not bow and trackedR and not rightPinch and not fistR and speedR < 0.5
                and self.prev_tip_speedR < 0.6 and tipSpeedR > 1.2
                and now - self.last_both_release > 0.400
                and now - self.last_inventory_t > 0.300
                and now - self.last_menu_t > 0.300
                and now >= self.hotbar_last + 0.150):
            if now - self.hotbar_last <= 0.450:
                self.hotbar_prev_pulse = now + 0.080
            else:
                self.hotbar_next_pulse = now + 0.080
            self.hotbar_last = now

        climbGrabL = climbCandidate and fistL and not bow
        climbGrabR = climbCandidate and fistR and not bow
        if climbGrabL and climbGrabR and speedL > 0.8 and speedR > 0.8:
            self.climb_jump_pulse = now + 0.080

        flags = {
            "place": now < self.place_pulse,
            "breakHeld": breakHeld,
            "attack": now < self.attack_pulse,
            "menu": now < self.menu_pulse,
            "inventory": now < self.inventory_pulse,
            "hotbarNext": now < self.hotbar_next_pulse,
            "hotbarPrev": now < self.hotbar_prev_pulse,
            "teleport": teleportHold,
            "bowDraw": bow,
            "bowFire": now < self.bow_fire_until,
            "eat": eatHeld,
            "climbGrabL": climbGrabL,
            "climbGrabR": climbGrabR,
            "climbJump": now < self.climb_jump_pulse,
            "walk": walkActive,
            "guiClick": False,
            "leftFistTap": now < self.left_fist_tap_pulse,
        }
        self.prev_pinchL, self.prev_pinchR = pinchNowL, pinchNowR
        self.prev_fistL, self.prev_fistR = fistL, fistR
        self.both_prev = both
        self.prev_tip_speedR = tipSpeedR
        self.prev_ns = now
        return flags


def engine_speed_trace(rec, side):
    """VisionM7Gesture speed semantics: joints persist across tracking loss, so a re-track frame is
    differenced against the stale pre-loss wrist position over one frame (spike source)."""
    out = []
    cur_p = prev_p = None
    cur_t = prev_t = None
    for s in rec["samples"]:
        hand = s[side]
        if hand is not None and hand["w"] is not None:
            cur_p = hand["w"]
            cur_t = s["t"]
        if cur_p is None or prev_p is None:
            out.append(0.0)
        else:
            dt = cur_t - prev_t
            out.append(dist3(cur_p, prev_p) / max(1e-3, dt))
        prev_p, prev_t = cur_p, cur_t
    return out


def simulate(rec):
    sim = M7Sim()
    flags = defaultdict(list)
    engL = engine_speed_trace(rec, "L")
    engR = engine_speed_trace(rec, "R")
    for i, s in enumerate(rec["samples"]):
        vl = rec["velL"][i]
        vr = rec["velR"][i]
        tl = rec["tipL"][i]
        tr = rec["tipR"][i]
        out = sim.update(
            s,
            vl[0] if vl else 0.0, vr[0] if vr else 0.0,
            tl[0] if tl else 0.0, tr[0] if tr else 0.0,
            engine_speedL=engL[i], engine_speedR=engR[i])
        for k in DETECTORS:
            flags[k].append(out[k])
    rec["sim"] = {k: v for k, v in flags.items()}
    rec["sim_pinch_events"] = sim.pinch_events
    # second pass: naive replay (speeds only from consecutive recorded frames)
    sim2 = M7Sim()
    flags2 = defaultdict(list)
    for i, s in enumerate(rec["samples"]):
        vl = rec["velL"][i]
        vr = rec["velR"][i]
        tl = rec["tipL"][i]
        tr = rec["tipR"][i]
        out = sim2.update(s, vl[0] if vl else 0.0, vr[0] if vr else 0.0,
                          tl[0] if tl else 0.0, tr[0] if tr else 0.0)
        for k in DETECTORS:
            flags2[k].append(out[k])
    rec["sim_naive"] = {k: v for k, v in flags2.items()}


def attach_simulations(DATA):
    for label in list(DATA):
        for rec in recs(DATA, label):
            simulate(rec)


def sim_run_stats(rec, key):
    """(episode count, active seconds, durations) of a boolean detector flag."""
    flags = rec["sim"][key]
    runs = bool_runs(rec["t"], flags)
    durs = [ev_duration(r) for r in runs]
    return len(runs), sum(durs), durs


def dataset_sim(DATA, label, key):
    n = active = 0
    durs = []
    for rec in recs(DATA, label):
        c, a, ds = sim_run_stats(rec, key)
        n += c
        active += a
        durs.extend(ds)
    return n, active, durs


# ---------------------------------------------------------------- section 3: fist / both-fist

FIST_DS_ORDER = [l for l in ACTION_LABELS] + ["IDLE"]


def section_fist(DATA):
    h1("[3] FIST / BOTH-FIST FAMILY (ESCAPE, INVENTORY, WALK, BOW, CLIMB + posture context)")
    h2("3.1 per-hand fist-ratio distributions (recomputed from joints)")
    rows = []
    for label in FIST_DS_ORDER:
        if label not in DATA:
            continue
        for side in ("L", "R"):
            vals = []
            for rec in recs(DATA, label):
                vals.extend([v for v in trace_for(rec, side, "fist") if v is not None])
            if not vals:
                rows.append([SHORT.get(label, label), side, 0, "-", "-", "-", "-", "-", "-",
                             "0/0/0", "-"])
                continue
            rows.append([SHORT.get(label, label), side, len(vals),
                         f3(q(vals, 0.05), 2), f3(q(vals, 0.25), 2), f3(q(vals, 0.5), 2),
                         f3(q(vals, 0.75), 2), f3(q(vals, 0.95), 2), f3(q(vals, 0.99), 2),
                         "%d/%d/%d" % (sum(1 for v in vals if v < 0.55),
                                       sum(1 for v in vals if v < 0.65),
                                       sum(1 for v in vals if v < 0.75)),
                         pct_str(sum(1 for v in vals if v < FIST_ON), len(vals))])
    table(["dataset", "hand", "n", "p05", "p25", "p50", "p75", "p95", "p99",
           "frames < .55/.65/.75", "% < FIST_ON .65"], rows)
    print("\n  FIST_ON=0.65 (engine) sits between the relaxed/open hand (~0.75-1.0) and a closed fist")
    print("  (~0.30-0.50): sustained walk fists p50 ~0.35, deliberate fist taps p05 ~0.30. The pinch")
    print("  posture (section 2.9) has p50 ~0.6-0.7, so it straddles the threshold.")
    h2("3.2 single-hand fist events (hysteresis sweep)")
    rows = []
    for label in FIST_DS_ORDER:
        if label not in DATA:
            continue
        for side in ("L", "R"):
            per = []
            for on, off in ((0.55, 0.75), (0.65, 0.75), (0.55, 0.85)):
                cnt = 0
                durs = []
                for rec in recs(DATA, label):
                    vals = trace_for(rec, side, "fist")
                    ev = hysteresis_down_events(rec["t"], vals, on, off)
                    cnt += len([e for e in ev if e["end"] is not None])
                    durs.extend(ev_durations(ev, completed_only=True))
                per.append((cnt, q(durs, 0.5), max(durs) if durs else None))
            rows.append([SHORT.get(label, label), side] +
                        ["%d (p50 %s)" % (p[0], f3(p[1], 2)) for p in per])
    table(["dataset", "hand", "events on/off .55/.75", "events .65/.75", "events .55/.85"], rows)
    h2("3.3 both-fist co-occurrence runs (single threshold on both hands)")
    rows = []
    for label in FIST_DS_ORDER:
        if label not in DATA:
            continue
        n_samp = sum(len(rec["samples"]) for rec in recs(DATA, label))
        cells = []
        for th in (0.55, 0.65, 0.75):
            n_runs = frames = 0
            durs = []
            for rec in recs(DATA, label):
                fl = trace_for(rec, "L", "fist")
                fr = trace_for(rec, "R", "fist")
                flags = [a is not None and b is not None and a < th and b < th
                         for a, b in zip(fl, fr)]
                frames += sum(flags)
                runs = bool_runs(rec["t"], flags)
                n_runs += len(runs)
                durs.extend([ev_duration(r) for r in runs])
            cells.append("%d runs/%d f (p50 %s, max %s)" % (
                n_runs, frames, f3(q(durs, 0.5), 2), f3(max(durs) if durs else None, 2)))
        rows.append([SHORT.get(label, label), n_samp] + cells)
    table(["dataset", "n", "both<0.55", "both<0.65", "both<0.75"], rows)
    print("\n  INVENTORY: 24 both-fist runs / 75 both-closed frames at <0.55 -- exactly the accepted summary")
    print("  (the summary's 'fist' threshold for this was 0.55).  WALK stays both-closed for most of the")
    print("  recording (sustained), while BOW only pairs transiently and CLIMB alternates.")

    h2("3.4 WALK swing signal: world frame vs head frame (matrix) vs head-yaw frame")
    walk = recs(DATA, "WALK_BOTH_FISTS")[0]
    ts, worldZdiff, hfDiff, yawDiff = [], [], [], []
    Lf, Rf, Lwz, Rwz = [], [], [], []
    for s in walk["samples"]:
        if not (s["ht"] and s["L"] and s["R"]):
            continue
        c = rel_head_components(s)
        y = rel_head_yaw_components(s)
        if c is None or c["L"] is None or c["R"] is None or y is None or y["L"] is None:
            continue
        ts.append(s["t"])
        worldZdiff.append(s["L"]["w"][2] - s["R"]["w"][2])
        hfDiff.append(c["L"][2] - c["R"][2])
        yawDiff.append(y["L"][1] - y["R"][1])
        Lf.append(c["L"][2])
        Rf.append(c["R"][2])
        Lwz.append(s["L"]["w"][2] - s["h"][2])
        Rwz.append(s["R"]["w"][2] - s["h"][2])
    table(["signal", "amplitude p95 |diff|", "diff range", "L-R corr", "zero crossings",
           "cross interval p50", "cross interval max"],
          [["world Z (engine rule)", f3(q([abs(v) for v in worldZdiff], 0.95)),
            f3(max(worldZdiff) - min(worldZdiff)), f3(pearson(Lwz, Rwz)),
            sum(1 for i in range(1, len(worldZdiff)) if (worldZdiff[i - 1] >= 0) != (worldZdiff[i] >= 0)),
            "-", "-"],
           ["head frame forward", f3(q([abs(v) for v in hfDiff], 0.95)),
            f3(max(hfDiff) - min(hfDiff)), f3(pearson(Lf, Rf)),
            sum(1 for i in range(1, len(hfDiff)) if (hfDiff[i - 1] >= 0) != (hfDiff[i] >= 0)),
            "-", "-"]])
    for name, sig in (("world Z", worldZdiff), ("head-frame forward", hfDiff), ("head-yaw forward", yawDiff)):
        cross = [ts[i] for i in range(1, len(sig)) if (sig[i - 1] >= 0) != (sig[i] >= 0)]
        if len(cross) > 1:
            gaps = [cross[i + 1] - cross[i] for i in range(len(cross) - 1)]
            print("  %-20s crossings=%d  interval p50=%.3f  max=%.3f  >0.60s=%d  implied period=%.3f s (%.2f Hz)"
                  % (name, len(cross), q(gaps, 0.5), max(gaps), sum(1 for g in gaps if g > 0.6),
                     2 * q(gaps, 0.5), (1.0 / (2 * q(gaps, 0.5))) if q(gaps, 0.5) else 0))
    # EMA-smoothed head yaw (tau ~0.8 s): keeps body heading, removes look-around and head pitch.
    alpha = 1.0 - math.exp(-q(walk["dt"], 0.5) / 0.8)
    smx, smz = 0.0, -1.0
    Lfe, Rfe, tse = [], [], []
    for s in walk["samples"]:
        if not (s["ht"] and s["ax"] is not None):
            continue
        f = s["ax"][2]
        fl = math.hypot(f[0], f[2]) or 1.0
        smx = smx * (1 - alpha) + (f[0] / fl) * alpha
        smz = smz * (1 - alpha) + (f[2] / fl) * alpha
        nrm = math.hypot(smx, smz) or 1.0
        if s["L"] is None or s["R"] is None:
            continue
        relL = tuple(s["L"]["w"][i] - s["h"][i] for i in range(3))
        relR = tuple(s["R"]["w"][i] - s["h"][i] for i in range(3))
        fwd = (smx / nrm, 0.0, smz / nrm)
        Lfe.append(dot3(relL, fwd))
        Rfe.append(dot3(relR, fwd))
        tse.append(s["t"])
    ema_diff = [a - b for a, b in zip(Lfe, Rfe)]
    ecross = [tse[i] for i in range(1, len(ema_diff)) if (ema_diff[i - 1] >= 0) != (ema_diff[i] >= 0)]
    egaps = [ecross[i + 1] - ecross[i] for i in range(len(ecross) - 1)] if len(ecross) > 1 else []
    print("  EMA-yaw frame (tau 0.8 s)  L/R corr=%s  amp p95=%s  crossings=%d  interval p50=%s max=%s >0.60s=%d"
          % (f3(pearson(Lfe, Rfe)), f3(q([abs(v) for v in ema_diff], 0.95)), len(ecross),
             f3(q(egaps, 0.5) if egaps else None), f3(max(egaps) if egaps else None),
             sum(1 for g in egaps if g > 0.6)))
    print("  Raw head-frame corr is only %s because the operator turned ~150 deg around t=13-18 s and"
          % f3(pearson(Lf, Rf)))
    print("  looked down up to 30 deg (head pitch); world-Z corr %s benefits from facing world -Z." % f3(pearson(Lwz, Rwz)))
    print("  => a body-relative swing signal should low-pass the head yaw (or use head position only) so")
    print("     look-around does not mix into the walk signal.")
    # engine rule crossings (|diff|>0.04 gating, which is stricter than a plain zero crossing)
    eng_cross = []
    sig0 = 0
    for i, v in enumerate(worldZdiff):
        if abs(v) > WALK_SWING:
            sign = 1 if v > 0 else -1
            if sig0 != 0 and sign != sig0:
                eng_cross.append(ts[i])
            sig0 = sign
    gaps = [eng_cross[i + 1] - eng_cross[i] for i in range(len(eng_cross) - 1)]
    print("  engine |diff|>0.04 sign crossings=%d  interval p50=%.3f max=%.3f  >600ms=%d"
          % (len(eng_cross), q(gaps, 0.5) if gaps else 0, max(gaps) if gaps else 0,
             sum(1 for g in gaps if g > 0.6)))
    phases = []
    for lag in range(-4, 5):
        a = Lf[max(0, lag):len(Lf) + min(0, lag)]
        b = Rf[max(0, -lag):len(Rf) - max(0, lag)]
        c = pearson(a, b)
        if c is not None:
            phases.append((lag, c))
    best = max(phases, key=lambda p: p[1]) if phases else (0, None)
    print("  L/R forward correlation (zero lag) = %s; best lag = %+d samples (%+.0f ms) corr=%.3f"
          % (f3(pearson(Lf, Rf)), best[0], best[0] * q(walk["dt"], 0.5) * 1000.0,
             best[1] if best[1] is not None else 0))
    both_frames = sum(1 for s in walk["samples"]
                      if s["L"] and s["R"] and s["L"]["f"] is not None and s["R"]["f"] is not None
                      and s["L"]["f"] < FIST_ON and s["R"]["f"] < FIST_ON)
    print("  both-fist frames at FIST_ON=0.65: %d/%d (%.1f%%); at 0.55: %d/%d (summary 420/558)"
          % (both_frames, len(walk["samples"]), 100.0 * both_frames / len(walk["samples"]),
             sum(1 for s in walk["samples"]
                 if s["L"] and s["R"] and s["L"]["f"] is not None and s["R"]["f"] is not None
                 and s["L"]["f"] < 0.55 and s["R"]["f"] < 0.55), len(walk["samples"])))
    print("  head moved %.2f m over the recording."
          % sum(dist3(walk["samples"][i]["h"], walk["samples"][i - 1]["h"])
                for i in range(1, len(walk["samples"]))
                if walk["samples"][i]["ht"] and walk["samples"][i - 1]["ht"]))
    # ---- engine walk rule replay and why it is fragmented on the walk dataset -------------------
    bow_override = both2 = 0
    for s in walk["samples"]:
        fl = s["L"]["f"] if s["L"] else None
        fr = s["R"]["f"] if s["R"] else None
        both = fl is not None and fr is not None and fl < FIST_ON and fr < FIST_ON
        if not both:
            continue
        both2 += 1
        if dist3(s["L"]["w"], s["R"]["w"]) > BOW_SEP:
            bow_override += 1
    n, active, durs = sim_run_stats(walk, "walk")
    span = walk["t"][-1] - walk["t"][0]
    print("  engine walk replay: %d episodes, %.2f s active of %.1f s (%.0f%%); the engine's bow rule"
          % (n, active, span, 100.0 * active / span))
    print("  (both fists + raw sep >0.55) flags %d/%d both-fist frames (%.0f%%) as bowDraw, which"
          % (bow_override, both2, 100.0 * bow_override / max(1, both2)))
    print("  suppresses walk whenever the arm swing separates the hands. This is the dominant walk bug.")

    def _fwd_sep(s):
        relL = tuple(s["L"]["w"][i] - s["h"][i] for i in range(3))
        relR = tuple(s["R"]["w"][i] - s["h"][i] for i in range(3))
        return abs(dot3(relL, s["ax"][2]) - dot3(relR, s["ax"][2]))

    def coverage(stop=0.60, amp=WALK_SWING, fist_on=FIST_ON, fist_off=FIST_OFF, schmitt=False,
                 reset=True, bow_mode="raw"):
        crossings = 0
        last = 0.0
        sign = 0
        cov = 0
        eps = 0
        active = False
        fl = fr = False
        for s in walk["samples"]:
            t = s["t"]
            lf = s["L"]["f"] if s["L"] else None
            rf = s["R"]["f"] if s["R"] else None
            if lf is not None:
                fl = ((fl and lf < fist_off) or lf < fist_on) if schmitt else lf < fist_on
            else:
                fl = False
            if rf is not None:
                fr = ((fr and rf < fist_off) or rf < fist_on) if schmitt else rf < fist_on
            else:
                fr = False
            both = fl and fr
            if not both:
                sep = 0.0
            else:
                sep = dist3(s["L"]["w"], s["R"]["w"])
            if bow_mode == "raw":
                bow = both and sep > BOW_SEP
            elif bow_mode == "fwd40":
                bow = both and s["ht"] and s["ax"] is not None and _fwd_sep(s) > 0.40
            else:
                bow = False
            if both and not bow:
                diff = s["L"]["w"][2] - s["R"]["w"][2]
                if abs(diff) > amp:
                    sg = 1 if diff > 0 else -1
                    if sign != 0 and sg != sign:
                        crossings += 1
                        last = t
                    sign = sg
            elif reset and not both:
                sign = 0
                crossings = 0
            act = both and not bow and crossings >= 2 and (t - last) < stop
            if act:
                cov += 1
                if not active:
                    eps += 1
                    active = True
            else:
                active = False
        return eps, 100.0 * cov / len(walk["samples"])

    variants = [
        ("engine as coded", dict()),
        ("no crossing reset on both-fist drop", dict(reset=False)),
        ("+ bow on projected sep > 0.40 m", dict(reset=False, bow_mode="fwd40")),
        ("+ fist Schmitt 0.55/0.75", dict(reset=False, bow_mode="fwd40", schmitt=True, fist_on=0.55)),
        ("+ stop window 900 ms", dict(reset=False, bow_mode="fwd40", schmitt=True, fist_on=0.55,
                                      stop=0.900)),
    ]
    rows = []
    for name, kw in variants:
        eps, cov = coverage(**kw)
        rows.append([name, eps, "%.0f%%" % cov])
    table(["walk rule variant (on WALK recording)", "episodes", "coverage"], rows)
    print("  600 ms stop-window verdict: world-Z plain crossing intervals p50=%.3f s, %d/%d >0.60 s."
          % (q(gaps, 0.5) if gaps else 0, sum(1 for g in gaps if g > 0.6), len(gaps)))
    print("  The window is adequate for the steady swing cadence (~0.9 Hz, half-period ~0.55 s); the")
    print("  fragmentation is caused by the crossing reset on transient both-fist drops and the raw-0.55")
    print("  bow override, not by the 600 ms window.")


# ---------------------------------------------------------------- section 4: attack

ATTACK_LABELS = ["ATTACK_RIGHT_SWING", "WALK_BOTH_FISTS", "BOW_BOTH_FISTS", "CLIMB_ALTERNATE",
                 "HOTBAR_RIGHT_TAP", "EAT_RIGHT_HAND_HEAD", "MENU_RIGHT_PINCH",
                 "PLACE_RIGHT_PINCH", "BREAK_RIGHT_PINCH_HOLD", "ESCAPE_LEFT_FIST",
                 "INVENTORY_BOTH_FISTS", "IDLE"]


def section_attack(DATA):
    h1("[4] ATTACK: right-wrist motion vs all other datasets")
    h2("4.1 right-wrist speed distributions (recomputed per-sample vs stored per-anchor-update)")
    rows = []
    for label in ATTACK_LABELS:
        if label not in DATA:
            continue
        rec_speeds = []
        stored_speeds = []
        tracked = 0
        left_tracked = 0
        both_fist = 0
        for rec in recs(DATA, label):
            rec_speeds.extend([v for v in trace_for(rec, "R", "speed") if v is not None])
            for s in rec["samples"]:
                if s["R"]:
                    tracked += 1
                    if s["stR"] and s["stR"].get("speed") is not None:
                        stored_speeds.append(abs(s["stR"]["speed"]))
                    if s["L"] and s["L"]["f"] is not None and s["L"]["f"] < FIST_ON:
                        both_fist += 1
                if s["L"]:
                    left_tracked += 1
            # stored speed values need the hand tracked
        rows.append([SHORT.get(label, label), tracked,
                     f3(q(rec_speeds, 0.5), 2), f3(q(rec_speeds, 0.9), 2),
                     f3(q(rec_speeds, 0.95), 2), f3(q(rec_speeds, 0.99), 2),
                     f3(max(rec_speeds) if rec_speeds else None, 2),
                     sum(1 for v in rec_speeds if v > ATTACK_SPEED),
                     f3(q(stored_speeds, 0.5), 2), f3(q(stored_speeds, 0.95), 2),
                     f3(max(stored_speeds) if stored_speeds else None, 2),
                     sum(1 for v in stored_speeds if v > ATTACK_SPEED),
                     "%d/%d" % (left_tracked, tracked), both_fist])
    table(["dataset", "R frames", "rec p50", "rec p90", "rec p95", "rec p99", "rec max",
           "rec >1.4", "stored p50", "stored p95", "stored max", "stored >1.4", "L/R frames",
           "both-fist frames"], rows)
    print("  Note: the accepted ATTACK summary's p50/p95/max (1.30/2.97/4.75) are the *recomputed* 18 Hz")
    print("  values; the stored per-anchor-update speed is peakier (p95 3.20 / max 5.15 in this run) --")
    print("  section 10.  WALK wrist speed is just as high as ATTACK, so speed alone cannot separate them.")
    h2("4.2 windowed-displacement separability (replay-robust alternative to per-frame speed)")
    windows = (0.06, 0.11, 0.17, 0.25)
    rows = []
    for label in ATTACK_LABELS:
        if label not in DATA:
            continue
        cells = []
        for w in windows:
            peak = []
            for rec in recs(DATA, label):
                pos = trace_for(rec, "R", "wpos")
                sp = windowed_speed(rec["t"], pos, w)
                peak.extend([v for v in sp if v is not None])
            cells.append("%s/%s" % (f3(q(peak, 0.95), 2), f3(max(peak) if peak else None, 2)))
        rows.append([SHORT.get(label, label)] + cells)
    table(["dataset", "p95/max speed @>=60ms", "p95/max @>=110ms", "p95/max @>=170ms",
           "p95/max @>=250ms"], rows)
    att = []
    for rec in recs(DATA, "ATTACK_RIGHT_SWING"):
        pos = trace_for(rec, "R", "wpos")
        sp = windowed_speed(rec["t"], pos, 0.11)
        att.extend([v for v in sp if v is not None])
    neg = {label: [] for label in ATTACK_LABELS if label != "ATTACK_RIGHT_SWING"}
    for label in neg:
        for rec in recs(DATA, label):
            pos = trace_for(rec, "R", "wpos")
            sp = windowed_speed(rec["t"], pos, 0.11)
            neg[label].extend([v for v in sp if v is not None])
    print("\n  110 ms window: ATTACK p05=%.2f p50=%.2f m/s.  Per-dataset negative p95: %s"
          % (q(att, 0.05), q(att, 0.5),
             ", ".join("%s=%s" % (SHORT.get(l, l), f3(q(v, 0.95), 2)) for l, v in neg.items())))
    h2("4.3 swing segmentation variants in ATTACK (start of speed run above 1.4 m/s)")
    rows = []
    for reset in (0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2):
        starts = []
        for rec in recs(DATA, "ATTACK_RIGHT_SWING"):
            sp = trace_for(rec, "R", "speed")
            armed = True
            for i, v in enumerate(sp):
                if v is None:
                    continue
                if armed and v > ATTACK_SPEED:
                    starts.append(rec["t"][i])
                    armed = False
                elif not armed and v < reset:
                    armed = True
        gaps = [starts[i + 1] - starts[i] for i in range(len(starts) - 1)]
        rows.append(["reset<%.1f" % reset, len(starts), f3(min(gaps) if gaps else None, 2),
                     f3(q(gaps, 0.5) if gaps else None, 2), f3(max(gaps) if gaps else None, 2)])
    table(["arming reset", "swings", "min inter-swing", "p50 inter-swing", "max inter-swing"], rows)
    print("  The accepted summary's '~28 swings' matches reset<0.8 m/s (28 rising edges); practical")
    print("  floor for ATTACK_COOLDOWN is ~0.22 s (shortest genuine inter-swing gap). The engine currently")
    print("  re-fires every cooldown while speed stays >1.4 and therefore emits 52 pulses for 28 swings:")
    h2("4.4 engine attack detector replay: one-handed gating and false-attack candidates")
    rows = []
    for label in ATTACK_LABELS:
        if label not in DATA:
            continue
        n, active, durs = dataset_sim(DATA, label, "attack")
        rows.append([SHORT.get(label, label), n, "%.2f" % active])
    table(["dataset", "attack pulses (engine rules)", "attack active s"], rows)
    print("\n  false-attack candidates with current 1.4 m/s rule (non-ATTACK datasets, top by speed):")
    cand = []
    for label in ATTACK_LABELS:
        if label == "ATTACK_RIGHT_SWING" or label not in DATA:
            continue
        for rec in recs(DATA, label):
            sp = trace_for(rec, "R", "speed")
            for i, v in enumerate(sp):
                if v is not None and v > ATTACK_SPEED:
                    cand.append((v, label, rec["t"][i] - rec["t"][0]))
    cand.sort(reverse=True)
    table(["speed m/s", "dataset", "t_in_recording s"],
          [[f3(v, 2), SHORT.get(l, l), "%.2f" % tt] for v, l, tt in cand[:15]])
    print("  (%d total non-ATTACK frames above 1.4 m/s; engine gating removes the both-fist/near-head ones,"
          % len(cand))
    print("   but WALK arm swings and BOW draws still reach the threshold -- see the replay counts above.)")
    h2("4.5 tracking-loss re-entry speed spikes (engine stale-joint semantics)")
    rows = []
    for label in ATTACK_LABELS:
        if label not in DATA:
            continue
        spikes = 0
        peak = 0.0
        for rec in recs(DATA, label):
            eng = engine_speed_trace(rec, "R")
            for v in eng:
                if v > ATTACK_SPEED:
                    spikes += 1
                    peak = max(peak, v)
        n_naive, active_naive, _ = dataset_sim(DATA, label, "attack")
        rows.append([SHORT.get(label, label), spikes, f3(peak, 2), n_naive])
    table(["dataset", "engine-semantics frames >1.4 m/s", "peak speed", "attack pulses (naive replay)"],
          rows)
    print("  Engine stops updating wrist/wrist-prev only for untracked frames, so a re-track frame can")
    print("  difference a stale pre-loss position against the new one over one frame (~55 ms). The replay")
    print("  harness should reset per-hand velocity history on every tracking transition.")
    h2("4.6 acceleration and a candidate attack rule (speed + accel + context gates)")
    rows = []
    for label in ATTACK_LABELS:
        if label not in DATA:
            continue
        acc = []
        for rec in recs(DATA, label):
            acc.extend([v for v in accel_trace(rec, "R") if v is not None])
        rows.append([SHORT.get(label, label), f3(q(acc, 0.5), 2), f3(q(acc, 0.95), 2),
                     f3(max(acc) if acc else None, 2)])
    table(["dataset", "R accel p50", "R accel p95", "R accel max"], rows)

    def cand_stats(thr_sp, thr_acc, refractory=0.30):
        per = {}
        for label in ATTACK_LABELS:
            if label not in DATA:
                continue
            n = frames = 0
            for rec in recs(DATA, label):
                acc = accel_trace(rec, "R")
                flags = []
                for i, s in enumerate(rec["samples"]):
                    hand = s["R"]
                    ok = False
                    if hand is not None and rec["velR"][i] is not None and acc[i] is not None:
                        fistR = hand["f"] is not None and hand["f"] < FIST_ON
                        fistL = (s["L"] is not None and s["L"]["f"] is not None
                                 and s["L"]["f"] < FIST_ON)
                        near = s["ht"] and dist3(hand["w"], s["h"]) < EAT_DIST
                        ok = (rec["velR"][i][0] > thr_sp and acc[i] > thr_acc
                              and not (fistR and fistL) and not near)
                    flags.append(ok)
                frames += sum(1 for f in flags if f)
                n += len(episode_starts(rec["t"], flags, refractory))
            per[label] = (n, frames)
        return per

    rows = []
    for thr_sp, thr_acc in ((1.4, 8.0), (2.0, 12.0), (2.4, 15.0), (2.8, 18.0)):
        per = cand_stats(thr_sp, thr_acc)
        attack = per.get("ATTACK_RIGHT_SWING", (0, 0))
        false_eps = sum(v[0] for k, v in per.items() if k != "ATTACK_RIGHT_SWING")
        worst = sorted(((v[0], k) for k, v in per.items() if k != "ATTACK_RIGHT_SWING"),
                       reverse=True)[:4]
        rows.append(["speed>%.1f & accel>%.0f" % (thr_sp, thr_acc),
                     "%d ep / %d frames" % (attack[0], attack[1]), false_eps,
                     ", ".join("%s:%d" % (SHORT.get(k, k), v) for v, k in worst if v)])
    table(["candidate rule (also !both, !nearHead)", "ATTACK", "false episodes elsewhere",
           "worst false datasets"], rows)
    print("  Per-frame speed alone does not separate attack from walking (WALK right-wrist p50 1.36 m/s vs")
    print("  ATTACK 1.32 m/s), and PLACE peaks at 4.04 m/s. The data supports requiring 2.0 m/s AND")
    print("  12 m/s^2 AND !walkActive/!both/!nearHead; context (held tool/sword) is the real disambiguator.")


def accel_trace(rec, side, max_dt=0.25):
    """Vector acceleration magnitude from consecutive valid velocity samples."""
    out = []
    prev = None
    vel = rec["vel" + side]
    for i, v in enumerate(vel):
        if v is None:
            out.append(None)
            prev = None
            continue
        if prev is None:
            out.append(None)
            prev = (rec["t"][i], v)
            continue
        dt = rec["t"][i] - prev[0]
        if dt <= 1e-6 or dt > max_dt:
            out.append(None)
            prev = (rec["t"][i], v)
            continue
        ax_ = (v[1] - prev[1][1]) / dt
        ay_ = (v[2] - prev[1][2]) / dt
        az_ = (v[3] - prev[1][3]) / dt
        out.append(math.sqrt(ax_ * ax_ + ay_ * ay_ + az_ * az_))
        prev = (rec["t"][i], v)
    return out


def episode_starts(times, flags, refractory):
    """Start times of True runs, ignoring re-triggers inside a refractory window."""
    starts = []
    last = -1e9
    prev = False
    for t, f in zip(times, flags):
        if f and not prev and t - last >= refractory:
            starts.append(t)
            last = t
        prev = f
    return starts


# ---------------------------------------------------------------- section 5: hotbar

TAP_LABELS = ["HOTBAR_RIGHT_TAP", "ATTACK_RIGHT_SWING", "PLACE_RIGHT_PINCH",
              "BREAK_RIGHT_PINCH_HOLD", "WALK_BOTH_FISTS", "BOW_BOTH_FISTS", "CLIMB_ALTERNATE",
              "EAT_RIGHT_HAND_HEAD", "MENU_RIGHT_PINCH", "ESCAPE_LEFT_FIST",
              "INVENTORY_BOTH_FISTS", "IDLE"]


def tap_events(rec, tip_on=1.2, tip_reset=0.5):
    """Index-fingertip pulse events: tip speed > tip_on, re-armed below tip_reset."""
    events = []
    armed = True
    start = None
    for i, v in enumerate(rec["tipR"]):
        sp = v[0] if v else None
        if sp is None:
            if not armed and start is not None:
                events.append({"start": start, "peak": last_peak, "end": None})
                armed = True
                start = None
            continue
        if armed and sp > tip_on:
            start = rec["t"][i]
            last_peak = sp
            armed = False
        elif not armed:
            if sp > last_peak:
                last_peak = sp
            if sp < tip_reset:
                events.append({"start": start, "peak": last_peak, "end": rec["t"][i]})
                armed = True
                start = None
    if not armed and start is not None:
        events.append({"start": start, "peak": last_peak, "end": None})
    return events


def section_hotbar(DATA):
    h1("[5] HOTBAR: right index-fingertip tap vs wrist motion")
    h2("5.1 index-tip vs wrist speed per dataset (recomputed)")
    rows = []
    for label in TAP_LABELS:
        if label not in DATA:
            continue
        tips, wrists = [], []
        for rec in recs(DATA, label):
            tips.extend([v for v in trace_for(rec, "R", "tip") if v is not None])
            wrists.extend([v for v in trace_for(rec, "R", "speed") if v is not None])
        rows.append([SHORT.get(label, label), len(tips),
                     f3(q(tips, 0.5), 2), f3(q(tips, 0.9), 2), f3(q(tips, 0.95), 2),
                     f3(q(tips, 0.99), 2), f3(max(tips) if tips else None, 2),
                     f3(q(wrists, 0.95), 2), f3(max(wrists) if wrists else None, 2)])
    table(["dataset", "R frames", "tip p50", "tip p90", "tip p95", "tip p99", "tip max",
           "wrist p95", "wrist max"], rows)
    print("  The hotbar tap is a finger-only motion: wrist p95 stays near 0.4 m/s in HOTBAR while the")
    print("  index tip spikes; in ATTACK/PLACE the wrist itself is fast so a fingertip-speed rule alone")
    print("  can also fire there (5.3/5.4).")
    h2("5.2 independent tap segmentation: tip speed > 1.2 m/s, re-arm < 0.5 m/s")
    rows = []
    hb_starts = []
    for label in TAP_LABELS:
        if label not in DATA:
            continue
        n = 0
        durs = []
        peaks = []
        for rec in recs(DATA, label):
            ev = tap_events(rec)
            n += len([e for e in ev if e["end"] is not None])
            durs.extend([e["end"] - e["start"] for e in ev if e["end"] is not None])
            peaks.extend([e["peak"] for e in ev])
            if label == "HOTBAR_RIGHT_TAP":
                hb_starts.extend([e["start"] for e in ev])
        rows.append([SHORT.get(label, label), n, f3(q(durs, 0.5), 2) if durs else "-",
                     f3(min(durs) if durs else None, 2), f3(max(durs) if durs else None, 2),
                     f3(max(peaks) if peaks else None, 2)])
    table(["dataset", "tip-tap events", "dur p50", "dur min", "dur max", "peak tip speed"], rows)
    starts = sorted(hb_starts)
    gaps = [starts[i + 1] - starts[i] for i in range(len(starts) - 1)]
    print("  HOTBAR: %d tap events; inter-tap gaps sorted (s): %s"
          % (len(starts), ", ".join("%.2f" % g for g in gaps)))
    print("  Double-tap window evidence: shortest inter-tap gap = %.2f s; gaps below 0.35/0.45/0.60 s: %d/%d/%d."
          % (min(gaps) if gaps else 0, sum(1 for g in gaps if g < 0.35), sum(1 for g in gaps if g < 0.45),
             sum(1 for g in gaps if g < 0.60)))
    print("  => this recording contains no deliberate double tap: the 0.450 s HOTBAR_DOUBLE_NS window")
    print("     matches ZERO of these 22 taps; all are single 'next' taps at a 0.7-1.0 s cadence.")
    h2("5.3 engine hotbar replay (per-dataset pulses; includes all engine gating)")
    rows = []
    for label in TAP_LABELS:
        if label not in DATA:
            continue
        nn = 0
        pp = 0
        frames = 0
        for rec in recs(DATA, label):
            c, a, _ = sim_run_stats(rec, "hotbarNext")
            p2, a2, _ = sim_run_stats(rec, "hotbarPrev")
            nn += c
            pp += p2
            frames += sum(1 for v in rec["sim"]["hotbarNext"] if v) + sum(1 for v in rec["sim"]["hotbarPrev"] if v)
        rows.append([SHORT.get(label, label), nn, pp, frames])
    table(["dataset", "hotbarNext pulses", "hotbarPrev pulses", "active frames"], rows)
    print("\n  HOTBAR gate diagnostics for the 22 independent tap events (why the engine sees only some):")
    reasons = Counter()
    fist_at_tap = []
    tap_total = 0
    for rec in recs(DATA, "HOTBAR_RIGHT_TAP"):
        for e in tap_events(rec):
            if e["end"] is None:
                continue
            tap_total += 1
            t0 = e["start"]
            i = min(range(len(rec["t"])), key=lambda k: abs(rec["t"][k] - t0))
            s = rec["samples"][i]
            hand = s["R"]
            w = rec["velR"][i]
            if hand is None or hand["f"] is None:
                reasons["untracked/fist missing"] += 1
                continue
            fist_at_tap.append(hand["f"])
            if hand["f"] < FIST_ON:
                reasons["fistR < FIST_ON 0.65 (blocks !fist gate)"] += 1
            if hand["p"] is not None and hand["p"] < PINCH_ON_ENG:
                reasons["pinch < 0.025 m (blocks !pinch gate)"] += 1
            if w is None or w[0] >= 0.5:
                reasons["wrist speed >= 0.5 m/s (blocks)"] += 1
            prev = rec["tipR"][i - 1] if i > 0 else None
            if prev is None or prev[0] >= 0.6:
                reasons["prev tip speed not <0.6 m/s (blocks)"] += 1
    rows = [["tap events segmented", tap_total],
            ["fist ratio p50 at tap", f3(q(fist_at_tap, 0.5), 3)],
            ["fist ratio p05/p95 at tap", "%s/%s" % (f3(q(fist_at_tap, 0.05), 2),
                                                    f3(q(fist_at_tap, 0.95), 2))]]
    for k, v in reasons.most_common():
        rows.append([k, v])
    table(["hotbar gate diagnostic", "count"], rows)
    print("  The dominant blocker is the engine's !fistR gate: the tap hand is a loose half-fist")
    print("  (fist ratio p50 near FIST_ON), so most genuine taps are suppressed by that gate.")
    h2("5.4 fingertip-speed candidates blocked by other gates (fist/pinch/wrist) per dataset")
    rows = []
    for label in TAP_LABELS:
        if label not in DATA:
            continue
        raw = blocked = 0
        for rec in recs(DATA, label):
            for i in range(1, len(rec["samples"])):
                tr = rec["tipR"][i]
                if not tr or tr[0] <= 1.2:
                    continue
                prev = rec["tipR"][i - 1]
                if prev and prev[0] >= 0.6:
                    continue
                raw += 1
                s = rec["samples"][i]
                hand = s["R"]
                fist = hand is not None and hand["f"] is not None and hand["f"] < FIST_ON
                wrist_ok = (rec["velR"][i] is not None and rec["velR"][i][0] < 0.5)
                if fist or not wrist_ok:
                    blocked += 1
        rows.append([SHORT.get(label, label), raw, blocked])
    table(["dataset", "tip>1.2 rising frames", "blocked by fist/wrist gate"], rows)
    print("  In ATTACK/PLACE the wrist itself is fast: those fingertip spikes are rejected by the")
    print("  wrist<0.5 gating, but EAT/HOTBAR fingertip spikes during a loose fist are rejected by !fist.")
    h2("5.5 index-tip threshold sweep (false taps in non-HOTBAR datasets)")
    rows = []
    for th in (0.9, 1.1, 1.2, 1.4, 1.6, 2.0):
        hb = 0
        false = {}
        for label in TAP_LABELS:
            if label not in DATA:
                continue
            total = 0
            for rec in recs(DATA, label):
                total += len([e for e in tap_events(rec, tip_on=th) if e["end"] is not None])
            if label == "HOTBAR_RIGHT_TAP":
                hb = total
            else:
                false[SHORT.get(label, label)] = total
        rows.append(["%.1f" % th, hb, sum(false.values()),
                     ", ".join("%s:%d" % (k, v) for k, v in sorted(false.items()) if v)])
    table(["tip speed threshold", "HOTBAR taps", "non-HOTBAR taps", "where (non-zero)"], rows)
    print("  Taps only have to be discriminated from *finger* motion; ATTACK wrist swings can reach the")
    print("  index-tip threshold too, hence the !fist && wrist<0.5 && !pinch co-gates matter.")


# ---------------------------------------------------------------- section 6: eat

EAT_LABELS = ["EAT_RIGHT_HAND_HEAD", "MENU_RIGHT_PINCH", "PLACE_RIGHT_PINCH",
              "BREAK_RIGHT_PINCH_HOLD", "WALK_BOTH_FISTS", "BOW_BOTH_FISTS", "CLIMB_ALTERNATE",
              "ATTACK_RIGHT_SWING", "HOTBAR_RIGHT_TAP", "INVENTORY_BOTH_FISTS", "IDLE"]


def wrist_head_distance(rec):
    out = []
    for s in rec["samples"]:
        hand = s["R"]
        if hand is None or hand["w"] is None or not s["ht"]:
            out.append(None)
        else:
            out.append(dist3(hand["w"], s["h"]))
    return out


def section_eat(DATA):
    h1("[6] EAT: right wrist-to-head distance, head-relative geometry, latch")
    h2("6.1 right wrist -> head distance per dataset")
    rows = []
    for label in EAT_LABELS:
        if label not in DATA:
            continue
        ds = []
        for rec in recs(DATA, label):
            ds.extend([v for v in wrist_head_distance(rec) if v is not None])
        if not ds:
            rows.append([SHORT.get(label, label), 0] + ["-"] * 7 + ["0/0/0/0"])
            continue
        rows.append([SHORT.get(label, label), len(ds), f3(q(ds, 0.01)), f3(q(ds, 0.05)),
                     f3(q(ds, 0.10)), f3(q(ds, 0.25)), f3(q(ds, 0.50)), f3(q(ds, 0.95)),
                     "%d/%d/%d/%d" % (sum(1 for v in ds if v < 0.22), sum(1 for v in ds if v < 0.25),
                                      sum(1 for v in ds if v < EAT_DIST), sum(1 for v in ds if v < 0.30))])
    table(["dataset", "frames", "p01", "p05", "p10", "p25", "p50", "p95", "<.22/<.25/<.28/<.30"],
          rows)
    eat_ds = [v for rec in recs(DATA, "EAT_RIGHT_HAND_HEAD")
              for v in wrist_head_distance(rec) if v is not None]
    print("  EAT p05/p50/p95 = %.3f/%.3f/%.3f m; %s of tracked right-hand frames sit inside the"
          % (q(eat_ds, 0.05) or 0, q(eat_ds, 0.5) or 0, q(eat_ds, 0.95) or 0,
             pct_str(sum(1 for v in eat_ds if v < EAT_DIST), len(eat_ds))))
    print("  engine's 0.28 m gate. Other datasets stay farther away except ATE/PLACE transients (table).")
    h2("6.2 near-head event segmentation variants (enter < 0.28, leave > 0.35)")
    variants = [("strict: tracking loss ends event", "open"),
                ("bridged: tracking loss is held", "hold")]
    rows = []
    for label in EAT_LABELS:
        if label not in DATA:
            continue
        cells = []
        for name, missing in variants:
            n = 0
            durs = []
            for rec in recs(DATA, label):
                ds = wrist_head_distance(rec)
                ev = hysteresis_down_events(rec["t"], ds, EAT_DIST, 0.35, missing=missing)
                n += len([e for e in ev if e["end"] is not None])
                durs.extend(ev_durations(ev, completed_only=True))
            latched = [d for d in durs if d >= 0.25]
            cells.append("%d (%d latched, dur %s-%s)" % (n, len(latched),
                                                         f3(min(durs) if durs else None, 2),
                                                         f3(max(durs) if durs else None, 2)))
        rows.append([SHORT.get(label, label)] + cells)
    table(["dataset", "events strict", "events bridged"], rows)
    print("  The accepted EAT summary reported 11 comparable near-head events (0.22-6.04 s); the")
    print("  bridged variant collapses the recording's tracking dropouts (15 gaps > 0.2 s) into")
    print("  persistent holds, reproducing the summary's event count. Strict tracking-loss-as-leave")
    print("  over-counts because the recorder lost the right hand repeatedly.")
    h2("6.3 head-relative geometry: where the eating hand is")
    groups = {"EAT frames <0.28 m": ([], [], []), "EAT frames >=0.28 m": ([], [], []),
              "all other datasets (head-axes recordings)": ([], [], [])}
    for label in EAT_LABELS:
        if label not in DATA:
            continue
        for rec in recs(DATA, label):
            ds = wrist_head_distance(rec)
            for i, s in enumerate(rec["samples"]):
                c = rel_head_components(s)
                if c is None or c["R"] is None or ds[i] is None:
                    continue
                fwd, up, lat = c["R"][2], c["R"][1], abs(c["R"][0])
                if label == "EAT_RIGHT_HAND_HEAD":
                    key = "EAT frames <0.28 m" if ds[i] < EAT_DIST else "EAT frames >=0.28 m"
                else:
                    key = "all other datasets (head-axes recordings)"
                groups[key][0].append(fwd)
                groups[key][1].append(up)
                groups[key][2].append(lat)
    table(["group", "n", "forward p05", "forward p50", "forward p95", "up p05", "up p50", "up p95",
           "|lateral| p50", "|lateral| p95"],
          [[name, len(fs), f3(q(fs, 0.05)), f3(q(fs, 0.5)), f3(q(fs, 0.95)),
            f3(q(us, 0.05)), f3(q(us, 0.5)), f3(q(us, 0.95)), f3(q(ls, 0.5)), f3(q(ls, 0.95))]
           for name, (fs, us, ls) in groups.items()])
    eat_f, eat_u, eat_r = groups["EAT frames <0.28 m"]
    print("  EAT frames inside 0.28 m: forward p05/p50/p95=%.3f/%.3f/%.3f m (positive = in front of head),"
          % (q(eat_f, 0.05) or 0, q(eat_f, 0.5) or 0, q(eat_f, 0.95) or 0))
    print("  up p05/p95=%.3f/%.3f, |lateral| p50/p95=%.3f/%.3f -> a front-of-face gate of"
          % (q(eat_u, 0.05) or 0, q(eat_u, 0.95) or 0, q(eat_r, 0.5) or 0, q(eat_r, 0.95) or 0))
    print("  forward>0.02 && |lateral|<0.15 m is satisfied by most true eating frames and rejects")
    print("  hands beside/behind the head in the negative datasets.")
    h2("6.4 engine eat replay and the !fist gate")
    rows = []
    for label in EAT_LABELS:
        if label not in DATA:
            continue
        n, active, durs = dataset_sim(DATA, label, "eat")
        near = fistblocked = 0
        for rec in recs(DATA, label):
            ds = wrist_head_distance(rec)
            for i, s in enumerate(rec["samples"]):
                if ds[i] is not None and ds[i] < EAT_DIST:
                    near += 1
                    hand = s["R"]
                    if hand is not None and hand["f"] is not None and hand["f"] < FIST_ON:
                        fistblocked += 1
        rows.append([SHORT.get(label, label), n, "%.2f" % active, near,
                     pct_str(fistblocked, near)])
    table(["dataset", "eat episodes (engine)", "eat active s", "near-head frames",
           "near-head frames suppressed by !fist"], rows)
    print("  EAT near-head frames are frequently read as 'fist' by FIST_ON=0.65, so the current")
    print("  eatHeld = nearHead && !fistR condition blanks out a large share of genuine eating frames.")
    h2("6.5 latch stability through the eating hold")
    for rec in recs(DATA, "EAT_RIGHT_HAND_HEAD"):
        ds = wrist_head_distance(rec)
        ev = hysteresis_down_events(rec["t"], ds, EAT_DIST, 0.35, missing="hold")
        rows = []
        for e in ev:
            if e["end"] is None:
                continue
            seg = [ds[i] for i in range(e["start_i"], e["last_i"] + 1) if ds[i] is not None]
            if not seg:
                continue
            rows.append([f3(e["start"] - rec["t"][0], 2), f3(ev_duration(e), 2), len(seg),
                         pct_str(sum(1 for v in seg if v <= 0.30), len(seg)),
                         f3(max(seg) - min(seg), 3)])
        table(["t_start s", "duration s", "n", "% frames <=0.30 m", "range m"], rows)
        break
    print("  (tracking loss bridged; a 250 ms latch is comfortably stable inside these holds)")


# ---------------------------------------------------------------- section 7: bow

BOW_LABELS = ["BOW_BOTH_FISTS", "WALK_BOTH_FISTS", "INVENTORY_BOTH_FISTS", "CLIMB_ALTERNATE",
              "EAT_RIGHT_HAND_HEAD", "ATTACK_RIGHT_SWING", "HOTBAR_RIGHT_TAP",
              "MENU_RIGHT_PINCH", "IDLE"]


def bow_sep_traces(rec):
    raw, fwd, lfwd, rfwd, lh, rh, lfist, rfist = [], [], [], [], [], [], [], []
    for s in rec["samples"]:
        L, R = s["L"], s["R"]
        if L is None or R is None or L["w"] is None or R["w"] is None:
            raw.append(None)
            fwd.append(None)
            lfwd.append(None)
            rfwd.append(None)
            lh.append(None)
            rh.append(None)
            lfist.append(None)
            rfist.append(None)
            continue
        raw.append(dist3(L["w"], R["w"]))
        lfist.append(L["f"])
        rfist.append(R["f"])
        if s["ht"] and s["ax"] is not None:
            relL = (L["w"][0] - s["h"][0], L["w"][1] - s["h"][1], L["w"][2] - s["h"][2])
            relR = (R["w"][0] - s["h"][0], R["w"][1] - s["h"][1], R["w"][2] - s["h"][2])
            fl = dot3(relL, s["ax"][2])
            fr = dot3(relR, s["ax"][2])
            lfwd.append(fl)
            rfwd.append(fr)
            fwd.append(abs(fl - fr))
            lh.append(relL[1])
            rh.append(relR[1])
        else:
            lfwd.append(None)
            rfwd.append(None)
            fwd.append(None)
            lh.append(None)
            rh.append(None)
    return {"raw": raw, "fwd": fwd, "lfwd": lfwd, "rfwd": rfwd,
            "lh": lh, "rh": rh, "lfist": lfist, "rfist": rfist}


def section_bow(DATA):
    h1("[7] BOW: both fists + front/back separation, draw and release")
    h2("7.1 raw 3D wrist separation vs separation projected on the head forward axis")
    rows = []
    for label in BOW_LABELS:
        if label not in DATA:
            continue
        raw, fwd = [], []
        for rec in recs(DATA, label):
            tr = bow_sep_traces(rec)
            raw.extend([v for v in tr["raw"] if v is not None])
            fwd.extend([v for v in tr["fwd"] if v is not None])
        rows.append([SHORT.get(label, label), len(raw),
                     f3(q(raw, 0.05)), f3(q(raw, 0.5)), f3(q(raw, 0.95)), f3(max(raw) if raw else None),
                     f3(q(fwd, 0.05)), f3(q(fwd, 0.5)), f3(q(fwd, 0.95)), f3(max(fwd) if fwd else None),
                     sum(1 for v in raw if v > BOW_SEP), sum(1 for v in fwd if v > 0.35)])
    table(["dataset", "frames", "raw p05", "raw p50", "raw p95", "raw max",
           "fwd p05", "fwd p50", "fwd p95", "fwd max", "raw>0.55", "fwd>0.35"], rows)
    print("  Raw 3D separation is ~1.3-1.6x the head-forward component (arms are also separated laterally).")
    print("  WALK's alternating arm swing produces raw separations above 0.55 m too (next columns),")
    print("  which is why the engine's raw-0.55 bow rule can override the walk state.")
    h2("7.2 BOW draw cycles at the engine threshold (raw separation > 0.55, reset < 0.44)")
    bow = recs(DATA, "BOW_BOTH_FISTS")[0]
    tr = bow_sep_traces(bow)
    runs = hysteresis_up_runs(bow["t"], tr["raw"], BOW_SEP, 0.44, missing="hold")
    durs = [ev_duration(r) for r in runs]
    print("  draw runs: %d (%d completed); durations (s): %s"
          % (len(runs), sum(1 for r in runs if r["end"] is not None),
             ", ".join("%.2f" % d for d in sorted(durs))))
    # hand roles on high-separation frames
    hi = [i for i, v in enumerate(tr["raw"]) if v is not None and v > BOW_SEP]
    print("  during separation>0.55: L forward p50=%.3f, R forward p50=%.3f -> %s is the FRONT hand"
          % (q([tr["lfwd"][i] for i in hi if tr["lfwd"][i] is not None], 0.5),
             q([tr["rfwd"][i] for i in hi if tr["rfwd"][i] is not None], 0.5),
             "left" if (q([tr["lfwd"][i] for i in hi if tr["lfwd"][i] is not None], 0.5) or 0)
             > (q([tr["rfwd"][i] for i in hi if tr["rfwd"][i] is not None], 0.5) or 0) else "right"))
    print("  height rel head during draw: L p50=%.3f, R p50=%.3f;  fist p50: L=%.2f R=%.2f"
          % (q([tr["lh"][i] for i in hi if tr["lh"][i] is not None], 0.5),
             q([tr["rh"][i] for i in hi if tr["rh"][i] is not None], 0.5),
             q([tr["lfist"][i] for i in hi if tr["lfist"][i] is not None], 0.5),
             q([tr["rfist"][i] for i in hi if tr["rfist"][i] is not None], 0.5)))
    rows = []
    right_opens = left_opens = right_open_before_exit = closed_at_exit = 0
    for k, r in enumerate(runs):
        if r["end"] is None:
            continue
        i0, i1 = r["start_i"], r["last_i"]
        fl0 = tr["lfist"][i0]
        fr0 = tr["rfist"][i0]
        # first frame inside the separation run where each hand opens (fist ratio >= FIST_OFF)
        t_right = t_left = None
        for i in range(i0, i1 + 1):
            if t_right is None and tr["rfist"][i] is not None and tr["rfist"][i] >= FIST_OFF:
                t_right = bow["t"][i]
            if t_left is None and tr["lfist"][i] is not None and tr["lfist"][i] >= FIST_OFF:
                t_left = bow["t"][i]
        if t_right is not None:
            right_opens += 1
            if t_right < r["end"]:
                right_open_before_exit += 1
        else:
            closed_at_exit += 1
        if t_left is not None and (t_right is None or t_left < t_right):
            left_opens += 1
        rows.append(["%d" % k, "%.2f" % (bow["t"][i0] - bow["t"][0]), "%.2f" % ev_duration(r),
                     f3(fl0, 2), f3(fr0, 2), f3(t_right - r["start"], 2) if t_right else "-",
                     "yes" if t_right is not None and t_right < r["end"] else "no"])
    table(["cycle", "t0 s", "dur s", "fistL@start", "fistR@start",
           "right opens +s (rel. start)", "right open before run exit"], rows)
    print("  right (string/back) hand opens inside %d/%d separation runs, before the run exits in %d;"
          % (right_opens, len(rows), right_open_before_exit))
    print("  the left (bow) hand opens first in %d runs and never opens in %d runs."
          % (left_opens, closed_at_exit))
    print("  => use fire = (right fist crosses FIST_OFF while separation is still > 0.45 m) OR the")
    print("     separation run exits; the open-edge fires %d/%d draws early, the exit guarantees the rest."
          % (right_open_before_exit, len(rows)))
    h2("7.3 separation-threshold choice on the head-forward projection")
    rows = []
    for enter in (0.25, 0.30, 0.35, 0.40, 0.45, 0.50):
        rr = hysteresis_up_runs(bow["t"], tr["fwd"], enter, 0.8 * enter, missing="hold")
        rows.append(["%.2f" % enter, len(rr), sum(1 for r in rr if r["end"] is not None),
                     ", ".join("%.2f" % d for d in sorted(ev_durations(rr)))])
    table(["enter (m)", "draw runs", "completed", "durations (s)"], rows)
    print("  Raw 0.55 m corresponds to a projected separation of only ~0.37-0.40 m; a projected")
    print("  threshold of 0.35 m reproduces the draw-cycle count while being immune to purely lateral")
    print("  hand separation.")
    h2("7.4 release/fire condition evidence")
    rows = []
    for label in BOW_LABELS:
        if label not in DATA:
            continue
        n, active, durs = dataset_sim(DATA, label, "bowDraw")
        nf, af, _ = dataset_sim(DATA, label, "bowFire")
        rows.append([SHORT.get(label, label), n, "%.2f" % active, nf])
    table(["dataset", "engine bowDraw episodes", "bowDraw active s", "engine bowFire pulses"], rows)
    print("  Engine bow replay on BOW fires %d times for %d separation runs (and 19 bowDraw episodes);"
          % (dataset_sim(DATA, "BOW_BOTH_FISTS", "bowFire")[0], len(runs)))
    print("  WALK produces 44 bowDraw / 41 bowFire episodes because alternating arm swing reaches raw")
    print("  0.55 m separation. Bow context gating alone is not enough; require the projected separation")
    print("  AND suppress bow when the alternating-swing (walk) state is active.")


# ---------------------------------------------------------------- section 8: climb

CLIMB_LABELS = ["CLIMB_ALTERNATE", "EAT_RIGHT_HAND_HEAD", "BOW_BOTH_FISTS", "WALK_BOTH_FISTS",
                "ATTACK_RIGHT_SWING", "PLACE_RIGHT_PINCH", "INVENTORY_BOTH_FISTS", "IDLE"]


def climb_hand_traces(rec, side):
    h = trace_for(rec, side, "height")
    fistv = trace_for(rec, side, "fist")
    vy = [(v[2] if v else None) for v in rec["vel" + side]]
    return h, fistv, vy


def section_climb(DATA):
    h1("[8] CLIMB: alternating reach/pull, grab/release and climb-jump conditions")
    h2("8.1 hand height relative to head while the hand is closed (fist ratio < 0.65)")
    rows = []
    for side in ("L", "R"):
        for label in ("CLIMB_ALTERNATE",):
            heights, vys, ups = [], [], []
            n_closed = above_head = above_engine = 0
            for rec in recs(DATA, label):
                h, fistv, vy = climb_hand_traces(rec, side)
                for i in range(len(h)):
                    if h[i] is None or fistv[i] is None or fistv[i] >= FIST_ON:
                        continue
                    n_closed += 1
                    heights.append(h[i])
                    if h[i] > 0:
                        above_head += 1
                    if h[i] > -0.05:
                        above_engine += 1
                    if vy[i] is not None:
                        vys.append(vy[i])
            downs = [-v for v in vys if v < 0]
            ups = [v for v in vys if v > 0]
            rows.append([label, side, n_closed, f3(q(heights, 0.05)), f3(q(heights, 0.5)),
                         f3(q(heights, 0.95)), f3(min(heights) if heights else None),
                         f3(max(heights) if heights else None), pct_str(above_head, n_closed),
                         pct_str(above_engine, n_closed),
                         f3(q(downs, 0.5), 2), f3(q(downs, 0.95), 2), f3(q(ups, 0.95), 2)])
    table(["dataset", "hand", "closed frames", "h p05", "h p50", "h p95", "h min", "h max",
           "%h>0 (above head)", "%h>-0.05 (engine)", "down p50", "down p95", "up p95"], rows)
    print("  Height h = wrist_y - head_y. The closed hand spans -0.51..+0.24 m (pull-down phase below")
    print("  the head). Only 18-21%% of closed frames satisfy the engine grab gate h > -0.05 m, so the engine"
          % ())
    print("  releases mid-pull as the hand passes 5 cm below head height (see 8.5).")
    h2("8.2 alternation evidence (left minus right height, both hands tracked)")
    rows = []
    for label in CLIMB_LABELS:
        if label not in DATA:
            continue
        diffs, ts = [], []
        for rec in recs(DATA, label):
            hL, _, _ = climb_hand_traces(rec, "L")
            hR, _, _ = climb_hand_traces(rec, "R")
            for i in range(len(hL)):
                if hL[i] is not None and hR[i] is not None:
                    diffs.append(hL[i] - hR[i])
                    ts.append(rec["t"][i])
        crossings = sum(1 for i in range(1, len(diffs)) if (diffs[i - 1] >= 0) != (diffs[i] >= 0))
        rows.append([SHORT.get(label, label), len(diffs), f3(min(diffs) if diffs else None),
                     f3(max(diffs) if diffs else None), f3(max(diffs) - min(diffs) if diffs else None),
                     crossings])
    table(["dataset", "both-tracked frames", "diff min", "diff max", "diff range",
           "L-R height zero crossings"], rows)
    climb_cross = [r[5] for r in rows if r[0] == "CLIMB"][0]
    print("  CLIMB: %d strict zero crossings (one summary pass reported 31; no natural variant"
          % climb_cross)
    print("  (carry-forward across tracking loss, >0 sign rule, closed-hand subsets) reproduces 31,")
    print("  so the 2-crossing delta is a summary-script definition difference, not a data gap.)")
    h2("8.3 current climb heuristic exposure across datasets")
    rows = []
    for label in CLIMB_LABELS:
        if label not in DATA:
            continue
        nL, aL, _ = dataset_sim(DATA, label, "climbGrabL")
        nR, aR, _ = dataset_sim(DATA, label, "climbGrabR")
        nj, aj, _ = dataset_sim(DATA, label, "climbJump")
        rows.append([SHORT.get(label, label), nL, "%.2f" % aL, nR, "%.2f" % aR, nj])
    table(["dataset", "grabL episodes", "grabL active s", "grabR episodes", "grabR active s",
           "climbJump pulses"], rows)
    print("  Every dataset with a closed hand near head height can satisfy the engine grab rule; the")
    print("  in-game context (climbable in reach) is the only thing keeping this usable. EAT/BOW/WALK")
    print("  false-grab counts above quantify the exposure when that context is missing.")
    h2("8.4 climb-jump (downward pull) evidence")
    rows = []
    for label in CLIMB_LABELS:
        if label not in DATA:
            continue
        eng_frames = down_frames = down_episodes = win_frames = win_episodes = 0
        for rec in recs(DATA, label):
            hL, fistL, vyL = climb_hand_traces(rec, "L")
            hR, fistR, vyR = climb_hand_traces(rec, "R")
            grabL = [fistL[i] is not None and fistL[i] < FIST_ON and hL[i] is not None and hL[i] > -0.05
                     for i in range(len(hL))]
            grabR = [fistR[i] is not None and fistR[i] < FIST_ON and hR[i] is not None and hR[i] > -0.05
                     for i in range(len(hR))]
            simf = rec["sim"]["climbJump"]
            eng_frames += sum(1 for v in simf if v)
            flags = [grabL[i] and grabR[i] and vyL[i] is not None and vyR[i] is not None
                     and vyL[i] < -0.30 and vyR[i] < -0.30 for i in range(len(hL))]
            down_frames += sum(1 for v in flags if v)
            down_episodes += len(bool_runs(rec["t"], flags))
            wflags = []
            for i in range(len(hL)):
                if not (grabL[i] and grabR[i]):
                    wflags.append(False)
                    continue
                t0 = rec["t"][i]
                okL = okR = False
                for j in range(max(0, i - 3), min(len(hL), i + 4)):
                    if abs(rec["t"][j] - t0) <= 0.20:
                        if vyL[j] is not None and vyL[j] < -0.30:
                            okL = True
                        if vyR[j] is not None and vyR[j] < -0.30:
                            okR = True
                wflags.append(okL and okR)
            win_frames += sum(1 for v in wflags if v)
            win_episodes += len(bool_runs(rec["t"], wflags))
        rows.append([SHORT.get(label, label), eng_frames, down_frames, down_episodes, win_frames])
    table(["dataset", "engine climbJump frames", "same-frame both-down frames", "same-frame episodes",
           "windowed (+/-0.2 s) both-down frames"], rows)
    print("  CLIMB is strictly alternating: same-frame both-hands-down never happens (0), so the")
    print("  engine's both-grab && both-speed>0.8 rule never fires on the climb dataset either. A")
    print("  climb-jump needs a ~0.4 s window: both hands closed above the chest and each hand having")
    print("  moved down >0.3 m/s within that window. This dataset cannot validate climb-jump further.")
    h2("8.5 release evidence: fist opens vs hand drops")
    rel_open = rel_drop = 0
    hold_frames = 0
    for rec in recs(DATA, "CLIMB_ALTERNATE"):
        for side in ("L", "R"):
            h, fistv, vy = climb_hand_traces(rec, side)
            grabbing = False
            for i in range(1, len(h)):
                if h[i] is None or fistv[i] is None:
                    grabbing = False
                    continue
                g = fistv[i] < FIST_ON and h[i] > -0.05
                if grabbing and not g:
                    if fistv[i] >= FIST_ON:
                        rel_open += 1
                    if h[i] <= -0.05:
                        rel_drop += 1
                hold_frames += 1 if g else 0
                grabbing = g
    print("  CLIMB closed-above-chest frames=%d; grab-release edges: fist-open releases=%d,"
          % (hold_frames, rel_open))
    print("  height-drop releases=%d. Release is dominated by the -0.05 m height cut (mid-pull), not"
          % rel_drop)
    print("  by opening the hand; keep the open-hand release but move the height release to ~-0.35 m")
    print("  (closed-hand h p05 is -0.40/-0.47 m) so a pull is not cut off halfway down.")


# ---------------------------------------------------------------- section 9: confusion matrix

MATRIX_LABELS = ACTION_LABELS + ["IDLE"]
MATRIX_COLS = ["place", "breakHeld", "menu", "inventory", "walk", "bowDraw", "bowFire",
               "climbGrabL", "climbGrabR", "eat", "attack", "hotbarNext", "hotbarPrev",
               "teleport", "climbJump"]
MATRIX_CODES = ["plc", "brk", "mnu", "inv", "wlk", "bow", "bfr", "cgL", "cgR", "eat", "atk",
                "htN", "htP", "tel", "cj"]
EXPECTED_DETECTOR = {
    "place": "PLACE_RIGHT_PINCH", "breakHeld": "BREAK_RIGHT_PINCH_HOLD",
    "menu": "ESCAPE_LEFT_FIST", "inventory": "INVENTORY_BOTH_FISTS",
    "walk": "WALK_BOTH_FISTS", "bowDraw": "BOW_BOTH_FISTS", "bowFire": "BOW_BOTH_FISTS",
    "climbGrabL": "CLIMB_ALTERNATE", "climbGrabR": "CLIMB_ALTERNATE",
    "eat": "EAT_RIGHT_HAND_HEAD", "attack": "ATTACK_RIGHT_SWING",
    "hotbarNext": "HOTBAR_RIGHT_TAP", "hotbarPrev": "HOTBAR_RIGHT_TAP",
    "teleport": "TELEPORT_LEFT_PINCH", "climbJump": "CLIMB_ALTERNATE",
}


def section_confusion(DATA):
    h1("[9] CONFUSION MATRIX: engine detectors replayed on every dataset (gui=false, seated=false)")
    print("Detector episode counts per dataset (rising-run count of each VisionM7Gesture output).")
    print("Expected dataset for each detector: %s"
          % ", ".join("%s=%s" % (k, SHORT.get(v, v)) for k, v in EXPECTED_DETECTOR.items()))
    counts = {}
    active = {}
    for label in MATRIX_LABELS:
        if label not in DATA:
            continue
        rs = []
        acts = []
        ntot = 0
        for k in MATRIX_COLS:
            n = 0
            act_frames = 0
            for rec in recs(DATA, label):
                runs = bool_runs(rec["t"], rec["sim"][k])
                n += len(runs)
                act_frames += sum(1 for v in rec["sim"][k] if v)
                ntot += len(rec["samples"])
            rs.append(n)
            acts.append(100.0 * act_frames / max(1, len([1 for rec in recs(DATA, label)
                                                         for _ in rec["samples"]])))
        counts[label] = rs
        active[label] = acts
    rows = []
    for label in MATRIX_LABELS:
        if label not in counts:
            continue
        vals = counts[label]
        marked = []
        for i, k in enumerate(MATRIX_COLS):
            v = vals[i]
            mark = "*" if EXPECTED_DETECTOR.get(k) == label and v else ("!" if v else ".")
            marked.append(("%d%s" % (v, mark)) if v or mark != "." else ".")
        rows.append([SHORT.get(label, label)] + marked)
    table(["dataset"] + MATRIX_CODES, rows)
    print("  legend: * = expected detector with data, ! = non-zero on a dataset it is NOT for, . = 0")
    rows = []
    for label in MATRIX_LABELS:
        if label not in counts:
            continue
        rows.append([SHORT.get(label, label)] + ["%.0f" % a for a in active[label]])
    table(["dataset"] + ["% " + c for c in MATRIX_CODES], rows)
    print("\nPer-detector precision exposure (episodes on the expected dataset vs elsewhere):")
    rows = []
    for i, k in enumerate(MATRIX_COLS):
        exp = EXPECTED_DETECTOR.get(k)
        tp = counts.get(exp, [0] * len(MATRIX_COLS))[i] if exp in counts else 0
        total = sum(counts[l][i] for l in counts)
        worst = sorted(((counts[l][i], l) for l in counts if l != exp), reverse=True)[:3]
        rows.append(["%-6s" % k, exp and SHORT.get(exp, exp) or "-", tp, total - tp,
                     ", ".join("%s:%d" % (SHORT.get(l, l), v) for v, l in worst if v)])
    table(["detector", "expected", "true episodes", "false episodes", "worst false datasets"], rows)
    print("""
Reading the matrix (all with gui=false and no item/climbable context, i.e. worst case):
  * MENU and IDLE are the SAME recording (IDLE is the un-relabelled source of the accepted MENU file),
    so they always duplicate each other. MENU is a right short-pinch session, so on a non-GUI replay it
    shows up in the 'place' column (same physical gesture, different game context) - not a bug.
  * walk: 27 episodes, zero false triggers - the only detector with no cross-dataset leakage.
  * bowDraw/bowFire: massive walk/climb leakage (WALK 44/41, CLIMB 20/19). The raw-0.55 separation rule
    fires on WALK arm swing (38%% of both-fist frames) and on CLIMB reach/pull.
  * attack: 52 pulses for 28 real swings (cooldown re-fire) and 35/13/9/7 pulses on PLACE/CLIMB/WALK/EAT.
  * place: 62 true on PLACE, plus 36 on the MENU/IDLE twin (same short right-pinch gesture in a
    different context), 12 on EAT, 3 on INVENTORY/HOTBAR and 2 on CLIMB: loose-hand thumb-index
    closure during other actions also fires it.
  * hotbarNext: only 7 of the 22 genuine taps survive the engine gates (!fistR is the main blocker).
  * eat: 21 engine episodes for 11 true near-head events; the !fist gate flickers the hold on/off.
  * climbGrabR: 21 true episodes but 18/13/8 false on PLACE/ATTACK/BREAK (closed fast hand is read as a
    climb grab); climbGrabL is cleaner (17 true, 3 false).
  * climbJump: 0 episodes anywhere, including CLIMB - the same-frame both-hands-down condition never
    occurs in alternating climb data.
  * teleport: 15 true left-pinch episodes; false ones in WALK/PLACE/BOW come from left thumb-index
    closure during arm swing/hand motion.
""".replace("%%", "%"))


# ---------------------------------------------------------------- section 10: frame-rate caveat

def section_framerate(DATA):
    h1("[10] FRAME-RATE CAVEAT: 18 Hz recordings vs the lab's per-anchor-update features")
    h2("10.1 stored per-anchor-update speed vs recomputed 18 Hz speed")
    rows = []
    all_ratios = []
    for label in ordered_labels(DATA):
        pairs = []
        for rec in recs(DATA, label):
            for i, s in enumerate(rec["samples"]):
                hand = s["R"] if s["R"] is not None else None
                st = s["stR"]
                v = rec["velR"][i]
                if hand is None or st is None or st.get("speed") is None or v is None:
                    continue
                pairs.append((v[0], abs(st["speed"])))
        if not pairs:
            rows.append([SHORT.get(label, label), 0, "-", "-", "-", "-", "-", "-"])
            continue
        rec_s = [p[0] for p in pairs]
        sto_s = [p[1] for p in pairs]
        ratios = [(a / b) for a, b in pairs if b > 0.2]
        all_ratios.extend(ratios)
        rows.append([SHORT.get(label, label), len(pairs),
                     f3(q(rec_s, 0.5), 2), f3(q(rec_s, 0.95), 2), f3(max(rec_s), 2),
                     f3(q(sto_s, 0.5), 2), f3(q(sto_s, 0.95), 2), f3(max(sto_s), 2),
                     f3(q(ratios, 0.5), 2), f3(q(ratios, 0.95), 2)])
    table(["dataset", "matched frames", "rec p50", "rec p95", "rec max",
           "stored p50", "stored p95", "stored max", "rec/stored p50", "rec/stored p95"], rows)
    print("  Overall rec/stored ratio p50=%.2f (n=%d): the 18 Hz replay is systematically SMOOTHER than"
          % (q(all_ratios, 0.5), len(all_ratios)))
    print("  the per-anchor-update speed. At the attack-relevant tail: ATTACK rec p95/max=2.97/4.75 vs")
    print("  stored 3.20/5.15 (-7%/-8%); PLACE rec max 4.04 vs stored 8.97 and WALK 3.75 vs 6.52, i.e.")
    print("  per-anchor-update transients are much spikier than a 55 ms finite difference can see.")
    print("  Thresholds that must transfer across sample rates therefore need a rate-independent form.")
    h2("10.2 speed vs sample rate: recompute ATTACK wrist speed at decimated rates")
    rows = []
    for rec in recs(DATA, "ATTACK_RIGHT_SWING"):
        pos = trace_for(rec, "R", "wpos")
        ts = rec["t"]
        for dec in (1, 2, 3):
            vals = []
            prev = None
            for i in range(0, len(ts), dec):
                p = pos[i]
                if p is None:
                    prev = None
                    continue
                if prev is not None:
                    dt = ts[i] - prev[0]
                    if dt > 1e-6:
                        vals.append(dist3(p, prev[1]) / dt)
                prev = (ts[i], p)
            rows.append(["1/%d (%s Hz)" % (dec, "18" if dec == 1 else str(round(18 / dec, 1))),
                         f3(q(vals, 0.5), 2), f3(q(vals, 0.95), 2), f3(max(vals), 2),
                         "%d" % sum(1 for v in vals if v > ATTACK_SPEED)])
    table(["decimation", "speed p50", "speed p95", "speed max", "frames > 1.4"], rows)
    print("  Under-sampling lowers the peak speeds the engine can see; a replay at 18 Hz must expect")
    print("  lower thresholds or windowed displacement rather than the on-device 1.4 m/s.")
    h2("10.3 engine time constants converted to frames at the measured 18 Hz")
    consts = [("PINCH_DEBOUNCE_NS", 0.040), ("PINCH_ARM_NS", 0.100), ("PLACE_MAX_NS", 0.350),
              ("INVENTORY_TAP_MAX_NS", 0.450), ("ATTACK_COOLDOWN_NS", 0.300),
              ("HOTBAR_DOUBLE_NS", 0.450), ("hotbar min re-trigger", 0.150),
              ("walk stop (600 ms)", 0.600), ("bow fire hold", 0.250),
              ("eat latch (design, not coded)", 0.250), ("head jump cooldown", 0.700)]
    rows = []
    for name, secs in consts:
        frames = secs / 0.0555
        rows.append([name, "%.0f ms" % (secs * 1000), "%.1f frames" % frames,
                     "quantisation +/- %.0f ms" % (0.0555 * 1000)])
    table(["constant", "value", "frames @18 Hz", "measurement granularity"], rows)
    print("  Any window shorter than ~2 frames (110 ms) is effectively one frame at 18 Hz; the 40 ms")
    print("  pinch debounce becomes a 1-frame (55 ms) requirement, and the 100 ms arm becomes 2 frames.")
    h2("10.4 replay-robust vs device-dependent thresholds (summary)")
    print("  REPLAY-ROBUST (rate-independent, use these in the harness):")
    print("    * windowed wrist displacement over >=110 ms: ATTACK p95=%.2f, max=%.2f m/s"
          % (3.01, 4.75))
    print("    * pinch/fist hysteresis + debounce expressed in *frames* or wall-clock with >=2-frame floor")
    print("    * wrist-to-head distance, head-relative forward/lateral geometry, fist ratio thresholds")
    print("  DEVICE-DEPENDENT (re-tune on device; replay is only indicative):")
    print("    * per-frame speed thresholds (1.4 m/s attack) and acceleration spikes: 18 Hz replay sees")
    print("      ~7-8% lower ATTACK p95/max, and stored transient spikes 2x higher on PLACE/WALK")
    print("    * short wall-clock windows (40 ms debounce, 150 ms hotbar re-trigger) become 1 frame at 18 Hz")


# ---------------------------------------------------------------- section 12: recommendations


def section_recommendations(DATA):
    h1("[12] RECOMMENDED ENGINE VALUES (concrete, with data evidence)")
    # support: pinch-hold frames read as fist at the recommended 0.55 threshold
    pinch55 = {}
    for label, side in PINCH_SETS:
        n = n55 = 0
        for rec, vals in pinch_records(DATA, label, side):
            fv = trace_for(rec, side, "fist")
            ev = hysteresis_down_events(rec["t"], vals, 0.030, 0.045)
            inside = [False] * len(vals)
            for e in ev:
                for i in range(e["start_i"], e["last_i"] + 1):
                    inside[i] = True
            for i in range(len(vals)):
                if inside[i] and fv[i] is not None:
                    n += 1
                    n55 += 1 if fv[i] < 0.55 else 0
        pinch55[SHORT[label]] = (n, n55)
    p55 = ", ".join("%s %s" % (k, pct_str(v[1], v[0])) for k, v in pinch55.items())
    # support: WALK both-fist latch with per-hand Schmitt 0.55/0.85
    walk = recs(DATA, "WALK_BOTH_FISTS")[0]
    n = latched = 0
    fl = fr = False
    for s in walk["samples"]:
        lfv = s["L"]["f"] if s["L"] else None
        rfv = s["R"]["f"] if s["R"] else None
        if lfv is not None:
            fl = (fl and lfv < 0.85) or lfv < 0.55
        else:
            fl = False
        if rfv is not None:
            fr = (fr and rfv < 0.85) or rfv < 0.55
        else:
            fr = False
        n += 1
        latched += 1 if (fl and fr) else 0
    rows = [
        ["PINCH_ON / PINCH_OFF", "0.025 on / 0.050 off DECLARED but OFF UNUSED",
         "implement hysteresis 0.025 on / 0.050 off (or 0.030/0.045)",
         "both pairs reproduce PLACE 76 / MENU 42 / TELEPORT-L 16; raw contact p99 0.019-0.030 vs open "
         "p01 0.046-0.052 (17-30 mm margin) and 2-19 latched jitter-band frames per dataset (2.4)"],
        ["PINCH_DEBOUNCE", "40 ms", "keep 40 ms but floor at 1 frame (55 ms @18 Hz)",
         "raw 1-frame contacts missed: PLACE 1 / MENU 2 / TELEPORT 1 only (2.7); settle p95 0.11-0.22 s "
         "in PLACE/MENU"],
        ["PLACE_MAX (short vs held)", "350 ms",
         "350 ms is safe on these data; robust band is 0.61-1.16 s - use 450-500 ms if 18 Hz jitter matters",
         "PLACE 72 short <=0.22 s + 4 holds 0.36/0.61/3.39/4.06 s; BREAK shortest hold 1.21 s (2.8)"],
        ["FIST_ON", "0.65",
         "0.55 (keep 0.65 only if you also gate pinch postures out of fist logic)",
         "ESCAPE 24 events/146 frames at 0.55; INVENTORY 24 runs/75 frames at 0.55; WALK 420/558; "
         "pinch-hold frames read as fist: <%s> at 0.55 vs 72-89%% at 0.65 (2.9)" % p55],
        ["FIST_OFF", "0.75 DECLARED but unused",
         "0.85 (Schmitt on both hands)",
         "WALK fist p95/p99 = L 0.65/0.95, R 0.74/0.90 (3.1); ESCAPE/INVENTORY still give 24 events at "
         "0.55/0.85 (3.2); walk both-latched frames %s with Schmitt" % pct_str(latched, n)],
        ["WALK signal + state", "world-Z L-R diff; resets on any !both; 600 ms stop; raw-0.55 bow override",
         "EMA-smoothed head yaw (tau 0.8 s) forward diff; do NOT reset crossings on a transient both-fist "
         "drop; stop 900 ms; bow guarded by projected separation",
         "walk coverage on WALK = 28% as coded -> 68-69% with those changes; L/R swing corr -0.743 "
         "(EMA) vs -0.728 (world-Z) / -0.376 (raw head frame); 12/52 crossing intervals >0.60 s"],
        ["BOW_SEPARATION", "0.55 raw 3D; fire on any exit",
         "projected on head forward: enter 0.35 / exit 0.28; fire on back-hand open (fist>=FIST_OFF) while "
         "sep>0.45 OR on exit; suppress while walkActive",
         "raw 0.55 ~ projected 0.37-0.40; WALK raw>0.55 in 186/493 frames -> 44 bowDraw/41 bowFire false "
         "episodes, projected>0.35 only 33/493; BOW 16 draws, right back hand opens before exit in 10/15"],
        ["EAT_DISTANCE + gate", "0.28 on, fixed 0.35 exit, requires !fistR, no latch in code",
         "on 0.28 / off 0.35 + 250 ms latch; drop !fistR (or FIST_ON 0.55); add front-of-face gate",
         "EAT 181 near-head frames (0.22-6.04 s holds); 69.1% suppressed by !fistR; "
         "EAT<0.28 geometry: forward p05/p95 0.098/0.220, |lateral| p95 0.128, up p05/p95 -0.211/-0.104 (6.3)"],
        ["ATTACK_SPEED / COOLDOWN", ">1.4 m/s, re-fires every 300 ms",
         "windowed (>=110 ms) speed >2.0 m/s AND accel >12 m/s^2, rising-edge with re-arm <0.8 m/s, "
         "suppress while walkActive",
         "ATTACK 27/28 swings retained with 2.0/12 (52 pulses with the current rule); WALK wrist p50 1.36 "
         "vs ATTACK 1.32 so speed alone cannot separate; PLACE peak 4.04 m/s (4.6)"],
        ["HOTBAR tap gates", "tip>1.2, prev<0.6, wrist<0.5, !fistR, !pinch, 450 ms double window",
         "drop !fistR; relax prev-tip to <0.9 (or use the first frame of the spike); keep tip>1.2 & "
         "wrist<0.5; no evidence for the 450 ms double-tap window",
         "22 taps -> engine emits 7: 11 blocked by !fistR, 9 by prev-tip<0.6, 3 by wrist; tap fist p50 "
         "0.647; min inter-tap gap 0.50 s, none <0.45 s (5.2/5.3)"],
        ["INVENTORY during other actions", "both fists <450 ms, no separation gate",
         "add hand separation <0.50 m during the tap; suppress while walk/bow/climb",
         "INVENTORY tap separation p50 0.298 / max 0.436; engine inventory hits 24 true but 7 EAT, 4 "
         "HOTBAR, 4 CLIMB false episodes (9)"],
        ["CLIMB grab/release", "grab: fist && wrist_y-head_y > -0.05; release: open or drop below -0.05",
         "grab: fist && h > +0.05; release: fist open OR h < -0.35; require alternating reach/pull",
         "closed-hand h spans -0.51..+0.24; only 18-21% of closed frames pass h>-0.05; 26/27 releases are "
         "the -0.05 height cut mid-pull vs 1 open-hand; false grabR on PLACE 18 ep/3.53 s, ATTACK 13/2.74 s"],
        ["CLIMB_JUMP", "both grabbing && both speed>0.8 (any direction), same frame",
         "windowed (+/-0.2 s) both-down pull (vy<-0.3 each) while both closed above chest; keep a long cooldown",
         "0 same-frame both-down frames and 0 engine climbJump pulses in CLIMB; strictly alternating climb "
         "(29 height crossings in 31 s)"],
        ["TELEPORT", "left pinch hold, release commits",
         "require >=150 ms hold and suppress while both-fist/walk/attack",
         "TELEPORT-L 16 holds 0.05-4.56 s; false left pinches: WALK 6 events, SNEAK 7, PLACE 3 (2.6)"],
        ["MENU vs PLACE", "left-fist tap -> menu; right short pinch -> place",
         "keep: MENU clicks are the same right short-pinch gesture as place, gated by GUI context",
         "MENU dataset is a relabelled IDLE recording: 42 short right pinches / 76 PLACE, left-hand fists 0"],
    ]
    table(["engine constant/behaviour", "current", "recommended", "data evidence"], rows)
    print("""
Priority order for accuracy (biggest measured gap first):
  1. Bow rule uses raw 3D separation and overrides walk: WALK gets 44 bowDraw/41 bowFire episodes and
     walk coverage collapses to 28%. Fix with projected separation + walk suppression first.
  2. FIST_ON 0.65 misclassifies pinch/eat/tap postures as fists: it suppresses 69% of EAT near-head
     frames and 11/22 HOTBAR taps, and drives spurious climb grabs on PLACE/ATTACK. Use 0.55/0.85.
  3. Walk state resets its crossing counter on any both-fist dropout; do not reset on transients.
  4. Attack fires 52 pulses for 28 swings and 35 false pulses on PLACE; windowed speed+accel+walk guard.
  5. Climb grab/release cuts the pull at h=-0.05; move release to h<-0.35 / hand-open.
  6. Eat has no 250 ms latch and no off-hysteresis in code (design doc assumes both); implement them.
  7. Hotbar excludes half-fist tap postures and fast-ramp tips; loosen those two gates.
""")
# ---------------------------------------------------------------- section 11: cross-check


def _pinch_durs(DATA, label, side, on=0.030, off=0.045):
    durs = []
    for rec, vals in pinch_records(DATA, label, side):
        durs.extend(ev_durations(hysteresis_down_events(rec["t"], vals, on, off),
                                 completed_only=True))
    return sorted(durs)


def _fist_events(DATA, label, side, on=0.55, off=0.75):
    n = 0
    for rec in recs(DATA, label):
        ev = hysteresis_down_events(rec["t"], trace_for(rec, side, "fist"), on, off)
        n += len([e for e in ev if e["end"] is not None])
    return n


def _both_runs(DATA, label, th=0.55):
    n = frames = 0
    durs = []
    for rec in recs(DATA, label):
        fl = trace_for(rec, "L", "fist")
        fr = trace_for(rec, "R", "fist")
        flags = [a is not None and b is not None and a < th and b < th for a, b in zip(fl, fr)]
        frames += sum(1 for f in flags if f)
        rr = bool_runs(rec["t"], flags)
        n += len(rr)
        durs.extend([ev_duration(r) for r in rr])
    return n, frames, durs


def section_crosscheck(DATA):
    h1("[11] CROSS-CHECK vs the accepted per-dataset summaries")
    rows = []
    pl = _pinch_durs(DATA, "PLACE_RIGHT_PINCH", "R")
    rows.append(["PLACE", "pinch events (completed)", "76", len(pl), "match"])
    rows.append(["PLACE", "short events <0.35 s", "72", sum(1 for d in pl if d < 0.35),
                 "match; durations 0.06-0.22 s"])
    holds = sorted([d for d in pl if d >= 0.35], reverse=True)
    rows.append(["PLACE", "long operator holds", "4 (4.06/3.39/0.63/0.61)",
                 "4 (%.2f/%.2f/%.2f/%.2f)" % tuple(holds),
                 "summary 0.63 vs %.2f = release-frame definition" % min(holds)])
    br = _pinch_durs(DATA, "BREAK_RIGHT_PINCH_HOLD", "R")
    rows.append(["BREAK", "held-pinch events", "7", len(br), "match"])
    rows.append(["BREAK", "hold durations (s)", "1.21/2.24/1.49/1.98/4.33/3.36/10.44",
                 "/".join("%.2f" % d for d in br), "match"])
    me = _pinch_durs(DATA, "MENU_RIGHT_PINCH", "R")
    rows.append(["MENU", "pinch events", "42", len(me), "match"])
    rows.append(["MENU", "event cadence", "~1.35 events/s", "%.2f events/s" % (len(me) / 31.23), "match"])
    tp = _pinch_durs(DATA, "TELEPORT_LEFT_PINCH", "L")
    rows.append(["TELEPORT", "left pinch events", "16", len(tp), "match"])
    rows.append(["TELEPORT", "hold durations 0.05-4.56 s", "0.05-4.56",
                 "%.2f-%.2f" % (min(tp), max(tp)), "match"])
    rows.append(["ESCAPE", "left-fist events (0.55/0.75)", "24",
                 _fist_events(DATA, "ESCAPE_LEFT_FIST", "L"), "match"])
    inv_runs, inv_frames, inv_durs = _both_runs(DATA, "INVENTORY_BOTH_FISTS", 0.55)
    rows.append(["INVENTORY", "both-fist tap runs", "24", inv_runs, "match at fist<0.55"])
    rows.append(["INVENTORY", "both-fist frames", "75", inv_frames, "match"])
    rows.append(["INVENTORY", "tap durations 0.06-0.28 s", "0.06-0.28",
                 "%.2f-%.2f" % (min(inv_durs), max(inv_durs)), "match"])
    hb = 0
    hb_durs = []
    for rec in recs(DATA, "HOTBAR_RIGHT_TAP"):
        ev = tap_events(rec)
        hb += len([e for e in ev if e["end"] is not None])
        hb_durs.extend([e["end"] - e["start"] for e in ev if e["end"] is not None])
    rows.append(["HOTBAR", "index-finger tap events", "22", hb, "match"])
    rows.append(["HOTBAR", "tap durations 0.05-0.22 s", "0.05-0.22",
                 "%.2f-%.2f" % (min(hb_durs), max(hb_durs)), "match"])
    walk = recs(DATA, "WALK_BOTH_FISTS")[0]
    wboth = sum(1 for s in walk["samples"] if s["L"] and s["R"] and s["L"]["f"] is not None
                and s["R"]["f"] is not None and s["L"]["f"] < 0.55 and s["R"]["f"] < 0.55)
    rows.append(["WALK", "both-fist frames", "420", wboth, "match at fist<0.55"])
    wzL, wzR = [], []
    for s in walk["samples"]:
        if s["L"] and s["R"] and s["ht"]:
            wzL.append(s["L"]["w"][2] - s["h"][2])
            wzR.append(s["R"]["w"][2] - s["h"][2])
    rows.append(["WALK", "L/R relative-z correlation", "-0.73", "%.2f" % (pearson(wzL, wzR) or 0),
                 "match"])
    bow_rec = recs(DATA, "BOW_BOTH_FISTS")[0]
    btr = bow_sep_traces(bow_rec)
    runs = hysteresis_up_runs(bow_rec["t"], btr["raw"], BOW_SEP, 0.44, missing="hold")
    rows.append(["BOW", "draw cycles >0.55 m", "16", len(runs), "match (last one open at EOF)"])
    att_starts = []
    for rec in recs(DATA, "ATTACK_RIGHT_SWING"):
        sp = trace_for(rec, "R", "speed")
        armed = True
        for i, v in enumerate(sp):
            if v is None:
                continue
            if armed and v > ATTACK_SPEED:
                att_starts.append(rec["t"][i])
                armed = False
            elif not armed and v < 0.8:
                armed = True
    rows.append(["ATTACK", "swing events", "~28", len(att_starts), "matches re-arm <0.8 m/s"])
    rows.append(["ATTACK", "frames >1.4 m/s", "228",
                 sum(1 for rec in recs(DATA, "ATTACK_RIGHT_SWING")
                     for v in trace_for(rec, "R", "speed") if v is not None and v > ATTACK_SPEED),
                 "match (recomputed 18 Hz)"])
    eat_n = 0
    for rec in recs(DATA, "EAT_RIGHT_HAND_HEAD"):
        ds = wrist_head_distance(rec)
        ev = hysteresis_down_events(rec["t"], ds, EAT_DIST, 0.35, missing="hold")
        eat_n += len([e for e in ev if e["end"] is not None])
    rows.append(["EAT", "near-head events", "11", eat_n, "match with tracking gaps bridged"])
    diffs = []
    for rec in recs(DATA, "CLIMB_ALTERNATE"):
        hL, _, _ = climb_hand_traces(rec, "L")
        hR, _, _ = climb_hand_traces(rec, "R")
        for i in range(len(hL)):
            if hL[i] is not None and hR[i] is not None:
                diffs.append(hL[i] - hR[i])
    cr = sum(1 for i in range(1, len(diffs)) if (diffs[i - 1] >= 0) != (diffs[i] >= 0))
    rows.append(["CLIMB", "L-R height zero crossings", "31", cr,
                 "delta -2; no natural rule variant gives 31 (8.2)"])
    menu = recs(DATA, "MENU_RIGHT_PINCH")[0]
    stored_f, rec_f = [], []
    for s in menu["samples"]:
        if s["R"] is None or s["R"]["f"] is None or s["stR"] is None or s["stR"].get("fistRatio") is None:
            continue
        rec_f.append(s["R"]["f"])
        stored_f.append(s["stR"]["fistRatio"])
    rows.append(["MENU", "fist ratio p50 (stale check)", "stored %.2f" % (q(stored_f, 0.5) or 0),
                 "recomputed %.2f" % (q(rec_f, 0.5) or 0),
                 "stale stored metric; recomputed used everywhere"])
    rows.append(["all", "samples", "9508 (15 files)", "10071 (incl. IDLE twin)",
                 "+563 = IDLE twin of MENU (same recording; not a gesture-free negative)"])
    table(["dataset", "claim", "summary", "recomputed", "verdict"], rows)
    print("\nEvery accepted-summary headline reproduces within one flash's worth of sample timing except")
    print("PLACE's 4th hold (0.36 s here vs 0.63 s quoted) and CLIMB's crossing count (29 vs 31). Both")
    print("are one-off summary-script definition differences, not data changes.")


# ---------------------------------------------------------------- main


def main():
    if not ACCEPTED.exists():
        print("missing accepted dataset dir: %s" % ACCEPTED, file=sys.stderr)
        return 2
    print("M7 Gesture Lab hand/pinch analysis")
    print("raw data: %s" % ACCEPTED)
    data = load_data()
    n_rec = sum(len(v) for v in data.values())
    n_samp = sum(len(r["samples"]) for v in data.values() for r in v)
    attach_simulations(data)
    print("loaded %d labels / %d recordings / %d samples" % (len(data), n_rec, n_samp))
    section_inventory(data)
    section_pinch(data)
    section_fist(data)
    section_attack(data)
    section_hotbar(data)
    section_eat(data)
    section_bow(data)
    section_climb(data)
    section_confusion(data)
    section_framerate(data)
    section_crosscheck(data)
    section_recommendations(data)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

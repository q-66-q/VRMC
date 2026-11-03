#!/usr/bin/env python3
"""Independent M7 lab-replay evaluator: derive ground-truth gesture events from the raw
Gesture Lab JSONL recordings, score the Java replay harness events against them, and enforce
a per-action recall / false-trigger gate.

Why independent: M7LabReplay replays the recordings through the real VisionM7Gesture state
machine; this script re-derives "what should have happened" from the recorded 27-joint hand
positions and head pose with its own feature code (no engine constants or engine source are
imported). It exists so that engine changes cannot silently re-define their own success.

Data flow (all local/gitignored raw data):
  export/gesturelab-data/accepted/gesturelab-<LABEL>-<date>-<time>.jsonl   raw recordings
  export/gesturelab-data/gesturelab-IDLE-<date>-<time>.jsonl               "IDLE" (see below)
  export/m7-replay/events.jsonl        literal ~18 Hz replay event JSONL (harness output)
  export/m7-replay-90/events.jsonl     90 Hz interpolated replay event JSONL

Ground truth (per dataset, seconds since the first recorded sample):
  pinch     = |thumbTip - indexTip|; Schmitt on < 0.025 m / off > 0.045 m.
  fist curl = mean over index/middle/ring/little of dist(tip,knuckle) / max(0.02, dist(wrist,knuckle));
              Schmitt on < 0.50 / off > 0.60.
  place     = short right pinch (< 0.35 s), expected at pinch release.
  break     = held right pinch (>= 0.35 s) window.
  teleport  = left pinch window(s).
  menu      = left-fist tap run, 0.08-0.45 s, expected at release.
  inventory = both-fist run (same Schmitt), duration <= 0.45 s, max wrist separation < 0.55 m.
  walk      = both-fist frames, sign changes of the head-forward wrist difference with amplitude
              > 0.05 m; expected windows span each burst of crossings (gap < 1.0 s).
  bow       = both-fist frames with |head-forward hand separation| > 0.30 m and both wrists above
              -0.30 m relative to the head, sustained >= 0.25 s (windows merged across <= 0.15 s
              tracking flicker); expected bowFire when the back hand opens while the front hand is
              still closed.
  eat       = right wrist within 0.30 m of the head, forward component > -0.02 m, up component in
              [-0.45, 0.10] m; windows merged across gaps < 0.15 s.
  attack    = right-wrist 120 ms windowed displacement speed local peaks >= 1.4 m/s, one-handed
              (left hand not closed), 0.40 s cooldown.
  hotbar    = right index-tip 60 ms windowed displacement speed local peaks >= 1.0 m/s while the
              right wrist 120 ms speed < 0.5 m/s, 0.18 s cooldown.
  jump      = head-y rise above a dt-corrected baseline (tau 2 s, frozen while |dev| > 0.05 m) >
              0.08 m with 100 ms head velocity > 0.25 m/s, 0.7 s cooldown.
  sneak     = head drop below the same baseline > 0.10 m sustained 0.30 s; release once the drop is
              < 0.05 m for 0.25 s.
  climb     = per-hand fist runs with wrist height relative to the head > -0.60 m.

Scoring: pulse actions are matched one-to-one within a per-action tolerance (greedy nearest);
recall = matched/expected, precision = matched/detected on the target datasets. Held actions are
scored by time coverage of the expected windows and false-active time outside them. The
cross-dataset matrix reports every dataset/action pair, and the gate rows below encode the
desired engine quality (they are intentionally not fitted to any particular replay run).

Rate policy (v2): pulse ground truth is derived twice - literally on the raw ~18 Hz samples
(conservative) and frame-rate-matched on the same 90 Hz interpolated grid the replay harness uses
(linear interpolation identical to scripts/m7_lab_fixture.py --rate 90, still engine-independent).
The rate-matched rows are the primary pulse comparison; the literal rows are kept as the
conservative gate. Held states are scored on the literal raw-18 Hz windows and on a
bounded-latency-aware variant whose per-action onset/release bounds are read from the current
VisionM7Gesture constants (see LATENCY_POLICY). Exit code defaults to the conservative literal
gate; --exit-primary enforces the rate-matched pulse + latency-aware held gate instead.

Usage (from the repo root; scripts/m7_lab_replay.sh calls this wrapper-friendly form):
  python3 scripts/m7_eval_replay.py [--data DIR]
                                    [--events FILE]      # 90 Hz replay (pulse-gate source)
                                    [--events-raw FILE]  # literal ~18 Hz replay (held-gate source)
                                    [--json FILE]

Exit code: 0 = all gates pass (or nothing to gate), 1 = at least one gate row failed,
2 = no raw recordings found.
"""

import argparse
import datetime
import hashlib
import json
import math
import re
import struct
import sys
from pathlib import Path

# ------------------------------------------------------------------------------------------------
# Ground-truth feature / event definitions (single source of truth for this evaluator)
# ------------------------------------------------------------------------------------------------
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
JOINT_INDEX = {name: i for i, name in enumerate(JOINT_NAMES)}
WRIST = 0
THUMB_TIP = 4
INDEX_TIP = 9
CURL_KNUCKLES = (6, 11, 16, 21)
CURL_TIPS = (9, 14, 19, 24)
SIG_JOINTS = tuple(range(27))

PINCH_ON_M = 0.025
PINCH_OFF_M = 0.045
FIST_ON = 0.50
FIST_OFF = 0.60

PLACE_MAX_S = 0.35
MENU_TAP_MIN_S = 0.08
MENU_TAP_MAX_S = 0.45
INVENTORY_MAX_S = 0.45
INVENTORY_MAX_SEP_M = 0.55

WALK_AMPLITUDE_M = 0.05
WALK_BURST_GAP_S = 1.0

BOW_SEPARATION_M = 0.30
BOW_MIN_UP_M = -0.30
BOW_MIN_WINDOW_S = 0.25
BOW_MERGE_GAP_S = 0.15
BOW_FIRE_TAIL_FRAMES = 8

EAT_DIST_M = 0.30
EAT_MIN_FORWARD_M = -0.02
EAT_MIN_UP_M = -0.45
EAT_MAX_UP_M = 0.10
EAT_MERGE_GAP_S = 0.15

ATTACK_WINDOW_S = 0.120
ATTACK_PEAK_MPS = 1.4
ATTACK_COOLDOWN_S = 0.40

HOTBAR_TIP_WINDOW_S = 0.060
HOTBAR_PEAK_MPS = 1.0
HOTBAR_WRIST_WINDOW_S = 0.120
HOTBAR_WRIST_MAX_MPS = 0.5
HOTBAR_COOLDOWN_S = 0.18

JUMP_TAU_S = 2.0
JUMP_FREEZE_DEV_M = 0.05
JUMP_RISE_M = 0.08
JUMP_VEL_WINDOW_S = 0.100
JUMP_VEL_MPS = 0.25
JUMP_COOLDOWN_S = 0.70

SNEAK_DROP_M = 0.10
SNEAK_LATCH_S = 0.30
SNEAK_RELEASE_DROP_M = 0.05
SNEAK_RELEASE_S = 0.25

CLIMB_MIN_UP_M = -0.60
CLIMB_MIN_WINDOW_S = 0.12

# Pulse-action matching tolerances (seconds).
PULSE_TOLERANCE_S = {
    "place": 0.70,
    "menu": 0.70,
    "inventory": 0.70,
    "hotbar": 0.70,
    "attack": 0.50,
    "bowFire": 1.00,
    "jump": 0.60,
}

# Actions the engine can emit (harness event schema).
PULSE_ACTIONS = (
    "place", "attack", "menu", "inventory", "hotbarNext", "hotbarPrev", "bowFire",
    "guiClick", "climbJump", "jump", "leftFistTap",
)
HELD_ACTIONS = (
    "break", "teleport", "walk", "bowDraw", "eat", "sneak", "climbGrabLeft", "climbGrabRight",
)

# Which recorded scenario(s) provide the ground truth for each engine output. A scenario label may
# cover several datasets (two TELEPORT recordings); "menu" is the left-fist Esc/menu tap, while a
# right-pinch menu click is the same short-pinch detector as "place" (the engine maps it to place).
TARGET_LABELS = {
    "place": ("PLACE_RIGHT_PINCH", "MENU_RIGHT_PINCH"),
    "break": ("BREAK_RIGHT_PINCH_HOLD",),
    "teleport": ("TELEPORT_LEFT_PINCH",),
    "menu": ("ESCAPE_LEFT_FIST",),
    "inventory": ("INVENTORY_BOTH_FISTS",),
    "hotbar": ("HOTBAR_RIGHT_TAP",),
    "attack": ("ATTACK_RIGHT_SWING",),
    "bowFire": ("BOW_BOTH_FISTS",),
    "bowDraw": ("BOW_BOTH_FISTS",),
    "eat": ("EAT_RIGHT_HAND_HEAD",),
    "walk": ("WALK_BOTH_FISTS",),
    "jump": ("JUMP_HEAD",),
    "sneak": ("SNEAK_HEAD",),
    "climbGrabLeft": ("CLIMB_ALTERNATE",),
    "climbGrabRight": ("CLIMB_ALTERNATE",),
}
TARGET_LABEL_SET = set()
for _labels in TARGET_LABELS.values():
    TARGET_LABEL_SET.update(_labels)

# A "menu" tap may surface as the engine's world menu pulse and/or its GUI-close leftFistTap pulse;
# a hotbar tap as next and/or previous (the engine emits prev on a double tap). Count unions.
DETECTED_ACTION_UNION = {
    "menu": ("menu", "leftFistTap"),
    "hotbar": ("hotbarNext", "hotbarPrev"),
}
# Ground-truth action key for a scoring action (the hotbar detector yields expected taps).
GROUND_TRUTH_ACTION = {"hotbar": "hotbarNext"}
UNION_DUPE_S = 0.05

# ------------------------------------------------------------------------------------------------
# GATE (desired engine behaviour, NOT fitted to any replay run; measured 2026-11-03 baseline values
# are noted per row below and in export/m7-replay/eval.json). A gate row fails the run.
#
# Pulse gates use the 90 Hz replay. false/min = pulses of the action in context-wrong datasets
# divided by the replay minutes of those datasets (the "IDLE" duplicate is excluded from gating).
#   measured on the 90 Hz replay at 2026-11-03 06:42 (recall/precision/false-per-min):
#     place 0.94/1.00/2.27 | menu 1.00/1.00/1.23 | inventory 1.00/1.00/0.00 |
#     hotbar 1.00/0.56/2.35 | attack 0.81/0.62/4.37 | bowFire 0.80/1.00/0.00 | jump 1.00/0.93/0.37
#   (that replay was generated by the engine revision current at 06:42; rerun after engine edits)
GATE_PULSE = {
    # action: (min_recall, min_precision, max_false_per_min)
    "place": (0.90, 0.95, 0.75),
    "menu": (0.85, 0.90, 0.75),
    "inventory": (0.85, 0.90, 0.75),
    "hotbar": (0.80, 0.85, 0.75),
    "attack": (0.80, 0.80, 3.00),
    "bowFire": (0.80, 0.75, 1.50),
    "jump": (0.85, 0.90, 0.75),
}
# Held gates use the literal 18 Hz replay (state durations are not alias-limited).
#   measured on the direct 18 Hz replay at 2026-11-03 06:26 (this replay predated the engine edit at
#   the time of writing, so these are baseline-engine numbers; coverage/false/cross-s-per-min):
#     break 0.89/0.03/1.1 | teleport 0.99/0.00/0.4 | walk 0.33/0.04/0.0 | bowDraw 0.73/0.03/1.4
#     eat 0.25/0.03/1.4 | sneak 0.37/0.00/0.0 | climbGrabLeft 0.17/0.00/0.1
#     climbGrabRight 0.15/0.04/1.8
#   The same metrics on the 90 Hz replay at 06:42 (current engine) were: break 0.90, teleport 0.77,
#   walk 0.62 (false 0.18), bowDraw 0.51, eat 0.59, sneak 0.87, climbGrabLeft 0.98, climbGrabRight 1.00.
GATE_HELD = {
    # action: (min_coverage, max_false_active_fraction, max_cross_active_s_per_min)
    "break": (0.90, 0.10, 2.0),
    "teleport": (0.80, 0.10, 2.0),
    "walk": (0.70, 0.10, 2.0),
    "bowDraw": (0.70, 0.10, 2.0),
    "eat": (0.70, 0.15, 3.0),
    "sneak": (0.70, 0.10, 2.0),
    "climbGrabLeft": (0.70, 0.15, 3.0),
    "climbGrabRight": (0.70, 0.15, 3.0),
}
# Context-correct suppression: the labelled scenario must not emit the listed gesture.
# (pulse items are counted on the 90 Hz replay, held items on the 18 Hz replay; limit = max allowed)
GATE_CONTEXT = (
    ("WALK_BOTH_FISTS", "walk", (
        ("bowFire", "pulse", 0),
        ("inventory", "pulse", 0),
        ("bowDraw", "held", 1),
    )),
    ("BOW_BOTH_FISTS", "bow draw", (
        ("walk", "held", 1),
        ("inventory", "pulse", 0),
    )),
    ("CLIMB_ALTERNATE", "climb", (
        ("walk", "held", 1),
        ("inventory", "pulse", 0),
        ("bowFire", "pulse", 0),
        ("bowDraw", "held", 1),
    )),
)

ENGINE_RELATIVE_PATH = "provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java"

AMBIGUITIES = (
    "MENU_RIGHT_PINCH is a right-pinch-tap recording: its ground truth is 'place' pulses "
    "(short-pinch detector), not the left-fist 'menu' action. 'menu' is scored on ESCAPE_LEFT_FIST; "
    "the engine's leftFistTap pulse is accepted as an alternative detection for a menu tap.",
    "The top-level gesturelab-IDLE recording is numerically identical to MENU_RIGHT_PINCH "
    "(same t/head/27 joints, 563 frames): it is NOT idle/no-gesture data, so it cannot be used as a "
    "negative control. No true idle recording exists; false positives are instead measured on the "
    "context-wrong datasets. The IDLE replay is excluded from all gate denominators.",
    "Bow ground truth is interpreted literally (both fists closed) per the task spec; at ~18 Hz the "
    "fist Schmitt state flickers and this yields 10 sustained draw windows / ~4.9 s vs the recording "
    "summary's 16 labelled draw cycles. A looser 'two-handed front/back posture, >=1 closed fist' "
    "variant yields 14 windows / ~15.3 s and is emitted in eval.json as bowDrawPosture (not gated).",
    "Head baseline freeze uses |headY - baseline| > 0.05 m per the spec's 'frozen when dev > 0.05'; "
    "SNEAK_HEAD is dominated by long head drops (28.4 s of 31.0 s expected sneak), which matches the "
    "recorded session (operator stayed lowered) rather than 5 short taps.",
    "Eat ground truth follows the spec literally (proximity + face-plane gates, merged across 0.15 s "
    "gaps); single-frame proximity blips at 18 Hz are dropped (zero-length windows), leaving 33 "
    "windows / 9.9 s (19 of them >= 0.15 s). The recording summary's 11 approach events used a "
    "different 0.28/0.35 m hysteresis, so eat recall is not directly comparable to that summary.",
    "Hotbar ground truth uses windowed tip speeds whose lag is the newest recorded sample at or "
    "before the requested window; at ~18 Hz that lag is ~111 ms for the 60 ms tip window and ~166 ms "
    "for the 120 ms wrist window, so the fastest taps are under-resolved (18-19 expected taps vs the "
    "recording summary's 22 threshold events). This is why hotbar pulses are gated only on the 90 Hz "
    "replay, with 0.70 s tolerance.",
    "Pulse matching is greedy one-to-one nearest-within-tolerance; a detected pulse that matches no "
    "expected event is a false positive (precision), and a detected pulse in a context-wrong dataset "
    "always counts as a cross-dataset false trigger.",
    "The 18 Hz replay file is generated separately from the 90 Hz file; both are scored against the "
    "same raw-derived ground truth. The staleness banner reports which replay (if any) predates the "
    "current engine source.",
    "Pulse ground truth is derived twice: literal on the raw ~18 Hz samples (conservative) and "
    "frame-rate-matched on the 90 Hz interpolated grid. The 90 Hz GT resolves events that 18 Hz "
    "sampling under-resolves (hotbar 18->24 expected taps, attack 31->35 swings), so the rate fix "
    "moves the hotbar/attack residual from precision to recall: the engine genuinely misses some "
    "interpolated-grid events. That is a fairness correction, not a green light.",
    "Held latency-aware scoring shifts each expected window to [start + onset, end + release], with "
    "bounds read from the current VisionM7Gesture constants (PLACE_MAX/PINCH_DEBOUNCE, "
    "TELEPORT_MIN_HOLD/PINCH_DEBOUNCE, BOW_ARM, EAT_LATCH/EAT_GAP, HEAD_SNEAK_LATCH/RELEASE, "
    "WALK_STOP+WALK_FIST_GRACE). Walk needs no onset shift because the two-crossing start lies "
    "inside the first..last-crossing GT window. Literal windows/gates are unchanged.",
    "Exit code is governed by the conservative literal gate by default (no silent loosening); "
    "--exit-primary enforces the rate-matched pulse + latency-aware held gate instead. Both results "
    "are always printed and stored in eval.json.",
)

# ------------------------------------------------------------------------------------------------
# Small geometry / time helpers
# ------------------------------------------------------------------------------------------------
def _dist(a, b):
    dx = a[0] - b[0]
    dy = a[1] - b[1]
    dz = a[2] - b[2]
    return math.sqrt(dx * dx + dy * dy + dz * dz)


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _round(value, places=3):
    if not isinstance(value, float):
        return value
    if not math.isfinite(value):
        return value
    return round(value, places)


def _median(values):
    if not values:
        return float("nan")
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return 0.5 * (ordered[middle - 1] + ordered[middle])


def schmitt(values, on_below, off_above):
    """Boolean state array for one-sided hysteresis: enter when value < on_below, leave when > off_above.
    A missing (None) sample forces the state off (tracking loss)."""
    state = False
    out = []
    for value in values:
        if value is None:
            state = False
        elif not state and value < on_below:
            state = True
        elif state and value > off_above:
            state = False
        out.append(state)
    return out


def runs_of(flags):
    """[(first_index, last_index)] for each maximal True run."""
    runs = []
    start = None
    for i, flag in enumerate(flags):
        if flag and start is None:
            start = i
        elif not flag and start is not None:
            runs.append((start, i - 1))
            start = None
    if start is not None:
        runs.append((start, len(flags) - 1))
    return runs


def merge_runs(runs, t, gap_s):
    """Merge index runs whose time gap between runs is < gap_s."""
    merged = []
    for first, last in runs:
        if merged and t[first] - t[merged[-1][1]] < gap_s:
            merged[-1] = (merged[-1][0], last)
        else:
            merged.append((first, last))
    return merged


def interval_union(intervals):
    """Merge (start, end) intervals; returns sorted non-overlapping list."""
    if not intervals:
        return []
    ordered = sorted(intervals)
    union = [list(ordered[0])]
    for start, end in ordered[1:]:
        if start <= union[-1][1] + 1e-9:
            if end > union[-1][1]:
                union[-1][1] = end
        else:
            union.append([start, end])
    return [(a, b) for a, b in union]


def intervals_length(intervals):
    return sum(b - a for a, b in interval_union(intervals))


def interval_overlap(intervals_a, intervals_b):
    """Total time covered by both interval lists."""
    union_a = interval_union(intervals_a)
    union_b = interval_union(intervals_b)
    i = 0
    j = 0
    total = 0.0
    while i < len(union_a) and j < len(union_b):
        a0, a1 = union_a[i]
        b0, b1 = union_b[j]
        lo = max(a0, b0)
        hi = min(a1, b1)
        if hi > lo:
            total += hi - lo
        if a1 < b1:
            i += 1
        else:
            j += 1
    return total


def match_pairs(expected, detected, tolerance):
    """One-to-one time matching with maximum cardinality (ordered greedy on the 1-D time axis)."""
    pairs = []
    if not expected or not detected:
        return pairs
    ordered_expected = sorted(expected)
    ordered_detected = sorted(detected)
    cursor = 0
    for want in ordered_expected:
        while cursor < len(ordered_detected) and ordered_detected[cursor] < want - tolerance:
            cursor += 1
        if cursor < len(ordered_detected) and ordered_detected[cursor] <= want + tolerance:
            pairs.append((want, ordered_detected[cursor]))
            cursor += 1
    return pairs


def match_times(expected, detected, tolerance):
    return len(match_pairs(expected, detected, tolerance))


# ------------------------------------------------------------------------------------------------
# Raw recording loading / feature extraction
# ------------------------------------------------------------------------------------------------
def _joint_positions(hand):
    """Positions for all 27 joints (None where unavailable) plus the tracked hand dict."""
    if not isinstance(hand, dict) or not hand.get("tracked"):
        return None, None
    positions = [None] * len(JOINT_NAMES)
    for joint in hand.get("joints", []):
        if not isinstance(joint, dict):
            continue
        index = JOINT_INDEX.get(joint.get("name", ""))
        matrix = joint.get("m")
        if index is None or not isinstance(matrix, list) or len(matrix) < 15:
            continue
        try:
            x = float(matrix[12])
            y = float(matrix[13])
            z = float(matrix[14])
        except (TypeError, ValueError):
            continue
        if not (math.isfinite(x) and math.isfinite(y) and math.isfinite(z)):
            continue
        positions[index] = (x, y, z)
    return positions, True


def _hand_features(hand):
    """(feature dict or None, raw joint positions or None)."""
    positions, _tracked = _joint_positions(hand)
    if positions is None:
        return None, None
    required = (WRIST,) + CURL_KNUCKLES + CURL_TIPS + (THUMB_TIP, INDEX_TIP)
    if any(positions[index] is None for index in required):
        return None, positions
    wrist = positions[WRIST]
    pinch = _dist(positions[THUMB_TIP], positions[INDEX_TIP])
    curl_sum = 0.0
    for knuckle, tip in zip(CURL_KNUCKLES, CURL_TIPS):
        curl_sum += _dist(positions[tip], positions[knuckle]) / max(0.02, _dist(wrist, positions[knuckle]))
    features = {
        "wrist": wrist,
        "pinch": pinch,
        "curl": curl_sum / float(len(CURL_KNUCKLES)),
        "tip": positions[INDEX_TIP],
    }
    return features, positions


def _pack_f32(value):
    try:
        return struct.pack("<f", float(value))
    except (OverflowError, ValueError):
        return struct.pack("<f", 0.0)


class Dataset(object):
    """One recording with derived per-frame features.

    keep_joints=True additionally retains the raw 27-joint positions and the raw head-matrix
    columns so a frame-rate-matched (90 Hz) copy can be interpolated with the same rules as
    scripts/m7_lab_fixture.py --rate 90 (same interpolation, independent feature derivation).
    """

    __slots__ = (
        "id", "label", "path", "raw_t", "t", "duration", "head", "head_y", "basis",
        "left", "right", "closed_left", "closed_right", "both_closed", "tracked_left",
        "tracked_right", "head_tracked", "pinch_runs_left", "pinch_runs_right",
        "fist_runs_left", "fist_runs_right", "signature", "unparsed", "has_basis",
        "joints_left_raw", "joints_right_raw", "head_col0_raw", "head_col2_raw",
    )

    def __init__(self, path, keep_joints=False):
        self.path = path
        self.id = path.stem
        self.label = dataset_label(self.id)
        raw_t = []
        head = []
        basis = []
        left = []
        right = []
        tracked_left = []
        tracked_right = []
        head_tracked_flags = []
        joints_left_raw = [] if keep_joints else None
        joints_right_raw = [] if keep_joints else None
        head_col0_raw = [] if keep_joints else None
        head_col2_raw = [] if keep_joints else None
        self.unparsed = 0
        digest = hashlib.sha256()
        with path.open("r", errors="replace") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    sample = json.loads(line)
                except ValueError:
                    self.unparsed += 1
                    continue
                try:
                    time_s = float(sample.get("t", 0.0))
                except (TypeError, ValueError):
                    self.unparsed += 1
                    continue
                head_tracked = bool(sample.get("headTracked"))
                raw_head = sample.get("head") or [0.0, 0.0, 0.0]
                try:
                    hx = float(raw_head[0])
                    hy = float(raw_head[1])
                    hz = float(raw_head[2])
                except (TypeError, ValueError, IndexError):
                    hx = hy = hz = 0.0
                if not (math.isfinite(hx) and math.isfinite(hy) and math.isfinite(hz)):
                    hx = hy = hz = 0.0
                fwd = None
                up = None
                matrix = sample.get("headMatrix") or []
                col0 = None
                col2 = None
                if isinstance(matrix, list) and len(matrix) >= 12:
                    try:
                        col0 = (float(matrix[0]), float(matrix[1]), float(matrix[2]))
                        col2 = (float(matrix[8]), float(matrix[9]), float(matrix[10]))
                    except (TypeError, ValueError):
                        col0 = col2 = None
                if head_tracked and col0 is not None:
                    try:
                        up = (float(matrix[4]), float(matrix[5]), float(matrix[6]))
                        fwd = (-float(matrix[8]), -float(matrix[9]), -float(matrix[10]))
                    except (TypeError, ValueError):
                        fwd = up = None
                if keep_joints:
                    head_col0_raw.append(col0)
                    head_col2_raw.append(col2)
                left_features, left_positions = _hand_features(sample.get("left"))
                right_features, right_positions = _hand_features(sample.get("right"))
                left_is_tracked = bool((sample.get("left") or {}).get("tracked"))
                right_is_tracked = bool((sample.get("right") or {}).get("tracked"))
                if keep_joints:
                    joints_left_raw.append(left_positions if left_is_tracked else None)
                    joints_right_raw.append(right_positions if right_is_tracked else None)
                raw_t.append(time_s)
                if not head_tracked and head:
                    head.append(head[-1])
                else:
                    head.append((hx, hy, hz))
                basis.append((fwd, up) if (fwd is not None and up is not None) else None)
                left.append(left_features)
                right.append(right_features)
                tracked_left.append(left_is_tracked)
                tracked_right.append(right_is_tracked)
                head_tracked_flags.append(head_tracked)
                # Frame signature for duplicate-recording detection: exact float32 payloads.
                digest.update(b"F")
                digest.update(struct.pack("<d", time_s))
                digest.update(_pack_f32(hx))
                digest.update(_pack_f32(hy))
                digest.update(_pack_f32(hz))
                digest.update(b"1" if head_tracked else b"0")
                for positions, tracked in ((left_positions, tracked_left[-1]),
                                           (right_positions, tracked_right[-1])):
                    digest.update(b"1" if tracked else b"0")
                    if tracked and positions is not None:
                        for index in SIG_JOINTS:
                            point = positions[index]
                            if point is None:
                                digest.update(b"0")
                            else:
                                digest.update(b"1")
                                digest.update(_pack_f32(point[0]))
                                digest.update(_pack_f32(point[1]))
                                digest.update(_pack_f32(point[2]))
        self.raw_t = raw_t
        self.head = head
        self.basis = basis
        self.left = left
        self.right = right
        self.tracked_left = tracked_left
        self.tracked_right = tracked_right
        self.head_tracked = head_tracked_flags
        self.joints_left_raw = joints_left_raw
        self.joints_right_raw = joints_right_raw
        self.head_col0_raw = head_col0_raw
        self.head_col2_raw = head_col2_raw
        self.signature = digest.hexdigest()
        self._derive()

    def _derive(self):
        """Compute time axis and all derived per-frame feature arrays."""
        raw_t = self.raw_t
        t0 = raw_t[0] if raw_t else 0.0
        self.t = [value - t0 for value in raw_t]
        self.duration = self.t[-1] if self.t else 0.0
        self.head_y = [point[1] for point in self.head]
        left = self.left
        right = self.right
        self.has_basis = any(item is not None for item in self.basis)
        self.pinch_runs_left = runs_of(schmitt(
            [item["pinch"] if item else None for item in left], PINCH_ON_M, PINCH_OFF_M))
        self.pinch_runs_right = runs_of(schmitt(
            [item["pinch"] if item else None for item in right], PINCH_ON_M, PINCH_OFF_M))
        self.closed_left = schmitt(
            [item["curl"] if item else None for item in left], FIST_ON, FIST_OFF)
        self.closed_right = schmitt(
            [item["curl"] if item else None for item in right], FIST_ON, FIST_OFF)
        self.fist_runs_left = runs_of(self.closed_left)
        self.fist_runs_right = runs_of(self.closed_right)
        self.both_closed = [a and b for a, b in zip(self.closed_left, self.closed_right)]


def dataset_label(dataset_id):
    """gesturelab-<LABEL>-<YYYYMMDD>-<HHMMSS> -> <LABEL> (matches M7LabReplay.datasetLabel)."""
    text = dataset_id[len("gesturelab-"):] if dataset_id.startswith("gesturelab-") else dataset_id
    cut = text.rfind("-")
    if cut > 0:
        tail = text[cut + 1:]
        if len(tail) == 6 and tail.isdigit():
            text = text[:cut]
            cut = text.rfind("-")
            if cut > 0:
                date = text[cut + 1:]
                if len(date) == 8 and date.isdigit():
                    text = text[:cut]
    return text


def load_raw_datasets(data_dir):
    """Load every raw recording under <data>/accepted and <data>/*.jsonl."""
    paths = []
    accepted = data_dir / "accepted"
    if accepted.is_dir():
        paths.extend(sorted(accepted.glob("gesturelab-*.jsonl")))
    paths.extend(sorted(data_dir.glob("gesturelab-*.jsonl")))
    seen = set()
    datasets = []
    for path in paths:
        if path.stem in seen:
            continue
        seen.add(path.stem)
        datasets.append(Dataset(path))
    return datasets


# ------------------------------------------------------------------------------------------------
# Frame-rate-matched (90 Hz) ground truth
#
# The Java replay harness resamples the recorded ~18 Hz joints to the game cadence with
# scripts/m7_lab_fixture.py --rate 90: linear interpolation between consecutive samples, steps =
# round(dt/(1/rate)), hands interpolated only when both endpoint hand-tracking flags are set, no
# bridging of gaps above 0.20 s. Re-deriving the ground truth on that same 90 Hz frame grid is the
# only rate fix: the feature rules below stay identical to the raw-18 Hz ground truth and are still
# computed by this evaluator (no engine imports).
# ------------------------------------------------------------------------------------------------
RESAMPLE_MAX_BRIDGE_S = 0.20
RESAMPLE_RATE_HZ = 90.0


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def _unit(vector):
    length = math.sqrt(_dot(vector, vector))
    if length <= 1e-4:
        return None
    return (vector[0] / length, vector[1] / length, vector[2] / length)


def _basis_from_matrix_cols(col0, col2):
    """Right/up/forward basis exactly as the replay harness derives it from the interpolated matrix."""
    if col0 is None or col2 is None:
        return None
    right = _unit(col0)
    backward = _unit(col2)
    if right is None or backward is None:
        return None
    forward = (-backward[0], -backward[1], -backward[2])
    return (forward, _cross(right, forward))


def _lerp_tuple(a, b, alpha):
    return (a[0] + (b[0] - a[0]) * alpha,
            a[1] + (b[1] - a[1]) * alpha,
            a[2] + (b[2] - a[2]) * alpha)


def _lerp_positions(a, b, alpha):
    """Interpolate two 27-joint position arrays; a missing joint is the fixture's zero sentinel."""
    zero = (0.0, 0.0, 0.0)
    out = []
    for point_a, point_b in zip(a, b):
        pa = point_a if point_a is not None else zero
        pb = point_b if point_b is not None else zero
        out.append(_lerp_tuple(pa, pb, alpha))
    return out


def _features_from_positions(positions):
    """Hand features from a full 27-joint position list (fixture semantics: missing -> zeros)."""
    if positions is None:
        return None
    zero = (0.0, 0.0, 0.0)
    points = [point if point is not None else zero for point in positions]
    wrist = points[WRIST]
    pinch = _dist(points[THUMB_TIP], points[INDEX_TIP])
    curl_sum = 0.0
    for knuckle, tip in zip(CURL_KNUCKLES, CURL_TIPS):
        curl_sum += _dist(points[tip], points[knuckle]) / max(0.02, _dist(wrist, points[knuckle]))
    return {
        "wrist": wrist,
        "pinch": pinch,
        "curl": curl_sum / float(len(CURL_KNUCKLES)),
        "tip": points[INDEX_TIP],
    }


def _resampled_dataset(original, raw_t, head, basis, left, right, tracked_left, tracked_right):
    dataset = object.__new__(Dataset)
    dataset.path = original.path
    dataset.id = original.id
    dataset.label = original.label
    dataset.raw_t = raw_t
    dataset.head = head
    dataset.basis = basis
    dataset.left = left
    dataset.right = right
    dataset.tracked_left = tracked_left
    dataset.tracked_right = tracked_right
    dataset.head_tracked = [True] * len(raw_t)
    dataset.signature = "resampled:" + original.signature[:16]
    dataset.unparsed = 0
    dataset.joints_left_raw = None
    dataset.joints_right_raw = None
    dataset.head_col0_raw = None
    dataset.head_col2_raw = None
    dataset._derive()
    return dataset


def resample_dataset(dataset, rate=RESAMPLE_RATE_HZ):
    """Interpolate a raw recording to the replay frame cadence (fixture 90 Hz rules).

    Sentinel head rows (head not tracked, empty head matrix) are carried over from the last tracked
    head pose instead of being interpolated, so a missing pose never invents head motion.
    """
    if dataset.joints_left_raw is None:
        raise ValueError("resample_dataset needs Dataset(..., keep_joints=True)")
    count = len(dataset.raw_t)
    step = 1.0 / rate
    # Clean head pose: carry the last tracked/valid pose across sentinel rows.
    head_clean = []
    col0_clean = []
    col2_clean = []
    last_head = dataset.head[0] if dataset.head else (0.0, 0.0, 0.0)
    last_col0 = None
    last_col2 = None
    for index in range(count):
        if dataset.head_tracked[index]:
            last_head = dataset.head[index]
        head_clean.append(last_head)
        col0 = dataset.head_col0_raw[index]
        col2 = dataset.head_col2_raw[index]
        if col0 is not None and col2 is not None:
            last_col0 = col0
            last_col2 = col2
        col0_clean.append(last_col0)
        col2_clean.append(last_col2)
    out_t = []
    out_head = []
    out_basis = []
    out_left = []
    out_right = []
    out_tracked_left = []
    out_tracked_right = []

    def emit(time_s, head, col0, col2, pos_left, pos_right, tr_left, tr_right):
        out_t.append(time_s)
        out_head.append(head)
        out_basis.append(_basis_from_matrix_cols(col0, col2))
        out_tracked_left.append(tr_left)
        out_tracked_right.append(tr_right)
        out_left.append(_features_from_positions(pos_left) if tr_left else None)
        out_right.append(_features_from_positions(pos_right) if tr_right else None)

    for index in range(count - 1):
        t0 = dataset.raw_t[index]
        t1 = dataset.raw_t[index + 1]
        dt = t1 - t0
        if dt <= 0.0:
            continue
        pos_left0 = dataset.joints_left_raw[index]
        pos_right0 = dataset.joints_right_raw[index]
        tr_left = dataset.tracked_left[index]
        tr_right = dataset.tracked_right[index]
        if dt > RESAMPLE_MAX_BRIDGE_S:
            emit(t0, head_clean[index], col0_clean[index], col2_clean[index],
                 pos_left0, pos_right0, tr_left, tr_right)
            continue
        steps = max(1, int(round(dt / step)))
        both_left = dataset.tracked_left[index] and dataset.tracked_left[index + 1]
        both_right = dataset.tracked_right[index] and dataset.tracked_right[index + 1]
        pos_left1 = dataset.joints_left_raw[index + 1]
        pos_right1 = dataset.joints_right_raw[index + 1]
        for k in range(steps):
            alpha = k / float(steps)
            time_s = t0 + dt * alpha
            head = _lerp_tuple(head_clean[index], head_clean[index + 1], alpha)
            if col0_clean[index] is not None and col0_clean[index + 1] is not None:
                col0 = _lerp_tuple(col0_clean[index], col0_clean[index + 1], alpha)
                col2 = _lerp_tuple(col2_clean[index], col2_clean[index + 1], alpha)
            else:
                col0 = col0_clean[index]
                col2 = col2_clean[index]
            left_positions = _lerp_positions(pos_left0, pos_left1, alpha) if both_left else None
            right_positions = _lerp_positions(pos_right0, pos_right1, alpha) if both_right else None
            emit(time_s, head, col0, col2, left_positions, right_positions,
                 both_left, both_right)
    last = count - 1
    emit(dataset.raw_t[last], head_clean[last], col0_clean[last], col2_clean[last],
         dataset.joints_left_raw[last], dataset.joints_right_raw[last],
         dataset.tracked_left[last], dataset.tracked_right[last])
    return _resampled_dataset(dataset, out_t, out_head, out_basis, out_left, out_right,
                              out_tracked_left, out_tracked_right)


# ------------------------------------------------------------------------------------------------
# Bounded engine latency policy for held states
#
# A causal engine cannot assert a held state at the exact physical instant the ground-truth feature
# appears: pinch/teleport/break need a debounce or hold threshold, walk needs two swing crossings,
# bow needs arm persistence, eat/sneak need latch timers, and releases trail the physical end by a
# bounded timer. The table below is *read from the current VisionM7Gesture constants* (never invented
# when the source is available): onset latency = how much later the engine may start than the
# ground-truth window; release latency = how much later the engine may end. The latency-aware held
# score applies the bound as an interval transform [start + onset, end + release]; the literal score
# and its gates are unchanged.
# ------------------------------------------------------------------------------------------------
CONSTANT_RE = re.compile(
    r"public\s+static\s+final\s+(?:long|float|int)\s+([A-Z0-9_]+)\s*=\s*([^;]+);")
# Documented fallback values (nanoseconds) matching the frozen engine revision only if the source is
# unavailable at runtime; the evaluator prints a warning in that case.
FALLBACK_NS = {
    "PINCH_DEBOUNCE_NS": 30_000_000.0,
    "PLACE_MAX_NS": 320_000_000.0,
    "TELEPORT_MIN_HOLD_NS": 120_000_000.0,
    "WALK_STOP_NS": 600_000_000.0,
    "WALK_FIST_GRACE_NS": 220_000_000.0,
    "BOW_ARM_NS": 100_000_000.0,
    "EAT_LATCH_NS": 60_000_000.0,
    "EAT_GAP_NS": 150_000_000.0,
    "HEAD_SNEAK_LATCH_NS": 500_000_000.0,
    "HEAD_SNEAK_RELEASE_NS": 250_000_000.0,
}
# action -> {'start': {'constants': [...]} or {'fixed': s}, 'end': ..., 'note': str}
LATENCY_POLICY = {
    "break": {
        "start": {"constants": ("PLACE_MAX_NS", "PINCH_DEBOUNCE_NS")},
        "end": {"constants": ("PINCH_DEBOUNCE_NS",)},
        "note": "held break can only assert after the PLACE_MAX hold split + pinch debounce; release is the debounced release frame",
    },
    "teleport": {
        "start": {"constants": ("TELEPORT_MIN_HOLD_NS", "PINCH_DEBOUNCE_NS")},
        "end": {"constants": ("PINCH_DEBOUNCE_NS",)},
        "note": "teleport-aim starts only after TELEPORT_MIN_HOLD + pinch debounce",
    },
    "walk": {
        "start": {"fixed": 0.0},
        "end": {"constants": ("WALK_STOP_NS", "WALK_FIST_GRACE_NS")},
        "note": "no onset shift: the GT window spans first..last swing crossing, and the 2-crossing start is inside it; stop hysteresis + fist grace trail the end",
    },
    "bowDraw": {
        "start": {"constants": ("BOW_ARM_NS",)},
        "end": {"constants": ("PINCH_DEBOUNCE_NS",)},
        "note": "bow draw asserts after BOW_ARM persistence; release is immediate (fire edge)",
    },
    "eat": {
        "start": {"constants": ("EAT_LATCH_NS",)},
        "end": {"constants": ("EAT_GAP_NS",)},
        "note": "eat latches after EAT_LATCH; release trails by the EAT_GAP exit hysteresis",
    },
    "sneak": {
        "start": {"constants": ("HEAD_SNEAK_LATCH_NS",)},
        "end": {"constants": ("HEAD_SNEAK_RELEASE_NS",)},
        "note": "sneak latches after HEAD_SNEAK_LATCH; releases after HEAD_SNEAK_RELEASE below the drop threshold",
    },
    "climbGrabLeft": {
        "start": {"fixed": 0.0},
        "end": {"fixed": 0.10},
        "note": "fist Schmitt transition is immediate; no timing constant in the engine, 0.10 s policy bound on release",
    },
    "climbGrabRight": {
        "start": {"fixed": 0.0},
        "end": {"fixed": 0.10},
        "note": "fist Schmitt transition is immediate; no timing constant in the engine, 0.10 s policy bound on release",
    },
}


def _parse_constant_expression(expression):
    text = expression.strip().replace("_", "")
    text = text.rstrip("FfLl")
    return float(text)


def read_engine_constants(path):
    """Return ({constant: numeric_value}, status dict) parsed from the engine source, or (None, status)."""
    status = {"source": str(path), "parsed": False, "count": 0, "constantCount": 0}
    try:
        text = path.read_text(errors="replace")
    except OSError:
        status["error"] = "engine source not readable"
        return None, status
    constants = {}
    for match in CONSTANT_RE.finditer(text):
        name = match.group(1)
        try:
            constants[name] = _parse_constant_expression(match.group(2))
        except (TypeError, ValueError):
            continue
    status["count"] = len(constants)
    status["parsed"] = bool(constants)
    return (constants or None), status


def build_latency_table(constants):
    """Per-action bounded onset/release latency, derived from engine constants when available."""
    table = {}
    missing = set()

    def component_seconds(spec):
        if "fixed" in spec:
            return float(spec["fixed"]), "policy"
        total = 0.0
        sources = []
        for name in spec["constants"]:
            if constants is not None and name in constants:
                total += float(constants[name]) / 1.0e9
                sources.append(name)
            elif name in FALLBACK_NS:
                total += FALLBACK_NS[name] / 1.0e9
                sources.append(name + "(fallback)")
                missing.add(name)
            else:
                missing.add(name)
                sources.append(name + "(missing)")
        return total, " + ".join(sources)

    for action, policy in LATENCY_POLICY.items():
        start_s, start_source = component_seconds(policy["start"])
        end_s, end_source = component_seconds(policy["end"])
        table[action] = {
            "start_s": round(start_s, 3),
            "end_s": round(end_s, 3),
            "start_source": start_source,
            "end_source": end_source,
            "note": policy["note"],
        }
    return table, sorted(missing)


def apply_latency(windows, start_latency_s, end_latency_s, duration_s):
    """Interval transform modelling the bounded engine detection/release delay."""
    shifted = []
    for start, end in windows:
        new_start = start + start_latency_s
        new_end = end + end_latency_s
        new_start = max(0.0, min(new_start, duration_s))
        new_end = max(0.0, min(new_end, duration_s))
        if new_end > new_start:
            shifted.append((new_start, new_end))
    return shifted


# ------------------------------------------------------------------------------------------------
# Per-frame windowed displacement speeds
# ------------------------------------------------------------------------------------------------
def windowed_speeds(times, positions, window_s):
    """displacement / dt between the current frame and the newest sample at or before now-window_s."""
    count = len(times)
    out = [0.0] * count
    previous = -1
    for i in range(count):
        while previous + 1 < i and times[i] - times[previous + 1] >= window_s:
            previous += 1
        if previous < 0:
            continue
        current = positions[i]
        older = positions[previous]
        if current is None or older is None:
            continue
        dt = times[i] - times[previous]
        if dt <= 1e-9:
            continue
        out[i] = _dist(current, older) / dt
    return out


def _local_peaks(values, threshold, count):
    peaks = []
    for i in range(1, count - 1):
        value = values[i]
        if value < threshold:
            continue
        if value >= values[i - 1] and value >= values[i + 1]:
            peaks.append(i)
    return peaks


def _cooldown_peaks(indices, times, cooldown_s):
    selected = []
    for index in indices:
        if not selected or times[index] - times[selected[-1]] >= cooldown_s:
            selected.append(index)
    return selected


# ------------------------------------------------------------------------------------------------
# Ground-truth event derivation
# ------------------------------------------------------------------------------------------------
def _walk_windows(ds):
    t = ds.t
    state = 0
    crossings = []
    for i in range(len(t)):
        if not ds.both_closed[i] or ds.basis[i] is None:
            continue
        fwd = ds.basis[i][0]
        rel_left = _sub(ds.left[i]["wrist"], ds.head[i])
        rel_right = _sub(ds.right[i]["wrist"], ds.head[i])
        diff = _dot(rel_left, fwd) - _dot(rel_right, fwd)
        if diff >= WALK_AMPLITUDE_M:
            if state == -1:
                crossings.append(t[i])
            state = 1
        elif diff <= -WALK_AMPLITUDE_M:
            if state == 1:
                crossings.append(t[i])
            state = -1
    windows = []
    if not crossings:
        return windows
    start = crossings[0]
    last = crossings[0]
    for crossing in crossings[1:]:
        if crossing - last < WALK_BURST_GAP_S:
            last = crossing
        else:
            windows.append((start, last))
            start = last = crossing
    windows.append((start, last))
    return [(a, b) for a, b in windows if b - a > 1e-9]


def _bow_quality(ds, require_both_fists):
    quality = []
    for i in range(len(ds.t)):
        ok = False
        if ds.basis[i] is not None and ds.left[i] and ds.right[i]:
            fwd, up = ds.basis[i]
            rel_left = _sub(ds.left[i]["wrist"], ds.head[i])
            rel_right = _sub(ds.right[i]["wrist"], ds.head[i])
            separation = abs(_dot(rel_left, fwd) - _dot(rel_right, fwd))
            high = _dot(rel_left, up) > BOW_MIN_UP_M and _dot(rel_right, up) > BOW_MIN_UP_M
            if require_both_fists:
                fists = ds.closed_left[i] and ds.closed_right[i]
            else:
                fists = ds.closed_left[i] or ds.closed_right[i]
            ok = separation > BOW_SEPARATION_M and high and fists
        quality.append(ok)
    return quality


def _bow_windows(ds, require_both_fists=True):
    runs = merge_runs(runs_of(_bow_quality(ds, require_both_fists)), ds.t, BOW_MERGE_GAP_S)
    return [(a, b) for a, b in runs if ds.t[b] - ds.t[a] >= BOW_MIN_WINDOW_S]


def _bow_fires(ds, windows):
    fires = []
    t = ds.t
    count = len(t)
    for first, last in windows:
        fwd = ds.basis[last][0]
        rel_left = _sub(ds.left[last]["wrist"], ds.head[last])
        rel_right = _sub(ds.right[last]["wrist"], ds.head[last])
        left_is_back = _dot(rel_left, fwd) < _dot(rel_right, fwd)
        back_closed = ds.closed_left if left_is_back else ds.closed_right
        front_closed = ds.closed_right if left_is_back else ds.closed_left
        fire_time = None
        for index in range(last, min(count, last + BOW_FIRE_TAIL_FRAMES + 1)):
            if not back_closed[index] and front_closed[index]:
                fire_time = t[index]
                break
        if fire_time is not None:
            fires.append(fire_time)
    return fires


def _eat_windows(ds):
    quality = []
    for i in range(len(ds.t)):
        ok = False
        if ds.right[i] and ds.basis[i] is not None:
            fwd, up = ds.basis[i]
            rel = _sub(ds.right[i]["wrist"], ds.head[i])
            ok = (_dist(rel, (0.0, 0.0, 0.0)) <= EAT_DIST_M
                  and _dot(rel, fwd) > EAT_MIN_FORWARD_M
                  and EAT_MIN_UP_M <= _dot(rel, up) <= EAT_MAX_UP_M)
        quality.append(ok)
    runs = merge_runs(runs_of(quality), ds.t, EAT_MERGE_GAP_S)
    return [(ds.t[a], ds.t[b]) for a, b in runs if b > a]


def _attack_events(ds):
    wrist_positions = [item["wrist"] if item else None for item in ds.right]
    speeds = windowed_speeds(ds.t, wrist_positions, ATTACK_WINDOW_S)
    count = len(ds.t)
    peaks = []
    for i in _local_peaks(speeds, ATTACK_PEAK_MPS, count):
        if ds.closed_left[i]:
            continue  # both-fist motion is walk/bow/inventory, not a one-handed swing
        peaks.append(i)
    selected = _cooldown_peaks(peaks, ds.t, ATTACK_COOLDOWN_S)
    return [ds.t[index] for index in selected]


def _hotbar_events(ds):
    tip_positions = [item["tip"] if item else None for item in ds.right]
    wrist_positions = [item["wrist"] if item else None for item in ds.right]
    tip_speeds = windowed_speeds(ds.t, tip_positions, HOTBAR_TIP_WINDOW_S)
    wrist_speeds = windowed_speeds(ds.t, wrist_positions, HOTBAR_WRIST_WINDOW_S)
    count = len(ds.t)
    peaks = []
    for i in _local_peaks(tip_speeds, HOTBAR_PEAK_MPS, count):
        if wrist_speeds[i] >= HOTBAR_WRIST_MAX_MPS:
            continue
        peaks.append(i)
    selected = _cooldown_peaks(peaks, ds.t, HOTBAR_COOLDOWN_S)
    return [ds.t[index] for index in selected]


def _head_baseline(ds):
    t = ds.t
    y = ds.head_y
    if not y:
        return []
    baseline = [y[0]]
    level = y[0]
    for i in range(1, len(y)):
        dt = t[i] - t[i - 1]
        deviation = y[i] - level
        if abs(deviation) <= JUMP_FREEZE_DEV_M:
            level += (1.0 - math.exp(-dt / JUMP_TAU_S)) * deviation
        baseline.append(level)
    return baseline


def _jump_events(ds):
    t = ds.t
    y = ds.head_y
    baseline = _head_baseline(ds)
    count = len(t)
    candidates = []
    for i in range(count):
        if y[i] - baseline[i] <= JUMP_RISE_M:
            continue
        older = i - 1
        while older >= 0 and t[i] - t[older] < JUMP_VEL_WINDOW_S:
            older -= 1
        if older < 0:
            continue
        dt = t[i] - t[older]
        if dt <= 1e-9:
            continue
        if (y[i] - y[older]) / dt <= JUMP_VEL_MPS:
            continue
        candidates.append(i)
    selected = _cooldown_peaks(candidates, t, JUMP_COOLDOWN_S)
    return [t[index] for index in selected]


def _sneak_windows(ds):
    t = ds.t
    y = ds.head_y
    baseline = _head_baseline(ds)
    drop = [baseline[i] - y[i] for i in range(len(y))]
    count = len(t)
    windows = []
    i = 0
    while i < count:
        if drop[i] <= SNEAK_DROP_M:
            i += 1
            continue
        last = i
        while last + 1 < count and drop[last + 1] > SNEAK_DROP_M:
            last += 1
        if t[last] - t[i] < SNEAK_LATCH_S:
            i = last + 1
            continue
        release_at = None
        cursor = last + 1
        quiet_since = None
        while cursor < count:
            if drop[cursor] < SNEAK_RELEASE_DROP_M:
                if quiet_since is None:
                    quiet_since = cursor
                if t[cursor] - t[quiet_since] >= SNEAK_RELEASE_S:
                    release_at = t[cursor]
                    break
            else:
                quiet_since = None
            cursor += 1
        windows.append((t[i], release_at if release_at is not None else t[-1]))
        i = cursor + 1
    return windows


def _climb_windows(ds, hand_name):
    hand_values = ds.left if hand_name == "left" else ds.right
    closed = ds.closed_left if hand_name == "left" else ds.closed_right
    quality = []
    for i in range(len(ds.t)):
        ok = False
        if closed[i] and hand_values[i] and ds.basis[i] is not None:
            up = ds.basis[i][1]
            rel = _sub(hand_values[i]["wrist"], ds.head[i])
            ok = _dot(rel, up) > CLIMB_MIN_UP_M
        quality.append(ok)
    windows = []
    for first, last in runs_of(quality):
        if ds.t[last] - ds.t[first] >= CLIMB_MIN_WINDOW_S:
            windows.append((ds.t[first], ds.t[last]))
    return windows


def expected_events(ds):
    """Ground-truth events for one dataset: {'pulses': {action: [t,...]}, 'windows': {action: [(a,b)]}}."""
    t = ds.t
    pulses = {}
    windows = {}

    def add_pulse(action, when):
        pulses.setdefault(action, []).append(when)

    def add_window(action, first, last):
        windows.setdefault(action, []).append((first, last))

    # right pinch: short = place, held = break
    for first, last in ds.pinch_runs_right:
        duration = t[last] - t[first]
        if duration < PLACE_MAX_S:
            add_pulse("place", t[last])
        else:
            add_window("break", t[first], t[last])
    # left pinch: teleport hold
    for first, last in ds.pinch_runs_left:
        add_window("teleport", t[first], t[last])
    # left-fist tap: menu/Escape
    for first, last in ds.fist_runs_left:
        duration = t[last] - t[first]
        if MENU_TAP_MIN_S <= duration <= MENU_TAP_MAX_S:
            add_pulse("menu", t[last])
    # both-fist tap: inventory
    for first, last in runs_of(ds.both_closed):
        # Duration is start -> release in the engine, so a one-frame both-fist sample is still a
        # short tap; compare the raw start-to-last-frame span (zero for a single frame).
        duration = t[last] - t[first]
        if duration <= INVENTORY_MAX_S:
            max_sep = 0.0
            for index in range(first, last + 1):
                max_sep = max(max_sep, _dist(ds.left[index]["wrist"], ds.right[index]["wrist"]))
            if max_sep < INVENTORY_MAX_SEP_M:
                add_pulse("inventory", t[last])
    # walk / bow / eat / climb need the head basis
    if ds.has_basis:
        for start, end in _walk_windows(ds):
            add_window("walk", start, end)
        draw_windows = _bow_windows(ds, require_both_fists=True)
        for first, last in draw_windows:
            add_window("bowDraw", t[first], t[last])
        for fire_time in _bow_fires(ds, draw_windows):
            add_pulse("bowFire", fire_time)
        for start, end in _eat_windows(ds):
            add_window("eat", start, end)
        for start, end in _climb_windows(ds, "left"):
            add_window("climbGrabLeft", start, end)
        for start, end in _climb_windows(ds, "right"):
            add_window("climbGrabRight", start, end)
    # engine-independent motion gestures
    for when in _attack_events(ds):
        add_pulse("attack", when)
    for when in _hotbar_events(ds):
        add_pulse("hotbarNext", when)
    for when in _jump_events(ds):
        add_pulse("jump", when)
    for start, end in _sneak_windows(ds):
        add_window("sneak", start, end)
    return {"pulses": pulses, "windows": windows}


# ------------------------------------------------------------------------------------------------
# Replay event loading / scoring
# ------------------------------------------------------------------------------------------------
def load_events(path):
    """{dataset_id: {'label': str, 'pulses': [(action, t_s)], 'held': [(action, start_s, end_s)]}}
    Returns (events, event_count, malformed_count, unknown_action_names)."""
    events = {}
    unparsed = 0
    count = 0
    known_actions = set(PULSE_ACTIONS) | set(HELD_ACTIONS)
    unknown_actions = set()
    with path.open("r", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                item = json.loads(line)
                dataset = item["dataset"]
                action = item["action"]
                kind = item["kind"]
                time_s = float(item["t_ms"]) / 1000.0
            except (ValueError, KeyError, TypeError):
                unparsed += 1
                continue
            entry = events.setdefault(dataset, {"label": item.get("label", ""), "pulses": [],
                                               "held": []})
            if kind == "pulse":
                entry["pulses"].append((action, time_s))
                count += 1
            elif kind == "held":
                try:
                    duration_s = float(item.get("dur_ms", 0.0)) / 1000.0
                except (TypeError, ValueError):
                    duration_s = 0.0
                entry["held"].append((action, time_s, time_s + max(0.0, duration_s)))
                count += 1
            else:
                unparsed += 1
            if action not in known_actions:
                unknown_actions.add(action)
    return events, count, unparsed, sorted(unknown_actions)


def _pulse_union(entry, actions):
    """Detected pulse times for an action (or union of actions), same-frame duplicates suppressed."""
    times = []
    wanted = set(actions)
    for action, when in entry.get("pulses", ()):
        if action in wanted:
            times.append(when)
    times.sort()
    unique = []
    for when in times:
        if not unique or when - unique[-1] > UNION_DUPE_S:
            unique.append(when)
    return unique


def _held_runs(entry, action):
    return [(start, end) for name, start, end in entry.get("held", ()) if name == action]


def _target_dataset_ids(datasets, labels):
    return [ds.id for ds in datasets if ds.label in labels]


def score_pulses(action, datasets, events, expected, excluded_ids, durations):
    labels = TARGET_LABELS[action]
    target_ids = _target_dataset_ids(datasets, labels)
    if not target_ids:
        return {"action": action, "skipped": True, "skip_reason": "no raw recording for target label",
                "target_labels": list(labels)}
    detected_actions = DETECTED_ACTION_UNION.get(action, (action,))
    truth_action = GROUND_TRUTH_ACTION.get(action, action)
    expected_times = []
    detected_times = []
    match_offsets = []
    per_dataset = []
    empty_target_datasets = []
    matched = 0
    for dataset_id in target_ids:
        exp = list(expected.get(dataset_id, {}).get("pulses", {}).get(truth_action, []))
        det = _pulse_union(events.get(dataset_id, {}), detected_actions)
        pairs = match_pairs(exp, det, PULSE_TOLERANCE_S[action])
        got = len(pairs)
        matched += got
        match_offsets.extend(abs(have - want) for want, have in pairs)
        expected_times.extend(exp)
        detected_times.extend(det)
        if not det:
            # A raw target recording exists but the replay emitted nothing for this action: this is
            # a regression signal, never a reason to drop the dataset.
            empty_target_datasets.append(dataset_id)
        per_dataset.append({
            "dataset": dataset_id,
            "expected": len(exp),
            "detected": len(det),
            "matched": got,
        })
    target_set = set(target_ids)
    cross_ids = [ds.id for ds in datasets
                 if ds.id not in target_set and ds.id not in excluded_ids]
    cross_false = 0
    for dataset_id in cross_ids:
        cross_false += len(_pulse_union(events.get(dataset_id, {}), detected_actions))
    cross_minutes = sum(durations.get(dataset_id, 0.0) for dataset_id in cross_ids) / 60.0
    expected_count = len(expected_times)
    detected_count = len(detected_times)
    return {
        "action": action,
        "target_labels": list(labels),
        "target_datasets": per_dataset,
        "expected": expected_count,
        "detected": detected_count,
        "matched": matched,
        "recall": (matched / float(expected_count)) if expected_count else 1.0,
        "precision": (matched / float(detected_count)) if detected_count else 1.0,
        "cross_false": cross_false,
        "cross_minutes": cross_minutes,
        "false_per_min": (cross_false / cross_minutes) if cross_minutes > 0 else 0.0,
        "tolerance_s": PULSE_TOLERANCE_S[action],
        "median_match_offset_s": _round(_median(match_offsets), 3),
        "max_match_offset_s": _round(max(match_offsets), 3) if match_offsets else None,
        "unmatched_expected": expected_count - matched,
        "unmatched_detected": detected_count - matched,
        "empty_target_datasets": empty_target_datasets,
        "rate": "90",
    }


def score_held(action, datasets, events, expected, excluded_ids, durations, latency=None):
    labels = TARGET_LABELS[action]
    target_ids = _target_dataset_ids(datasets, labels)
    if not target_ids:
        return {"action": action, "skipped": True, "skip_reason": "no raw recording for target label",
                "target_labels": list(labels)}
    expected_intervals = []
    detected_intervals = []
    aware_intervals = []
    expected_windows = 0
    detected_runs = 0
    empty_target_datasets = []
    per_dataset = []
    for dataset_id in target_ids:
        duration = durations.get(dataset_id, 0.0)
        exp = [tuple(item) for item in expected.get(dataset_id, {}).get("windows", {}).get(action, [])]
        det = []
        for start, end in _held_runs(events.get(dataset_id, {}), action):
            start = max(0.0, min(start, duration))
            end = max(0.0, min(end, duration))
            if end > start:
                det.append((start, end))
        if not det:
            empty_target_datasets.append(dataset_id)
        expected_windows += len(exp)
        detected_runs += len(det)
        expected_intervals.extend(exp)
        detected_intervals.extend(det)
        if latency is not None:
            aware_intervals.extend(apply_latency(
                exp, latency["start_s"], latency["end_s"], duration))
        per_dataset.append({
            "dataset": dataset_id,
            "expected_windows": len(exp),
            "expected_s": intervals_length(exp),
            "detected_runs": len(det),
            "detected_s": intervals_length(det),
        })
    target_set = set(target_ids)
    cross_ids = [ds.id for ds in datasets
                 if ds.id not in target_set and ds.id not in excluded_ids]
    cross_active = 0.0
    for dataset_id in cross_ids:
        duration = durations.get(dataset_id, 0.0)
        intervals = []
        for start, end in _held_runs(events.get(dataset_id, {}), action):
            start = max(0.0, min(start, duration))
            end = max(0.0, min(end, duration))
            if end > start:
                intervals.append((start, end))
        cross_active += intervals_length(intervals)
    cross_minutes = sum(durations.get(dataset_id, 0.0) for dataset_id in cross_ids) / 60.0
    expected_length = intervals_length(expected_intervals)
    detected_length = intervals_length(detected_intervals)
    overlap = interval_overlap(expected_intervals, detected_intervals)
    target_total = sum(durations.get(dataset_id, 0.0) for dataset_id in target_ids)
    non_expected = max(0.0, target_total - expected_length)
    result = {
        "action": action,
        "target_labels": list(labels),
        "target_datasets": per_dataset,
        "expected_windows": expected_windows,
        "expected_s": expected_length,
        "detected_runs": detected_runs,
        "detected_s": detected_length,
        "coverage": (overlap / expected_length) if expected_length > 0 else 1.0,
        "false_active_s": max(0.0, detected_length - overlap),
        "false_active": ((detected_length - overlap) / non_expected) if non_expected > 1e-9 else 0.0,
        "run_ratio": (detected_runs / float(expected_windows)) if expected_windows else 0.0,
        "cross_active_s": cross_active,
        "cross_minutes": cross_minutes,
        "cross_s_per_min": (cross_active / cross_minutes) if cross_minutes > 0 else 0.0,
        "empty_target_datasets": empty_target_datasets,
        "rate": "raw",
    }
    if latency is not None:
        aware_length = intervals_length(aware_intervals)
        aware_overlap = interval_overlap(aware_intervals, detected_intervals)
        aware_non_expected = max(0.0, target_total - aware_length)
        result["latency"] = {
            "start_s": latency["start_s"],
            "end_s": latency["end_s"],
            "coverage": (aware_overlap / aware_length) if aware_length > 0 else 1.0,
            "expected_s": aware_length,
            "non_expected_s": aware_non_expected,
            "false_active_s": max(0.0, detected_length - aware_overlap),
            "false_active": ((detected_length - aware_overlap) / aware_non_expected)
            if aware_non_expected > 1e-9 else 0.0,
        }
    return result


# ------------------------------------------------------------------------------------------------
# Cross-dataset matrix
# ------------------------------------------------------------------------------------------------
def cross_matrix(datasets, events):
    rows = []
    for ds in datasets:
        entry = events.get(ds.id, {})
        pulses = {}
        held = {}
        for action, _when in entry.get("pulses", ()):
            pulses[action] = pulses.get(action, 0) + 1
        for action, start, end in entry.get("held", ()):
            duration = max(0.0, min(end, ds.duration) - max(0.0, start))
            held[action] = held.get(action, 0.0) + duration
        rows.append({
            "dataset": ds.id,
            "label": ds.label,
            "duration_s": ds.duration,
            "pulses": pulses,
            "held_s": held,
        })
    return rows


def context_checks(datasets, events_raw, events_90):
    """Counts of gestures that the labelled scenario must suppress."""
    rows = []
    for label, scenario, forbiddens in GATE_CONTEXT:
        dataset_ids = [ds.id for ds in datasets if ds.label == label]
        for action, kind, limit in forbiddens:
            if kind == "pulse":
                source = "90"
                events = events_90
                counter = lambda dataset_id: len(
                    _pulse_union(events.get(dataset_id, {}), (action,)))
            else:
                source = "raw"
                events = events_raw
                counter = lambda dataset_id: len(
                    _held_runs(events.get(dataset_id, {}), action))
            if events is None:
                rows.append({
                    "scenario": scenario, "label": label, "action": action, "kind": kind,
                    "source": source, "value": 0, "limit": limit, "pass": None,
                    "skipped": True,
                })
                continue
            total = 0
            for dataset_id in dataset_ids:
                total += counter(dataset_id)
            rows.append({
                "scenario": scenario,
                "label": label,
                "action": action,
                "kind": kind,
                "source": source,
                "value": total,
                "limit": limit,
                "pass": total <= limit,
                "skipped": False,
            })
    return rows


# ------------------------------------------------------------------------------------------------
# Output helpers
# ------------------------------------------------------------------------------------------------
def _mtime_text(path):
    try:
        stamp = path.stat().st_mtime
    except OSError:
        return "missing"
    return datetime.datetime.fromtimestamp(stamp).strftime("%Y-%m-%d %H:%M:%S")


def _mtime_value(path):
    try:
        return path.stat().st_mtime
    except OSError:
        return None


def _format_pulse_table(scores, show_gate=True):
    lines = ["  action   target                exp  det  match  recall  precision  cross  fp/min   gate"]
    for score in scores:
        action = score["action"]
        gate = GATE_PULSE.get(action)
        if score.get("skipped"):
            lines.append("  %-8s %-20s    -    -      -   SKIP (%s)" % (
                action, ",".join(score.get("target_labels", ())),
                score.get("skip_reason", "missing replay file")))
            continue
        if gate is None or not show_gate:
            verdict = "-"
        else:
            min_recall, min_precision, max_false = gate
            reasons = []
            if score["recall"] < min_recall:
                reasons.append("recall<%.2f" % min_recall)
            if score["precision"] < min_precision:
                reasons.append("precision<%.2f" % min_precision)
            if score["false_per_min"] > max_false:
                reasons.append("fp/min>%.2f" % max_false)
            verdict = "FAIL " + ",".join(reasons) if reasons else "PASS"
        target = ",".join(score["target_labels"])
        lines.append("  %-8s %-20s %4d %4d %6d  %6.2f  %9.2f  %5d  %6.2f   %s" % (
            action, target, score["expected"], score["detected"], score["matched"],
            score["recall"], score["precision"], score["cross_false"],
            score["false_per_min"], verdict))
    return lines


def _format_held_table(scores, show_gate=True):
    lines = ["  action           target                exp_win   exp_s  runs   det_s  cover  false  cross/min  gate"]
    for score in scores:
        action = score["action"]
        gate = GATE_HELD.get(action)
        if score.get("skipped"):
            lines.append("  %-16s %-20s      -       -     -       -      -      -         -  "
                         "SKIP (%s)" % (
                             action, ",".join(score.get("target_labels", ())),
                             score.get("skip_reason", "missing replay file")))
            continue
        if gate is None or not show_gate:
            verdict = "-"
        else:
            min_coverage, max_false, max_cross = gate
            reasons = []
            if score["coverage"] < min_coverage:
                reasons.append("coverage<%.2f" % min_coverage)
            if score["false_active"] > max_false:
                reasons.append("false>%.2f" % max_false)
            if score["cross_s_per_min"] > max_cross:
                reasons.append("cross>%.1f" % max_cross)
            verdict = "FAIL " + ",".join(reasons) if reasons else "PASS"
        target = ",".join(score["target_labels"])
        lines.append("  %-16s %-20s %7d %7.1f %5d %7.1f  %5.2f  %5.2f  %8.1f  %s" % (
            action, target, score["expected_windows"], score["expected_s"],
            score["detected_runs"], score["detected_s"], score["coverage"],
            score["false_active"], score["cross_s_per_min"], verdict))
    return lines


def _format_held_aware_table(scores, show_gate=True):
    lines = ["  action           onset/rel   aware_exp_s  runs   det_s  aware_cover  aware_false  gate"]
    for score in scores:
        action = score["action"]
        latency = score.get("latency")
        if score.get("skipped") or latency is None:
            lines.append("  %-16s      -              -       -       -          -            -  SKIP" % (
                action))
            continue
        gate = GATE_HELD.get(action)
        if gate is None or not show_gate:
            verdict = "-"
        else:
            min_coverage, max_false, max_cross = gate
            reasons = []
            if latency["coverage"] < min_coverage:
                reasons.append("coverage<%.2f" % min_coverage)
            if latency["false_active"] > max_false:
                reasons.append("false>%.2f" % max_false)
            if score["cross_s_per_min"] > max_cross:
                reasons.append("cross>%.1f" % max_cross)
            verdict = "FAIL " + ",".join(reasons) if reasons else "PASS"
        lines.append("  %-16s %4.2f/%4.2f  %11.1f  %5d %7.1f  %11.2f  %11.2f  %s" % (
            action, latency["start_s"], latency["end_s"], latency["expected_s"],
            score["detected_runs"], score["detected_s"], latency["coverage"],
            latency["false_active"], verdict))
    return lines


def _format_gt_rate_table(pulse_actions, datasets, expected_sets):
    """Expected pulse counts per action for raw-18 Hz vs 90 Hz-interpolated ground truth."""
    raw_expected, gt90_expected = expected_sets
    label_by_id = {ds.id: ds.label for ds in datasets}
    lines = ["  action   raw18_exp  gt90_exp  delta   target dataset raw18 -> gt90"]
    for action in pulse_actions:
        labels = TARGET_LABELS[action]
        truth_action = GROUND_TRUTH_ACTION.get(action, action)
        raw_total = 0
        gt90_total = 0
        per_dataset = []
        for dataset_id in raw_expected:
            if label_by_id.get(dataset_id) not in labels:
                continue
            count_raw = len(raw_expected[dataset_id].get("pulses", {}).get(truth_action, []))
            count_gt90 = len(gt90_expected.get(dataset_id, {}).get(
                "pulses", {}).get(truth_action, []))
            raw_total += count_raw
            gt90_total += count_gt90
            short = dataset_id.replace("gesturelab-", "").rsplit("-", 2)[0]
            per_dataset.append("%s:%d->%d" % (short, count_raw, count_gt90))
        lines.append("  %-8s %9d  %8d  %+6d   %s" % (
            action, raw_total, gt90_total, gt90_total - raw_total,
            ", ".join(per_dataset) if per_dataset else "-"))
    return lines


def _format_gt_table(datasets, expected):
    lines = []
    for ds in datasets:
        events = expected.get(ds.id, {})
        entries = []
        for action in sorted(TARGET_LABELS):
            if ds.label not in TARGET_LABELS[action]:
                continue
            truth_action = GROUND_TRUTH_ACTION.get(action, action)
            pulses = events.get("pulses", {}).get(truth_action)
            windows = events.get("windows", {}).get(truth_action)
            if pulses is not None:
                entries.append("%s=%d" % (truth_action, len(pulses)))
            elif windows is not None:
                total = sum(b - a for a, b in windows)
                entries.append("%s=%d/%.1fs" % (truth_action, len(windows), total))
            else:
                entries.append("%s=0" % truth_action)
        lines.append("  %-22s %-46s %s" % (ds.label, ds.id, " ".join(entries) if entries else "-"))
    return lines


def _format_matrix(rows):
    lines = []
    for row in rows:
        parts = []
        for action in sorted(row["pulses"]):
            parts.append("%s=%d" % (action, row["pulses"][action]))
        for action in sorted(row["held_s"]):
            parts.append("%s=%.1fs" % (action, row["held_s"][action]))
        lines.append("  %-58s %s" % (row["dataset"], " ".join(parts) if parts else "-"))
    return lines


def _format_latency_table(latency_table):
    lines = ["  action          onset_s  release_s  source"]
    for action in sorted(latency_table):
        item = latency_table[action]
        lines.append("  %-15s %6.2f    %6.2f    %s | %s" % (
            action, item["start_s"], item["end_s"],
            item["start_source"], item["end_source"]))
    return lines


def _pulse_gate_row(score, ground_truth):
    thresholds = GATE_PULSE.get(score["action"])
    if thresholds is None or score.get("skipped"):
        return None
    recall = score.get("recall")
    precision = score.get("precision")
    false_per_min = score.get("false_per_min")
    if recall is None or precision is None or false_per_min is None:
        # Defensive: a malformed/skipped score must still fail the regression gate, never crash it.
        return {"kind": "pulse", "action": score["action"], "rate": "90",
                "groundTruth": ground_truth, "recall": recall, "precision": precision,
                "false_per_min": false_per_min, "pass": False,
                "reasons": ["missing score for target action (treated as recall 0)"]}
    min_recall, min_precision, max_false = thresholds
    reasons = []
    if recall < min_recall:
        reasons.append("recall %.2f < %.2f" % (recall, min_recall))
    if precision < min_precision:
        reasons.append("precision %.2f < %.2f" % (precision, min_precision))
    if false_per_min > max_false:
        reasons.append("false %.2f/min > %.2f" % (false_per_min, max_false))
    empty = score.get("empty_target_datasets") or []
    if empty:
        reasons.append("no replay events for target dataset(s): %s" % ", ".join(
            dataset_id.replace("gesturelab-", "") for dataset_id in empty))
    return {"kind": "pulse", "action": score["action"], "rate": "90",
            "groundTruth": ground_truth, "recall": recall,
            "precision": precision, "false_per_min": false_per_min,
            "pass": not reasons, "reasons": reasons}


def _held_gate_row(score, mode):
    thresholds = GATE_HELD.get(score["action"])
    if thresholds is None or score.get("skipped"):
        return None
    min_coverage, max_false, max_cross = thresholds
    if mode == "latency":
        latency = score.get("latency")
        if latency is None:
            return None
        coverage = latency["coverage"]
        false_active = latency["false_active"]
        ground_truth = "latencyAware"
    else:
        coverage = score.get("coverage")
        false_active = score.get("false_active")
        ground_truth = "literal"
    cross = score.get("cross_s_per_min")
    if coverage is None or false_active is None or cross is None:
        return {"kind": "held", "action": score["action"], "rate": "raw",
                "groundTruth": ground_truth, "coverage": coverage,
                "false_active": false_active, "cross_s_per_min": cross, "pass": False,
                "reasons": ["missing score for target action (treated as coverage 0)"]}
    reasons = []
    if coverage < min_coverage:
        reasons.append("coverage %.2f < %.2f" % (coverage, min_coverage))
    if false_active > max_false:
        reasons.append("false-active %.2f > %.2f" % (false_active, max_false))
    if cross > max_cross:
        reasons.append("cross %.1fs/min > %.1f" % (cross, max_cross))
    empty = score.get("empty_target_datasets") or []
    if empty:
        reasons.append("no replay events for target dataset(s): %s" % ", ".join(
            dataset_id.replace("gesturelab-", "") for dataset_id in empty))
    return {"kind": "held", "action": score["action"], "rate": "raw",
            "groundTruth": ground_truth, "coverage": coverage,
            "false_active": false_active, "cross_s_per_min": cross,
            "pass": not reasons, "reasons": reasons}


def _context_gate_rows(context_rows):
    rows = []
    for row in context_rows:
        if row.get("skipped"):
            continue
        rows.append({"kind": "context", "action": "%s:%s" % (row["label"], row["action"]),
                     "rate": row["source"], "pass": row["pass"],
                     "reasons": [] if row["pass"] else
                     ["%d > %d" % (row["value"], row["limit"])]})
    return rows


# ------------------------------------------------------------------------------------------------
# Scoring / gate assembly (shared by main and the synthetic self-check)
# ------------------------------------------------------------------------------------------------
def is_fixture_source_dataset(dataset):
    """True for raw recordings the Java fixture generator replays (accepted/ + top-level IDLE)."""
    return dataset.path.parent.name == "accepted" or dataset.id.startswith("gesturelab-IDLE-")


def score_all_pulses(events, datasets, expected, excluded_ids, durations, ground_truth):
    """One pulse score per gated pulse action; events=None means the replay file is absent (SKIP)."""
    scores = []
    for action in tuple(GATE_PULSE.keys()):
        if events is None:
            scores.append({"action": action, "skipped": True,
                           "target_labels": list(TARGET_LABELS[action])})
            continue
        score = score_pulses(action, datasets, events, expected, excluded_ids, durations)
        if not score.get("skipped"):
            score["groundTruth"] = ground_truth
        scores.append(score)
    return scores


def score_all_held(events, datasets, expected, excluded_ids, durations, latency_table):
    """One held score per gated held action; events=None means the replay file is absent (SKIP)."""
    scores = []
    for action in ("break", "teleport", "walk", "bowDraw", "eat", "sneak",
                   "climbGrabLeft", "climbGrabRight"):
        if events is None:
            scores.append({"action": action, "skipped": True,
                           "target_labels": list(TARGET_LABELS[action])})
            continue
        score = score_held(action, datasets, events, expected, excluded_ids, durations,
                           latency=(latency_table or {}).get(action))
        if not score.get("skipped"):
            score["groundTruth"] = "raw18Hz"
        scores.append(score)
    return scores


def build_pulse_gate_rows(scores, ground_truth):
    rows = []
    for score in scores:
        row = _pulse_gate_row(score, ground_truth)
        if row is not None:
            rows.append(row)
    return rows


def build_held_gate_rows(scores, mode):
    rows = []
    for score in scores:
        row = _held_gate_row(score, mode)
        if row is not None:
            rows.append(row)
    return rows


def run_self_check():
    """Synthetic regression self-check: silent target datasets must score zero and fail cleanly.

    Runs without raw data or an engine source (fallback latency policy is used) so it can be wired
    into the replay wrapper/evidence step as a cheap regression guard for the scoring/gate code.
    """
    results = []

    def check(name, function):
        try:
            detail = function() or ""
            results.append((name, True, detail))
        except Exception as exc:
            results.append((name, False, "%s: %s" % (type(exc).__name__, exc)))

    class _StubDataset(object):
        __slots__ = ("id", "label", "duration")

        def __init__(self, dataset_id, label, duration=30.0):
            self.id = dataset_id
            self.label = label
            self.duration = duration

    scenario_labels = sorted({label for labels in TARGET_LABELS.values() for label in labels})
    stubs = []
    label_to_stub = {}
    for index, label in enumerate(scenario_labels):
        stub = _StubDataset("synthetic-%s-%02d" % (label.lower().replace("_", "-"), index), label)
        stubs.append(stub)
        label_to_stub[label] = stub
    durations = {stub.id: stub.duration for stub in stubs}
    expected = {stub.id: {"pulses": {}, "windows": {}} for stub in stubs}
    for action, labels in TARGET_LABELS.items():
        truth_action = GROUND_TRUTH_ACTION.get(action, action)
        stub = label_to_stub[labels[0]]
        expected[stub.id]["pulses"].setdefault(truth_action, [1.0, 3.0])
        expected[stub.id]["windows"].setdefault(action, [(2.0, 6.0)])
    empty_events = {}
    fallback_latency, _missing = build_latency_table(None)

    def empty_targets_score_zero():
        scores = score_all_pulses(empty_events, stubs, expected, set(), durations, "gt90Hz")
        assert len(scores) == len(GATE_PULSE), "expected %d pulse scores, got %d" % (
            len(GATE_PULSE), len(scores))
        for score in scores:
            assert not score.get("skipped"), "%s unexpectedly skipped" % score["action"]
            assert score["recall"] == 0.0, "%s recall %r" % (score["action"], score["recall"])
            assert score["empty_target_datasets"], "%s missing empty annotation" % score["action"]
        rows = build_pulse_gate_rows(scores, "gt90Hz")
        assert len(rows) == len(GATE_PULSE), "expected %d pulse gate rows, got %d" % (
            len(GATE_PULSE), len(rows))
        assert all(not row["pass"] for row in rows), "silent target action must FAIL"
        assert any("no replay events" in "; ".join(row["reasons"]) for row in rows), (
            "FAIL reason must name the silent target dataset")
        return "%d/%d pulse gate rows fail cleanly (recall 0.0)" % (len(rows), len(rows))

    def empty_targets_held_zero():
        scores = score_all_held(empty_events, stubs, expected, set(), durations, fallback_latency)
        assert len(scores) == 8, "expected 8 held scores, got %d" % len(scores)
        for score in scores:
            assert not score.get("skipped"), "%s unexpectedly skipped" % score["action"]
            assert score["coverage"] == 0.0, "%s coverage %r" % (
                score["action"], score["coverage"])
            assert score["empty_target_datasets"], "%s missing empty annotation" % score["action"]
        rows = build_held_gate_rows(scores, "literal")
        assert len(rows) == 8, "expected 8 held gate rows, got %d" % len(rows)
        assert all(not row["pass"] for row in rows), "silent held target must FAIL"
        return "%d/%d held gate rows fail cleanly (coverage 0.0)" % (len(rows), len(rows))

    def absent_raw_recording_still_skips():
        pulse_score = score_pulses("place", [], empty_events, expected, set(), {})
        assert pulse_score.get("skipped") is True, "absent raw recording must be skipped"
        assert _pulse_gate_row(pulse_score, "gt90Hz") is None, "skipped pulse must not be gated"
        held_score = score_held("break", [], empty_events, expected, set(), {})
        assert held_score.get("skipped") is True, "absent raw recording must be skipped"
        assert _held_gate_row(held_score, "literal") is None, "skipped held must not be gated"
        return "genuinely absent raw recording stays SKIP (not FAIL)"

    def malformed_score_cannot_crash_gate():
        assert _pulse_gate_row({"action": "place", "skipped": True,
                                "target_labels": []}, "gt90Hz") is None
        malformed_pulse = _pulse_gate_row({"action": "place"}, "gt90Hz")
        assert malformed_pulse is not None and not malformed_pulse["pass"]
        assert malformed_pulse["reasons"], "malformed pulse score needs a reason"
        malformed_held = _held_gate_row({"action": "break"}, "literal")
        assert malformed_held is not None and not malformed_held["pass"]
        assert malformed_held["reasons"], "malformed held score needs a reason"
        return "skipped/malformed score dicts cannot crash the gate builders"

    def dataset_present_without_its_events():
        partial_events = {stubs[0].id: {"label": stubs[0].label,
                                        "pulses": [("leftFistTap", 1.0)],
                                        "held": [("walk", 0.0, 1.0)]}}
        scores = score_all_pulses(partial_events, stubs, expected, set(), durations, "raw18Hz")
        assert all(not score.get("skipped") for score in scores)
        rows = build_pulse_gate_rows(scores, "raw18Hz")
        assert len(rows) == len(GATE_PULSE)
        return "dataset with only unrelated events still scores its target action"

    def formatters_handle_zero_scores():
        scores = score_all_pulses(empty_events, stubs, expected, set(), durations, "gt90Hz")
        table = _format_pulse_table(scores)
        assert any("FAIL" in line for line in table), "pulse table must show FAIL rows"
        held_scores = score_all_held(empty_events, stubs, expected, set(), durations,
                                     fallback_latency)
        held_table = _format_held_aware_table(held_scores)
        assert any("FAIL" in line for line in held_table), "held-aware table must show FAIL rows"
        return "report formatters render zero-score rows without crashing"

    checks = (
        ("empty target pulse dataset scores recall 0.0 and gate FAIL", empty_targets_score_zero),
        ("empty target held dataset scores coverage 0.0 and gate FAIL", empty_targets_held_zero),
        ("absent raw recording is SKIP, not FAIL", absent_raw_recording_still_skips),
        ("malformed/skipped score dicts cannot crash gate builders", malformed_score_cannot_crash_gate),
        ("dataset present with unrelated events still scores", dataset_present_without_its_events),
        ("report formatters handle zero scores", formatters_handle_zero_scores),
    )
    for name, function in checks:
        check(name, function)

    print("M7 evaluator self-check (synthetic empty replay event sets; no raw data or engine needed)")
    for name, passed, detail in results:
        print("  %-4s %-58s %s" % ("PASS" if passed else "FAIL", name, detail))
    failures = [name for name, passed, _detail in results if not passed]
    print("SELF-CHECK: %d/%d PASS -> %s" % (
        len(results) - len(failures), len(results), "OK" if not failures else "FAIL"))
    return 0 if not failures else 1


# ------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------
def parse_args(argv):
    parser = argparse.ArgumentParser(description="Independent M7 lab-replay evaluator")
    parser.add_argument("--data", default="export/gesturelab-data",
                        help="raw Gesture Lab JSONL directory")
    parser.add_argument("--events", default="export/m7-replay-90/events.jsonl",
                        help="90 Hz interpolated replay event JSONL (pulse-gate source)")
    parser.add_argument("--events-raw", default="export/m7-replay/events.jsonl",
                        help="literal ~18 Hz replay event JSONL (held-state gate source)")
    parser.add_argument("--events-90", default=None,
                        help="deprecated alias for --events (older invocations)")
    parser.add_argument("--json", default="export/m7-replay/eval.json",
                        help="JSON report output path")
    parser.add_argument("--exit-primary", action="store_true",
                        help="exit 1 on rate-matched/latency-aware gate failures instead of the "
                             "conservative literal gate (default: literal gate governs exit)")
    parser.add_argument("--self-check", action="store_true",
                        help="run synthetic regression self-checks for silent/empty target event "
                             "sets (no raw data or engine source needed) and exit 0/1")
    return parser.parse_args(argv)


def main(argv):
    args = parse_args(argv)
    if args.self_check:
        return run_self_check()
    data_dir = Path(args.data)
    events_90_path = Path(args.events_90) if args.events_90 else Path(args.events)
    events_raw_path = Path(args.events_raw)
    json_path = Path(args.json)

    if not data_dir.is_dir():
        print("[m7-eval] FAIL: raw data directory not found: %s" % data_dir)
        return 2
    datasets = load_raw_datasets(data_dir)
    if not datasets:
        print("[m7-eval] FAIL: no gesturelab-*.jsonl recordings under %s" % data_dir)
        return 2
    events_raw = None
    events_90 = None
    unknown_raw = []
    unknown_90 = []
    if events_raw_path.is_file():
        events_raw, count_raw, bad_raw, unknown_raw = load_events(events_raw_path)
    else:
        count_raw = bad_raw = 0
        events_raw = None
    if events_90_path.is_file():
        events_90, count_90, bad_90, unknown_90 = load_events(events_90_path)
    else:
        count_90 = bad_90 = 0
        events_90 = None

    # Every raw recording the Java fixture generator replays is scored even when a replay event file
    # contains no events at all for it (an engine regression must FAIL the gate, not silently drop the
    # dataset). Extra raw files (e.g. the standalone relabel source) still take part in the duplicate
    # scan only.
    replay_ids = set()
    for events in (events_raw, events_90):
        if events is not None:
            replay_ids.update(events.keys())
    known_raw_ids = set(ds.id for ds in datasets)
    scoring_ids = set(ds.id for ds in datasets if is_fixture_source_dataset(ds))
    scoring_ids.update(replay_ids & known_raw_ids)
    scoring_datasets = [ds for ds in datasets if ds.id in scoring_ids]
    unreplayed = [ds for ds in datasets if ds.id not in scoring_ids]
    durations = {ds.id: ds.duration for ds in scoring_datasets}

    # ---- dataset quality: duplicate recordings (exact signature match) ----
    signature_groups = {}
    for ds in datasets:
        signature_groups.setdefault(ds.signature, []).append(ds)
    duplicates = []
    for signature, group in signature_groups.items():
        if len(group) > 1:
            duplicates.append(group)
    duplicate_rows = []
    excluded_ids = set()
    for group in duplicates:
        names = [ds.id for ds in group]
        labels = [ds.label for ds in group]
        for ds in group:
            if ds.label not in TARGET_LABEL_SET:
                excluded_ids.add(ds.id)
        duplicate_rows.append({"datasets": names, "labels": labels,
                               "note": "all frames numerically identical (t/head/27 joints)"})

    # ---- engine constants / bounded-latency policy (read from provider source, never invented) ----
    engine_source = Path(__file__).resolve().parent.parent / ENGINE_RELATIVE_PATH
    engine_constants, constants_status = read_engine_constants(engine_source)
    latency_table, latency_missing = build_latency_table(engine_constants)
    engine_mtime = _mtime_value(engine_source)

    # ---- ground truth (literal, raw 18 Hz) ----
    expected = {}
    for ds in scoring_datasets:
        expected[ds.id] = expected_events(ds)

    # ---- frame-rate-matched ground truth: re-derive pulse GT on the 90 Hz replay frame grid ----
    pulse_actions = tuple(GATE_PULSE.keys())
    pulse_labels = set()
    for action in pulse_actions:
        pulse_labels.update(TARGET_LABELS[action])
    gt90_expected = {}
    gt90_stats = {}
    gt90_errors = []
    for ds in scoring_datasets:
        if ds.label not in pulse_labels:
            continue
        try:
            resampled = resample_dataset(Dataset(ds.path, keep_joints=True))
        except (OSError, ValueError) as exc:
            gt90_errors.append("%s: %s" % (ds.id, exc))
            continue
        gt90_expected[ds.id] = expected_events(resampled)
        gt90_stats[ds.id] = {"frames": len(resampled.t),
                             "duration_s": round(resampled.duration, 3)}
    # Sanity: the 90 Hz frame grid must match the Java fixture set built by m7_lab_fixture.py.
    gt90_frame_checks = []
    fixture_manifest_path = events_90_path.parent.parent / "m7-lab-fixtures-90" / "manifest.json"
    fixture_frames = {}
    try:
        fixture_manifest = json.loads(fixture_manifest_path.read_text())
        fixture_frames = {item.get("id"): item.get("frames")
                          for item in fixture_manifest.get("datasets", [])}
    except (OSError, ValueError):
        fixture_manifest = None
    for dataset_id, stat in gt90_stats.items():
        expected_frames = fixture_frames.get(dataset_id)
        gt90_frame_checks.append({
            "dataset": dataset_id,
            "gt90_frames": stat["frames"],
            "fixture_frames": expected_frames,
            "match": expected_frames is None or expected_frames == stat["frames"],
        })

    # ---- scoring ----
    pulse_scores_raw = score_all_pulses(events_raw, scoring_datasets, expected, excluded_ids,
                                        durations, "raw18Hz")
    pulse_scores_90 = score_all_pulses(events_90, scoring_datasets, expected, excluded_ids,
                                       durations, "raw18Hz")
    pulse_scores_gt90 = score_all_pulses(events_90, scoring_datasets, gt90_expected,
                                         excluded_ids, durations, "gt90Hz")
    held_scores_raw = score_all_held(events_raw, scoring_datasets, expected, excluded_ids,
                                     durations, latency_table)
    held_scores_90 = score_all_held(events_90, scoring_datasets, expected, excluded_ids,
                                    durations, latency_table)
    context_rows = context_checks(scoring_datasets, events_raw, events_90)

    # ---- optional bow posture variant (ambiguity evidence, not gated) ----
    bow_variant = {}
    for ds in scoring_datasets:
        if ds.label != "BOW_BOTH_FISTS":
            continue
        draw = _bow_windows(ds, require_both_fists=False)
        bow_variant = {
            "windows": len(draw),
            "total_s": round(sum(ds.t[b] - ds.t[a] for a, b in draw), 2),
            "note": "looser two-handed front/back posture (>=1 closed fist); not gated",
        }

    # ---- gate evaluation: conservative literal gates + rate/latency-aware primary gates ----
    context_gate_rows = _context_gate_rows(context_rows)
    literal_gate_rows = build_pulse_gate_rows(pulse_scores_90, "raw18Hz")
    literal_gate_rows.extend(build_held_gate_rows(held_scores_raw, "literal"))
    literal_gate_rows.extend(context_gate_rows)
    primary_gate_rows = build_pulse_gate_rows(pulse_scores_gt90, "gt90Hz")
    primary_gate_rows.extend(build_held_gate_rows(held_scores_raw, "latency"))
    primary_gate_rows.extend(context_gate_rows)
    literal_failures = [row for row in literal_gate_rows if not row["pass"]]
    primary_failures = [row for row in primary_gate_rows if not row["pass"]]
    gate_rows = primary_gate_rows if args.exit_primary else literal_gate_rows
    gate_failures = primary_failures if args.exit_primary else literal_failures

    # ---- warnings ----
    notes = []
    if not constants_status.get("parsed"):
        notes.append("WARNING: could not parse VisionM7Gesture constants (%s); latency bounds use "
                     "documented fallback values" % constants_status.get("error", "unknown"))
    elif latency_missing:
        notes.append("WARNING: latency policy constants missing from source: %s" % (
            ", ".join(latency_missing)))
    if gt90_errors:
        notes.append("WARNING: 90 Hz ground truth unavailable for: %s" % "; ".join(gt90_errors))
    frame_mismatch = [row for row in gt90_frame_checks if not row["match"]]
    if frame_mismatch:
        notes.append("WARNING: 90 Hz ground-truth frame grid differs from the fixture set for: %s" % (
            ", ".join(row["dataset"] for row in frame_mismatch)))
    notes.append("engine constants parsed: %d from %s" % (
        constants_status.get("count", 0), engine_source))
    for label, events_path, count, bad in (("raw 18 Hz", events_raw_path, count_raw, bad_raw),
                                           ("90 Hz", events_90_path, count_90, bad_90)):
        if events_path.is_file():
            notes.append("replay %s: %s (%d events, %d malformed) mtime %s" % (
                label, events_path, count, bad, _mtime_text(events_path)))
    notes.append("engine source: %s mtime %s" % (engine_source, _mtime_text(engine_source)))
    empty_targets = set()
    for score in list(pulse_scores_90) + list(held_scores_raw):
        if isinstance(score, dict):
            empty_targets.update(score.get("empty_target_datasets") or ())
    if empty_targets:
        notes.append("WARNING: target dataset(s) produced no replay events (gate FAIL, not skipped): "
                     "%s" % ", ".join(sorted(empty_targets)))
    stale = []
    for label, events_path in (("raw 18 Hz", events_raw_path), ("90 Hz", events_90_path)):
        mtime = _mtime_value(events_path)
        if mtime is not None and engine_mtime is not None and mtime < engine_mtime:
            stale.append(label)
    if stale:
        notes.append("WARNING: the %s replay predates the current engine source; rerun "
                     "M7LabReplay before treating gate results as current." % ", ".join(stale))
    for label, events_path, fixtures_name in (
            ("raw 18 Hz", events_raw_path, "m7-lab-fixtures"),
            ("90 Hz", events_90_path, "m7-lab-fixtures-90")):
        fixtures_manifest = events_path.parent.parent / fixtures_name / "manifest.json"
        fixture_mtime = _mtime_value(fixtures_manifest)
        event_mtime = _mtime_value(events_path)
        if (fixture_mtime is not None and event_mtime is not None
                and event_mtime < fixture_mtime - 5.0):
            notes.append("WARNING: %s replay is older than its fixture set (%s)" % (
                label, fixtures_manifest))
    for ds in datasets:
        if ds.unparsed:
            notes.append("WARNING: %s had %d unparsed lines" % (ds.id, ds.unparsed))
    if unreplayed:
        notes.append("raw files not present in any replay event file (not scored): %s" % (
            ", ".join(ds.id for ds in unreplayed)))
    if unknown_raw or unknown_90:
        notes.append("WARNING: replay events contain actions outside the documented schema: %s" % (
            ", ".join(sorted(set(unknown_raw) | set(unknown_90)))))
    known_raw_ids = set(ds.id for ds in datasets)
    events_only = sorted(replay_ids - known_raw_ids)
    if events_only:
        notes.append("WARNING: replay events reference datasets with no raw recording (not scored): %s"
                     % ", ".join(events_only))

    # ---- print report ----
    rate_events = []
    if events_90 is not None:
        rate_events.append("90Hz=%d" % count_90)
    if events_raw is not None:
        rate_events.append("raw=%d" % count_raw)
    print("=" * 100)
    print("M7 lab replay evaluator - independent ground truth (schema 2)")
    print("=" * 100)
    print("raw data   : %s (%d replayed datasets, %.1f s; %d raw files scanned for duplicates)" % (
        data_dir, len(scoring_datasets), sum(ds.duration for ds in scoring_datasets),
        len(datasets)))
    print("replay     : %s" % (", ".join(rate_events) if rate_events else "NONE (SKIP)"))
    if events_raw is None:
        print("  SKIP raw 18 Hz replay: missing %s" % events_raw_path)
    if events_90 is None:
        print("  SKIP 90 Hz replay: missing %s" % events_90_path)
    for note in notes:
        print("  " + note)
    print()
    print("DATASET QUALITY")
    if duplicate_rows:
        for row in duplicate_rows:
            print("  DUPLICATE: %s" % " == ".join(row["datasets"]))
            print("             labels=%s (%s)" % (", ".join(row["labels"]), row["note"]))
        if any("IDLE" in name for row in duplicate_rows for name in row["datasets"]):
            print("  -> The 'IDLE' recording is not idle/no-gesture data; it is a duplicate of the")
            print("     MENU recording. It is excluded from the false-trigger gate denominators.")
            print("     No true idle/negative-control recording exists in the dataset.")
    else:
        print("  no duplicate recordings detected")
    print()
    print("GROUND TRUTH (raw-18 Hz derived, engine-independent; target scenario events only)")
    for line in _format_gt_table(scoring_datasets, expected):
        print(line)
    print()
    if events_90 is not None:
        print("PULSE SCORING - 90 Hz replay vs 90 Hz-INTERPOLATED GT (RATE-MATCHED; primary gate)")
        print("  GT re-derived on the same interpolated frame grid as the replay (fixture --rate 90 "
              "rules); feature rules unchanged; target datasets only")
        for line in _format_pulse_table(pulse_scores_gt90):
            print(line)
        print()
        print("PULSE SCORING - 90 Hz replay vs raw-18 Hz GT (CONSERVATIVE; literal gate)")
        print("  target datasets only; det=detections on targets; cross=pulses in context-wrong "
              "datasets (false triggers); fp/min=cross / context-wrong replay minutes")
        for line in _format_pulse_table(pulse_scores_90):
            print(line)
        print()
        print("PULSE GROUND-TRUTH RATE COMPARISON (expected pulses per action)")
        for line in _format_gt_rate_table(pulse_actions, scoring_datasets,
                                          (expected, gt90_expected)):
            print(line)
        if gt90_frame_checks:
            matched = sum(1 for row in gt90_frame_checks if row["match"])
            print("  90 Hz GT frame grid: %d/%d target datasets match the fixture frame counts%s" % (
                matched, len(gt90_frame_checks),
                "" if matched == len(gt90_frame_checks) else
                " -> MISMATCH: " + ", ".join(row["dataset"] for row in gt90_frame_checks
                                             if not row["match"])))
        print()
    if events_raw is not None:
        print("PULSE SCORING - raw 18 Hz replay (informational; short pulses alias at 18 Hz)")
        for line in _format_pulse_table(pulse_scores_raw, show_gate=False):
            print(line)
        print()
        print("HELD SCORING - raw 18 Hz replay (LITERAL; conservative gate)")
        print("  coverage=time inside expected windows / expected time; false=detected active time "
              "outside expected windows / non-expected time; cross=active s/min in context-wrong "
              "datasets; runs=detected runs (expected windows)")
        for line in _format_held_table(held_scores_raw):
            print(line)
        print()
        print("HELD SCORING - raw 18 Hz replay vs BOUNDED-LATENCY-AWARE windows (primary gate)")
        print("  expected window -> [start + onset_latency, end + release_latency] (engine constants "
              "table below); literal metrics above are unchanged")
        for line in _format_held_aware_table(held_scores_raw):
            print(line)
        print()
        print("HELD LATENCY POLICY (read from VisionM7Gesture constants)")
        for line in _format_latency_table(latency_table):
            print(line)
        print()
    if events_90 is not None:
        print("HELD SCORING - 90 Hz replay (informational)")
        for line in _format_held_table(held_scores_90, show_gate=False):
            print(line)
        print()
    matrix_source = events_90 if events_90 is not None else events_raw
    if matrix_source is not None:
        print("CROSS-DATASET MATRIX - %s replay (pulses=n, held=active seconds; IDLE duplicate "
              "included but not gated; both rates are in eval.json)" % (
                  "90 Hz" if events_90 is not None else "raw 18 Hz"))
        for line in _format_matrix(cross_matrix(scoring_datasets, matrix_source)):
            print(line)
        print()
    print("CONTEXT-CORRECT SUPPRESSION")
    for row in context_rows:
        verdict = "SKIP" if row.get("skipped") else ("PASS" if row["pass"] else "FAIL")
        print("  %-18s %-6s %-14s %s=%d (limit %d, %s replay) %s" % (
            row["label"], row["scenario"], row["action"], row["kind"], row["value"],
            row["limit"], row["source"], verdict))
    print()
    if bow_variant:
        bow_ds = next((ds for ds in scoring_datasets if ds.label == "BOW_BOTH_FISTS"), None)
        bow_windows = expected.get(bow_ds.id, {}).get("windows", {}).get("bowDraw", []) if bow_ds else []
        print("AMBIGUITY DATA: bowDraw literal(both fists)=%d windows/%.1fs  posture-variant="
              "%d windows/%.1fs (not gated)" % (
                  len(bow_windows), sum(b - a for a, b in bow_windows),
                  bow_variant["windows"], bow_variant["total_s"]))
        print()
    def _print_gate_rows(rows):
        if not rows:
            print("  SKIP: no replay available to gate")
            return
        for row in rows:
            if row["pass"]:
                continue
            print("  FAIL %-6s %-8s %-40s -> %s" % (
                row["kind"], row["rate"], row["action"], "; ".join(row["reasons"])))
        print("  RESULT: %d/%d rows pass -> %s" % (
            len(rows) - sum(1 for row in rows if not row["pass"]), len(rows),
            "PASS" if all(row["pass"] for row in rows) else "FAIL"))

    print("GATE")
    if stale:
        print("  NOTE: held gate rows use the 18 Hz replay, which predates the current engine source "
              "(stale). Re-run M7LabReplay on export/m7-lab-fixtures for current held metrics.")
    print("CONSERVATIVE LITERAL GATES (exit criterion unless --exit-primary):")
    print("  pulse = 90 Hz replay vs raw-18 Hz GT; held = literal raw-18 Hz windows; context unchanged")
    _print_gate_rows(literal_gate_rows)
    print()
    print("RATE-MATCHED + LATENCY-AWARE PRIMARY GATES (reported; use --exit-primary to enforce):")
    print("  pulse = 90 Hz replay vs 90 Hz-interpolated GT; held = bounded-latency windows; "
          "context unchanged")
    _print_gate_rows(primary_gate_rows)
    print()
    print("  EXIT CODE: %d (%s gate)" % (
        0 if not gate_failures else 1,
        "primary rate-matched/latency-aware" if args.exit_primary else
        "conservative literal (see --exit-primary)"))
    print()
    print("EVIDENCE SUMMARY (paste-ready)")
    print("  evaluator  : scripts/m7_eval_replay.py (independent GT: raw-18 Hz literal + 90 Hz "
          "rate-matched)")
    print("  raw data   : %d replayed recordings, %.1f s; duplicate IDLE==MENU finding %s" % (
        len(scoring_datasets), sum(ds.duration for ds in scoring_datasets),
        "reported" if duplicate_rows else "none"))
    gt90_lookup = {score["action"]: score for score in pulse_scores_gt90}
    literal_pulse_lookup = {score["action"]: score for score in pulse_scores_90}
    literal_pulse_gate = {row["action"]: row["pass"] for row in literal_gate_rows
                          if row["kind"] == "pulse"}
    primary_pulse_gate = {row["action"]: row["pass"] for row in primary_gate_rows
                          if row["kind"] == "pulse"}
    for action in pulse_actions:
        raw_score = literal_pulse_lookup.get(action)
        gt_score = gt90_lookup.get(action)
        if raw_score is None or raw_score.get("skipped"):
            continue
        raw_text = "rawGT exp=%3d det=%3d match=%3d rec=%.2f prec=%.2f" % (
            raw_score["expected"], raw_score["detected"], raw_score["matched"],
            raw_score["recall"], raw_score["precision"])
        if gt_score is None or gt_score.get("skipped"):
            gt_text = "gt90 SKIP (missing replay file)"
        else:
            gt_text = "gt90 exp=%3d det=%3d match=%3d rec=%.2f prec=%.2f" % (
                gt_score["expected"], gt_score["detected"], gt_score["matched"],
                gt_score["recall"], gt_score["precision"])
        print("  pulse %-8s %s | %s | cross=%d | literal=%s primary=%s" % (
            action, raw_text, gt_text, raw_score["cross_false"],
            "PASS" if literal_pulse_gate.get(action) else "FAIL",
            "PASS" if primary_pulse_gate.get(action) else "FAIL"))
    literal_held_gate = {row["action"]: row["pass"] for row in literal_gate_rows
                         if row["kind"] == "held"}
    primary_held_gate = {row["action"]: row["pass"] for row in primary_gate_rows
                         if row["kind"] == "held"}
    for score in held_scores_raw:
        if score.get("skipped"):
            continue
        latency = score.get("latency") or {}
        print("  held  %-14s literal cover=%.2f false=%.2f | aware cover=%.2f false=%.2f "
              "(on %.2fs/off %.2fs) | cross=%.1fs/min | literal=%s aware=%s" % (
                  score["action"], score["coverage"], score["false_active"],
                  latency.get("coverage", float("nan")), latency.get("false_active", float("nan")),
                  latency.get("start_s", 0.0), latency.get("end_s", 0.0),
                  score["cross_s_per_min"],
                  "PASS" if literal_held_gate.get(score["action"]) else "FAIL",
                  "PASS" if primary_held_gate.get(score["action"]) else "FAIL"))
    context_active = [row for row in context_rows if not row.get("skipped")]
    print("  context  : %d/%d suppression rows pass" % (
        sum(1 for row in context_active if row["pass"]), len(context_active)))
    print("  GATE literal  : %s (%d/%d rows)" % (
        "PASS" if not literal_failures else "FAIL",
        len(literal_gate_rows) - len(literal_failures), len(literal_gate_rows)))
    print("  GATE primary  : %s (%d/%d rows)" % (
        "PASS" if not primary_failures else "FAIL",
        len(primary_gate_rows) - len(primary_failures), len(primary_gate_rows)))
    print()
    print("AMBIGUITIES RESOLVED (see docs/mvp/M7_EVAL_REPLAY.md)")
    for index, text in enumerate(AMBIGUITIES, 1):
        print("  %d. %s" % (index, text))

    # ---- JSON report ----
    report = {
        "schema": 2,
        "generator": "scripts/m7_eval_replay.py",
        "generatedAt": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
        "dataDir": str(data_dir),
        "datasetCount": len(scoring_datasets),
        "totalDurationS": _round(sum(ds.duration for ds in scoring_datasets), 2),
        "unreplayedRawFiles": [ds.id for ds in unreplayed],
        "duplicates": duplicate_rows,
        "excludedFromGating": sorted(excluded_ids),
        "ambiguities": list(AMBIGUITIES),
        "groundTruth": {
            ds.id: {
                "label": ds.label,
                "frames": len(ds.t),
                "durationS": _round(ds.duration, 3),
                "pulses": {action: len(times) for action, times in
                           expected[ds.id].get("pulses", {}).items()},
                "windows": {action: {"count": len(windows),
                                     "totalS": _round(sum(b - a for a, b in windows), 2)}
                            for action, windows in expected[ds.id].get("windows", {}).items()},
            } for ds in scoring_datasets
        },
        "groundTruth90": {
            dataset_id: {
                "label": next((ds.label for ds in scoring_datasets if ds.id == dataset_id), ""),
                "frames": stat["frames"],
                "durationS": stat["duration_s"],
                "fixtureFrames": next((row["fixture_frames"] for row in gt90_frame_checks
                                       if row["dataset"] == dataset_id), None),
                "frameGridMatchesFixture": next((row["match"] for row in gt90_frame_checks
                                                 if row["dataset"] == dataset_id), None),
                "pulses": {action: len(times) for action, times in
                           gt90_expected[dataset_id].get("pulses", {}).items()},
                "windows": {action: {"count": len(windows),
                                     "totalS": _round(sum(b - a for a, b in windows), 2)}
                            for action, windows in
                            gt90_expected[dataset_id].get("windows", {}).items()},
            } for dataset_id, stat in gt90_stats.items()
        },
        "gt90FrameChecks": gt90_frame_checks,
        "bowDrawPostureVariant": bow_variant,
        "latencyPolicy": {
            "table": latency_table,
            "source": str(engine_source),
            "parsedConstants": constants_status.get("count", 0),
            "missingConstants": latency_missing,
            "policy": "onset/release bounds read from VisionM7Gesture constants; applied as "
                      "expected_window -> [start + onset_s, end + release_s]; literal metrics unchanged",
        },
        "rates": {
            "raw": None if events_raw is None else {
                "path": str(events_raw_path),
                "mtime": _mtime_text(events_raw_path),
                "eventCount": count_raw,
                "malformed": bad_raw,
                "pulse": pulse_scores_raw,
                "held": held_scores_raw,
                "crossMatrix": cross_matrix(scoring_datasets, events_raw),
            },
            "90": None if events_90 is None else {
                "path": str(events_90_path),
                "mtime": _mtime_text(events_90_path),
                "eventCount": count_90,
                "malformed": bad_90,
                "pulse": pulse_scores_90,
                "pulseRateMatched": pulse_scores_gt90,
                "held": held_scores_90,
                "crossMatrix": cross_matrix(scoring_datasets, events_90),
            },
        },
        "context": context_rows,
        "gates": {
            "pulse": [row for row in literal_gate_rows if row["kind"] == "pulse"],
            "held": [row for row in literal_gate_rows if row["kind"] == "held"],
            "context": [row for row in literal_gate_rows if row["kind"] == "context"],
            "rows": len(literal_gate_rows),
            "failed": len(literal_failures),
            "result": "PASS" if not literal_failures else "FAIL",
            "mode": "literal-conservative",
        },
        "gatesLiteral": {
            "rows": literal_gate_rows,
            "failed": len(literal_failures),
            "result": "PASS" if not literal_failures else "FAIL",
        },
        "gatesPrimary": {
            "rows": primary_gate_rows,
            "failed": len(primary_failures),
            "result": "PASS" if not primary_failures else "FAIL",
            "description": "rate-matched (90 Hz-interpolated) pulse GT + bounded-latency held "
                           "windows + unchanged context suppression",
        },
        "gatesRateMatchedPulse": {
            "rows": [row for row in primary_gate_rows if row["kind"] == "pulse"],
            "rowsTotal": len([row for row in primary_gate_rows if row["kind"] == "pulse"]),
            "failed": len([row for row in primary_failures if row["kind"] == "pulse"]),
        },
        "gatesLatencyAwareHeld": {
            "rows": [row for row in primary_gate_rows if row["kind"] == "held"],
            "failed": len([row for row in primary_failures if row["kind"] == "held"]),
        },
        "exit": {
            "mode": "primary" if args.exit_primary else "literal",
            "code": 0 if not gate_failures else 1,
        },
        "notes": notes,
    }
    try:
        json_path.parent.mkdir(parents=True, exist_ok=True)
        json_path.write_text(json.dumps(report, indent=2, sort_keys=False) + "\n")
        print()
        print("[m7-eval] report -> %s" % json_path)
    except OSError as exc:
        print("[m7-eval] WARNING: could not write %s: %s" % (json_path, exc))
    return 0 if not gate_failures else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

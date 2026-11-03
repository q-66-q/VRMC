#!/usr/bin/env python3
"""Convert Gesture Lab JSONL recordings into a compact replay fixture for the M7 host harness.

The Java replay harness (provider/tests/dev/vrmc/provider/M7LabReplay.java) replays the *recorded*
27-joint hand positions and head pose through the real VisionM7Gesture state machine, so every
threshold change can be scored against labelled operator data before device testing.

Raw JSONL stays local/gitignored. The derived binary fixture is also local/gitignored
(export/m7-lab-fixtures/). This tool is a host analysis aid, not device evidence.

Layout (little-endian, fixed record; see M7LabReplay.java):
  header: magic "VRMCLAB\x01" (8 bytes), uint32 version=1, uint32 frameCount
  record: float64 t (epoch seconds)
          uint8 flags (bit0 headTracked, bit1 leftTracked, bit2 rightTracked)
          float32 head[3]
          float32 headMatrix[16] (column-major, right=col0, up=col1, backward=col2)
          float32 jointsLeft[27*3]   (raw joint positions in ARKit device/anchor space, metres)
          float32 jointsRight[27*3]

A second fixture set can be generated with --rate 90: the recorded samples (~18 Hz) are linearly
interpolated to the game's ~90 Hz frame cadence. Recorded snapshots under-sample short gestures (a
60 ms pinch can be a single sample), which makes duration/debounce gates look worse than they will on
device; the 90 Hz set answers "does the state machine fire when it sees a normal frame cadence"
while the raw set answers "does it handle the literal recorded samples". Both are host analysis only.

Usage (from repo root):
  python3 scripts/m7_lab_fixture.py [--data export/gesturelab-data]
                                   [--out export/m7-lab-fixtures] [--rate 0|90]
"""
import argparse
import json
import math
import struct
import sys
from pathlib import Path

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
JOINT_INDEX = {n: i for i, n in enumerate(JOINT_NAMES)}
JOINTS = len(JOINT_NAMES)
FLOATS = JOINTS * 3
MAGIC = b"VRMCLAB\x01"
VERSION = 1
HEADER = struct.Struct("<8sII")
RECORD = struct.Struct("<dB3f16f" + str(FLOATS) + "f" + str(FLOATS) + "f")


def joint_positions(hand):
    """Return float32[27*3] positions (or None when the hand is not tracked)."""
    out = [0.0] * FLOATS
    if not isinstance(hand, dict) or not hand.get("tracked"):
        return None
    seen = set()
    for joint in hand.get("joints", []):
        if not isinstance(joint, dict):
            continue
        idx = JOINT_INDEX.get(joint.get("name", ""))
        m = joint.get("m")
        if idx is None or not isinstance(m, list) or len(m) < 15:
            continue
        try:
            x, y, z = float(m[12]), float(m[13]), float(m[14])
        except (TypeError, ValueError):
            continue
        if not (math.isfinite(x) and math.isfinite(y) and math.isfinite(z)):
            continue
        base = idx * 3
        out[base] = x
        out[base + 1] = y
        out[base + 2] = z
        seen.add(idx)
    return out


def load_recording(path):
    frames = []
    bad = 0
    with path.open("r", errors="replace") as handle:
        for lineno, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                s = json.loads(line)
            except Exception:
                bad += 1
                continue
            t = float(s.get("t", 0.0))
            head_tracked = bool(s.get("headTracked"))
            head = s.get("head") or [0.0, 0.0, 0.0]
            try:
                hx, hy, hz = float(head[0]), float(head[1]), float(head[2])
            except (TypeError, ValueError, IndexError):
                hx = hy = hz = 0.0
            if not (math.isfinite(hx) and math.isfinite(hy) and math.isfinite(hz)):
                hx = hy = hz = 0.0
            hm = s.get("headMatrix") or []
            head_m = [0.0] * 16
            try:
                for i in range(min(16, len(hm))):
                    v = float(hm[i])
                    head_m[i] = v if math.isfinite(v) else 0.0
            except (TypeError, ValueError):
                pass
            jl = joint_positions(s.get("left"))
            jr = joint_positions(s.get("right"))
            flags = 0
            if head_tracked:
                flags |= 1
            if jl is not None:
                flags |= 2
                jl = jl
            else:
                jl = [0.0] * FLOATS
            if jr is not None:
                flags |= 4
            else:
                jr = [0.0] * FLOATS
            frames.append((t, flags, hx, hy, hz, head_m, jl, jr))
    return frames, bad


def resample(frames, rate):
    """Linear interpolation to a uniform frame rate; long gaps are not bridged (tracking gaps stay)."""
    if rate <= 0 or len(frames) < 2:
        return frames
    step = 1.0 / float(rate)
    max_bridge = 0.20  # do not invent motion across recording gaps / tracking outages
    out = []
    for i in range(len(frames) - 1):
        t0, f0, hx0, hy0, hz0, hm0, jl0, jr0 = frames[i]
        t1, f1, hx1, hy1, hz1, hm1, jl1, jr1 = frames[i + 1]
        dt = t1 - t0
        if dt <= 0.0:
            continue
        if dt > max_bridge:
            out.append((t0, f0, hx0, hy0, hz0, hm0, jl0, jr0))
            continue
        steps = max(1, int(round(dt / step)))
        both_flags = f0 & f1
        for k in range(steps):
            a = k / float(steps)
            t = t0 + dt * a
            flags = both_flags
            hx = hx0 + (hx1 - hx0) * a
            hy = hy0 + (hy1 - hy0) * a
            hz = hz0 + (hz1 - hz0) * a
            hm = [hm0[j] + (hm1[j] - hm0[j]) * a for j in range(16)]
            if (f0 & 2) and (f1 & 2):
                jl = [jl0[j] + (jl1[j] - jl0[j]) * a for j in range(FLOATS)]
            else:
                jl = [0.0] * FLOATS
            if (f0 & 4) and (f1 & 4):
                jr = [jr0[j] + (jr1[j] - jr0[j]) * a for j in range(FLOATS)]
            else:
                jr = [0.0] * FLOATS
            out.append((t, flags, hx, hy, hz, hm, jl, jr))
    out.append(frames[-1])
    return out


def write_fixture(path, frames):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as out:
        out.write(HEADER.pack(MAGIC, VERSION, len(frames)))
        for t, flags, hx, hy, hz, head_m, jl, jr in frames:
            out.write(RECORD.pack(t, flags, hx, hy, hz, *head_m, *jl, *jr))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="export/gesturelab-data")
    ap.add_argument("--out", default="export/m7-lab-fixtures")
    ap.add_argument("--rate", type=int, default=0,
                    help="0 = literal recorded samples; 90 = interpolate to 90 Hz frames")
    args = ap.parse_args()
    data = Path(args.data)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    sources = []
    for path in sorted((data / "accepted").glob("gesturelab-*.jsonl")):
        sources.append((path.stem, path))
    # IDLE is the negative/no-gesture recording kept outside the accepted set.
    for path in sorted(data.glob("gesturelab-IDLE-*.jsonl")):
        sources.append((path.stem, path))
    if not sources:
        print(f"[m7-fixture] no gesturelab JSONL under {data}", file=sys.stderr)
        return 2

    manifest = {"version": VERSION, "rate": args.rate, "generatedFrom": str(data),
                "datasets": [], "skipped": []}
    total_frames = 0
    total_bytes = 0
    for stem, path in sources:
        frames, bad = load_recording(path)
        if not frames:
            manifest["skipped"].append({"source": str(path), "reason": "no frames"})
            print(f"[m7-fixture] SKIP {stem}: no frames")
            continue
        raw_frames = len(frames)
        frames = resample(frames, args.rate)
        duration = frames[-1][0] - frames[0][0]
        bin_path = out / (stem + ".bin")
        write_fixture(bin_path, frames)
        size = bin_path.stat().st_size
        total_frames += len(frames)
        total_bytes += size
        manifest["datasets"].append({
            "id": stem,
            "label": stem.replace("gesturelab-", "").rsplit("-", 1)[0],
            "source": str(path),
            "bin": bin_path.name,
            "frames": len(frames),
            "rawFrames": raw_frames,
            "rate": args.rate,
            "duration": duration,
            "bytes": size,
            "unparsedLines": bad,
        })
        print(f"[m7-fixture] {stem}: frames={len(frames)} (raw {raw_frames}) "
              f"duration={duration:.2f}s bytes={size}")
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"[m7-fixture] datasets={len(manifest['datasets'])} frames={total_frames} "
          f"bytes={total_bytes} -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

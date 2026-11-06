#!/usr/bin/env python3
"""Generate the M8 device tuning guide from the measured host quality ladder plus device-class pixel budgets.

The quality ladder probe (runtime/probes/m8-quality-ladder) measures, on host Metal, what the
compositor's upscale + fovea-weighted sharpening does at several provider eye-target scales. This
script turns that measurement into a device-oriented guide: the same scales expressed as pixel budgets
for the expected 4K-class logical per-eye display size, with SSAA cost, plus concrete push-command
recommendations for the D1 A/B. Host numbers are a proxy, not device optics - the guide says so.

Usage:
  scripts/m8_tuning_guide.py [--out FILE] [--print] [--logical WxH] [--probe-out DIR]
Exit: 0 written/printed / 1 probe failed / 2 usage error.
"""
import argparse
import math
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROBE = os.path.join(ROOT, "runtime", "probes", "m8-quality-ladder", "run.sh")
SSAA_FACTOR = 1.44


def parse_size(text):
    match = re.fullmatch(r"([0-9]+)x([0-9]+)", text.strip())
    if not match:
        raise ValueError("expected WxH, got " + text)
    return int(match.group(1)), int(match.group(2))


def run_probe(probe_out):
    env = dict(os.environ)
    env["OUT"] = probe_out
    proc = subprocess.run([PROBE], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return proc.returncode, proc.stdout


def parse_ladder(output):
    device = ""
    rows = []
    row_re = re.compile(
        r"\[m8-quality-ladder\] ([0-9.]+)\s+(\d+)x(\d+)\s+([0-9.]+)\s+([0-9.]+)\s+"
        r"([0-9.]+)\s+([0-9.]+)\s+([+-]?[0-9.]+)\s+([0-9.]+)")
    for line in output.splitlines():
        if "[m8-quality-ladder] device=" in line:
            device = line.split("device=", 1)[1].strip()
        match = row_re.search(line)
        if match:
            rows.append({
                "scale": float(match.group(1)),
                "eye_w": int(match.group(2)),
                "eye_h": int(match.group(3)),
                "upscale": float(match.group(4)),
                "strength": float(match.group(5)),
                "psnr_flat": float(match.group(6)),
                "psnr_sharp": float(match.group(7)),
                "d_psnr": float(match.group(8)),
                "acutance": float(match.group(9)),
            })
    return device, rows


def main():
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--out", default=os.path.join(ROOT, "docs", "mvp", "M8_TUNING.md"))
    parser.add_argument("--probe-out", default="/tmp/vrmc-m8-tuning-probe")
    parser.add_argument("--logical", default="3660x3200", help="expected device-class logical per-eye size WxH")
    parser.add_argument("--print", action="store_true", help="print the guide instead of writing it")
    args = parser.parse_args()
    try:
        logical_w, logical_h = parse_size(args.logical)
    except ValueError as error:
        print("[m8-tuning] ERROR: " + str(error), file=sys.stderr)
        return 2

    rc, output = run_probe(args.probe_out)
    if rc != 0:
        print("[m8-tuning] probe failed (exit " + str(rc) + "):", file=sys.stderr)
        print(output, file=sys.stderr)
        return 1
    device, rows = parse_ladder(output)
    if not rows:
        print("[m8-tuning] ERROR: no ladder rows parsed", file=sys.stderr)
        return 1

    ssaa_axis = math.sqrt(SSAA_FACTOR)
    lines = []
    lines.append("# M8 rendering tuning guide (generated)")
    lines.append("")
    lines.append("Generated " + time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()) + " on host GPU "
                 + (device if device else "unknown") + " by scripts/m8_tuning_guide.py.")
    lines.append("")
    lines.append("This guide combines the **measured host quality ladder** (what the compositor's flat vs")
    lines.append("fovea-weighted sharp shader does at each provider eye-target scale) with **pixel budgets**")
    lines.append("for the expected device-class logical per-eye size " + str(logical_w) + "x" + str(logical_h) + ".")
    lines.append("Host numbers are a resampling proxy, not device optics; device acceptance still needs A6-A9")
    lines.append("plus the operator visual statement (docs/mvp/M8_DEVICE_RUN.md, M8_DEVICE_HANDOFF.md).")
    lines.append("")
    lines.append("## Measured upscale ladder (host Metal, synthetic pattern)")
    lines.append("")
    lines.append("| eye scale | eye target | upscale | auto sharpening | PSNR bilinear | PSNR sharp | dPSNR | edge acutance |")
    lines.append("|---|---|---|---|---|---|---|---|")
    for row in rows:
        lines.append("| %.3f | %dx%d | %.2fx | %.3f | %.2f dB | %.2f dB | %+.2f | %.2fx |" % (
            row["scale"], row["eye_w"], row["eye_h"], row["upscale"], row["strength"],
            row["psnr_flat"], row["psnr_sharp"], row["d_psnr"], row["acutance"]))
    lines.append("")
    lines.append("Reading: the auto sharpening strength is the compositor formula (min(0.45,")
    lines.append("(upscale-1)*0.35), zero at <=1.02); it is an acutance trade (bounded PSNR cost), and")
    lines.append("raising the provider eye-target resolution is by far the largest sharpness lever.")
    lines.append("")
    lines.append("## Device-class pixel budgets (per eye, logical " + str(logical_w) + "x" + str(logical_h) + ")")
    lines.append("")
    lines.append("| eye scale | eye target | eye MP | world target (SSAA %.2fx) | world MP | 2-eye world MP | SSAA pixel cost |" % SSAA_FACTOR)
    lines.append("|---|---|---|---|---|---|---|")
    for row in rows:
        ew = int(round(logical_w * row["scale"]))
        eh = int(round(logical_h * row["scale"]))
        ww = int(math.ceil(ew * ssaa_axis))
        wh = int(math.ceil(eh * ssaa_axis))
        eye_mp = ew * eh / 1000000.0
        world_mp = ww * wh / 1000000.0
        two_eye_mp = 2.0 * world_mp
        lines.append("| %.3f | %dx%d | %.2f | %dx%d | %.2f | %.2f | %.2fx |" % (
            row["scale"], ew, eh, eye_mp, ww, wh, world_mp, two_eye_mp, SSAA_FACTOR))
    lines.append("")
    lines.append("Budgets are the *world-render* pixels per frame (both eyes) at the given eye-target")
    lines.append("scale, with and without the startup SSAA knob; the compositor's foveated drawable cost is")
    lines.append("separate and covered by the max-render-quality knob.")
    lines.append("")
    lines.append("## Recommendations for the D1 A/B")
    lines.append("")
    lines.append("- 120 Hz first (the objective's hard part): start at --eye-scale 0.5 --target-hz 120")
    lines.append("  --content-first on --sharpening auto. The ladder shows 0.4 is ~8 dB below 0.5, so prefer")
    lines.append("  0.5+ and let the auto policy/content-first keep the cadence; watch the frame trace.")
    lines.append("- Image quality at 90 Hz: raise --eye-scale toward 0.75-1.0 and/or enable")
    lines.append("  --world-supersample 1.44 (SSAA, 1.44x world pixels, startup-only; relaunch). Sharpening is")
    lines.append("  a no-op at scale 1.0 and mainly helps the sub-native 120 Hz case.")
    lines.append("- Sharpening A/B: --sharpening off vs auto at the same eye scale; judge halos at edges.")
    lines.append("- Whatever the result, collect it with scripts/m8_device_session.sh collect --report so the")
    lines.append("  frame trace, A6-A9 and operator statement land in one artifact.")
    lines.append("")
    lines.append("Commands (live unless noted):")
    lines.append("")
    lines.append("    scripts/push_m8_render_config.sh --eye-scale 0.5 --target-hz 120 \\")
    lines.append("        --content-first on --sharpening auto")
    lines.append("    scripts/push_m8_render_config.sh --world-supersample 1.44    # next launch (SSAA)")
    lines.append("    scripts/push_m8_render_config.sh --sharpening off             # halo A/B")
    lines.append("")
    guide = "\n".join(lines) + "\n"
    if args.print:
        sys.stdout.write(guide)
    else:
        os.makedirs(os.path.dirname(args.out), exist_ok=True)
        with open(args.out, "w") as handle:
            handle.write(guide)
        print("[m8-tuning] wrote " + args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())

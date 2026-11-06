#!/usr/bin/env python3
"""Analyse an M8 device pull and classify the device verification rows A6-A9.

Reads a directory containing (pulled or simulator-copied) logs:
  vrmc-compositor.log | compositor.log     (CompositorServices M8 lines)
  vrmc-shell.log      | shell.log          (layer configuration lines)
  latestlog.txt                            (provider [VRMC-M8] / [VRMC-M5] lines)

Rows (see docs/mvp/M8_PLAN.md §5/§7):
  A6 foveation actually active: layer foveation=1 and rasterization rate maps present, and the
     compositor's display-geometry line reports rateMaps>0.
  A7 4K-class per-eye display path + provider eye targets follow it: logical per-eye >= 4K-class
     (>=3200x2800), provider published render settings and resized its eye targets at least once,
     without thrash.
  A8 120 Hz presented: latest measured displayHz >= 117 with few repeated frames (else report 90 Hz).
  A9 frame pacing within the measured cadence budget + no hard rendering regressions.

Exit codes: 0 = PASS (all rows), 2 = PARTIAL (M8 running but a row not satisfied, e.g. 90 Hz or no
foveation), 3 = NOT RUN (no M8 evidence: old build / logs not pulled), 4 = FAIL (hard regression).

This tool only reads logs; it makes no device claims by itself.
"""
import argparse
import os
import re
import sys

FOVEATION_4K_MIN_W = 3200
FOVEATION_4K_MIN_H = 2800
CADENCE_120_MIN_HZ = 117.0
CADENCE_90_MIN_HZ = 85.0
MAX_REPEATS_RATIO = 0.20
MAX_RESIZES = 40


def read_first(directory, names):
    """First readable candidate file; names are tried in priority order."""
    for name in names:
        path = os.path.join(directory, name)
        if os.path.isfile(path):
            with open(path, "r", errors="replace") as handle:
                return name, handle.read()
    return None, ""


def read_best(directory, names, marker):
    """First candidate containing marker (preferring the current session log); else the first file."""
    fallback = (None, "")
    for name in names:
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        with open(path, "r", errors="replace") as handle:
            text = handle.read()
        if not fallback[0]:
            fallback = (name, text)
        if marker in text:
            return name, text
    return fallback


def last_session(text, start_pattern):
    """Scope to the last session: from the last occurrence of start_pattern to EOF."""
    matches = list(re.finditer(start_pattern, text))
    if not matches:
        return text
    return text[matches[-1].start():]


def find_ints(pattern, text, group_count=0):
    return [m.groups() for m in re.finditer(pattern, text)]


def parse_compositor(text):
    info = {
        "configured_foveation": None,
        "max_render_quality": None,
        "rate_maps": [],
        "display_geometry": None,
        "feedback_publishes": 0,
        "last_feedback": None,
        "publish_failed": 0,
        "buffer_failed": 0,
    }
    m = re.search(r"layer configuration colorFormat=\d+ depthFormat=\d+ foveation=(\d) layout=\d+ "
                  r"maxRenderQuality=([0-9.]+)", text)
    if m:
        info["configured_foveation"] = int(m.group(1))
        info["max_render_quality"] = float(m.group(2))
    for m in re.finditer(r"foveation rate map view (\d+).*?screen=(\d+)x(\d+) physical=(\d+)x(\d+) "
                         r"layerCount=(\d+)", text):
        info["rate_maps"].append({
            "view": int(m.group(1)), "screen_w": int(m.group(2)), "screen_h": int(m.group(3)),
            "physical_w": int(m.group(4)), "physical_h": int(m.group(5)),
        })
    m = re.search(r"display geometry: logical L=(\d+)x(\d+) R=(\d+)x(\d+) physical drawable="
                  r"(\d+)x(\d+) foveation=(\d) rateMaps=(\d+) renderQuality=([0-9.]+|nan)", text)
    if m:
        info["display_geometry"] = {
            "left_w": int(m.group(1)), "left_h": int(m.group(2)),
            "right_w": int(m.group(3)), "right_h": int(m.group(4)),
            "physical_w": int(m.group(5)), "physical_h": int(m.group(6)),
            "foveation": int(m.group(7)), "rate_maps": int(m.group(8)),
            "quality": float(m.group(9)),
        }
    info["feedback_publishes"] = len(re.findall(r"render feedback published: logical L=", text))
    # The summary line gained "sharpen=<x>" in M8 round 4; accept both the old and new layouts so a
    # previously pulled log still classifies.
    feedback = list(re.finditer(
        r"render feedback: displayHz=([0-9.]+) presentHz=([0-9.]+) p50=([0-9.]+)ms p95=([0-9.]+)ms "
        r"repeats=(\d+)/(\d+) quality=([0-9.]+|nan)(?: sharpen=([0-9.]+|nan))? "
        r"logical L=(\d+)x(\d+) R=(\d+)x(\d+) "
        r"physical=(\d+)x(\d+) foveation=(\d) rateMaps=(\d+) published=(\d+) errors=(\d+)", text))
    if feedback:
        f = feedback[-1]
        info["last_feedback"] = {
            "display_hz": float(f.group(1)), "present_hz": float(f.group(2)),
            "p50": float(f.group(3)), "p95": float(f.group(4)),
            "repeats": int(f.group(5)), "samples": int(f.group(6)),
            "sharpen": float(f.group(8)) if f.group(8) not in (None, "nan") else 0.0,
            "logical_left": (int(f.group(9)), int(f.group(10))),
            "logical_right": (int(f.group(11)), int(f.group(12))),
            "physical": (int(f.group(13)), int(f.group(14))),
            "foveation": int(f.group(15)), "rate_maps": int(f.group(16)),
            "published": int(f.group(17)), "errors": int(f.group(18)),
        }
    info["publish_failed"] = len(re.findall(r"render feedback publish FAILED", text))
    info["buffer_failed"] = len(re.findall(r"command buffer FAILED", text))
    return info


def parse_shell(text):
    info = {"supports_foveation": None, "chosen_foveation": None, "max_quality": None, "layout": None}
    m = re.search(r"layer config: supportsFoveation=(\w+) defaultRenderQuality=([-0-9.naN]+) "
                  r"qualitySupported=(\w+) maxRenderQuality=([0-9.]+|system-default)", text)
    if m:
        info["supports_foveation"] = m.group(1) == "true"
        info["max_quality"] = m.group(4)
    m = re.search(r"layer config: layout=(.+?) foveation=(\w+)", text)
    if m:
        info["chosen_foveation"] = m.group(2) == "true"
        info["layout"] = m.group(1)
    return info


def parse_provider(text):
    info = {
        "settings_line": None,
        "resizes": [],
        "state_line": None,
        "diag": None,
        "crash_markers": [],
    }
    m = re.search(r"\[VRMC-M8\] render settings: (.+)", text)
    if m:
        info["settings_line"] = m.group(1).strip()
    for m in re.finditer(r"\[VRMC-M8\] eye target resize #(\d+): (\d+)x(\d+) -> (\d+)x(\d+)", text):
        info["resizes"].append({
            "index": int(m.group(1)), "from": (int(m.group(2)), int(m.group(3))),
            "to": (int(m.group(4)), int(m.group(5))),
        })
    states = list(re.finditer(r"\[VRMC-M8\] render state frame=\d+ eyeTarget=(\d+)x(\d+) "
                              r"logical=(\d+)x(\d+) drawable=(\d+)x(\d+) foveation=(\d) "
                              r"rateMaps=(\d+) displayHz=([0-9.]+)", text))
    if states:
        s = states[-1]
        info["state_line"] = {
            "eye_target": (int(s.group(1)), int(s.group(2))),
            "logical": (int(s.group(3)), int(s.group(4))),
            "drawable": (int(s.group(5)), int(s.group(6))),
            "foveation": int(s.group(7)), "rate_maps": int(s.group(8)),
            "display_hz": float(s.group(9)),
        }
    diags = list(re.finditer(r"\[VRMC-M5\] diag: (.+)", text))
    if diags:
        line = diags[-1].group(1)
        values = {}
        for key in ("p50Ms", "p95Ms", "missed90", "missedTarget", "targetHz", "displayHz"):
            m2 = re.search(key + r"=([0-9.]+)", line)
            if m2:
                values[key] = float(m2.group(1))
        info["diag"] = values
    for marker in ("hs_err_pid", "A fatal error has been detected", "Game crashed",
                   "Exception in thread \"Render thread\""):
        if re.search(marker, text):
            info["crash_markers"].append(marker)
    return info


def check_a6(comp, shell):
    reasons = []
    ok = True
    if shell.get("supports_foveation") is False:
        return "NOT RUN", ["shell: layer reports supportsFoveation=false (environment has no foveation; "
                           "not a device regression)"]
    if comp.get("configured_foveation") != 1:
        reasons.append("compositor: layer configuration foveation=%s (expected 1)" %
                       comp.get("configured_foveation"))
        ok = False
    if not comp.get("rate_maps"):
        reasons.append("compositor: no 'foveation rate map' geometry line")
        ok = False
    geom = comp.get("display_geometry")
    if not geom:
        reasons.append("compositor: no 'display geometry' line")
        ok = False
    elif geom["rate_maps"] <= 0:
        reasons.append("compositor: display geometry rateMaps=%d" % geom["rate_maps"])
        ok = False
    return ("PASS" if ok else "FAIL"), reasons


def check_a7(comp, provider):
    reasons = []
    ok = True
    geom = comp.get("display_geometry")
    feedback = comp.get("last_feedback")
    logical = None
    if geom:
        logical = (geom["left_w"], geom["left_h"])
    elif feedback:
        logical = feedback["logical_left"]
    if logical is None:
        reasons.append("no logical per-eye size reported")
        ok = False
    elif logical[0] < FOVEATION_4K_MIN_W or logical[1] < FOVEATION_4K_MIN_H:
        reasons.append("logical per-eye %dx%d is below the 4K-class threshold (%dx%d)" %
                       (logical[0], logical[1], FOVEATION_4K_MIN_W, FOVEATION_4K_MIN_H))
        ok = False
    if not provider.get("settings_line"):
        reasons.append("provider: no '[VRMC-M8] render settings' line")
        ok = False
    resizes = provider.get("resizes", [])
    if not resizes:
        reasons.append("provider: no eye-target resize (eye target did not follow the display)")
        ok = False
    elif len(resizes) > MAX_RESIZES:
        reasons.append("provider: %d eye-target resizes (thrash; max %d)" % (len(resizes), MAX_RESIZES))
        ok = False
    target = provider.get("state_line", {}).get("eye_target") if provider.get("state_line") else None
    if target and target[0] < 1024:
        reasons.append("provider: final eye target %dx%d smaller than the pre-M8 1024 baseline" % target)
        ok = False
    return ("PASS" if ok else "PARTIAL"), reasons, logical


def check_a8(comp):
    feedback = comp.get("last_feedback")
    reasons = []
    if not feedback:
        return "NOT RUN", ["no render-feedback cadence line"], None
    hz = feedback["display_hz"]
    repeats = feedback["repeats"]
    samples = max(1, feedback["samples"])
    ratio = repeats / samples
    if hz >= CADENCE_120_MIN_HZ:
        status = "PASS"
        reasons.append("displayHz=%.1f (120 Hz)" % hz)
    elif hz >= CADENCE_90_MIN_HZ:
        status = "PARTIAL"
        reasons.append("displayHz=%.1f (90 Hz; 120 Hz NOT achieved)" % hz)
    else:
        status = "PARTIAL"
        reasons.append("displayHz=%.1f (below the 90 Hz floor)" % hz)
    if ratio > MAX_REPEATS_RATIO:
        status = "PARTIAL"
        reasons.append("repeated frames %d/%d (%.0f%%)" % (repeats, samples, ratio * 100.0))
    else:
        reasons.append("repeated frames %d/%d" % (repeats, samples))
    return status, reasons, hz


def check_a9(comp, provider):
    reasons = []
    ok = True
    hard_failure = False
    if comp.get("publish_failed", 0) > 0:
        reasons.append("compositor: render feedback publish FAILED")
        hard_failure = True
    if comp.get("buffer_failed", 0) > 0:
        reasons.append("compositor: command buffer FAILED")
        hard_failure = True
    if provider.get("crash_markers"):
        reasons.append("provider: crash markers present")
        hard_failure = True
    diag = provider.get("diag")
    if not diag:
        reasons.append("provider: no '[VRMC-M5] diag' line (game/session log missing)")
        return "PARTIAL", reasons
    p95 = diag.get("p95Ms", 0.0)
    target_hz = diag.get("targetHz", 90.0) or 90.0
    budget = 1500.0 / target_hz
    if p95 > budget:
        reasons.append("provider: p95=%.2f ms above the 1.5x %.0f Hz budget (%.2f ms)" %
                       (p95, target_hz, budget))
        ok = False
    if diag.get("missedTarget", 0) > max(3.0, 0):
        # report only; a few missed frames in a window are normal on a shared device
        reasons.append("provider: missedTarget=%d in the last window" % int(diag["missedTarget"]))
    if not reasons:
        reasons.append("p95=%.2f ms targetHz=%.0f" % (p95, target_hz))
    if hard_failure:
        return "FAIL", reasons
    return ("PASS" if ok else "PARTIAL"), reasons


def main():
    parser = argparse.ArgumentParser(description="Analyse an M8 device pull (A6-A9)")
    parser.add_argument("directory", help="pull directory with vrmc-compositor.log / vrmc-shell.log / latestlog.txt (or compositor.log / shell.log)")
    args = parser.parse_args()
    directory = args.directory
    # Prefer a log that actually contains M8 lines (the app may have been relaunched after the test
    # session, rotating vrmc-compositor.log and leaving the M8 run in .prev.log).
    comp_name, comp_text = read_best(
        directory, ["vrmc-compositor.log", "vrmc-compositor.prev.log", "compositor.log"],
        "render feedback:")
    shell_name, shell_text = read_best(
        directory, ["vrmc-shell.log", "vrmc-shell.prev.log", "shell.log"], "layer config:")
    provider_name, provider_text = read_best(
        directory, ["latestlog.txt", "latestlog-game.txt"], "[VRMC-M8]")
    if comp_text:
        comp_text = last_session(comp_text, r"starting compositor thread")
    if shell_text:
        shell_text = last_session(shell_text, r"vrmc_shell_start invoked")
    comp = parse_compositor(comp_text)
    shell = parse_shell(shell_text)
    provider = parse_provider(provider_text)

    print(f"[m8-device] dir={directory}")
    print(f"[m8-device] logs: compositor={comp_name or 'MISSING'} shell={shell_name or 'MISSING'} "
          f"provider={provider_name or 'MISSING'}")

    has_m8 = bool(comp.get("display_geometry") or comp.get("feedback_publishes") or
                  comp.get("rate_maps") or provider.get("settings_line") or provider.get("resizes"))
    if not has_m8:
        print("[m8-device] RESULT: NOT RUN (no M8 rendering lines; old build or logs not pulled)")
        return 3

    a6, a6r = check_a6(comp, shell)
    a7, a7r, logical = check_a7(comp, provider)
    a8, a8r, hz = check_a8(comp)
    a9, a9r = check_a9(comp, provider)
    rows = [("A6 foveation active", a6, a6r), ("A7 4K-class display + provider eye targets", a7, a7r),
            ("A8 display cadence", a8, a8r), ("A9 pacing / regressions", a9, a9r)]
    print(f"{'row':40s} {'status':10s} detail")
    for name, status, reasons in rows:
        print(f"{name:40s} {status:10s} " + "; ".join(reasons))
    geom = comp.get("display_geometry")
    if geom:
        print(f"  display: logical L={geom['left_w']}x{geom['left_h']} R={geom['right_w']}x"
              f"{geom['right_h']} physical={geom['physical_w']}x{geom['physical_h']} "
              f"foveation={geom['foveation']} rateMaps={geom['rate_maps']} quality={geom['quality']}")
    target = provider.get("state_line", {}).get("eye_target") if provider.get("state_line") else None
    if target:
        print(f"  provider eye target: {target[0]}x{target[1]}  resizes={len(provider.get('resizes', []))}"
              f"  scale={provider.get('state_line', {}).get('logical')}")
    if hz:
        sharpen = comp.get("last_feedback", {}).get("sharpen", 0.0) if comp.get("last_feedback") else 0.0
        print(f"  measured display cadence: {hz:.1f} Hz  foveated sharpening: {sharpen:.2f}")
    statuses = [a6, a7, a8, a9]
    if all(s == "PASS" for s in statuses):
        print("[m8-device] RESULT: PASS (A6-A9)")
        return 0
    if "FAIL" in statuses:
        print("[m8-device] RESULT: FAIL (" + ", ".join(
            f"{name}={status}" for name, status, _ in rows if status != "PASS") + ")")
        return 4
    print("[m8-device] RESULT: PARTIAL (" + ", ".join(
        f"{name}={status}" for name, status, _ in rows if status != "PASS") + ")")
    return 2


if __name__ == "__main__":
    sys.exit(main())

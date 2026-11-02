#!/usr/bin/env python3
"""Summarize the M3C lifecycle probe runs.

Reads results/<variant>/sim-shell.log for every variant and prints (and writes
results/summary.md) a comparison table plus the event timeline of each run.

Evidence-only helper: it does not change any behaviour. Simulator code/convention evidence.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(HERE, "results")

TIME_RE = re.compile(r"t=\+([0-9.]+)")
TICK_RE = re.compile(r"TICK t=(\d+)s app=(\w+).*?comp\(frames=(\d+) state=([^ )]+).*?\| (.*)$")
ACT_RE = re.compile(r"scene(\d+)\(role=(\S+) sid=(\S+) activation=(\w+) count=(\d+)\)")
FRAME_RE = re.compile(r"frames=(\d+)")


def read_lines(path):
    with open(path, "r", errors="replace") as handle:
        return handle.readlines()


def time_of(line):
    match = TIME_RE.search(line)
    return float(match.group(1)) if match else None


def first_event(lines, needle, after_time=None):
    for line in lines:
        if needle not in line:
            continue
        stamp = time_of(line)
        if stamp is None:
            continue
        if after_time is not None and stamp < after_time:
            continue
        return stamp, line.rstrip()
    return None, None


def last_tick(lines):
    last = None
    for line in lines:
        if "TICK" in line:
            last = line.rstrip()
    return last


def parse_tick(line):
    if not line:
        return {}
    match = TICK_RE.search(line)
    if not match:
        return {}
    rest = match.group(5)
    scenes = ACT_RE.findall(rest)
    return {
        "t": int(match.group(1)),
        "app": match.group(2),
        "frames": int(match.group(3)),
        "comp_state": match.group(4),
        "scenes": ", ".join("%s:%s(%d)" % (name, act, int(count)) for _, name, _, act, count in scenes),
        "raw": line,
    }


def summarize_variant(tag):
    log_path = os.path.join(RESULTS, tag, "sim-shell.log")
    if not os.path.exists(log_path):
        return None
    lines = read_lines(log_path)

    config_line = next((l.strip() for l in lines if "config " in l), "")
    park_mode = re.search(r"park=(\S+)", config_line)
    park_when = re.search(r"parkWhen=(\S+)", config_line)
    park_scope = re.search(r"parkScope=(\S+)", config_line)
    open_delay = re.search(r"openDelay=(\S+)", config_line)

    park_time, _ = first_event(lines, "PARK begin")
    open_time, open_line = first_event(lines, "OPEN result=opened")
    deactivate_time, _ = first_event(lines, "UIScene.willDeactivate")
    resign_time, _ = first_event(lines, "UIApplication.willResignActive")
    background_time, _ = first_event(lines, "UIApplication.didEnterBackground")
    activate_time, _ = first_event(lines, "UIScene.didActivate", after_time=park_time)
    invalidated_time, _ = first_event(lines, "INVALIDATED")
    exit_time, _ = first_event(lines, "render thread exit")
    restore_time, _ = first_event(lines, "RESTORE done")
    second_open_time, _ = first_event(lines, "OPEN result=opened", after_time=(deactivate_time or 1e9))

    tick = parse_tick(last_tick(lines))
    shots = sorted(f for f in os.listdir(os.path.join(RESULTS, tag)) if f.startswith("shot-"))
    return {
        "tag": tag,
        "park": park_mode.group(1) if park_mode else "?",
        "when": park_when.group(1) if park_when else "?",
        "scope": park_scope.group(1) if park_scope else "?",
        "openDelay": open_delay.group(1) if open_delay else "?",
        "open_t": open_time,
        "park_t": park_time,
        "deactivate_t": deactivate_time,
        "resign_t": resign_time,
        "background_t": background_time,
        "reactivate_t": activate_time,
        "invalidated_t": invalidated_time,
        "exit_t": exit_time,
        "restore_t": restore_time,
        "last": tick,
        "shots": shots,
        "lines": lines,
    }


def fmt(value):
    return "-" if value is None else "+%.1fs" % value


def main():
    # Only the parking variants (01-13); the d1..d5 drawable-array probes have their own report.
    tags = sorted(d for d in os.listdir(RESULTS)
                  if os.path.isdir(os.path.join(RESULTS, d)) and d[:1].isdigit())
    results = [r for r in (summarize_variant(tag) for tag in tags) if r]
    if not results:
        print("no results found under", RESULTS)
        return 1

    out = []
    out.append("# M3C lifecycle probe — run summary\n")
    out.append("Simulator-only evidence (visionOS 27.0 simulator). Times are seconds since the app log started.\n")
    out.append("| variant | park | when | open | park | UIScene.willDeactivate | willResignActive | didEnterBackground | layer invalidated | last frames | last app/scene |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|")
    for r in results:
        last = r["last"]
        out.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s / %s |" % (
            r["tag"], r["park"], r["when"], fmt(r["open_t"]), fmt(r["park_t"]),
            fmt(r["deactivate_t"]), fmt(r["resign_t"]), fmt(r["background_t"]),
            fmt(r["invalidated_t"]), last.get("frames", "?"),
            last.get("app", "?"), last.get("scenes", "?")))
    out.append("")
    out.append("## Event timelines\n")
    for r in results:
        out.append("### %s\n" % r["tag"])
        out.append("\n".join(l.rstrip() for l in r["lines"]
                            if any(key in l for key in ("config ", "OPEN result", "PARK ", "RESTORE ", "EVENT UIScene",
                                                        "EVENT UIApplication", "INVALIDATED", "render thread exit",
                                                        "waitUntilRunning returned"))))
        out.append("\nlast tick: %s\n" % r["last"].get("raw", "n/a"))
        out.append("screenshots: %s\n" % ", ".join(r["shots"]))
    text = "\n".join(out)
    with open(os.path.join(RESULTS, "summary.md"), "w") as handle:
        handle.write(text + "\n")
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
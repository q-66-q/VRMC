#!/usr/bin/env python3
"""Compute stage latency percentiles from VRMC telemetry CSV.

Accepted CSV forms (header required):
  stage,duration_ms
  stage,ms
  capture,encode,network,decode,render,present   (one row per frame in ms)

The script never invents data. It prints a markdown table and the source row count.
"""
from __future__ import annotations

import argparse
import csv
import math
import statistics
import sys
from pathlib import Path


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = fraction * (len(ordered) - 1)
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv", type=Path)
    parser.add_argument("--json", action="store_true", help="emit JSON instead of markdown")
    args = parser.parse_args()
    if not args.csv.exists():
        print(f"missing {args.csv}", file=sys.stderr)
        return 2
    samples: dict[str, list[float]] = {}
    with args.csv.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            print("CSV has no header", file=sys.stderr)
            return 2
        fields = [name for name in reader.fieldnames if name not in ("stage", "frame", "frame_id", "timestamp")]
        for row in reader:
            if "stage" in row and ("duration_ms" in row or "ms" in row):
                stage = str(row.get("stage") or "unknown")
                value = row.get("duration_ms") or row.get("ms") or "0"
                try:
                    samples.setdefault(stage, []).append(float(value))
                except ValueError:
                    continue
            else:
                for field in fields:
                    value = row.get(field)
                    if value in (None, ""):
                        continue
                    try:
                        samples.setdefault(field, []).append(float(value))
                    except ValueError:
                        continue
    if not samples:
        print("no numeric samples found", file=sys.stderr)
        return 2

    result = {}
    for stage, values in sorted(samples.items()):
        result[stage] = {
            "count": len(values),
            "mean_ms": round(statistics.fmean(values), 3),
            "p50_ms": round(percentile(values, 0.50), 3),
            "p95_ms": round(percentile(values, 0.95), 3),
            "p99_ms": round(percentile(values, 0.99), 3),
            "max_ms": round(max(values), 3),
        }
    if args.json:
        import json
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    print("| stage | n | mean | p50 | p95 | p99 | max |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
    for stage, values in result.items():
        print(f"| {stage} | {values['count']} | {values['mean_ms']} | {values['p50_ms']} | "
              f"{values['p95_ms']} | {values['p99_ms']} | {values['max_ms']} |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

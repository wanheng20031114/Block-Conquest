"""Preserve and summarize resolution experiments and whole-GPU NVIDIA telemetry.

Viewport GPU timestamps are asynchronous. A display-frame observation contains
the latest available GPU result, not necessarily the GPU work for that frame.
NVIDIA samples are aligned only to phase windows, never to individual frames.
"""
from __future__ import annotations

import argparse
from collections import Counter
import csv
from datetime import datetime, timedelta, timezone
import hashlib
import json
import math
from pathlib import Path
import statistics

from run_gpu_investigation import FIELDS


LOCAL_TIMEZONE = timezone(timedelta(hours=8), name="Asia/Shanghai")
FRAME_COLUMNS = ["frame_ms", "gpu_ms", "render_cpu_ms", "physics_steps"]
BUDGET_MS = 1000.0 / 60.0
NUMERIC_FIELDS = FIELDS[1:10]
REASON_FIELDS = FIELDS[11:]
MONITOR_FIELDS = ["alive", "moving", "waiting", "damage", "draw_calls",
                  "primitives", "video_memory_bytes"]
METADATA = ["schema", "run_id", "scenario", "seed", "map", "roster_per_side",
            "natural_health", "profiled", "debug_build", "godot", "gpu",
            "renderer", "quality", "checks", "failures", "notes"]


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def distribution(values: list[float | int]) -> dict:
    if not values:
        return {"count": 0, "min": None, "median": None, "mean": None,
                "p50": None, "p95": None, "p99": None, "max": None}
    ordered = sorted(values)
    # Match the Godot harness: zero-based floor(n * percentile), capped at n-1.
    quantile = lambda p: ordered[min(len(ordered) - 1, math.floor(len(ordered) * p))]
    return {"count": len(values), "min": ordered[0], "median": statistics.median(values),
            "mean": statistics.mean(values), "p50": quantile(0.50),
            "p95": quantile(0.95), "p99": quantile(0.99), "max": ordered[-1]}


def read_telemetry(path: Path, fields: list[str]) -> tuple[list[list[str]], list[float]]:
    if fields != FIELDS:
        raise ValueError(f"Unsupported telemetry column order in {path}")
    with path.open(encoding="utf-8", newline="") as source:
        rows = [[value.strip() for value in row] for row in csv.reader(source)]
    timestamps = []
    for line, row in enumerate(rows, 1):
        if len(row) != len(fields):
            raise ValueError(f"Incomplete telemetry row {path}:{line}")
        local = datetime.strptime(row[0], "%Y/%m/%d %H:%M:%S.%f").replace(tzinfo=LOCAL_TIMEZONE)
        timestamps.append(local.timestamp())
    if not rows:
        raise ValueError(f"Empty telemetry: {path}")
    if timestamps != sorted(timestamps):
        raise ValueError(f"Telemetry timestamps run backwards: {path}")
    return rows, timestamps


def telemetry_summary(rows: list[list[str]]) -> dict:
    result = {"samples": len(rows), "numeric": {}, "event_reasons": {}}
    for field in NUMERIC_FIELDS:
        index = FIELDS.index(field)
        values, unavailable = [], Counter()
        for row in rows:
            raw = row[index]
            if raw in {"N/A", "[N/A]", "[Not Supported]"}:
                unavailable[raw] += 1
            else:
                value = float(raw)
                if not math.isfinite(value):
                    raise ValueError(f"Non-finite NVIDIA value for {field}: {raw}")
                values.append(value)
        result["numeric"][field] = {**distribution(values), "unavailable": dict(unavailable)}
    result["pstate_counts"] = dict(sorted(Counter(row[FIELDS.index("pstate")] for row in rows).items()))
    for field in REASON_FIELDS:
        states = Counter(row[FIELDS.index(field)] for row in rows)
        result["event_reasons"][field] = {
            "active_samples": states["Active"], "not_active_samples": states["Not Active"],
            "unavailable_samples": sum(count for state, count in states.items()
                                       if state not in {"Active", "Not Active"}),
            "state_counts": dict(sorted(states.items())),
        }
    return result


def summarize_phase(phase: dict, nv_rows: list[list[str]], nv_times: list[float]) -> dict:
    samples = phase["samples"]
    start, duration = phase["started_unix"], phase["duration_s"]
    end = start + duration
    indices = [i for i, timestamp in enumerate(nv_times) if start <= timestamp < end]
    steps = [sample["physics_steps"] for sample in samples]
    result = {
        "name": phase["name"], "started_unix": start, "ended_unix": end,
        "started_local": datetime.fromtimestamp(start, LOCAL_TIMEZONE).isoformat(),
        "duration_s": duration, "fps": phase["fps"], "frames": phase["frames"],
        "ticks": phase["ticks"], "tps": phase["tps"], "damage_events": phase["damage_events"],
        "frame_samples_columns": FRAME_COLUMNS,
        "frame_samples": [[sample[field] for field in FRAME_COLUMNS] for sample in samples],
        "physics_steps": {**distribution(steps), "sum": sum(steps),
                          "histogram": dict(sorted(Counter(steps).items())),
                          "display_frames_with_multiple_steps": sum(value >= 2 for value in steps)},
        "population_and_render_monitors": phase["monitors"],
        "monitor_summary": {field: distribution([monitor[field] for monitor in phase["monitors"]])
                            for field in MONITOR_FIELDS},
        "nvidia": {"raw_sample_indices": indices,
                   **telemetry_summary([nv_rows[index] for index in indices])},
        "consistency": {"sample_count_matches_frames": len(samples) == phase["frames"],
                        "sample_steps_match_ticks": sum(steps) == phase["ticks"]},
    }
    for field in FRAME_COLUMNS[:3]:
        values = [sample[field] for sample in samples]
        result[field] = {**distribution(values),
                         "samples_over_60fps_budget": sum(value > BUDGET_MS for value in values)}
    # Keep independent harness measurements, without combining their timers.
    result["harness_phase_measurements"] = {key: phase[key] for key in
                                            ["scene_physics_ms", "path_queries", "path_query_ms", "counters"]}
    return result


def summarize_run(game_path: Path, build_receipt: dict) -> dict:
    label = game_path.name.removesuffix("-game.json")
    directory = game_path.parent
    names = [game_path.name, f"{label}-game.environment.json", f"{label}-game.stdout.log",
             f"{label}-game.stderr.log", f"{label}.gpu.csv", f"{label}.gpu.stderr.log",
             f"{label}.telemetry.json"]
    paths = [directory / name for name in names]
    missing = [str(path) for path in paths if not path.is_file()]
    if missing:
        raise ValueError("Run not finalized; missing evidence: " + ", ".join(missing))
    game = read_json(game_path)
    environment = read_json(directory / f"{label}-game.environment.json")
    telemetry = read_json(directory / f"{label}.telemetry.json")
    rows, times = read_telemetry(directory / f"{label}.gpu.csv", telemetry["fields"])
    observations = environment["observations"]
    observation_times = [entry["elapsed_s"] for entry in observations]
    hashes = environment["runtime_hashes"]
    integrity = {
        "pck_matches_build_receipt": hashes["pck_sha256"] == build_receipt["pck_sha256"],
        "release_runtime_matches_template": hashes["release_exe_sha256"] == build_receipt["template_sha256"],
        "game_checks_passed": not game["failures"],
        "game_exit_zero": environment["exit_code"] == 0,
        "gpu_stderr_empty": (directory / f"{label}.gpu.stderr.log").stat().st_size == 0,
    }
    return {
        "label": label, "metadata": {field: game[field] for field in METADATA},
        "runtime": telemetry["runtime"], "render_scale": telemetry["render_scale"],
        "raw_file_sha256": {path.name: sha256(path) for path in paths},
        "integrity": integrity, "environment": environment,
        "environment_observation_interval_s": distribution([later - earlier for earlier, later in
                                                             zip(observation_times, observation_times[1:])]),
        "nvidia_telemetry": {"collection": telemetry, "fields": telemetry["fields"],
                             "raw_rows": rows, "timestamps_unix": times,
                             "whole_run_summary": telemetry_summary(rows)},
        "phases": [summarize_phase(phase, rows, times) for phase in game["phases"]],
    }


def summarize(runs: Path, build: Path) -> dict:
    receipt_path = build / "receipt.json"
    receipt = read_json(receipt_path)
    game_files = sorted(runs.glob("*-game.json"))
    if not game_files:
        raise ValueError(f"No completed game results in {runs}")
    return {
        "schema": 1, "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "frame_budget_ms": BUDGET_MS, "telemetry_timezone": "Asia/Shanghai (+08:00)",
        "interpretation": [
            "frame_samples retain display-frame observations in their original order.",
            "gpu_ms is the latest asynchronous viewport GPU result; a row is not an exact CPU/GPU frame pair.",
            "GPU samples over budget count reads, not unique completed GPU frames; repeated reads may refer to the same result.",
            "NVIDIA CSV samples describe the entire GPU, including the user's editor and other applications.",
            "NVIDIA samples are assigned to [phase.started_unix, started_unix + duration_s), with no per-frame interpolation.",
            "utilization.gpu and utilization.memory are NVIDIA sampling-window activity percentages, not memory capacity use.",
            "No GPU utilization is inferred by dividing GPU time by wall-clock frame time.",
            "Active power/thermal values count telemetry samples, not unique events or duration.",
            "Environment process observations are scheduled every 5 seconds; actual intervals include query overhead.",
            "Monitors may be delayed and are about one second apart; population snapshots do not prove all units attack simultaneously.",
            "Quantiles use sorted[floor(n*p)] capped at n-1, matching the Godot harness; median uses statistics.median.",
        ],
        "nvidia_numeric_units": {"utilization.gpu": "% activity", "utilization.memory": "% activity",
                                 "memory.used": "MiB", "memory.total": "MiB", "power.draw": "W",
                                 "power.limit": "W", "temperature.gpu": "C", "clocks.current.graphics": "MHz",
                                 "clocks.current.memory": "MHz"},
        "build_receipt_sha256": sha256(receipt_path), "build_receipt": receipt,
        "runs": [summarize_run(path, receipt) for path in game_files],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = summarize(args.runs, args.build)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(result['runs'])} GPU experiment runs to {args.output}")

"""Summarize sandbox movement evidence without making causal speedup claims.

Reads schema 1 from SandboxMovementPerformance / MovementProbeCounters. Entry
timers are inclusive and are never summed. Corridor exits and body collision
buckets are separate, mutually exclusive partitions within their own families.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics


METADATA = (
    "schema", "run_id", "scenario", "map", "roster_per_side", "seed", "profiled",
    "natural_health", "godot", "debug_build", "renderer", "gpu", "quality",
    "checks", "failures", "notes",
)
BODY_BUCKETS = (
    "body.zero_collisions", "body.one_collision", "body.two_collisions",
    "body.three_plus_collisions",
)


def fraction(value: float, denominator: float) -> float | None:
    return value / denominator if denominator else None


def observations(values: list[float | int]) -> dict:
    if not values:
        return {"count": 0, "min": None, "median": None, "max": None}
    return {"count": len(values), "min": min(values),
            "median": statistics.median(values), "max": max(values)}


def monitor_series(monitors: list[dict], key: str) -> dict:
    values = [item[key] for item in monitors]
    return {**observations(values), "mean": statistics.mean(values) if values else None,
            "first": values[0] if values else None, "last": values[-1] if values else None}


def entry_summary(name: str, entry: dict, ticks: int) -> dict:
    calls, usec = entry["calls"], entry["usec"]
    return {"name": name, "calls": calls, "total_ms": usec / 1000.0,
            "calls_per_actual_tick": fraction(calls, ticks),
            "ms_per_actual_tick": fraction(usec / 1000.0, ticks),
            "ms_per_call": fraction(usec / 1000.0, calls),
            "max_call_ms": entry["max_usec"] / 1000.0}


def corridor_summaries(corridors: dict, ticks: int) -> dict:
    additive = ("calls", "usec", "rows", "span_x", "span_z")

    def empty() -> dict:
        return dict.fromkeys((*additive, "max_rows"), 0)

    def add(target: dict, item: dict) -> None:
        for key in additive:
            target[key] += item[key]
        target["max_rows"] = max(target["max_rows"], item["max_rows"])

    total, sources, branches = empty(), {}, {}
    for key, item in corridors.items():
        source, branch = key.split(":", 1)
        add(total, item)
        add(sources.setdefault(source, empty()), item)
        add(branches.setdefault(branch, empty()), item)

    def summarize(item: dict) -> dict:
        return {"calls": item["calls"], "total_ms": item["usec"] / 1000.0,
                "ms_per_actual_tick": fraction(item["usec"] / 1000.0, ticks),
                "ms_per_call": fraction(item["usec"] / 1000.0, item["calls"]),
                "rows_inspected": item["rows"], "max_rows_per_call": item["max_rows"],
                "mean_rows_per_call": fraction(item["rows"], item["calls"]),
                "mean_span_x": fraction(item["span_x"], item["calls"]),
                "mean_span_z": fraction(item["span_z"], item["calls"]),
                "call_fraction_of_corridors": fraction(item["calls"], total["calls"]),
                "time_fraction_of_corridors": fraction(item["usec"], total["usec"]),
                "row_fraction_of_corridors": fraction(item["rows"], total["rows"])}

    detailed = []
    for key, item in sorted(corridors.items(), key=lambda pair: pair[1]["usec"], reverse=True):
        source, branch = key.split(":", 1)
        detailed.append({"source": source, "branch": branch, **summarize(item),
                         "call_fraction_within_source": fraction(item["calls"], sources[source]["calls"]),
                         "time_fraction_within_source": fraction(item["usec"], sources[source]["usec"]),
                         "row_fraction_within_source": fraction(item["rows"], sources[source]["rows"])})
    return {"totals": summarize(total), "by_source_branch": detailed,
            "by_source": [{"source": name, **summarize(item)} for name, item in
                          sorted(sources.items(), key=lambda pair: pair[1]["usec"], reverse=True)],
            "by_branch": [{"branch": name, **summarize(item)} for name, item in
                          sorted(branches.items(), key=lambda pair: pair[1]["usec"], reverse=True)],
            "notes": "Each corridor call contributes to one source:branch exit. Rows count actual scanned rows or columns, including early exits. Row shares are undefined when no scan occurs."}


def body_summary(entries: dict, values: dict, ticks: int) -> dict:
    empty = {"calls": 0, "usec": 0, "max_usec": 0}
    total = entries.get("body.move_and_slide", empty)
    buckets = []
    for name in BODY_BUCKETS:
        item = entries.get(name, empty)
        buckets.append({**entry_summary(name, item, ticks),
                        "call_fraction": fraction(item["calls"], total["calls"]),
                        "time_fraction": fraction(item["usec"], total["usec"])})
    return {"move_and_slide": entry_summary("body.move_and_slide", total, ticks),
            "collision_buckets": buckets,
            "slides": values.get("body.slides", 0),
            "colliding_moves": values.get("body.colliding_moves", 0),
            "slides_per_move": fraction(values.get("body.slides", 0), total["calls"]),
            "bucket_calls_match_total": sum(entries.get(name, empty)["calls"] for name in BODY_BUCKETS) == total["calls"],
            "bucket_usec_match_total": sum(entries.get(name, empty)["usec"] for name in BODY_BUCKETS) == total["usec"],
            "notes": "The four buckets partition move_and_slide calls; they are already included in its total and in enclosing entry timers. A call with zero reported slide collisions can still do native collision queries."}


def phase_summary(phase: dict, profiled: bool) -> dict:
    steps = [sample["physics_steps"] for sample in phase["samples"]]
    if any(not isinstance(step, int) or step < 0 for step in steps):
        raise ValueError("physics_steps must contain nonnegative integer counts")
    histogram = {str(step): steps.count(step) for step in sorted(set(steps))}
    ticks = phase["ticks"]
    monitors = phase["monitors"]
    result = {key: phase[key] for key in (
        "name", "duration_s", "frames", "ticks", "fps", "tps", "frame_ms", "gpu_ms",
        "scene_physics_ms", "path_query_ms", "path_queries", "damage_events",
    )}
    result["physics_steps_per_rendered_frame"] = {
        "sample_count": len(steps), "actual_steps_sum": sum(steps),
        "ge_2_frames": sum(step >= 2 for step in steps),
        "ge_2_fraction": fraction(sum(step >= 2 for step in steps), len(steps)),
        "ge_4_frames": sum(step >= 4 for step in steps),
        "ge_4_fraction": fraction(sum(step >= 4 for step in steps), len(steps)),
        "max": max(steps) if steps else None, "histogram": histogram,
        "reported_distribution": phase["physics_steps"],
    }
    result["sample_consistency"] = {"frames_match_samples": phase["frames"] == len(steps),
                                    "ticks_match_step_sum": ticks == sum(steps)}
    result["population_observations"] = {key: monitor_series(monitors, key) for key in ("alive", "moving", "waiting")}
    result["monitors"] = monitors
    if profiled:
        counters = phase["counters"]
        result["entries_inclusive"] = [entry_summary(name, item, ticks) for name, item in
                                       sorted(counters["entries"].items(), key=lambda pair: pair[1]["usec"], reverse=True)]
        result["corridors"] = corridor_summaries(counters["corridors"], ticks)
        result["body"] = body_summary(counters["entries"], counters["values"], ticks)
        result["counter_values"] = counters["values"]
    return result


def run_prefix(run_id: str) -> str:
    """Drop only a conventional final replicate number, e.g. short-axis-2."""
    return re.sub(r"[-_](?:run[-_]?)?\d+$", "", run_id)


def group_observations(runs: list[dict]) -> list[dict]:
    groups = {}
    for run in runs:
        if not run["included_in_unprofiled_observations"]:
            continue
        configuration = {key: run[key] for key in (
            "scenario", "map", "roster_per_side", "seed", "natural_health", "godot",
            "debug_build", "renderer", "gpu",
        )}
        configuration["quality"] = {key: value for key, value in run["quality"].items() if key != "user_data_dir"}
        prefix = run_prefix(run["run_id"])
        for phase in run["phases"]:
            key = json.dumps([prefix, configuration, phase["name"]], sort_keys=True)
            group = groups.setdefault(key, {"run_id_prefix": prefix, "configuration": configuration,
                                           "phase": phase["name"], "run_ids": [], "metrics": {}})
            group["run_ids"].append(run["run_id"])
            steps = phase["physics_steps_per_rendered_frame"]
            values = {"fps": phase["fps"], "frame_p95_ms": phase["frame_ms"]["p95"],
                      "frame_p99_ms": phase["frame_ms"]["p99"], "tps": phase["tps"],
                      "physics_steps_ge_2_fraction": steps["ge_2_fraction"],
                      "physics_steps_ge_4_fraction": steps["ge_4_fraction"],
                      "max_physics_steps_per_frame": steps["max"],
                      "damage_events": phase["damage_events"]}
            for population in ("alive", "moving", "waiting"):
                for statistic in ("min", "median", "max"):
                    values[f"{population}_monitor_{statistic}"] = phase["population_observations"][population][statistic]
            for metric, value in values.items():
                if value is not None:
                    group["metrics"].setdefault(metric, []).append(value)
    for group in groups.values():
        group["runs"] = len(group["run_ids"])
        group["metrics"] = {name: observations(values) for name, values in group["metrics"].items()}
    return sorted(groups.values(), key=lambda group: (group["run_id_prefix"], group["phase"], json.dumps(group["configuration"], sort_keys=True)))


def collect(folder: Path, output: Path | None = None) -> dict:
    runs, excluded = [], []
    seen_ids = set()
    for path in sorted(folder.glob("*.json")):
        if output is not None and path.resolve() == output.resolve():
            continue
        if path.name.endswith(".environment.json"):
            excluded.append({"file": path.name, "reason": "environment sidecar"})
            continue
        if "harness" in path.stem.lower():
            excluded.append({"file": path.name, "reason": "harness check"})
            continue
        raw = path.read_bytes()
        report = json.loads(raw.decode("utf-8-sig"))
        if not isinstance(report, dict) or "run_id" not in report or "phases" not in report:
            excluded.append({"file": path.name, "reason": "not a movement run report"})
            continue
        if report["schema"] != 1 or report["scenario"] != "sandbox_400_infantry":
            raise ValueError(f"Unsupported movement report schema or scenario: {path}")
        environment_file = path.with_name(path.stem + ".environment.json")
        environment = json.loads(environment_file.read_text(encoding="utf-8-sig")) if environment_file.exists() else None
        if ("harness" in report["run_id"].lower() or report.get("harness_check", False)
                or (environment is not None and "--harness-check" in environment["command"])):
            excluded.append({"file": path.name, "reason": "harness check"})
            continue
        if report["run_id"] in seen_ids:
            raise ValueError(f"Repeated run_id: {report['run_id']}")
        seen_ids.add(report["run_id"])
        run = {key: report[key] for key in METADATA}
        run["source_file"] = str(path.resolve())
        run["source_sha256"] = hashlib.sha256(raw).hexdigest()
        run["environment_exit_code"] = environment["exit_code"] if environment is not None else None
        run["environment_observation_count"] = len(environment["observations"]) if environment is not None else None
        local_script_profiling = None
        if environment is not None:
            command = environment["command"]
            engine_arguments = command[:command.index("--")] if "--" in command else command
            local_script_profiling = "--profiling" in engine_arguments
        run["runtime"] = {
            "local_script_profiling": local_script_profiling,
            "local_script_profiling_evidence": "environment.command" if environment is not None else "unavailable",
        }
        run["phases"] = [phase_summary(phase, report["profiled"]) for phase in report["phases"]]
        reasons = []
        if report["profiled"]:
            reasons.append("instrumented attribution run")
        if local_script_profiling is None:
            reasons.append("runtime profiling status unknown: environment command unavailable")
        elif local_script_profiling:
            reasons.append("Godot built-in script profiler enabled (--profiling)")
        if report["failures"]:
            reasons.append("run reported failed checks")
        if environment is not None and environment["exit_code"] != 0:
            reasons.append("nonzero process exit")
        if any(not all(phase["sample_consistency"].values()) for phase in run["phases"]):
            reasons.append("frame/tick sample counts disagree")
        if not run["phases"]:
            reasons.append("no completed phases")
        run["included_in_unprofiled_observations"] = not reasons
        run["unprofiled_observation_exclusion_reasons"] = reasons
        runs.append(run)
    return {"schema": 1, "source_directory": str(folder.resolve()), "run_count": len(runs),
            "runs": runs, "excluded_files": excluded,
            "unprofiled_observational_groups": group_observations(runs),
            "notes": [
                "No inclusive entry timers are added: nested entries overlap, and body collision buckets duplicate their parent timer.",
                "Only mutually exclusive corridor source:branch exits and the four body collision buckets have within-family totals or shares.",
                "Physics-step fractions use actual per-rendered-frame samples; entry costs use the phase's actual elapsed physics tick count.",
                "Population figures describe periodic monitors, not a complete per-frame population trace. Damage is the phase's recorded event count.",
                "Unprofiled groups summarize observed ranges and medians by run-id prefix, phase and matching configuration. User-data directory paths do not split otherwise matching quality settings.",
                "Groups are descriptive observations, not causal speedup estimates; no baseline/candidate difference or significance claim is computed. Custom-instrumented and Godot --profiling runs are attribution evidence only and are excluded from these groups.",
                "report.profiled describes custom counters only. runtime.local_script_profiling records the Godot --profiling launch flag before the user-argument separator; null means environment evidence is missing and excludes the run from unprofiled groups.",
                "Run-id prefixes strip only a final numeric replicate suffix. Environment sidecars and harness checks are excluded from run reports; background workload has not been certified absent.",
                "Null fractions mean a zero denominator or no samples, not a measured zero cost.",
            ]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.runs.is_dir():
        parser.error("--runs must be an existing directory")
    result = collect(args.runs, args.output)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")
    print(f"Summarized {result['run_count']} runs into {args.output}; descriptive groups only.")


if __name__ == "__main__":
    main()

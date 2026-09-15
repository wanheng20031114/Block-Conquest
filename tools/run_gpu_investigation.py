"""Serial resolution experiment with bounded NVIDIA telemetry collection.

Telemetry describes the whole selected GPU, including the user's editor. GPU
viewport timestamps are asynchronous; neither source is an exact per-frame
utilization meter. All variants run from the same exported game build.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess

from run_movement_investigation import run


FIELDS = ["timestamp", "utilization.gpu", "utilization.memory", "memory.used", "memory.total",
          "power.draw", "power.limit", "temperature.gpu", "clocks.current.graphics",
          "clocks.current.memory", "pstate", "clocks_event_reasons.sw_power_cap",
          "clocks_event_reasons.hw_thermal_slowdown", "clocks_event_reasons.sw_thermal_slowdown"]


def experiment(build: Path, output: Path, label: str, scale: float, runtime: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_-]+", label) or not 0.25 <= scale <= 2.0:
        raise ValueError("Expected a plain run label and render scale between 0.25 and 2.0")
    output.mkdir(parents=True, exist_ok=True)
    if any(output.glob(label + ".*")):
        raise ValueError("Existing GPU evidence must not be overwritten")
    telemetry = output / (label + ".gpu.csv")
    command = ["nvidia-smi", "--id=0", "--query-gpu=" + ",".join(FIELDS),
               "--format=csv,noheader,nounits", "--loop-ms=500"]
    with telemetry.open("wb") as stdout, (output / (label + ".gpu.stderr.log")).open("wb") as stderr:
        process = subprocess.Popen(command, stdout=stdout, stderr=stderr,
                                   creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        try:
            # GPU telemetry files are separate from the existing run-id family.
            run(build, output, label + "-game", 20, [f"--render-scale={scale}"], runtime)
            result = json.loads((output / (label + "-game.json")).read_text(encoding="utf-8"))
            if abs(result["quality"]["scale"] - scale) > 0.00001:
                raise RuntimeError("Build did not apply the requested render scale; refresh the diagnostic harness")
            if not all("gpu_ms" in sample and "render_cpu_ms" in sample
                       for phase in result["phases"] for sample in phase["samples"]):
                raise RuntimeError("Build lacks the GPU frame sampling harness")
        finally:
            running = process.poll() is None
            if running:
                process.terminate()
            process.wait(timeout=10)
            (output / (label + ".telemetry.json")).write_text(json.dumps({
                "command": command, "fields": FIELDS, "pid": process.pid,
                "terminated_after_game": running, "exit_code": process.returncode,
                "render_scale": scale, "runtime": runtime,
            }, indent=2), encoding="utf-8")
    errors = (output / (label + ".gpu.stderr.log")).read_text(encoding="utf-8", errors="replace")
    if not running or errors.strip() or not telemetry.stat().st_size:
        raise RuntimeError("GPU telemetry failed; inspect retained evidence")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--scale", type=float, required=True)
    parser.add_argument("--runtime", choices=["release", "debug"], default="release")
    args = parser.parse_args()
    if not 0.25 <= args.scale <= 2.0:
        parser.error("--scale must be between 0.25 and 2.0")
    experiment(args.build, args.output, args.label, args.scale, args.runtime)

"""Run one frozen sandbox experiment and retain bounded process observations."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
from build_movement_investigation import digest


def observe(exclude: int) -> list[dict]:
    command = ("Get-CimInstance Win32_Process | Where-Object { "
               "($_.Name -like 'Godot*' -or $_.Name -eq 'movement.exe' -or $_.Name -eq 'battle-600.exe') "
               f"-and $_.ProcessId -ne {exclude} "
               "} | Select-Object ProcessId,Name,CommandLine,UserModeTime,KernelModeTime | ConvertTo-Json -Compress")
    raw = subprocess.check_output(["powershell", "-NoProfile", "-Command", command], text=True,
                                  encoding="utf-8", errors="replace", timeout=12,
                                  creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    if not raw.strip():
        return []
    result = json.loads(raw)
    return result if isinstance(result, list) else [result]


def run(build: Path, output: Path, run_id: str, seconds: int, flags: list[str], runtime: str = "release") -> None:
    if not re.fullmatch(r"[A-Za-z0-9_-]+", run_id):
        raise ValueError("Run ID must be a plain alphanumeric label")
    build, output = build.resolve(), output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    result_file = output / (run_id + ".json")
    if any(output.glob(run_id + ".*")):
        raise ValueError("Existing evidence will not be overwritten")
    receipt = json.loads((build / "receipt.json").read_text(encoding="utf-8"))
    runtime_hashes = {"pck_sha256": digest(build / "bin/movement.pck"), "release_exe_sha256": digest(build / "bin/movement.exe")}
    if runtime_hashes["pck_sha256"] != receipt["pck_sha256"] or runtime_hashes["release_exe_sha256"] != receipt["template_sha256"]:
        raise ValueError("Frozen release executable or PCK changed")
    if runtime != "release":
        runtime_hashes["editor_sha256"] = digest(Path("C:/Program Files/Godot/Godot.exe"))
        if runtime_hashes["editor_sha256"] != receipt["editor_sha256"]:
            raise ValueError("Frozen editor identity changed")
        for relative, expected in receipt["frozen_source_sha256"].items():
            if digest(build / "source" / relative) != expected:
                raise ValueError(f"Frozen debug source changed: {relative}")
    startup = subprocess.STARTUPINFO() if os.name == "nt" else None
    if startup is not None:
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = subprocess.SW_HIDE
    executable = [str(build / "bin/movement.exe")] if runtime == "release" else ["C:/Program Files/Godot/Godot.exe", "--path", str(build / "source")]
    if runtime == "profiler":
        executable += ["--debug", "--profiling"]
    command = [*executable, "--position", "40,40", "--resolution", "1600x900", "--",
               "--run-id=" + run_id, "--output=" + str(output), "--seconds=" + str(seconds), *flags]
    observations = [{"elapsed_s": 0, "background": observe(-1)}]
    since = time.monotonic()
    with (output / (run_id + ".stdout.log")).open("wb") as stdout, (output / (run_id + ".stderr.log")).open("wb") as stderr:
        process = subprocess.Popen(command, stdout=stdout, stderr=stderr, startupinfo=startup,
                                   creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        print(f"RUN {run_id} PID {process.pid}", flush=True)
        try:
            while process.poll() is None:
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    observations.append({"elapsed_s": time.monotonic() - since, "background": observe(process.pid)})
                    if time.monotonic() - since > 190:
                        raise TimeoutError("Sandbox experiment exceeded external timeout")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=10)
            try:
                observations.append({"elapsed_s": time.monotonic() - since, "background": observe(-1)})
            except (subprocess.SubprocessError, OSError, ValueError) as error:
                observations.append({"elapsed_s": time.monotonic() - since, "observation_error": str(error)})
            (output / (run_id + ".environment.json")).write_text(json.dumps({"command": command, "pid": process.pid, "runtime_hashes": runtime_hashes,
                "exit_code": process.returncode, "observations": observations}, indent=2, ensure_ascii=False), encoding="utf-8")
    print((output / (run_id + ".stdout.log")).read_text(encoding="utf-8", errors="replace")[-2200:], flush=True)
    errors = (output / (run_id + ".stderr.log")).read_text(encoding="utf-8", errors="replace")
    if errors:
        print(errors[-4000:], flush=True)
    if process.returncode or "SCRIPT ERROR" in errors or "ERROR:" in errors or not result_file.exists():
        raise RuntimeError("Experiment failed; inspect retained logs")
    result = json.loads(result_file.read_text(encoding="utf-8"))
    if result["failures"]:
        raise RuntimeError(str(result["failures"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--seconds", type=int, default=20)
    parser.add_argument("--render-scale", type=float, default=1.0)
    parser.add_argument("--natural-health", action="store_true")
    parser.add_argument("--harness-check", action="store_true")
    parser.add_argument("--runtime", choices=["release", "debug", "profiler"], default="release")
    args = parser.parse_args()
    flags = (["--natural-health"] if args.natural_health else []) + (["--harness-check"] if args.harness_check else []) + [f"--render-scale={args.render_scale}"]
    run(args.build, args.output, args.run_id, args.seconds, flags, args.runtime)

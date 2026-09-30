"""Run the frozen-reference/production targeting CPU benchmark serially.

The hidden, timeout-bounded Godot child is the only engine process owned by this
runner. It is always reaped; no editor or unrelated Godot process is terminated.
All output lives below the repository's .local directory. This measures target
selection, not simulate(), frame time, graphics, or a screenshot replay.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
TEST = "res://tests/block_war_targeting_benchmark.gd"
REFERENCE_SHA256 = "cd8fedaed3b5b5d6431146654d075cec49bc203a046156ea6289123e9607520b"
SOURCES = (
    "tests/block_war_targeting_benchmark.gd", "tools/benchmark_targeting.py",
    "scripts/block_war/war_marches.gd", "scripts/block_war/war_factions.gd",
    "scripts/block_war/war_skill_rules.gd", "scripts/block_war/war_map_definition.gd",
    "scenes/block_war/marches.tscn", "data/block_war/maps/islands.tres",
)
HIDDEN = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0


def hashes() -> dict[str, str]:
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCES}


def reference_body() -> str:
    text = (ROOT / TEST.removeprefix("res://")).read_text(encoding="utf-8")
    start = text.index("\tfunc acquire_targets(")
    end = text.index("\nvar reference:", start)
    return "\n".join(line[1:] if line.startswith("\t") else line for line in text[start:end].splitlines()).strip() + "\n"


def pid_alive(pid: int) -> tuple[bool, str]:
    """Command-level verification of this exact owned PID after wait/kill."""
    if os.name == "nt":
        result = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"],
            capture_output=True, timeout=15, creationflags=HIDDEN)
        if result.returncode != 0:
            raise RuntimeError("tasklist process verification failed")
        output = result.stdout.decode(errors="replace")
        alive = any(len(row) > 1 and row[1] == str(pid) for row in csv.reader(output.splitlines()))
        return alive, "tasklist /FI PID eq <owned PID> /FO CSV /NH"
    result = subprocess.run(["ps", "-p", str(pid), "-o", "pid="], capture_output=True, timeout=15)
    if result.returncode not in (0, 1):
        raise RuntimeError("ps process verification failed")
    return bool(result.stdout.strip()), "ps -p <owned PID> -o pid="


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=ROOT / ".local/network/runtime/Godot_v4.7.2-stable_win64.exe")
    parser.add_argument("--out", type=Path, default=ROOT / ".local/targeting-benchmark")
    parser.add_argument("--mode", choices=("verify", "perf"), default="perf", help="perf always runs equivalence checks first")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--samples", type=int, default=60)
    parser.add_argument("--warmup", type=int, default=10)
    parser.add_argument("--sizes", default="200,600,1000,1800,2000,4000")
    parser.add_argument("--densities", default="sparse,bridge,dense,empty_radius")
    parser.add_argument("--queries", default="tower_mixed,orb_farthest")
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--check-source-only", action="store_true", help="validate frozen reference without launching Godot or writing output")
    args = parser.parse_args()
    if min(args.rounds, args.samples, args.timeout) < 1 or args.warmup < 0:
        parser.error("positive rounds/samples/timeout and nonnegative warmup required")
    size_tokens = args.sizes.split(",")
    if not all(token.isdigit() and 1 <= int(token) <= 16384 for token in size_tokens):
        parser.error("sizes must be comma-separated integers in 1..16384")
    sizes = [int(token) for token in size_tokens]
    densities, queries = args.densities.split(","), args.queries.split(",")
    if not densities or any(item not in {"sparse", "bridge", "dense", "empty_radius"} for item in densities):
        parser.error("unsupported density")
    if not queries or any(item not in {"tower_mixed", "orb_farthest"} for item in queries):
        parser.error("unsupported query mode")
    if len(set(sizes)) != len(sizes) or len(set(densities)) != len(densities) or len(set(queries)) != len(queries):
        parser.error("duplicate sizes/densities/queries are not allowed")
    frozen_hash = hashlib.sha256(reference_body().encode("utf-8")).hexdigest()
    if frozen_hash != REFERENCE_SHA256:
        parser.error("the frozen pre-optimization reference body changed")
    if args.check_source_only:
        print(json.dumps({"reference_body_sha256": frozen_hash, "sources": hashes(), "godot_started": False}))
        return 0
    output_dir = args.out.resolve()
    if not output_dir.is_relative_to((ROOT / ".local").resolve()):
        parser.error("--out must resolve inside the repository .local directory")
    if not args.godot.is_file():
        parser.error("--godot must name an existing engine executable")
    output_dir.mkdir(parents=True, exist_ok=True)
    before = hashes()
    stdout_path = output_dir / "stdout.log"
    engine_log = output_dir / "engine.log"
    environment = os.environ.copy()
    environment["APPDATA"] = str(output_dir / "userdata")
    Path(environment["APPDATA"]).mkdir(parents=True, exist_ok=True)
    command = [str(args.godot.resolve()), "--headless", "--path", str(ROOT),
        "--audio-driver", "Dummy", "--log-file", str(engine_log), "--script", TEST,
        "--", f"--mode={args.mode}", f"--rounds={args.rounds}", f"--samples={args.samples}",
        f"--warmup={args.warmup}", f"--sizes={args.sizes}",
        f"--densities={args.densities}", f"--queries={args.queries}"]
    process = None
    timed_out = False
    errors: list[str] = []
    began = time.monotonic()
    with stdout_path.open("wb") as output:
        try:
            process = subprocess.Popen(command, cwd=ROOT, env=environment,
                stdout=output, stderr=subprocess.STDOUT, creationflags=HIDDEN)
            process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            errors.append("Godot timed out")
        except OSError as exc:
            errors.append(f"Godot launch failed: {exc}")
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=15)
    cleanup = {"owned_pid": process.pid if process else None, "exited": process is not None and process.poll() is not None}
    if process is not None:
        try:
            alive, method = pid_alive(process.pid)
            cleanup.update({"pid_alive_after_wait": alive, "verification": method})
            if alive: errors.append("Owned Godot PID is still present after cleanup")
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
            cleanup["verification_error"] = str(exc)
            errors.append("Could not independently verify owned process cleanup")
    if process is None or process.returncode != 0:
        errors.append("Godot did not exit successfully")
    # Stdout is freshly truncated for this invocation; old engine logs cannot
    # provide a stale passing result if compilation/startup fails this time.
    lines = stdout_path.read_text(encoding="utf-8", errors="replace").splitlines()
    parsed: dict[str, list] = {"contract": [], "verify": [], "results": []}
    for prefix, key in (("TARGETING_CONTRACT ", "contract"), ("TARGETING_VERIFY ", "verify"), ("TARGETING_RESULT ", "results")):
        for line in lines:
            if line.startswith(prefix):
                try:
                    parsed[key].append(json.loads(line[len(prefix):]))
                except json.JSONDecodeError:
                    errors.append(f"Malformed {prefix.strip()} output")
    summaries = [line for line in lines if line.startswith("TARGETING_CHECKS ")]
    diagnostics = [line for line in lines if line.startswith(("SCRIPT ERROR:", "ERROR:", "FAIL "))]
    fatal = [line for line in diagnostics if line != "ERROR: Failed to read the root certificate store."]
    if fatal: errors.append("Unexpected engine/script/assertion diagnostics")
    if len(parsed["contract"]) != 1 or len(parsed["verify"]) != 1 or parsed["verify"][0].get("failures") != []:
        errors.append("Missing complete passing equivalence verification")
    if len(summaries) != 1 or not re.fullmatch(r"TARGETING_CHECKS checks=[1-9][0-9]* failures=0", summaries[0]):
        errors.append("Missing passing final check summary")
    expected = args.rounds * len(sizes) * len(densities) * len(queries) * 2 if args.mode == "perf" else 0
    if len(parsed["results"]) != expected:
        errors.append(f"Expected {expected} performance records, got {len(parsed['results'])}")
    for row in parsed["results"]:
        if len(row.get("raw_call_matrix_ms", [])) != args.samples or any(len(calls) != 12 for calls in row.get("raw_call_matrix_ms", [])):
            errors.append("Incomplete raw timing samples")
            break
    after = hashes()
    if before != after: errors.append("Measured sources changed during the run")
    receipt = {"command": command, "pid": process.pid if process else None,
        "exit_code": process.returncode if process else None, "timeout": timed_out,
        "seconds": round(time.monotonic() - began, 3), "cleanup": cleanup,
        "source_sha256_before": before, "source_sha256_after": after,
        "frozen_reference_body_sha256": frozen_hash,
        "mode": args.mode, **parsed, "summaries": summaries,
        "diagnostics": diagnostics, "errors": errors, "successful": not errors}
    destination = output_dir / "receipt.json"
    destination.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for row in parsed["results"]:
        print(json.dumps({key: value for key, value in row.items() if not key.startswith("raw_")}, ensure_ascii=True), flush=True)
    print(json.dumps({"receipt": str(destination), "cleanup": cleanup, "seconds": receipt["seconds"], "errors": errors}, ensure_ascii=True), flush=True)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())

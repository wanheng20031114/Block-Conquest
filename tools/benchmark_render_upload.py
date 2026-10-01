"""Prepare and run isolated MultiMesh setter/buffer A/B experiments.

Never edits production scripts. Native verification and timed performance runs
are separate. The private-desktop runner requests 24 FPS, but Settings may
override the CLI value. Report the observed engine limit and wall timing;
this isolated benchmark cannot establish end-to-end 60 FPS performance.
An explicit --source-ref freezes only the historical _render body. Both variants
still inherit the current project, including pose calculations and resources.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".local/multiplayer-candidates/render-upload"
PRODUCTION = ROOT / "scripts/block_war/war_marches.gd"
TEST = "res://tests/block_war_render_upload_benchmark.gd"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replace_once(source: str, before: str, after: str) -> str:
    if source.count(before) != 1:
        raise ValueError(f"Render recipe no longer matches exactly once: {before!r}")
    return source.replace(before, after, 1)


def git_output(*arguments: str) -> str:
    return subprocess.run(["git", *arguments], cwd=ROOT, check=True, capture_output=True,
                          text=True, encoding="utf-8").stdout


def prepare(source_ref: str = "current") -> dict:
    current_source = PRODUCTION.read_text(encoding="utf-8")
    current_head = git_output("rev-parse", "HEAD").strip()
    selected_commit = None
    if source_ref == "current":
        source = current_source
    else:
        selected_commit = git_output("rev-parse", "--verify", "--end-of-options", source_ref + "^{commit}").strip()
        source = git_output("show", selected_commit + ":scripts/block_war/war_marches.gd")
    if source.count("func _render() -> void:\n") != 1:
        raise ValueError("Selected source must contain exactly one _render function")
    render = "func _render() -> void:\n" + source.split("func _render() -> void:\n", 1)[1]
    if "\nfunc " in render:
        raise ValueError("Selected _render no longer matches the expected final-function structure")
    prefix = 'extends "res://scripts/block_war/war_marches.gd"\n'
    baseline = prefix + "## Frozen selected render body; all inherited dependencies are current.\n\n" + render
    candidate_render = replace_once(render, "\tvar slot := 0\n", "\t_prepare_upload_buffers()\n\tvar slot := 0\n")
    candidate_render = replace_once(candidate_render,
        "\t\t_multimesh.set_instance_transform(slot, Transform3D(basis, _presentation_position(unit)))\n",
        "\t\tvar transform := Transform3D(basis, _presentation_position(unit))\n")
    candidate_render = replace_once(candidate_render, "\t\t_multimesh.set_instance_custom_data(slot, color)\n",
        "\t\tvar offset := slot * 16\n" + "".join(
            f"\t\t_normal_upload[offset + {index}] = {expression}\n" for index, expression in enumerate([
                "transform.basis.x.x", "transform.basis.y.x", "transform.basis.z.x", "transform.origin.x",
                "transform.basis.x.y", "transform.basis.y.y", "transform.basis.z.y", "transform.origin.y",
                "transform.basis.x.z", "transform.basis.y.z", "transform.basis.z.z", "transform.origin.z",
                "color.r", "color.g", "color.b", "color.a"])))
    candidate_render = replace_once(candidate_render, "\t_multimesh.visible_instance_count = slot\n",
        "\tif slot > 0:\n\t\t_multimesh.buffer = _normal_upload\n"
        "\t_multimesh.visible_instance_count = slot\n")
    candidate = prefix + '''## 3D transform + custom data, no vertex-color stream: 16 floats/instance.
## https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-multimesh-set-buffer
## The initial 4096-slot CPU buffer occupies 256 KiB; hidden units are omitted.
var _normal_upload := PackedFloat32Array()

func _prepare_upload_buffers() -> void:
	var floats := _multimesh.instance_count * 16
	if _normal_upload.size() != floats:
		_normal_upload.resize(floats)

''' + candidate_render
    OUT.mkdir(parents=True, exist_ok=True)
    # Audit evidence only. Loading a renamed full WarMarches copy would introduce
    # incompatible MarchUnit/MarchOrder types; both variants inherit production.
    (OUT / "selected-war-marches-source.txt").write_text(source, encoding="utf-8")
    (OUT / "baseline.gd").write_text(baseline, encoding="utf-8")
    (OUT / "candidate.gd").write_text(candidate, encoding="utf-8")
    paths = {"production": PRODUCTION, "baseline": OUT / "baseline.gd", "candidate": OUT / "candidate.gd",
             "test": ROOT / TEST.removeprefix("res://"), "runner": Path(__file__)}
    manifest = {"sources_sha256": {key: digest(path) for key, path in paths.items()},
                "render_source": {"requested_ref": source_ref, "resolved_commit": selected_commit,
                                  "selected_source_sha256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
                                  "selected_render_body_sha256": hashlib.sha256(render.encode("utf-8")).hexdigest()},
                "shared_dependencies": {"current_head": current_head,
                                        "scope": "Both variants inherit current WarMarches behavior except _render and use current scenes, scripts, shaders, assets and project settings.",
                                        "tracked_worktree_changes": git_output("status", "--porcelain", "--untracked-files=no").splitlines(),
                                        "exact_historical_project_replay": False},
                "initial_capacity_per_mesh": 4096, "stride_floats": 16,
                "initial_additional_cpu_buffers_bytes": 4096 * 16 * 4,
                "baseline_render_body_is_exact_selected_source_copy": baseline.endswith(render),
                "selected_source_matches_current_production": source == current_source}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--source-ref", default="current",
                        help="Freeze _render from current working tree or an explicit Git commit/ref; all other dependencies stay current")
    parser.add_argument("--mode", choices=["verify", "perf"], default="verify")
    parser.add_argument("--backend", choices=["headless", "rendered"], default="headless")
    parser.add_argument("--godot", type=Path, default=ROOT / ".local/network/runtime/Godot_v4.7.2-stable_win64.exe")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--frames", type=int, default=120)
    parser.add_argument("--warmup", type=int, default=30)
    parser.add_argument("--sizes", default="512,4096")
    parser.add_argument("--timeout", type=int, default=480)
    args = parser.parse_args()
    if min(args.rounds, args.frames, args.warmup, args.timeout) < 1:
        parser.error("rounds, frames, warmup and timeout must be positive")
    if not all(value.isdigit() and int(value) > 0 for value in args.sizes.split(",")):
        parser.error("sizes must contain comma-separated positive integers")
    manifest = prepare(args.source_ref)
    if args.prepare_only:
        print(json.dumps({"prepared": str(OUT), **manifest}, indent=2))
        for backend in ("headless", "rendered"):
            for mode in ("verify", "perf"):
                print(subprocess.list2cmdline([sys.executable, str(Path(__file__).resolve()), "--backend", backend, "--mode", mode,
                                              "--source-ref", args.source_ref]))
        return 0
    run_dir = OUT / f"{args.backend}-{args.mode}"
    run_dir.mkdir(parents=True, exist_ok=True)
    script_args = ["--mode=" + args.mode, "--rounds=" + str(args.rounds), "--frames=" + str(args.frames),
                   "--warmup=" + str(args.warmup), "--sizes=" + args.sizes]
    engine_log = run_dir / "engine.log"
    if args.backend == "rendered":
        command = [sys.executable, str(ROOT / "tools/run_godot_private_desktop.py"), TEST,
                   "--output", str(run_dir), "--godot", str(args.godot.resolve()), "--real-time", "--timeout", str(args.timeout)]
        command.extend("--script-arg=" + value for value in script_args)
    else:
        command = [str(args.godot.resolve()), "--headless", "--path", str(ROOT), "--audio-driver", "Dummy",
                   "--log-file", str(engine_log), "--script", TEST, "--", str(run_dir), *script_args]
    environment = os.environ.copy()
    environment["APPDATA"] = str(run_dir / "userdata")
    Path(environment["APPDATA"]).mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    process = None
    expired = False
    stdout_path = run_dir / "stdout.log"
    with stdout_path.open("wb") as log:
        try:
            process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=log, stderr=subprocess.STDOUT,
                                       creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            process.wait(timeout=args.timeout + 30)
        except subprocess.TimeoutExpired:
            expired = True
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=10)
    output = stdout_path.read_text(encoding="utf-8", errors="replace")
    results = [json.loads(line.removeprefix("UPLOAD_AB ")) for line in output.splitlines() if line.startswith("UPLOAD_AB ")]
    diagnostics = [line for line in output.splitlines() if line.startswith(("ERROR:", "SCRIPT ERROR:", "FAIL "))]
    # This engine/environment emits a known startup certificate-store error.
    allowed_diagnostics = [line for line in diagnostics if line == "ERROR: Failed to read the root certificate store."]
    fatal_diagnostics = [line for line in diagnostics if line not in allowed_diagnostics]
    summary = [line for line in output.splitlines() if line.startswith("UPLOAD_AB_CHECKS")]
    unchanged = digest(PRODUCTION) == manifest["sources_sha256"]["production"]
    expected_results = args.rounds * len(args.sizes.split(",")) * 2 * 2 if args.mode == "perf" else 2
    successful = (not expired and process.returncode == 0 and not fatal_diagnostics and unchanged
                  and len(summary) == 1 and summary[0].endswith("failures=0") and len(results) == expected_results)
    receipt = {**manifest, "command": command, "pid": process.pid, "exit_code": process.returncode,
               "timeout": expired, "exited": process.poll() is not None, "seconds": round(time.monotonic() - started, 3),
               "production_unchanged": unchanged, "mode": args.mode, "backend": args.backend,
               "requested_cli_max_fps": 24 if args.backend == "rendered" else None,
               "observed_engine_max_fps": sorted({result["engine_max_fps"] for result in results}),
               "observed_vsync_modes": sorted({result["vsync_mode"] for result in results}),
               "results": results, "summaries": summary, "allowed_diagnostics": allowed_diagnostics,
               "fatal_diagnostics": fatal_diagnostics, "successful": successful}
    (run_dir / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, ensure_ascii=True, indent=2))
    return 0 if successful else 1


if __name__ == "__main__":
    sys.exit(main())

"""Freeze and instrument the real 400-infantry sandbox without editing game code.

Each build owns copied resources and a release PCK; all builds share a research-only user-data directory,
and a source/hash receipt. Timed builds are for attribution; compare unprofiled
variants separately. All Godot subprocesses have bounded lifetime and cleanup.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
EDITOR = Path("C:/Program Files/Godot/Godot.exe")
TEMPLATE = Path(os.environ["APPDATA"]) / "Godot/export_templates/4.6.3.stable/windows_release_x86_64.exe"
HARNESS = {
    "tests/sandbox_movement_performance.gd", "tests/movement_probe_counters.gd",
    "tests/skirmish_profile_probe.gd", "tests/skirmish_profile_probe.tscn",
    "tests/movement_corridor_probe_test.gd", "tests/movement_navigation_test.gd",
    "tests/path_budget_test.gd", "tests/path_budget_startup_test.gd",
    "tests/balance_combat_host.gd", "tests/balance_combat_host.tscn",
    "tests/movement_corridor_microbenchmark.gd",
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replace_once(source: str, old: str, new: str) -> str:
    if source.count(old) != 1:
        raise ValueError(f"Expected one source site: {old[:120]!r}")
    return source.replace(old, new, 1)


def wrap(source: str, name: str, label: str) -> str:
    pattern = rf"^func {re.escape(name)}\((.*)\) -> ([^:]+):$"
    matches = list(re.finditer(pattern, source, re.MULTILINE))
    if len(matches) != 1:
        raise ValueError(f"Expected one typed function: {name}")
    match = matches[0]
    arguments, returns = match.groups()
    passed = ", ".join(part.split(":")[0].strip() for part in arguments.split(",") if part.strip())
    original = "_movement_original" + name
    call = f"{original}({passed})"
    invoke = f"\t{call}\n" if returns == "void" else f"\tvar result: {returns} = {call}\n"
    finish = "" if returns == "void" else "\treturn result\n"
    wrapper = (match[0] + "\n\tvar started := Time.get_ticks_usec() if MovementProbeCounters.enabled else 0\n"
               + invoke + f'\tif started > 0: MovementProbeCounters.record(&"{label}", Time.get_ticks_usec() - started)\n'
               + finish + "\n" + match[0].replace(f"func {name}", f"func {original}"))
    return source[:match.start()] + wrapper + source[match.end():]


def instrument(project: Path) -> None:
    from movement_corridor_probe import instrument_corridor, instrument_corridor_callers

    def edit(relative: str, fn) -> None:
        path = project / relative
        path.write_text(fn(path.read_text(encoding="utf-8-sig")), encoding="utf-8")

    edit("scripts/construction_navigation.gd", instrument_corridor)
    path_file = project / "scripts/path_budget.gd"
    corridor_file = project / "scripts/navigation/path_corridor.gd"
    path_source, corridor_source = instrument_corridor_callers(
        path_file.read_text(encoding="utf-8-sig"), corridor_file.read_text(encoding="utf-8-sig"))
    path_file.write_text(path_source, encoding="utf-8")
    corridor_file.write_text(corridor_source, encoding="utf-8")

    def unit(source: str) -> str:
        source = replace_once(source, "\t\tmove_and_slide()", "\t\t_movement_body_move()")
        source += '''
func _movement_body_move() -> void:
\tvar started := Time.get_ticks_usec() if MovementProbeCounters.enabled else 0
\tmove_and_slide()
\tif started > 0:
\t\tvar elapsed := Time.get_ticks_usec() - started
\t\tvar collisions := get_slide_collision_count()
\t\tMovementProbeCounters.record(&"body.move_and_slide", elapsed)
\t\tvar bucket: StringName = &"body.zero_collisions" if collisions == 0 else (&"body.one_collision" if collisions == 1 else (&"body.two_collisions" if collisions == 2 else &"body.three_plus_collisions"))
\t\tMovementProbeCounters.record(bucket, elapsed)
\t\tMovementProbeCounters.count(&"body.slides", collisions)
\t\tMovementProbeCounters.count(&"body.colliding_moves", 1 if collisions > 0 else 0)
'''
        return source

    edit("scripts/battle_unit.gd", unit)
    entries = {
        "scripts/battle_unit.gd": ["_physics_process", "_apply_velocity", "_path_velocity", "_chase_velocity", "_face_direction", "_find_auto_target"],
        "scripts/path_budget.gd": ["next_position", "_physics_process", "try_direct_pursuit"],
        "scripts/unit_render_batches.gd": ["_process"],
        "scripts/unit_visual.gd": ["_synchronize_locomotion", "synchronize_animation"],
    }
    for relative, methods in entries.items():
        for method in methods:
            edit(relative, lambda source, method=method, relative=relative: wrap(source, method, Path(relative).stem + "." + method))


def native_process(command: list[str], log_base: Path, timeout: int) -> dict:
    startup = subprocess.STARTUPINFO() if os.name == "nt" else None
    if startup is not None:
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = subprocess.SW_HIDE
    with log_base.with_suffix(".stdout.log").open("wb") as out, log_base.with_suffix(".stderr.log").open("wb") as err:
        process = subprocess.Popen(command, stdout=out, stderr=err, startupinfo=startup,
                                   creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        print(f"{log_base.name}: PID {process.pid}", flush=True)
        try:
            code = process.wait(timeout=timeout)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=10)
    errors = log_base.with_suffix(".stderr.log").read_text(encoding="utf-8", errors="replace")
    if code or "SCRIPT ERROR" in errors or "ERROR:" in errors:
        raise RuntimeError(f"Command failed ({code}): {log_base}\n{errors[-5000:]}")
    return {"pid": process.pid, "exit_code": code, "command": command}


def build(output: Path, variant: str, base: Path | None = None, refresh_harness: bool = False) -> None:
    output = output.resolve()
    if output.exists():
        raise ValueError("Use a fresh output directory; previous evidence must be preserved")
    project = output / "source"
    project.mkdir(parents=True)
    tracked = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT).decode().split("\0")
    selected = [path for path in tracked if path.startswith(("assets/", "scripts/", "scenes/", "data/", "shaders/", "resources/"))
                or path in ("project.godot", "default_bus_layout.tres")
                or path in HARNESS]
    if base:
        receipt = json.loads((base / "receipt.json").read_text(encoding="utf-8"))
        selected = list(receipt["frozen_source_sha256"])
        for relative, expected in receipt["frozen_source_sha256"].items():
            if digest(base / "source" / relative) != expected:
                raise ValueError(f"Frozen source changed: {relative}")
    hashes = {}
    for relative in sorted(set(selected)):
        source = (base / "source" if base else ROOT) / relative
        if not source.is_file():
            continue
        target = project / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        hashes[relative] = digest(source)
    # Additional validation fixtures do not replace any frozen gameplay source.
    for relative in HARNESS:
        target = project / relative
        source = ROOT / relative
        if not target.exists() and source.is_file():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            hashes[relative] = digest(source)
    # Explicitly update this diagnostic entry point while preserving frozen gameplay.
    if refresh_harness:
        relative = "tests/sandbox_movement_performance.gd"
        source = ROOT / relative
        shutil.copy2(source, project / relative)
        hashes[relative] = digest(source)
    (project / "artifacts").mkdir(exist_ok=True)
    shutil.copytree((base / "source" if base else ROOT) / ".godot/imported", project / ".godot/imported")
    from movement_corridor_probe import corridor_differential_sources
    for relative, source in corridor_differential_sources((project / "scripts/construction_navigation.gd").read_text(encoding="utf-8-sig")).items():
        target = project / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(source, encoding="utf-8")
    if variant in ("path", "combined"):
        from movement_path_candidate import optimize_path_sampling
        path = project / "scripts/path_budget.gd"
        path.write_text(optimize_path_sampling(path.read_text(encoding="utf-8-sig")), encoding="utf-8")
    if variant in ("short-axis", "combined"):
        from movement_corridor_probe import optimize_corridor_short_axis
        path = project / "scripts/construction_navigation.gd"
        path.write_text(optimize_corridor_short_axis(path.read_text(encoding="utf-8-sig")), encoding="utf-8")
    if variant == "profile":
        instrument(project)
    config_path = project / "project.godot"
    config = config_path.read_text(encoding="utf-8-sig")
    if base is None:
        config = replace_once(config, "[application]", '[application]\nrun/main_loop_type="SandboxMovementPerformance"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="jimu-movement-research-20260915"')
        config += '\n[movement_probe]\nprofiled=false\n'
    config = config.replace("profiled=false", "profiled=true" if variant == "profile" else "profiled=false")
    config_path.write_text(config, encoding="utf-8")
    (project / "export_presets.cfg").write_text(f'''[preset.0]
name="Movement Research"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="data/*.json,scenes/maps/*_layout.json,scripts/network/*.crt"
exclude_filter="assets/audio/sources/*"
script_export_mode=2

[preset.0.options]
custom_template/release="{TEMPLATE.as_posix()}"
binary_format/architecture="x86_64"
binary_format/embed_pck=false
application/modify_resources=false
texture_format/s3tc_bptc=true
''', encoding="utf-8")
    bundle = output / "bin"
    bundle.mkdir()
    steps = []
    for name, arguments in (("import", ["--editor", "--import", "--quit"]),
                            ("export", ["--export-pack", "Movement Research", str(bundle / "movement.pck")])):
        steps.append(native_process([str(EDITOR), "--headless", "--path", str(project), *arguments], output / name, 180))
    shutil.copy2(TEMPLATE, bundle / "movement.exe")
    frozen = {str(path.relative_to(project)).replace("\\", "/"): digest(path)
              for path in project.rglob("*") if path.is_file() and ".godot" not in path.relative_to(project).parts}
    receipt = {"variant": variant, "harness_refreshed": refresh_harness, "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
               "workspace_status": subprocess.check_output(["git", "status", "--short"], cwd=ROOT, text=True),
               "input_sha256": hashes, "frozen_source_sha256": frozen,
               "editor_sha256": digest(EDITOR), "template_sha256": digest(TEMPLATE),
               "pck_sha256": digest(bundle / "movement.pck"), "build_steps": steps}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"BUILD_COMPLETE {output}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--base", type=Path)
    parser.add_argument("--refresh-harness", action="store_true", help="Copy the current diagnostic entry point while retaining frozen game files")
    parser.add_argument("--variant", choices=["baseline", "profile", "path", "short-axis", "combined"], default="baseline")
    args = parser.parse_args()
    build(args.output, args.variant, args.base, args.refresh_harness)

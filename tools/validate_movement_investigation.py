"""Validate frozen candidates in an independent copy; never time these FPS."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil

from build_movement_investigation import EDITOR, ROOT, digest, native_process


def validate(build: Path, output: Path, tests: list[str]) -> None:
    build, output = build.resolve(), output.resolve()
    if output.exists():
        raise ValueError("Preserve earlier validation evidence; choose a new directory")
    output.mkdir(parents=True)
    project = output / "source"
    shutil.copytree(build / "source", project)
    extras = ["balance_combat_host.gd", "balance_combat_host.tscn", "movement_corridor_microbenchmark.gd"]
    extra_hashes = {}
    for name in extras:
        source = ROOT / "tests" / name
        shutil.copy2(source, project / "tests" / name)
        extra_hashes[name] = digest(source)
    (project / "artifacts").mkdir(exist_ok=True)
    steps = [native_process([str(EDITOR), "--headless", "--path", str(project), "--editor", "--import", "--quit"], output / "import", 120)]
    for name in tests:
        if name not in {"movement_corridor_microbenchmark", "movement_corridor_probe_test", "movement_navigation_test", "path_budget_test", "path_budget_startup_test"}:
            raise ValueError("Only this investigation's bounded tests are supported")
        command = [str(EDITOR), "--headless", "--path", str(project), "--script", "res://tests/" + name + ".gd"]
        if name == "movement_corridor_microbenchmark":
            command += ["--", "--output=" + str(output / "microbenchmark.json")]
        else:
            command += ["--fixed-fps", "120"]
        steps.append(native_process(command, output / name, 140))
        print((output / (name + ".stdout.log")).read_text(encoding="utf-8", errors="replace")[-1500:], flush=True)
    (output / "validation.json").write_text(json.dumps({"build_receipt_sha256": digest(build / "receipt.json"),
        "extra_fixture_sha256": extra_hashes, "steps": steps, "note": "Headless/fixed FPS used for behavior tests only; CPU microbenchmark records batch time, never game FPS."}, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--test", action="append", required=True)
    args = parser.parse_args()
    validate(args.build, args.output, args.test)

"""Build the packaged multiplayer compatibility fingerprint (UTF-8, deterministic)."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data/block_war/network_manifest.json"


def source_hash(path: Path) -> str:
    data = path.read_bytes()
    if path.suffix in {".gd", ".tscn", ".tres"}:
        # Match the repository's eol=lf policy even in an existing Windows
        # checkout. Binary route resources retain their exact original bytes.
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()


def manifest() -> dict:
    # Include authored map topology and all rule/replication dependencies. Runtime
    # uses this packaged manifest because exported GDScript is remapped to GDC.
    files: set[Path] = set()
    for folder, pattern in (
        ("scripts/block_war", "*.gd"),
        ("scripts/network", "*.gd"),
        ("data/block_war/maps", "*.tres"),
        ("data/block_war/routes", "*.res"),
        ("scenes/block_war", "*.tscn"),
    ):
        files.update((ROOT / folder).rglob(pattern))
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    version = re.search(r'^config/version="([^"]+)"', project, re.M)
    if version is None:
        raise ValueError("project.godot has no release version")
    return {
        "schema": 1,
        "release": version.group(1),
        "physics_ticks_per_second": 30,
        "sha256": {
            path.relative_to(ROOT).as_posix(): source_hash(path)
            for path in sorted(files)
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if a source changed after the last manifest build")
    args = parser.parse_args()
    data = (json.dumps(manifest(), ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_bytes() != data:
            raise SystemExit("Network manifest is stale; run python tools/build_network_manifest.py before export.")
    else:
        OUTPUT.write_bytes(data)
    print(f"Network content: {hashlib.sha256(data).hexdigest()} ({len(manifest()['sha256'])} files)")


if __name__ == "__main__":
    main()

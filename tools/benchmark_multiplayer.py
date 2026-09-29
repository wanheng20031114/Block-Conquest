"""Run paired, interleaved multiplayer A/B benchmarks without changing live scripts.

A restores only the three redundant operations removed by this optimization.
Both variants otherwise use the same current gameplay, scenes and protocol.
Generated reference scripts and engine logs stay in .local/multiplayer-ab.
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
OUT = ROOT / '.local/multiplayer-ab'


def replace_once(source: str, before: str, after: str) -> str:
    if source.count(before) != 1:
        raise ValueError(f'Reference recipe no longer matches current source: {before!r}')
    return source.replace(before, after, 1)


def prepare_reference() -> dict:
    snapshot_path = ROOT / 'scripts/network/war_snapshot.gd'
    coordinator_path = ROOT / 'scripts/network/war_network_match.gd'
    snapshot = snapshot_path.read_text(encoding='utf-8')
    coordinator = coordinator_path.read_text(encoding='utf-8')
    original_sources = {'snapshot': snapshot, 'coordinator': coordinator}
    snapshot = replace_once(snapshot,
        '\tfor key: String in state.fields:\n\t\tvar row: Array = state.fields[key]\n\t\tif row[0] == "shield": continue',
        '\tfor row: Array in state.fields.values():\n\t\tif row[0] == "shield": continue')
    snapshot = replace_once(snapshot, 'seconds: float, _at_time: float) -> void:', 'seconds: float, at_time: float) -> void:')
    snapshot = replace_once(snapshot, '\tvar step: float = game.marches.movement_distance(unit, seconds)',
        '\t_set_field_clock(game, _last_state, at_time, false)\n\tvar step: float = game.marches.movement_distance(unit, seconds)')
    snapshot = replace_once(snapshot, '\t_set_field_clock(game, _last_state, before, false)\n', '')
    coordinator = replace_once(coordinator, 'const RECORD_TIME_INDEX := {"buildings": 11, "factions": 8, "units": 12}\n', '')
    coordinator = replace_once(coordinator, 'RECORD_TIME_INDEX[group]', '{"buildings": 11, "factions": 8, "units": 12}[group]')
    coordinator = replace_once(coordinator, 'else: _send_blob_bytes(kind, bytes, target)', 'else: _send_blob(kind, payload, target)')
    coordinator = replace_once(coordinator, 'res://scripts/network/war_snapshot.gd', 'res://.local/multiplayer-ab/reference/war_snapshot.gd')
    reference = OUT / 'reference'
    reference.mkdir(parents=True, exist_ok=True)
    (reference / 'war_snapshot.gd').write_text(snapshot, encoding='utf-8')
    (reference / 'war_network_match.gd').write_text(coordinator, encoding='utf-8')
    return {label: hashlib.sha256(value.encode()).hexdigest() for label, value in
            {**{f'B_{k}': v for k, v in original_sources.items()}, 'A_snapshot': snapshot, 'A_coordinator': coordinator}.items()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=ROOT / '.local/network/runtime/Godot_v4.7.2-stable_win64.exe')
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--frames', type=int, default=120)
    parser.add_argument('--soldiers', type=int, default=4096)
    parser.add_argument('--timeout', type=int, default=360)
    args = parser.parse_args()
    if min(args.rounds, args.frames, args.soldiers) < 1:
        parser.error('rounds, frames and soldiers must be positive')
    sources = prepare_reference()
    environment = os.environ.copy()
    environment['APPDATA'] = str(OUT / 'userdata')
    Path(environment['APPDATA']).mkdir(parents=True, exist_ok=True)
    engine_log = OUT / 'benchmark.engine.log'
    command = [str(args.godot), '--headless', '--path', str(ROOT), '--log-file', str(engine_log),
               '--script', 'res://tests/block_war_network_benchmark.gd', '--', str(args.rounds), str(args.frames), str(args.soldiers)]
    process = None
    expired = False
    start = time.monotonic()
    with (OUT / 'benchmark.stdout.log').open('wb') as output:
        try:
            process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=output, stderr=subprocess.STDOUT,
                                       creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            expired = True
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=10)
    log = engine_log.read_text(encoding='utf-8', errors='replace')
    results = [json.loads(line.removeprefix('NETWORK_AB ')) for line in log.splitlines() if line.startswith('NETWORK_AB ')]
    receipts = {'sources_sha256': sources, 'pid': process.pid, 'exit_code': process.returncode,
                'timeout': expired, 'exited': process.poll() is not None, 'seconds': round(time.monotonic() - start, 2),
                'rounds': args.rounds, 'frames': args.frames, 'soldiers': args.soldiers, 'results': results,
                'summaries': [line for line in log.splitlines() if line.startswith('NETWORK_AB_CHECKS')],
                'diagnostics': [line for line in log.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:', 'FAIL '))]}
    (OUT / 'benchmark.json').write_text(json.dumps(receipts, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for result in results:
        print(json.dumps(result, ensure_ascii=True), flush=True)
    print(json.dumps({k: v for k, v in receipts.items() if k != 'results'}, ensure_ascii=True))
    script_errors = any(line.startswith(('SCRIPT ERROR:', 'FAIL ')) for line in receipts['diagnostics'])
    completed = len(receipts['summaries']) == 1 and receipts['summaries'][0].endswith('failures=0')
    return 1 if expired or process.returncode != 0 or script_errors or not completed or len(results) != args.rounds * 4 else 0


if __name__ == '__main__':
    sys.exit(main())

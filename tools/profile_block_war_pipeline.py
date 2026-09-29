"""Run the P0 pipeline CPU profile serially, without changing runtime scripts.

The micro pass attributes direct calls and repeated fixed-state subprobes. The
coordinator pass runs actual process() methods with serialized in-memory packets
and virtual packet age. Their results are not additive and are not GPU/FPS data.
The sole Godot child is hidden, timeout-bounded and reaped before this exits.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
SOURCES = (
    'tests/block_war_pipeline_profile.gd', 'tests/block_war_replication_test.gd',
    'tools/profile_block_war_pipeline.py', 'scripts/network/war_network_match.gd',
    'scripts/network/war_snapshot.gd', 'scripts/block_war/block_war.gd',
    'scripts/block_war/war_marches.gd', 'scenes/block_war/marches.tscn',
)


def source_hashes() -> dict[str, str]:
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCES}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=ROOT / '.local/network/runtime/Godot_v4.7.2-stable_win64.exe')
    parser.add_argument('--out', type=Path, default=ROOT / '.local/pipeline-profile')
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--frames', type=int, default=120)
    parser.add_argument('--warmup', type=int, default=30)
    parser.add_argument('--soldiers', type=int, default=4096)
    parser.add_argument('--mode', choices=('both', 'micro', 'coordinator'), default='both')
    parser.add_argument('--timeout', type=int, default=900)
    args = parser.parse_args()
    if min(args.rounds, args.frames, args.soldiers, args.timeout) < 1 or args.warmup < 0 or args.soldiers > 16384:
        parser.error('positive rounds/frames/timeout, nonnegative warmup, and 1..16384 soldiers required')
    args.out.mkdir(parents=True, exist_ok=True)
    args.out = args.out.resolve()
    before = source_hashes()
    engine_log = args.out / 'profile.engine.log'
    stdout_log = args.out / 'profile.stdout.log'
    environment = os.environ.copy()
    environment['APPDATA'] = str(args.out / 'userdata')
    Path(environment['APPDATA']).mkdir(parents=True, exist_ok=True)
    command = [str(args.godot.resolve()), '--headless', '--path', str(ROOT),
               '--log-file', str(engine_log), '--script', 'res://tests/block_war_pipeline_profile.gd',
               '--', str(args.rounds), str(args.frames), str(args.soldiers), str(args.warmup), args.mode]
    process = None
    timed_out = False
    began = time.monotonic()
    with stdout_log.open('wb') as output:
        try:
            process = subprocess.Popen(command, cwd=ROOT, env=environment,
                stdout=output, stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=10)
    # Read this run's truncated stdout, not a possibly stale engine log.
    lines = stdout_log.read_text(encoding='utf-8', errors='replace').splitlines()
    results = [json.loads(line.removeprefix('PIPELINE_PROFILE ')) for line in lines if line.startswith('PIPELINE_PROFILE ')]
    contract = [json.loads(line.removeprefix('PIPELINE_PROFILE_CONTRACT ')) for line in lines if line.startswith('PIPELINE_PROFILE_CONTRACT ')]
    summary = [line for line in lines if line.startswith('PIPELINE_PROFILE_CHECKS ')]
    diagnostics = [line for line in lines if line.startswith(('SCRIPT ERROR:', 'ERROR:', 'FAIL '))]
    after = source_hashes()
    expected = args.rounds * (4 if args.mode == 'both' else 2)
    errors = []
    if timed_out or process.returncode != 0: errors.append('Godot timed out or exited unsuccessfully')
    if len(results) != expected: errors.append(f'Expected {expected} results; got {len(results)}')
    if len(contract) != 1 or len(summary) != 1 or not summary[0].endswith('failures=0'):
        errors.append('Missing complete passing contract/summary')
    if before != after: errors.append('Measured sources changed during the run')
    if any(line != 'ERROR: Failed to read the root certificate store.' for line in diagnostics):
        errors.append('Unexpected engine/script/assertion diagnostics')
    receipt = {'command': command, 'pid': process.pid, 'exit_code': process.returncode,
        'timeout': timed_out, 'exited': process.poll() is not None,
        'seconds': round(time.monotonic() - began, 2), 'source_sha256_before': before,
        'source_sha256_after': after, 'contract': contract, 'results': results,
        'summary': summary, 'diagnostics': diagnostics, 'errors': errors}
    destination = args.out / 'profile.json'
    destination.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for result in results:
        print(json.dumps({key: value for key, value in result.items() if key != 'raw_samples_ms'}, ensure_ascii=True), flush=True)
    print(json.dumps({'receipt': str(destination), 'pid': process.pid, 'exited': receipt['exited'],
        'seconds': receipt['seconds'], 'summary': summary, 'errors': errors}, ensure_ascii=True), flush=True)
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())

"""Compare real client process() motion against a recorded Git baseline.

Headless runs measure the exact position/gait supplied to the renderer, not GPU
readback. The same test also checks MultiMesh readback on a rendered desktop.
All child processes are owned, bounded by a timeout, and reaped in finally.
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
OUT = ROOT / '.local/client-smoothness'
SCRIPT = 'res://tests/block_war_client_motion_test.gd'


def prepare_reference(ref: str) -> dict:
    revision = subprocess.check_output(
        ['git', 'rev-parse', '--verify', f'{ref}^{{commit}}'], cwd=ROOT, text=True).strip()
    destination = OUT / 'reference'
    destination.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for name in ['war_network_match.gd', 'war_snapshot.gd']:
        path = f'scripts/network/{name}'
        source = subprocess.check_output(['git', 'show', f'{revision}:{path}'], cwd=ROOT)
        hashes[path] = hashlib.sha256(source).hexdigest()
        if name == 'war_network_match.gd':
            source = source.replace(b'res://scripts/network/war_snapshot.gd',
                                    b'res://.local/client-smoothness/reference/war_snapshot.gd')
        (destination / name).write_bytes(source)
    return {'revision': revision, 'source_sha256': hashes}


def run(engine: Path, variant: str, round_index: int, timeout: int) -> dict:
    label = f'motion-{round_index}-{variant}'
    log = OUT / (label + '.engine.log')
    env = os.environ.copy()
    env['APPDATA'] = str(OUT / 'userdata' / label)
    Path(env['APPDATA']).mkdir(parents=True, exist_ok=True)
    command = [str(engine), '--headless', '--path', str(ROOT), '--log-file', str(log),
               '--script', SCRIPT]
    if variant == 'baseline': command.extend(['--', '--baseline'])
    process = None
    timed_out = False
    begun = time.monotonic()
    with (OUT / (label + '.stdout.log')).open('wb') as output:
        try:
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=output,
                stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=10)
    lines = log.read_text(encoding='utf-8', errors='replace').splitlines() if log.exists() else []
    result = {'variant': variant, 'round': round_index, 'pid': process.pid,
              'code': process.returncode, 'timeout': timed_out, 'exited': process.poll() is not None,
              'seconds': round(time.monotonic() - begun, 2),
              'metrics': [json.loads(line.removeprefix('CLIENT_MOTION_METRICS '))
                          for line in lines if line.startswith('CLIENT_MOTION_METRICS ')],
              'summary': [line for line in lines if line.startswith('CLIENT_MOTION checks=')],
              'diagnostics': [line for line in lines if line.startswith(('SCRIPT ERROR:', 'ERROR:', 'FAIL '))]}
    for metric in result['metrics']:
        print(json.dumps({'round': round_index, **metric}), flush=True)
    print(json.dumps({key: value for key, value in result.items() if key != 'metrics'}), flush=True)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-ref', default='106b8e5')
    parser.add_argument('--godot', type=Path, default=ROOT / '.local/network/runtime/Godot_v4.7.2-stable_win64.exe')
    parser.add_argument('--rounds', type=int, default=2)
    parser.add_argument('--timeout', type=int, default=120)
    args = parser.parse_args()
    if args.rounds < 1 or args.timeout < 1: parser.error('rounds and timeout must be positive')
    reference = prepare_reference(args.baseline_ref)
    results = []
    for index in range(args.rounds):
        for variant in (['baseline', 'current'] if index % 2 == 0 else ['current', 'baseline']):
            results.append(run(args.godot, variant, index, args.timeout))
    equivalence_errors = []
    for index in range(args.rounds):
        pair = {result['variant']: {metric['case']: metric for metric in result['metrics']}
                for result in results if result['round'] == index}
        for case in ['clean', 'frequent_facts', 'jitter_and_loss']:
            for field in ['host_rule_hash', 'public_rule_hash', 'mirror_hash', 'raw_rule_bytes',
                          'event_sequence', 'rule_tick', 'units']:
                if (case not in pair['baseline'] or case not in pair['current'] or
                        pair['baseline'][case].get(field) != pair['current'][case].get(field)):
                    equivalence_errors.append(f'round {index} {case}: {field}')
    (OUT / 'motion-ab.json').write_text(json.dumps({'reference': reference, 'results': results,
        'equivalence_errors': equivalence_errors},
        ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    if equivalence_errors:
        print(json.dumps({'equivalence_errors': equivalence_errors}), flush=True)
        return 1
    for result in results:
        if result['timeout'] or not result['exited'] or len(result['metrics']) != 3 or len(result['summary']) != 1:
            return 1
        # Baseline behavioral assertions are expected to fail; engine errors are not.
        if any(line.startswith('SCRIPT ERROR:') or (line.startswith('ERROR:') and
               line != 'ERROR: Failed to read the root certificate store.') for line in result['diagnostics']):
            return 1
        if result['variant'] == 'current' and (result['code'] != 0 or not result['summary'][0].endswith('failures=0')):
            return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

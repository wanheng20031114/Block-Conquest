"""Compare C2: skip terrain reprojection for exact-zero elevated ground offsets.

Production files are read only. Reference/candidate scripts and all receipts stay
under .local/surface-projection. Performance runs are headless CPU measurements;
the GDScript fixture also supports native-renderer correctness runs independently.
The pair is rebuilt from current sources, not a complete historical replay.
The sole hidden Godot child is timeout-bounded and reaped in finally.
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
GENERATED = ROOT / '.local/surface-projection'
RUNTIME_SOURCE = ROOT / 'scripts/block_war/war_marches.gd'
SCRIPT = 'res://tests/block_war_surface_projection_test.gd'
SOURCE_PATHS = (
    'scripts/block_war/war_marches.gd', 'scripts/block_war/war_map_definition.gd',
    'scripts/block_war/war_terrain_surface.gd', 'scenes/block_war/marches.tscn',
    'tests/block_war_surface_projection_test.gd', 'tools/benchmark_surface_projection.py',
    'data/block_war/maps/highland.tres', 'data/block_war/maps/terraces.tres',
    'data/block_war/maps/switchback.tres', 'data/block_war/maps/crown.tres',
    'data/block_war/terrain/terraces.res', 'data/block_war/terrain/switchback.res', 'data/block_war/terrain/crown.res',
)
EXPECTED_CASES = {(map_id, scenario) for map_id in ('highland', 'terraces', 'switchback', 'crown')
    for scenario in ('zero_ground', 'mixed_ground', 'nonzero_ground', 'zero_levitating',
                     'mixed_levitating', 'zero_airborne', 'nonzero_airborne')}


def hashes() -> dict[str, str]:
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCE_PATHS}


def make_variants(source: str) -> tuple[str, str, bool]:
    class_line = 'class_name WarMarches\n'
    signature = 'func _presentation_position(unit: MarchUnit) -> Vector3:\n'
    if source.count(class_line) != 1 or source.count(signature) != 1:
        raise ValueError('Candidate recipe does not match the current runtime script')
    prefix = signature + '\tvar at := unit.position + unit.presentation_offset\n'
    original_condition = '\tif map_definition.has_elevation() and not unit.order.airborne:\n'
    narrowed_condition = '\tif map_definition.has_elevation() and not unit.order.airborne and unit.presentation_offset != Vector3.ZERO:\n'
    body = source.split(signature, 1)[1].split('\nfunc ', 1)[0]
    installed = source.count(prefix + narrowed_condition)
    if (installed not in (0, 1) or source.count(prefix + original_condition) != 1 - installed or
            body.count(original_condition) != 1 - installed or body.count(narrowed_condition) != installed or
            'if unit.presentation_offset == Vector3.ZERO:' in body):
        raise ValueError('Terrain condition differs from the exact C2 recipe or occurs more than once')
    reference = source.replace(class_line, '', 1)
    if installed:
        reference = reference.replace(prefix + narrowed_condition, prefix + original_condition, 1)
    candidate = reference.replace(prefix + original_condition, prefix + narrowed_condition, 1)
    if reference == candidate or candidate.replace(prefix + narrowed_condition, prefix + original_condition, 1) != reference:
        raise ValueError('Reference/candidate must differ by exactly the C2 terrain condition')
    return reference, candidate, bool(installed)


def prepare() -> dict:
    reference, candidate, installed = make_variants(RUNTIME_SOURCE.read_text(encoding='utf-8'))
    GENERATED.mkdir(parents=True, exist_ok=True)
    result = {'candidate': 'C2_elevated_ground_zero_offset',
              'recipe': 'Remove class_name from both copies; normalize the exact C2 terrain condition in reference, then add its trailing nonzero-offset condition only in candidate. Preserve the initial position addition and flat/airborne short-circuit paths.',
              'comparison_scope': 'Current-source A/B reconstruction, not a complete historical replay; both variants share every other current-source change.',
              'production_condition_present': installed, 'sha256': {}}
    for label, text in (('reference', reference), ('candidate', candidate)):
        path = GENERATED / f'{label}.gd'
        path.write_text(text, encoding='utf-8', newline='\n')
        result['sha256'][str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=ROOT / '.local/network/runtime/Godot_v4.7.2-stable_win64.exe')
    parser.add_argument('--out', type=Path, default=GENERATED / 'results')
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--iterations', type=int, default=100)
    parser.add_argument('--warmup', type=int, default=10)
    parser.add_argument('--soldiers', type=int, default=4096)
    parser.add_argument('--timeout', type=int, default=900)
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--prepare-only', action='store_true', help='Generate isolated scripts without starting Godot')
    args = parser.parse_args()
    if min(args.rounds, args.iterations, args.timeout) < 1 or args.warmup < 0 or not 8 <= args.soldiers <= 16384:
        parser.error('positive rounds/iterations/timeout, nonnegative warmup, and 8..16384 soldiers required')
    reference = prepare()
    if args.prepare_only:
        print(json.dumps(reference, ensure_ascii=True))
        return 0
    args.out.mkdir(parents=True, exist_ok=True)
    args.out = args.out.resolve()
    before = hashes()
    environment = os.environ.copy()
    environment['APPDATA'] = str(args.out / 'userdata')
    Path(environment['APPDATA']).mkdir(parents=True, exist_ok=True)
    engine_log = args.out / 'surface.engine.log'
    stdout_log = args.out / 'surface.stdout.log'
    command = [str(args.godot.resolve()), '--headless', '--path', str(ROOT), '--log-file', str(engine_log),
               '--script', SCRIPT, '--', f'--rounds={args.rounds}', f'--iterations={args.iterations}',
               f'--soldiers={args.soldiers}', f'--warmup={args.warmup}']
    if args.verify_only:
        command.append('--verify-only')
    process = None
    timed_out = False
    began = time.monotonic()
    with stdout_log.open('wb') as output:
        try:
            process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=output,
                stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=10)
    lines = stdout_log.read_text(encoding='utf-8', errors='replace').splitlines()
    results = [json.loads(line.removeprefix('SURFACE_PROJECTION ')) for line in lines if line.startswith('SURFACE_PROJECTION ')]
    contract = [json.loads(line.removeprefix('SURFACE_PROJECTION_CONTRACT ')) for line in lines if line.startswith('SURFACE_PROJECTION_CONTRACT ')]
    summary = [line for line in lines if line.startswith('SURFACE_PROJECTION_CHECKS ')]
    diagnostics = [line for line in lines if line.startswith(('SCRIPT ERROR:', 'ERROR:', 'FAIL '))]
    after = hashes()
    errors = []
    if timed_out or process.returncode != 0: errors.append('Godot timed out or exited unsuccessfully')
    actual_cases = {(result['map'], result['case']) for result in results}
    if len(results) != len(EXPECTED_CASES) or actual_cases != EXPECTED_CASES:
        errors.append('Missing or duplicate terrain/scenario results')
    if len(contract) != 1 or len(summary) != 1 or not summary[0].endswith('failures=0'):
        errors.append('Missing complete passing contract/summary')
    if before != after: errors.append('Measured sources changed during the run')
    if any(line != 'ERROR: Failed to read the root certificate store.' for line in diagnostics):
        errors.append('Unexpected engine/script/assertion diagnostics')
    for result in results:
        expected_rounds = 0 if args.verify_only else args.rounds
        if len(result['timings']) != expected_rounds: errors.append(f'Wrong timing count for {result["map"]}/{result["case"]}')
    receipt = {'reference': reference, 'command': command, 'pid': process.pid,
        'exit_code': process.returncode, 'timeout': timed_out, 'exited': process.poll() is not None,
        'seconds': round(time.monotonic() - began, 2), 'source_sha256_before': before,
        'source_sha256_after': after, 'contract': contract, 'results': results,
        'summary': summary, 'diagnostics': diagnostics, 'errors': errors}
    destination = args.out / 'surface.json'
    destination.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for result in results:
        compact = {key: value for key, value in result.items() if key != 'timings'}
        compact['timings'] = [{key: value for key, value in timing.items() if key != 'raw_samples_ms'} for timing in result['timings']]
        print(json.dumps(compact, ensure_ascii=True), flush=True)
    print(json.dumps({'receipt': str(destination), 'pid': process.pid, 'exited': receipt['exited'],
        'seconds': receipt['seconds'], 'summary': summary, 'errors': errors}, ensure_ascii=True), flush=True)
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())

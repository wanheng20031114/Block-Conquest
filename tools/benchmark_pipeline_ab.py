"""Run an interleaved whole-pipeline A/B against a frozen Git reference.

Both variants live in one Godot process, have independent real battles and wire
queues, and alternate execution order every frame. Generated coordinator copies
use the same virtual millisecond clock; CPU timers still use the real clock.
Production files are read only, hashed before/after, and never swapped in place.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.local/pipeline-ab'
SCRIPT = 'res://tests/block_war_pipeline_ab_test.gd'
FILES = {
    'war_marches.gd': 'scripts/block_war/war_marches.gd',
    'block_war.gd': 'scripts/block_war/block_war.gd',
    'war_network_match.gd': 'scripts/network/war_network_match.gd',
    'war_snapshot.gd': 'scripts/network/war_snapshot.gd',
    'marches.tscn': 'scenes/block_war/marches.tscn',
    'block_war.tscn': 'scenes/block_war/block_war.tscn',
}
OVERRIDES = ('_movement_segment', '_presentation_position', '_render')
SOURCES = (*FILES.values(), 'scripts/block_war/war_map_definition.gd',
           'scripts/block_war/war_terrain_surface.gd', 'scripts/network/war_protocol.gd',
           'tests/block_war_replication_test.gd', 'tests/block_war_pipeline_profile.gd',
           'tests/block_war_pipeline_ab_test.gd', 'tools/benchmark_pipeline_ab.py')
CODEC_PROBE = '''extends "%(source)s"
var bench_install_usec := 0
var bench_install_calls := 0
var bench_present_usec := 0
var bench_present_calls := 0

func install(game: Node, state: Dictionary, at_time: float = -1.0, public_view: bool = false, defer_render: bool = false) -> bool:
	var began := Time.get_ticks_usec()
	var changed: bool = super.install(game, state, at_time, public_view, defer_render)
	bench_install_usec += Time.get_ticks_usec() - began
	bench_install_calls += 1
	return changed

func present(game: Node, state: Dictionary, delta: float) -> void:
	var began := Time.get_ticks_usec()
	super.present(game, state, delta)
	bench_present_usec += Time.get_ticks_usec() - began
	bench_present_calls += 1
'''


def hashes() -> dict[str, str]:
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCES}


def methods(source: str) -> dict[str, str]:
    declarations = list(re.finditer(r'^func (\w+)\(', source, re.MULTILINE))
    return {match.group(1): source[match.start():
        declarations[index + 1].start() if index + 1 < len(declarations) else len(source)].strip()
        for index, match in enumerate(declarations)}


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if source.count(old) != 1:
        raise ValueError(f'{label}: expected one source anchor')
    return source.replace(old, new)


def prepare(reference: str) -> dict:
    revision = subprocess.check_output(['git', 'rev-parse', '--verify', reference + '^{commit}'],
                                       cwd=ROOT, text=True).strip()
    original = {name: subprocess.check_output(['git', 'show', f'{revision}:{path}'], cwd=ROOT)
                .decode('utf-8').replace('\r\n', '\n') for name, path in FILES.items()}
    current = {name: (ROOT / path).read_text(encoding='utf-8') for name, path in FILES.items()}
    old_methods, new_methods = methods(original['war_marches.gd']), methods(current['war_marches.gd'])
    for name in OVERRIDES:
        if name not in old_methods or name not in new_methods:
            raise ValueError(f'Missing required WarMarches method: {name}')
    unexpected = [name for name, body in old_methods.items()
                  if name not in OVERRIDES and new_methods.get(name) != body]
    if unexpected:
        raise ValueError('Shared WarMarches functions changed outside the isolated recipe: ' + ', '.join(unexpected))
    changes = {name: old_methods[name] != new_methods[name] for name in OVERRIDES}
    generated = {}
    clock_calls = {}
    for variant, source in (('reference', original), ('candidate', current)):
        prefix = f'res://.local/pipeline-ab/{variant}/'
        files = dict(source)
        # All gameplay helpers retain the canonical nested unit/order types.
        # The reference overrides only the three optimized methods. Every other
        # inherited original method was checked byte-for-byte above.
        files['war_marches.gd'] = 'extends "res://scripts/block_war/war_marches.gd"\n'
        if variant == 'reference':
            files['war_marches.gd'] += '\n\n'.join(old_methods[name] for name in OVERRIDES) + '\n'
        files['war_snapshot_probe.gd'] = CODEC_PROBE % {'source': prefix + 'war_snapshot.gd'}
        redirects = {
            'block_war.gd': [('res://scripts/network/war_network_match.gd', prefix + 'war_network_match.gd')],
            'war_network_match.gd': [('res://scripts/network/war_snapshot.gd', prefix + 'war_snapshot_probe.gd')],
            'marches.tscn': [('res://scripts/block_war/war_marches.gd', prefix + 'war_marches.gd')],
            'block_war.tscn': [('res://scripts/block_war/block_war.gd', prefix + 'block_war.gd'),
                               ('res://scenes/block_war/marches.tscn', prefix + 'marches.tscn')],
        }
        for name, pairs in redirects.items():
            for old, new in pairs:
                files[name] = replace_once(files[name], old, new, f'{variant}/{name}')
        count = files['war_network_match.gd'].count('Time.get_ticks_msec()')
        if count < 1: raise ValueError('Coordinator no longer contains the expected wall clock calls')
        clock_calls[variant] = count
        files['war_network_match.gd'] = files['war_network_match.gd'].replace(
            'Time.get_ticks_msec()', '_bench_clock_msec()')
        files['war_network_match.gd'] += '\nvar bench_now_ms := 10000\n\nfunc _bench_clock_msec() -> int:\n\treturn bench_now_ms\n'
        destination = OUT / variant
        destination.mkdir(parents=True, exist_ok=True)
        for name, content in files.items():
            data = content.encode('utf-8')
            (destination / name).write_bytes(data)
            generated[f'{variant}/{name}'] = hashlib.sha256(data).hexdigest()
    receipt = {'reference_revision': revision, 'method_changes': changes,
        'source_sha256': {FILES[name]: hashlib.sha256(source.encode('utf-8')).hexdigest()
                          for name, source in original.items()},
        'generated_sha256': generated, 'virtualized_clock_calls': clock_calls,
        'recipe': 'Reference battle/coordinator/snapshot/scenes are from Git. WarMarches preserves the current canonical nested types and overrides exactly three original methods; all other original methods must match. Candidate copies current production scripts/scenes. Both codecs receive identical inclusive install/present timers and coordinators receive an identical virtual millisecond clock.'}
    (OUT / 'preparation.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', default='de06d22')
    parser.add_argument('--godot', type=Path, default=ROOT / '.local/network/runtime/Godot_v4.7.2-stable_win64.exe')
    parser.add_argument('--out', type=Path, default=OUT / 'results')
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--frames', type=int, default=60)
    parser.add_argument('--warmup', type=int, default=10)
    parser.add_argument('--soldiers', type=int, default=4096)
    parser.add_argument('--map', default='crown', choices=('highland', 'crown'))
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--allow-identical', action='store_true', help='Permit harness smoke tests before the production optimizations are applied')
    args = parser.parse_args()
    if min(args.rounds, args.frames, args.soldiers, args.timeout) < 1 or args.soldiers > 16384 or args.warmup < 0:
        parser.error('positive rounds/frames/timeout, nonnegative warmup, and 1..16384 soldiers required')
    preparation = prepare(args.reference)
    if args.prepare_only:
        print(json.dumps(preparation, ensure_ascii=False), flush=True)
        return 0
    if not any(preparation['method_changes'].values()) and not args.allow_identical:
        parser.error('Reference and candidate methods are identical; apply the production changes or explicitly request --allow-identical for a harness smoke test')
    args.out.mkdir(parents=True, exist_ok=True)
    output = args.out.resolve()
    before = hashes()
    environment = os.environ.copy()
    environment['APPDATA'] = str(output / 'userdata')
    Path(environment['APPDATA']).mkdir(parents=True, exist_ok=True)
    command = [str(args.godot.resolve()), '--headless', '--path', str(ROOT),
        '--log-file', str(output / 'engine.log'), '--script', SCRIPT, '--',
        f'--rounds={args.rounds}', f'--frames={args.frames}', f'--warmup={args.warmup}',
        f'--soldiers={args.soldiers}', f'--map={args.map}']
    process = None
    timed_out = False
    begun = time.monotonic()
    with (output / 'stdout.log').open('wb') as stream:
        try:
            process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=stream,
                stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=10)
    lines = (output / 'stdout.log').read_text(encoding='utf-8', errors='replace').splitlines()
    results = [json.loads(line.removeprefix('PIPELINE_AB_RESULT ')) for line in lines if line.startswith('PIPELINE_AB_RESULT ')]
    contract = [json.loads(line.removeprefix('PIPELINE_AB_CONTRACT ')) for line in lines if line.startswith('PIPELINE_AB_CONTRACT ')]
    summary = [line for line in lines if line.startswith('PIPELINE_AB_CHECKS ')]
    diagnostics = [line for line in lines if line.startswith(('SCRIPT ERROR:', 'ERROR:', 'FAIL '))]
    after = hashes()
    errors = []
    if timed_out or process.returncode != 0: errors.append('Godot timed out or exited unsuccessfully')
    if len(results) != args.rounds * 2: errors.append('Missing paired case/round results')
    expected = {(index, case) for index in range(args.rounds) for case in ('ordinary_march', 'overlapping_fields')}
    if {(result['round'], result['case']) for result in results} != expected: errors.append('Case/round coverage mismatch')
    if len(contract) != 1 or len(summary) != 1 or not summary[0].endswith('failures=0'):
        errors.append('Missing complete passing contract/summary')
    if before != after: errors.append('Measured sources changed during the run')
    if any(line != 'ERROR: Failed to read the root certificate store.' for line in diagnostics):
        errors.append('Unexpected engine/script/assertion diagnostics')
    receipt = {'preparation': preparation, 'command': command, 'pid': process.pid,
        'exit_code': process.returncode, 'timeout': timed_out, 'exited': process.poll() is not None,
        'seconds': round(time.monotonic() - begun, 2), 'source_sha256_before': before,
        'source_sha256_after': after, 'contract': contract, 'results': results,
        'summary': summary, 'diagnostics': diagnostics, 'errors': errors}
    path = output / 'pipeline-ab.json'
    path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for result in results:
        print(json.dumps({key: value for key, value in result.items() if key != 'raw_samples_ms'}, ensure_ascii=True), flush=True)
    print(json.dumps({'receipt': str(path), 'seconds': receipt['seconds'], 'pid': process.pid,
        'exited': receipt['exited'], 'summary': summary, 'errors': errors}, ensure_ascii=True), flush=True)
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())

"""Prepare and compare an isolated synchronous MultiMesh batching candidate.

Production sources are never rewritten. Headless runs validate rules, events and
render inputs; use run_godot_private_desktop.py for actual MultiMesh readback.
The GDScript benchmark alternates the A/B measurement order every sample and
keeps assertions, fixture staging and snapshot capture outside timed regions.
The pair is rebuilt from current sources, not a complete historical replay.
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
OUT = ROOT / '.local/render-batch'
SCRIPT = 'res://tests/block_war_render_batch_test.gd'
SOURCES = {
    'block_war.gd': 'scripts/block_war/block_war.gd',
    'war_network_match.gd': 'scripts/network/war_network_match.gd',
    'war_snapshot.gd': 'scripts/network/war_snapshot.gd',
    'block_war.tscn': 'scenes/block_war/block_war.tscn',
    'marches.tscn': 'scenes/block_war/marches.tscn',
}

# Exact wrappers can be present in production after adoption. Normalize those
# four call sites before creating the pair, keeping all other current code.
BATCH_WRAPPERS = {
    'block_war.gd': (
        ('\tvar remaining := delta\n\twhile remaining > 0.0 and not finished:',
         '\tmarches.begin_render_batch()\n\tvar remaining := delta\n\twhile remaining > 0.0 and not finished:',
         'simulate begin'),
        ('\t\tremaining = maxf(0.0, remaining - step)\n\nfunc _simulate_step',
         '\t\tremaining = maxf(0.0, remaining - step)\n\tmarches.end_render_batch()\n\nfunc _simulate_step',
         'simulate end'),
    ),
    'war_network_match.gd': (
        ('\tif online.is_host:\n\t\t_set_transport_paused(false)\n',
         '\tif online.is_host:\n\t\t_set_transport_paused(false)\n\t\tgame.marches.begin_render_batch()\n',
         'host begin'),
        ('\t\t\t\t_publish_step(STEP)\n\t\t_since_time += delta',
         '\t\t\t\t_publish_step(STEP)\n\t\tgame.marches.end_render_batch()\n\t\t_since_time += delta',
         'host end'),
    ),
}

# Inheritance preserves WarMarches.MarchUnit/MarchOrder identity for all the
# production helpers. A full script copy would introduce incompatible types.
# These counters deliberately omit the underscore used by production batching.
# Overridden begin/end keep the inherited _render_batch_depth at zero, so
# super._render() remains an immediate submission in both experimental variants.
MARCHES = '''extends "res://scripts/block_war/war_marches.gd"
const BATCHED := %(batched)s
var render_calls := 0
var render_requests := 0
var render_batch_depth := 0
var render_pending := false

func begin_render_batch() -> void:
	render_batch_depth += 1

func end_render_batch() -> void:
	assert(render_batch_depth > 0)
	render_batch_depth -= 1
	if render_batch_depth == 0 and render_pending:
		_commit_render()

func _render() -> void:
	render_requests += 1
	if BATCHED and render_batch_depth > 0:
		render_pending = true
		return
	_commit_render()

func _commit_render() -> void:
	render_pending = false
	render_calls += 1
	super._render()
'''


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if source.count(old) != 1:
        raise ValueError(f'{label}: expected exactly one source anchor')
    return source.replace(old, new)


def normalize_batches(sources: dict[str, str]) -> tuple[dict[str, str], list[str]]:
    normalized = dict(sources)
    removed = []
    for name, wrappers in BATCH_WRAPPERS.items():
        source = sources[name]
        present = [source.count(batched) for _, batched, _ in wrappers]
        if present not in ([0, 0], [1, 1]):
            raise ValueError(f'{name}: batching wrappers must be an exact balanced pair')
        if (source.count('marches.begin_render_batch()') != present[0] or
                source.count('marches.end_render_batch()') != present[1]):
            raise ValueError(f'{name}: unknown or duplicate batching call site')
        if present == [1, 1]:
            for plain, batched, label in wrappers:
                source = replace_once(source, batched, plain, f'normalize {label}')
            removed.append(name)
        normalized[name] = source
    return normalized, removed


def add_batches(sources: dict[str, str]) -> dict[str, str]:
    candidate = dict(sources)
    for name, wrappers in BATCH_WRAPPERS.items():
        for plain, batched, label in wrappers:
            candidate[name] = replace_once(candidate[name], plain, batched, label)
        if candidate[name] == sources[name]:
            raise ValueError(f'{name}: reference and candidate batching scopes are identical')
    return candidate


def prepare() -> dict:
    original = {name: (ROOT / path).read_text(encoding='utf-8')
                for name, path in SOURCES.items()}
    reference, removed = normalize_batches(original)
    candidate = add_batches(reference)
    if normalize_batches(candidate)[0] != reference:
        raise ValueError('Candidate normalization must reproduce the exact current-source reference')
    hashes = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
              for path in [*SOURCES.values(), 'scripts/block_war/war_marches.gd']}
    generated = {}
    for variant in ('reference', 'candidate'):
        prefix = f'res://.local/render-batch/{variant}/'
        files = dict(reference if variant == 'reference' else candidate)
        files['war_marches.gd'] = MARCHES % {'batched': str(variant == 'candidate').lower()}
        redirects = {
            'block_war.gd': [('res://scripts/network/war_network_match.gd', prefix + 'war_network_match.gd')],
            'war_network_match.gd': [('res://scripts/network/war_snapshot.gd', prefix + 'war_snapshot.gd')],
            'block_war.tscn': [('res://scripts/block_war/block_war.gd', prefix + 'block_war.gd'),
                               ('res://scenes/block_war/marches.tscn', prefix + 'marches.tscn')],
            'marches.tscn': [('res://scripts/block_war/war_marches.gd', prefix + 'war_marches.gd')],
        }
        for name, pairs in redirects.items():
            for old, new in pairs:
                files[name] = replace_once(files[name], old, new, f'{variant}/{name}')
        destination = OUT / variant
        destination.mkdir(parents=True, exist_ok=True)
        for name, source in files.items():
            data = source.encode('utf-8')
            (destination / name).write_bytes(data)
            generated[f'{variant}/{name}'] = hashlib.sha256(data).hexdigest()
    receipt = {
        'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'source_sha256': hashes,
        'generated_sha256': generated,
        'comparison_scope': 'Current-source A/B reconstruction, not a complete historical replay; both variants share every other current-source change.',
        'production_wrappers_removed': removed,
        'shared_dependencies': 'All dependencies other than the generated battle, coordinator, snapshot and scenes remain production resources. WarMarches is inherited to retain nested class identity.',
    }
    (OUT / 'preparation.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return receipt


def run(args: argparse.Namespace, round_index: int) -> dict:
    label = f'paired-{round_index}'
    log = OUT / (label + '.engine.log')
    env = os.environ.copy()
    env['APPDATA'] = str(OUT / 'userdata' / label)
    Path(env['APPDATA']).mkdir(parents=True, exist_ok=True)
    command = [str(args.godot.resolve()), '--headless', '--path', str(ROOT),
               '--log-file', str(log), '--script', SCRIPT, '--',
               f'--samples={args.samples}', f'--warmup={args.warmup}',
               f'--soldiers={args.soldiers}', f'--round={round_index}']
    process = None
    timed_out = False
    started = time.monotonic()
    with (OUT / (label + '.stdout.log')).open('wb') as output:
        try:
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=output,
                stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=10)
    lines = log.read_text(encoding='utf-8', errors='replace').splitlines() if log.exists() else []
    result = {'round': round_index, 'pid': process.pid, 'exit_code': process.returncode,
              'timeout': timed_out, 'exited': process.poll() is not None,
              'seconds': round(time.monotonic() - started, 2),
              'metrics': [json.loads(line.removeprefix('RENDER_BATCH_METRICS '))
                          for line in lines if line.startswith('RENDER_BATCH_METRICS ')],
              'summary': [line for line in lines if line.startswith('RENDER_BATCH checks=')],
              'diagnostics': [line for line in lines if line.startswith(('SCRIPT ERROR:', 'ERROR:', 'FAIL '))]}
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--godot', type=Path, default=ROOT / '.local/network/runtime/Godot_v4.7.2-stable_win64.exe')
    parser.add_argument('--rounds', type=int, default=2)
    parser.add_argument('--samples', type=int, default=80)
    parser.add_argument('--warmup', type=int, default=8)
    parser.add_argument('--soldiers', type=int, default=2048)
    parser.add_argument('--timeout', type=int, default=180)
    args = parser.parse_args()
    if min(args.rounds, args.samples, args.soldiers, args.timeout) < 1 or args.warmup < 0:
        parser.error('rounds, samples, soldiers, timeout must be positive; warmup must be nonnegative')
    preparation = prepare()
    if args.prepare_only:
        print(json.dumps({'prepared': str(OUT), **preparation}, ensure_ascii=False))
        return 0
    results = [run(args, index) for index in range(args.rounds)]
    (OUT / 'benchmark.json').write_text(json.dumps({'preparation': preparation, 'results': results},
        ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for result in results:
        if (result['timeout'] or not result['exited'] or result['exit_code'] != 0 or
                len(result['metrics']) != 4 or len(result['summary']) != 1 or
                not result['summary'][0].endswith('failures=0')):
            return 1
        if any(line != 'ERROR: Failed to read the root certificate store.' for line in result['diagnostics']):
            return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

"""Attribute single-player CPU spikes with five real AI seats, serially.

The original acquire_targets body and the current implementation run in separate
hidden Godot children using the same synthetic midgame fixture and fixed seed.
Inclusive method elapsed timings include scheduling waits, not thread CPU time.
Whole-process Windows CPU totals are separate; neither metric implies GPU/FPS.
Every frame is retained; exact initial/final state hashes and frame rule counts
must agree. Children are timeout-bounded and reaped in finally blocks.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = 'res://tests/block_war_singleplayer_profile.gd'
SCRIPT_PATH = ROOT / 'tests/block_war_singleplayer_profile.gd'
PREFIX = 'SINGLEPLAYER_PROFILE_RESULT '
CONTRACT_PREFIX = 'SINGLEPLAYER_PROFILE_CONTRACT '
ALLOWED_DIAGNOSTICS = {'ERROR: Failed to read the root certificate store.'}
AI_REFERENCE_TEST = ROOT / 'tests/block_war_ai_damage_benchmark.gd'
AI_REFERENCE_DIRECTORY = ROOT / '.local/singleplayer-reference'
AI_REFERENCE_FUNCTION_SHA256 = '684e63adb528747a03fe523764125044afc5c717dad99d6ef13bd0d26d9628bc'
ZONE_REFERENCE_FUNCTION_SHA256 = '153ba6819cb87d922af7d88356e1af2b186e30dcca6a44e83029b56570c49c63'
AI_LIGHTENING_REVISION = '035db7c7d7fc7ecaf3f303efa02f482334696105'
AI_LIGHTENING_SHA256 = {
    'war_ai.gd': '39e4805ff1e3717f6c5264553d02d28a3768fd0711a7fc218dc7915a1a63ad1a',
    'war_ai_skills.gd': '1d7bfdca44f179c15282a9f5b08e7f7e118242c139bf8a93ca19c375746291da',
    'war_ai_information.gd': 'b63fb6d69a3ee655ecb834b1f9ac11534054fd4de762cebff7e009456e1ee684',
}
RULE_FIELDS = ('frame', 'elapsed', 'simulate_calls', 'substep_calls', 'tower_calls',
               'target_calls', 'selected_targets', 'march_tick_calls', 'render_calls',
               'render_submissions', 'ai_calls', 'hud_calls', 'before', 'after',
               'tower_projectiles', 'orb_projectiles', 'weak_fields', 'haste_fields',
               'fire_fields', 'new_haste_zones', 'finished')


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def windows_process_cpu_times(handle: int) -> dict:
    """Read whole-process CPU usage while Popen still owns its Windows handle."""
    if os.name != 'nt':
        raise OSError('GetProcessTimes requires Windows')
    kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
    get_process_times = kernel32.GetProcessTimes
    get_process_times.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
    get_process_times.restype = wintypes.BOOL
    creation, exit_time, kernel, user = (wintypes.FILETIME() for _ in range(4))
    if not get_process_times(wintypes.HANDLE(handle), ctypes.byref(creation), ctypes.byref(exit_time),
                             ctypes.byref(kernel), ctypes.byref(user)):
        raise ctypes.WinError(ctypes.get_last_error())
    user_ticks = (user.dwHighDateTime << 32) | user.dwLowDateTime
    kernel_ticks = (kernel.dwHighDateTime << 32) | kernel.dwLowDateTime
    return {'status': 'ok', 'source': 'Windows GetProcessTimes',
            'scope': 'All Godot process threads for its full lifetime, including setup, checkpoint capture and shutdown; not an AI stage timer',
            'user_100ns': user_ticks, 'kernel_100ns': kernel_ticks,
            'user_seconds': user_ticks / 10_000_000,
            'kernel_seconds': kernel_ticks / 10_000_000,
            'total_seconds': (user_ticks + kernel_ticks) / 10_000_000}


def source_hashes(map_id: str, include_ai_reference: bool = False) -> dict[str, str]:
    paths = set((ROOT / 'scripts').rglob('*.gd'))
    paths.update((ROOT / 'scenes/block_war').rglob('*.tscn'))
    paths.update((ROOT / 'data/block_war/maps').glob('*.tres'))
    paths.update((ROOT / 'data/block_war/terrain').glob('*.res'))
    paths.update([SCRIPT_PATH, Path(__file__).resolve(), ROOT / 'project.godot',
                  ROOT / f'data/block_war/routes/{map_id}.res'])
    if include_ai_reference: paths.add(AI_REFERENCE_TEST)
    return {p.relative_to(ROOT).as_posix(): file_hash(p) for p in sorted(paths)}


def replace_once(source: str, old: str, new: str) -> str:
    if source.count(old) != 1:
        raise ValueError(f'Expected exactly one reference-module substitution: {old}')
    return source.replace(old, new, 1)


def build_ai_reference() -> tuple[dict[Path, str], dict]:
    """Freeze incoming_damage and route the current snapshot API through it."""
    frozen = AI_REFERENCE_TEST.read_text(encoding='utf-8')
    start_marker, end_marker = '# BEGIN_REFERENCE_DAMAGE\n', '# END_REFERENCE_DAMAGE'
    if frozen.count(start_marker) != 1 or frozen.count(end_marker) != 1:
        raise ValueError('Expected one frozen incoming-damage reference body')
    body = frozen.split(start_marker, 1)[1].split(end_marker, 1)[0].strip() + '\n'
    body_hash = hashlib.sha256(body.encode('utf-8')).hexdigest()
    if body_hash != AI_REFERENCE_FUNCTION_SHA256:
        raise ValueError('Frozen incoming-damage reference SHA-256 changed')
    reference_method = replace_once(body, 'func reference_damage(', 'static func incoming_damage(')
    reference_method = replace_once(reference_method, 'INFORMATION.is_unit_known(', 'is_unit_known(')
    source_directory = ROOT / 'scripts/block_war'
    information = (source_directory / 'war_ai_information.gd').read_text(encoding='utf-8')
    signature = 'static func incoming_damage('
    if information.count(signature) != 1:
        raise ValueError('Expected one production incoming-damage method')
    start = information.index(signature)
    end = information.find('\nstatic func ', start + len(signature))
    if end == -1: end = len(information)
    information = information[:start] + reference_method + '\n' + information[end:].lstrip('\n')
    snapshot_signature = 'static func snapshot_defense(game: Node3D, faction: int) -> IncomingSnapshot:'
    if information.count(snapshot_signature) != 1:
        raise ValueError('Expected one production defense-snapshot method')
    snapshot_adapter = (snapshot_signature + '\n'
                        '\t# Legacy reference: observe once, then run frozen damage for each allied building.\n'
                        '\tvar result := IncomingSnapshot.new()\n'
                        '\tresult.counts = snapshot_incoming(game, faction)\n'
                        '\tfor building: WarBuilding in game.buildings:\n'
                        '\t\tif game.FACTIONS.allied(building.faction, faction):\n'
                        '\t\t\tresult.damage[building.building_id] = incoming_damage(game, building, result.counts, faction)\n'
                        '\treturn result\n')
    start = information.index(snapshot_signature)
    end = information.index('\nstatic func ', start + len(snapshot_signature))
    information = information[:start] + snapshot_adapter + '\n' + information[end:].lstrip('\n')
    source_info = 'preload("res://scripts/block_war/war_ai_information.gd")'
    reference_info = 'preload("res://.local/singleplayer-reference/war_ai_information.gd")'
    skills = replace_once((source_directory / 'war_ai_skills.gd').read_text(encoding='utf-8'),
                          source_info, reference_info)
    strategy = replace_once((source_directory / 'war_ai.gd').read_text(encoding='utf-8'),
                            source_info, reference_info)
    strategy = replace_once(strategy, 'preload("res://scripts/block_war/war_ai_skills.gd")',
                            'preload("res://.local/singleplayer-reference/war_ai_skills.gd")')
    generated = {AI_REFERENCE_DIRECTORY / 'war_ai_information.gd': information,
                 AI_REFERENCE_DIRECTORY / 'war_ai_skills.gd': skills,
                 AI_REFERENCE_DIRECTORY / 'war_ai.gd': strategy}
    return generated, {'frozen_source': AI_REFERENCE_TEST.relative_to(ROOT).as_posix(),
                       'frozen_function_sha256': body_hash,
                       'snapshot_adapter_sha256': hashlib.sha256(snapshot_adapter.encode('utf-8')).hexdigest(),
                       'generated_sha256_expected': {path.relative_to(ROOT).as_posix():
                           hashlib.sha256(text.encode('utf-8')).hexdigest()
                           for path, text in generated.items()},
                       'scope': 'incoming_damage is frozen; snapshot_defense adapts the current API by calling snapshot_incoming and frozen incoming_damage for every allied building; strategy/skills change only INFORMATION and SKILL_TACTICS preload paths'}


def generated_hashes(paths: dict[Path, str]) -> dict[str, str | None]:
    return {path.relative_to(ROOT).as_posix(): file_hash(path) if path.is_file() else None
            for path in paths}


def inner_profile_class(name: str, following: str) -> str:
    source = SCRIPT_PATH.read_text(encoding='utf-8')
    start = source.index(f'class {name} extends ')
    end = source.index(f'\nclass {following} extends ', start)
    lines = source[start:end].splitlines()[1:]
    return '\n'.join(line[1:] if line.startswith('\t') else line for line in lines).strip('\n') + '\n'


def build_ai_lightening(scope: str, detailed: bool) -> tuple[dict[Path, str], dict]:
    """Compare against the complete fixed 035db7c AI baseline, not f5c0cc8."""
    frozen = {}
    for name, expected in AI_LIGHTENING_SHA256.items():
        process = subprocess.run(['git', 'show', f'{AI_LIGHTENING_REVISION}:scripts/block_war/{name}'],
            cwd=ROOT, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        if hashlib.sha256(process.stdout).hexdigest() != expected:
            raise ValueError(f'035db7c frozen AI source hash changed: {name}')
        frozen[name] = process.stdout.decode('utf-8')
    current = {name: (ROOT / 'scripts/block_war' / name).read_text(encoding='utf-8')
               for name in AI_LIGHTENING_SHA256}
    selected = {'war_ai_information.gd'}
    if scope in ('strategy', 'both'): selected.add('war_ai.gd')
    if scope in ('skills', 'both'): selected.add('war_ai_skills.gd')
    generated = {}
    scripts = {}
    provenance = {}
    directory = ROOT / '.local/ai-lightening-035db7c' / scope / ('detailed' if detailed else 'plain')
    for variant in ('baseline', 'candidate'):
        folder = directory / variant
        prefix = 'res://' + folder.relative_to(ROOT).as_posix()
        source = {name: current[name] if variant == 'candidate' and name in selected else frozen[name]
                  for name in AI_LIGHTENING_SHA256}
        provenance[variant] = {name: 'current' if variant == 'candidate' and name in selected else AI_LIGHTENING_REVISION
                               for name in source}
        for name in ('war_ai.gd', 'war_ai_skills.gd'):
            source[name] = replace_once(source[name], 'preload("res://scripts/block_war/war_ai_information.gd")',
                                        f'preload("{prefix}/war_ai_information.gd")')
        source['war_ai.gd'] = replace_once(source['war_ai.gd'], 'preload("res://scripts/block_war/war_ai_skills.gd")',
                                          f'preload("{prefix}/war_ai_skills.gd")')
        for name, text in source.items(): generated[folder / name] = text
        scripts[variant] = prefix + '/war_ai.gd'
        if detailed:
            skills = f'extends "{prefix}/war_ai_skills.gd"\n' + inner_profile_class('ProfileSkills', 'ProfileStrategy')
            strategy = f'extends "{prefix}/war_ai.gd"\n' + inner_profile_class('ProfileStrategy', 'ProfileGame')
            strategy = replace_once(strategy, 'ProfileSkills.new(controlled_faction)',
                                    f'preload("{prefix}/profile_skills.gd").new(controlled_faction)')
            strategy = replace_once(strategy, '(_skills as ProfileSkills).reset_profile()', '_skills.reset_profile()')
            generated[folder / 'profile_skills.gd'] = skills
            generated[folder / 'profile_strategy.gd'] = strategy
            scripts[variant] = prefix + '/profile_strategy.gd'
    return generated, {'revision': AI_LIGHTENING_REVISION, 'scope': scope,
        'frozen_source_sha256': AI_LIGHTENING_SHA256, 'module_provenance': provenance,
        'strategy_scripts': scripts,
        'generated_sha256_expected': {path.relative_to(ROOT).as_posix(): hashlib.sha256(text.encode('utf-8')).hexdigest()
                                      for path, text in generated.items()},
        'global_algorithms': 'Both variants use current acquire_targets and _zone_intervals',
        'limits': 'Current information accompanies selected candidate strategy/skills because their new API is a shared dependency'}


def targeting_body_hash() -> str:
    source = SCRIPT_PATH.read_text(encoding='utf-8')
    start = source.index('\tfunc _baseline_acquire_targets(')
    end = source.index('\n\tfunc _render()', start)
    method = source[start:end].strip('\n')
    method = '\n'.join(line[1:] if line.startswith('\t') else line for line in method.splitlines())
    method = method.replace('func _baseline_acquire_targets(', 'func acquire_targets(', 1)
    return hashlib.sha256((method + '\n').encode('utf-8')).hexdigest()


def zone_body_hash() -> str:
    source = SCRIPT_PATH.read_text(encoding='utf-8')
    start = source.index('\tfunc _baseline_zone_intervals(')
    end = source.index('\n\tfunc create_haste_zone(', start)
    method = source[start:end].strip('\n')
    method = '\n'.join(line[1:] if line.startswith('\t') else line for line in method.splitlines())
    method = method.replace('func _baseline_zone_intervals(', 'func _zone_intervals(', 1)
    actual = hashlib.sha256((method + '\n').encode('utf-8')).hexdigest()
    if actual != ZONE_REFERENCE_FUNCTION_SHA256:
        raise ValueError('Frozen zone-geometry reference SHA-256 changed')
    return actual


def run_variant(args: argparse.Namespace, round_index: int, variant: str) -> dict:
    output = args.out / f'round-{round_index:02d}-{variant}'
    output.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment['APPDATA'] = str(output / 'userdata')
    Path(environment['APPDATA']).mkdir(parents=True, exist_ok=True)
    command = [str(args.godot.resolve()), '--headless', '--audio-driver', 'Dummy',
               '--path', str(ROOT), '--log-file', str(output / 'engine.log'),
               '--script', SCRIPT, '--', f'--frames={args.frames}',
               f'--population={args.population}', f'--seed={args.seed}',
               f'--map={args.map}', f'--top={args.top}',
               f'--variant={variant}',
               f'--baseline-targeting={str(variant == "baseline" and args.ai_lightening is None).lower()}',
               f'--ai-commander={args.ai_commander}',
               f'--ai-strategy-script={args.ai_script_paths.get(variant, "")}',
               f'--ai-decision-checkpoints={str(args.ai_lightening is not None).lower()}',
               f'--detailed-ai={str(args.detailed_ai).lower()}',
               f'--front-towers={str(args.front_towers).lower()}',
               f'--baseline-ai-information={str(args.baseline_ai_information and variant == "baseline").lower()}',
               f'--baseline-zone-geometry={str(args.baseline_zone_geometry and variant == "baseline").lower()}',
               f'--out={output.as_posix()}']
    stdout_path = output / 'stdout.log'
    process = None
    timed_out = False
    launch_error = None
    cpu_error = None
    process_cpu = {'status': 'not_started' if os.name == 'nt' else 'unsupported_platform',
                   'source': 'Windows GetProcessTimes', 'user_seconds': None,
                   'kernel_seconds': None, 'total_seconds': None}
    begun = time.monotonic()
    with stdout_path.open('wb') as stream:
        try:
            process = subprocess.Popen(command, cwd=ROOT, env=environment,
                stdout=stream, stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
        except OSError as error:
            launch_error = str(error)
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=10)
    process_wall_seconds = time.monotonic() - begun
    # wait() reaps the child but Popen retains its native handle until close/GC.
    # Query before result parsing so no process handle can be discarded first.
    if os.name == 'nt' and process is not None:
        try:
            process_cpu = windows_process_cpu_times(int(process._handle))
        except OSError as error:
            cpu_error = str(error)
            process_cpu['status'] = 'error'
            process_cpu['error'] = cpu_error
    lines = stdout_path.read_text(encoding='utf-8', errors='replace').splitlines()
    errors = []
    if cpu_error is not None:
        errors.append(f'Failed to read Godot process CPU times: {cpu_error}')
    results = []
    contracts = []
    for line in lines:
        try:
            if line.startswith(PREFIX): results.append(json.loads(line[len(PREFIX):]))
            elif line.startswith(CONTRACT_PREFIX): contracts.append(json.loads(line[len(CONTRACT_PREFIX):]))
        except json.JSONDecodeError as error:
            errors.append(f'Invalid structured stdout: {error}')
    checks = [line for line in lines if line.startswith('SINGLEPLAYER_PROFILE_CHECKS ')]
    diagnostics = [line for line in lines if line.startswith(('SCRIPT ERROR:', 'ERROR:', 'FAIL '))]
    if process is None or process.returncode != 0 or timed_out:
        errors.append(f'Godot did not complete successfully: launch={launch_error}, timeout={timed_out}')
    if len(results) != 1 or len(contracts) != 1:
        errors.append('Expected exactly one result and one contract')
    if len(checks) != 1 or not checks[0].endswith('failures=0'):
        errors.append('Missing passing check summary')
    if any(line not in ALLOWED_DIAGNOSTICS for line in diagnostics):
        errors.append('Unexpected engine/script/assertion diagnostics')
    result = results[0] if len(results) == 1 else None
    trace = []
    artifacts = {}
    if result is not None:
        if (result['variant'] != variant or result['frames'] != args.frames or
                result['detailed_ai'] != args.detailed_ai or result['front_towers'] != args.front_towers or
                result['baseline_targeting'] != (variant == 'baseline' and args.ai_lightening is None) or
                result['ai_commander'] != args.ai_commander or result['ai_strategy_script'] != args.ai_script_paths.get(variant, '') or
                result['ai_decision_checkpoints'] != (args.ai_lightening is not None) or
                result['baseline_ai_information'] != (args.baseline_ai_information and variant == 'baseline') or
                result['baseline_zone_geometry'] != (args.baseline_zone_geometry and variant == 'baseline') or
                result['baseline_zone_body_sha256'] != ZONE_REFERENCE_FUNCTION_SHA256 or result['failures']):
            errors.append('Variant/frame/failure contract mismatch')
        for name in ('frames.jsonl', 'initial-snapshot.json', 'final-snapshot.json', 'summary.json'):
            artifact = output / name
            if artifact.is_file(): artifacts[name] = file_hash(artifact)
            else: errors.append(f'Missing artifact: {name}')
        raw = output / 'frames.jsonl'
        if raw.is_file():
            try:
                trace = [json.loads(line) for line in raw.read_text(encoding='utf-8').splitlines()]
            except json.JSONDecodeError as error:
                errors.append(f'Invalid frame trace: {error}')
        if len(trace) != args.frames or [row['frame'] for row in trace] != list(range(args.frames)):
            errors.append('Frame trace is incomplete or not sequential')
        if args.ai_lightening:
            checkpoints = result['ai_checkpoints']
            expected = [(row['frame'], row['elapsed'], row['ai_calls']) for row in trace if row['ai_calls'] > 0]
            actual = [(item['frame'], item['elapsed'], item['ai_calls']) for item in checkpoints]
            if actual != expected or sum(item['ai_calls'] for item in checkpoints) != result['statistics']['ai_calls']:
                errors.append('AI decision checkpoints do not cover every measured turn')
            for item in checkpoints:
                name = f'ai-decision-{item["frame"]:06d}-snapshot.json'
                artifact = output / name
                if artifact.is_file(): artifacts[name] = file_hash(artifact)
                else: errors.append(f'Missing AI checkpoint snapshot: {name}')
    frame_rule_hash = hashlib.sha256(json.dumps(
        [{key: row[key] for key in RULE_FIELDS} for row in trace],
        ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')).hexdigest()
    return {'round': round_index, 'variant': variant, 'command': command,
            'pid': process.pid if process else None,
            'exit_code': process.returncode if process else None,
            'exited': process is None or process.poll() is not None,
            'timed_out': timed_out, 'launch_error': launch_error,
            'wall_seconds': round(time.monotonic() - begun, 3),
            'process_wall_seconds': round(process_wall_seconds, 6),
            'process_cpu': process_cpu,
            'output': str(output), 'contract': contracts, 'result': result,
            'checks': checks, 'diagnostics': diagnostics, 'artifact_sha256': artifacts,
            'frame_rule_trace_sha256': frame_rule_hash, 'errors': errors}


def compare_pair(baseline: dict, candidate: dict) -> dict:
    mismatches = []
    if baseline['errors'] or candidate['errors']:
        return {'round': baseline['round'], 'equal': False, 'mismatches': ['A variant did not pass']}
    for phase in ('initial_hashes', 'final_hashes'):
        for key, value in baseline['result'][phase].items():
            if value != candidate['result'][phase][key]: mismatches.append(f'{phase}.{key}')
    if baseline['frame_rule_trace_sha256'] != candidate['frame_rule_trace_sha256']:
        mismatches.append('frame_rule_trace_sha256')
    if baseline['result']['ai_checkpoints'] != candidate['result']['ai_checkpoints']:
        mismatches.append('ai_decision_checkpoint_hashes')
    changes = {}
    for stage in (key for key in baseline['result']['statistics'] if key.endswith('_us')):
        first = baseline['result']['statistics'][stage]
        second = candidate['result']['statistics'][stage]
        changes[stage] = {metric: {'baseline': first[metric], 'candidate': second[metric],
            'change_percent': round(100.0 * (second[metric] / first[metric] - 1.0), 3) if first[metric] else None}
            for metric in ('mean', 'p95', 'p99', 'max')}
    process_cpu_changes = {}
    if baseline['process_cpu']['status'] == 'ok' and candidate['process_cpu']['status'] == 'ok':
        for metric in ('user_seconds', 'kernel_seconds', 'total_seconds'):
            first, second = baseline['process_cpu'][metric], candidate['process_cpu'][metric]
            process_cpu_changes[metric] = {'baseline': first, 'candidate': second,
                'change_percent': round(100.0 * (second / first - 1.0), 3) if first else None}
    return {'round': baseline['round'], 'equal': not mismatches,
            'mismatches': mismatches, 'timing_changes': changes,
            'whole_process_cpu_changes': process_cpu_changes,
            'call_changes': {key: {'baseline': value, 'candidate': candidate['result']['statistics'][key]}
                             for key, value in baseline['result']['statistics'].items() if key.endswith('_calls')}}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=ROOT / '.local/network/runtime/Godot_v4.7.2-stable_win64.exe')
    parser.add_argument('--out', type=Path, default=ROOT / '.local/singleplayer-profile')
    parser.add_argument('--frames', type=int, default=3000)
    parser.add_argument('--population', type=int, default=1800)
    parser.add_argument('--seed', type=int, default=20260930)
    parser.add_argument('--map', choices=('islands', 'highland', 'crown'), default='islands')
    parser.add_argument('--mode', choices=('both', 'baseline', 'candidate'), default='both')
    parser.add_argument('--rounds', type=int, default=1)
    parser.add_argument('--top', type=int, default=20)
    parser.add_argument('--ai-lightening', choices=('information', 'strategy', 'skills', 'both'),
                        help='Compare AI modules with pinned 035db7c; current targeting and zone geometry in both variants')
    parser.add_argument('--ai-commander', choices=('squirrel', 'pig', 'fox', 'frog', 'bear', 'rabbit'), default='squirrel',
                        help='Commander used by each of the five real AI seats')
    parser.add_argument('--detailed-ai', action='store_true',
                        help='Optional nested AI timings and call-only soldier counters; off for normal A/B')
    parser.add_argument('--front-towers', action='store_true',
                        help='Convert each faction nearest-enemy house into a level-3 midgame tower')
    parser.add_argument('--baseline-ai-information', action='store_true',
                        help='Also freeze incoming_damage in baseline variants using generated AI modules')
    parser.add_argument('--baseline-zone-geometry', action='store_true',
                        help='Also freeze old _zone_intervals in baseline variants; no SceneTree test dependency')
    parser.add_argument('--timeout', type=float, default=600.0, help='Wall timeout for each serial Godot child')
    parser.add_argument('--describe-only', action='store_true', help='Print source contract without starting Godot')
    args = parser.parse_args()
    if not (1 <= args.frames <= 36000 and 600 <= args.population <= 16384 and
            args.rounds >= 1 and args.timeout > 0 and 1 <= args.top <= 200):
        parser.error('invalid frames/population/rounds/timeout/top bounds')
    if args.baseline_ai_information and args.detailed_ai:
        parser.error('--baseline-ai-information cannot be combined with --detailed-ai')
    if args.ai_lightening and (args.baseline_ai_information or args.baseline_zone_geometry):
        parser.error('--ai-lightening is isolated from the previous targeting/information/geometry baseline')
    args.out = args.out.resolve()
    before = source_hashes(args.map, args.baseline_ai_information)
    if args.ai_lightening:
        generated, reference_contract = build_ai_lightening(args.ai_lightening, args.detailed_ai)
    else:
        generated, reference_contract = build_ai_reference() if args.baseline_ai_information else ({}, {})
    args.ai_script_paths = reference_contract['strategy_scripts'] if args.ai_lightening else {}
    frozen_methods = ['acquire_targets']
    if args.baseline_ai_information: frozen_methods.append('incoming_damage')
    if args.baseline_zone_geometry: frozen_methods.append('_zone_intervals')
    contract = {'scope': (f'AI {args.ai_lightening} compared with complete 035db7c AI baseline; current targeting and zone geometry in both variants'
                          if args.ai_lightening else ', '.join(frozen_methods) + ' use frozen references; all other current runtime code is shared'),
                'baseline_targeting_body_sha256': targeting_body_hash(),
                'baseline_zone_body_sha256': zone_body_hash(),
                'source_sha256_before': before,
                'frames': args.frames, 'population': args.population, 'seed': args.seed,
                'map': args.map, 'mode': args.mode, 'rounds': args.rounds,
                'ai_lightening': args.ai_lightening, 'ai_commander': args.ai_commander,
                'ai_decision_checkpoints': args.ai_lightening is not None,
                'detailed_ai': args.detailed_ai,
                'front_towers': args.front_towers,
                'baseline_ai_information': args.baseline_ai_information,
                'baseline_zone_geometry': args.baseline_zone_geometry,
                'ai_reference': reference_contract,
                'process_cpu_measurement': 'Windows GetProcessTimes user/kernel CPU seconds for all child threads over the complete Godot lifetime; separate from process_wall_seconds and AI/frame elapsed timings',
                'timing': 'Inclusive elapsed microseconds, including scheduling waits; not thread CPU time; no GPU/FPS inference'}
    if args.describe_only:
        print(json.dumps(contract, ensure_ascii=False, indent=2))
        return 0
    if generated:
        for path, source in generated.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(source, encoding='utf-8', newline='\n')
    generated_before = generated_hashes(generated)
    if generated and generated_before != reference_contract['generated_sha256_expected']:
        raise ValueError('Generated AI reference content does not match its expected SHA-256')
    args.out.mkdir(parents=True, exist_ok=True)
    runs = []
    comparisons = []
    errors = []
    for round_index in range(args.rounds):
        variants = (['baseline', 'candidate'] if round_index % 2 == 0 else ['candidate', 'baseline']) if args.mode == 'both' else [args.mode]
        paired = {}
        for variant in variants:
            run = run_variant(args, round_index, variant)
            runs.append(run)
            paired[variant] = run
            errors.extend(f'round {round_index} {variant}: {error}' for error in run['errors'])
            print(json.dumps({'round': round_index, 'variant': variant, 'pid': run['pid'],
                              'exited': run['exited'], 'seconds': run['wall_seconds'],
                              'process_wall_seconds': run['process_wall_seconds'],
                              'process_cpu': run['process_cpu'],
                              'output': run['output'], 'errors': run['errors']}, ensure_ascii=False), flush=True)
            if run['errors']: break
        if args.mode == 'both' and len(paired) == 2:
            comparison = compare_pair(paired['baseline'], paired['candidate'])
            comparisons.append(comparison)
            if not comparison['equal']: errors.append(f'round {round_index}: paired rule/state mismatch')
        if errors: break
    after = source_hashes(args.map, args.baseline_ai_information)
    if before != after: errors.append('Measured sources changed while the serial runs were active')
    generated_after = generated_hashes(generated)
    if generated_before != generated_after: errors.append('Generated reference modules changed while serial runs were active')
    receipt = {**contract, 'source_sha256_after': after, 'runs': runs,
               'generated_sha256_before': generated_before, 'generated_sha256_after': generated_after,
               'comparisons': comparisons, 'errors': errors}
    path = args.out / 'profile.json'
    path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'receipt': str(path), 'paired_equal': [item['equal'] for item in comparisons],
                      'all_children_exited': all(run['exited'] for run in runs), 'errors': errors},
                     ensure_ascii=False), flush=True)
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())

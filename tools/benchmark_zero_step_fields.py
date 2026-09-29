"""Compare skipping empty field-integration segments against the original body."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.local/zero-step-fields'


def source_hashes() -> dict:
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in (
        'scripts/block_war/war_marches.gd', 'scripts/block_war/war_skill_rules.gd',
        'tests/block_war_zero_step_field_test.gd', 'tools/benchmark_zero_step_fields.py')}


def prepare() -> dict:
    source = (ROOT / 'scripts/block_war/war_marches.gd').read_text(encoding='utf-8')
    start = source.index('func _movement_segment(')
    end = source.index('\nfunc _movement_with_fields(', start)
    body = source[start:end]
    # Kept as a literal recipe so the comparison cannot silently change scope.
    guard = '\tif delta == 0.0:\n\t\treturn 0.0\n'
    first_line, rest = body.split('\n', 1)
    if rest.startswith(guard):
        candidate = body
        reference = first_line + '\n' + rest[len(guard):]
    else:
        reference = body
        candidate = first_line + '\n' + guard + rest
    OUT.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for label, text in [('reference', reference), ('candidate', candidate)]:
        script = 'extends WarMarches\n\n' + text + '\n'
        (OUT / f'{label}.gd').write_text(script, encoding='utf-8')
        hashes[label] = hashlib.sha256(script.encode()).hexdigest()
    return hashes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rounds', type=int, default=5)
    parser.add_argument('--frames', type=int, default=120)
    parser.add_argument('--soldiers', type=int, default=4096)
    parser.add_argument('--timeout', type=int, default=300)
    parser.add_argument('--label', default='initial')
    args = parser.parse_args()
    if min(args.rounds, args.frames, args.soldiers, args.timeout) <= 0:
        parser.error('positive parameters required')
    hashes = prepare()
    before = source_hashes()
    out = OUT / args.label
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env['APPDATA'] = str(out / 'userdata')
    Path(env['APPDATA']).mkdir(parents=True, exist_ok=True)
    command = [str(ROOT / '.local/network/runtime/Godot_v4.7.2-stable_win64.exe'),
        '--headless', '--path', str(ROOT), '--log-file', str(out / 'engine.log'),
        '--script', 'res://tests/block_war_zero_step_field_test.gd', '--',
        str(args.rounds), str(args.frames), str(args.soldiers)]
    expired = False
    process = None
    begun = time.monotonic()
    with (out / 'stdout.log').open('wb') as output:
        try:
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=output,
                stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            expired = True
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=10)
    lines = (out / 'stdout.log').read_text(encoding='utf-8', errors='replace').splitlines()
    results = [json.loads(line.removeprefix('ZERO_STEP_FIELDS ')) for line in lines if line.startswith('ZERO_STEP_FIELDS ')]
    summary = [line for line in lines if line.startswith('ZERO_STEP_CHECKS ')]
    diagnostics = [line for line in lines if line.startswith(('ERROR:', 'SCRIPT ERROR:', 'FAIL '))]
    after = source_hashes()
    success = (before == after and not expired and process.returncode == 0 and len(summary) == 1 and
        summary[0].endswith('failures=0') and len(results) == args.rounds * 12 and
        all(line == 'ERROR: Failed to read the root certificate store.' for line in diagnostics))
    receipt = {'hashes': hashes, 'source_sha256_before': before, 'source_sha256_after': after,
        'pid': process.pid, 'exit_code': process.returncode,
        'exited': process.poll() is not None, 'timeout': expired, 'seconds': round(time.monotonic()-begun, 2),
        'results': results, 'summary': summary, 'diagnostics': diagnostics, 'passed': success}
    (out / 'results.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    for result in results:
        print(json.dumps({key: value for key, value in result.items() if key != 'samples_ms'}), flush=True)
    print(json.dumps({key: value for key, value in receipt.items() if key != 'results'}), flush=True)
    return 0 if success else 1


if __name__ == '__main__':
    raise SystemExit(main())

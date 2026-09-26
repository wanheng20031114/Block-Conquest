"""Compare native Godot mixer captures and export auditions at shipped defaults.

Run after tests/block_war_loudness_capture.gd, with --before DIR --after DIR.
Short cues use 50 ms RMS / true peak, not streaming-platform LUFS targets.
Long mixes additionally use FFmpeg's BS.1770 / EBU R128 measurement.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import wave

import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parents[1]
LABELS = {
    "select": "建筑轻敲", "drag": "拖起技能", "ratio": "比例／设置滑条",
    "order": "松手派兵／确认", "denied": "条件不足", "cancel": "取消／返回",
    "pause": "暂停", "resume": "继续", "march": "行军脚步", "melee": "交战",
    "capture": "占领", "lost": "失守", "reinforce": "增援到达",
    "upgrade": "升级完成", "rebuild": "施工开始",
    "skill_command": "松鼠 Q · 征召军令", "skill_drum": "松鼠 W · 疾行战鼓",
    "skill_shield": "松鼠 E · 防护罩", "skill_breach": "松鼠 R · 火攻",
    "rabbit_dash": "兔子 Q · 蹦蹦小径", "rabbit_seal": "兔子 W · 封条急件",
    "rabbit_recall": "兔子 E · 归巢口哨", "rabbit_burrow": "兔子 R · 兔洞快递",
    "projectile_hit": "炮弹命中", "victory": "胜利", "defeat": "失败",
    "cannon_shot": "炮台发射", "menu_select": "arc-nice 菜单点击",
}


def db(value):
    return round(float(20 * np.log10(max(value, 1e-12))), 2)


def window_rms(samples, rate, seconds):
    energy = (samples ** 2).mean(axis=1)
    size = min(len(energy), round(rate * seconds))
    # Cumulative sum avoids a large sliding-window matrix for long mixed clips.
    sums = np.r_[0.0, np.cumsum(energy)]
    return float(np.sqrt(np.maximum(0, (sums[size:] - sums[:-size]) / size).max()))


def r128(samples, rate):
    process = subprocess.run([
        "ffmpeg", "-hide_banner", "-f", "f32le", "-ar", str(rate), "-ac", "2", "-i", "pipe:0",
        "-af", "ebur128=peak=true", "-f", "null", "-",
    ], input=samples.astype("<f4").tobytes(), capture_output=True, check=True)
    summary = process.stderr.decode("utf-8", errors="replace").rsplit("Summary:", 1)[1]
    return {"integrated_lufs": float(re.search(r"I:\s+(-?[\d.]+) LUFS", summary)[1]),
            "loudness_range_lu": float(re.search(r"LRA:\s+([\d.]+) LU", summary)[1])}


def read_capture(directory, name, tap="post"):
    samples = np.fromfile(directory / f"{name}_{tap}.f32", dtype="<f4").reshape(-1, 2).astype(float)
    assert len(samples) > 100 and np.isfinite(samples).all() and np.any(samples), name
    return samples


def measure(directory):
    manifest = json.loads((directory / "captures.json").read_text(encoding="utf-8"))
    assert len(manifest["captures"]) == 57, "Incomplete native capture run"
    assert manifest["discarded_frames"] == [0, 0], "Native capture overran its buffer"
    rate = int(manifest["mix_rate"])
    rows = {}
    for entry in manifest["captures"]:
        name = entry["name"]
        x = read_capture(directory, name)
        raw = read_capture(directory, name, "pre")
        peak = float(np.max(np.abs(signal.resample_poly(x, 4, 1, axis=0))))
        row = dict(entry, max_50ms_rms_dbfs=db(window_rms(x, rate, .05)),
                   max_400ms_rms_dbfs=db(window_rms(x, rate, .4)),
                   true_peak_dbtp=db(peak), sample_peak_dbfs=db(abs(x).max()),
                   pre_limiter_sample_peak_dbfs=db(abs(raw).max()),
                   limiter_threshold_frames_percent=round(float(np.mean(np.max(abs(raw), axis=1) > 10 ** (-1 / 20)) * 100), 4))
        if entry["type"] in {"mix", "music"}:
            row.update(r128(x * 10 ** (entry["master_db"] / 20), rate))
        rows[name] = row
    return rate, rows


def write_wave(path, samples, rate):
    assert np.max(abs(samples)) < 1.0, f"Audition would clip: {path}"
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(2)
        writer.setsampwidth(2)
        writer.setframerate(rate)
        writer.writeframes(np.round(samples * 32767).astype("<i2").tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--reference", default="cd82051", help="Commit containing the approved source timbres")
    args = parser.parse_args()
    rate, before = measure(args.before)
    final_rate, after = measure(args.after)
    assert rate == final_rate and before.keys() == after.keys()
    output = ROOT / "docs/audio/block_war/loudness"
    output.mkdir(parents=True, exist_ok=True)
    checks = []

    def check(ok, description):
        checks.append({"passed": bool(ok), "description": description})
        print(("PASS " if ok else "FAIL ") + description)

    # Every game sample is byte-identical; this pass changes playback gains only.
    source_manifest = json.loads((ROOT / "assets/audio/block_war/audio_manifest.json").read_text(encoding="utf-8"))
    for item in source_manifest["files"]:
        relative = "assets/audio/block_war/" + item["file"]
        current = (ROOT / relative).read_bytes()
        original = subprocess.check_output(["git", "show", args.reference + ":" + relative], cwd=ROOT)
        check(hashlib.sha256(current).digest() == hashlib.sha256(original).digest(), "unchanged source " + item["file"])
    for relative in ["assets/audio/ui/arc_nice_click.wav", "assets/audio/cannon_shot_01.wav", "assets/audio/cannon_shot_02.wav",
                     "assets/audio/block_war/music/battle_bgm_01.mp3", "assets/audio/block_war/music/battle_bgm_02.mp3"]:
        check((ROOT / relative).read_bytes() == subprocess.check_output(["git", "show", args.reference + ":" + relative], cwd=ROOT), "unchanged source " + Path(relative).name)

    previews = []
    for kind, label in LABELS.items():
        event = kind if kind in {"cannon_shot", "menu_select"} else "war_" + kind
        names = [n for n in after if (n.startswith(event + "_") and not n.endswith("_edge")) or n == event]
        assert names, event
        deltas = [round(after[n]["max_50ms_rms_dbfs"] - before[n]["max_50ms_rms_dbfs"], 2) for n in names]
        changed = abs(float(np.median(deltas))) > .2
        pieces, timeline = [], []
        cursor = 0
        for name in names:
            # Native spatial balance, buses and compression are already captured.
            # Bake the shipped 50% Master fader, never normalize previews separately.
            samples = read_capture(args.after, name) * 10 ** (after[name]["master_db"] / 20)
            audible = np.flatnonzero(np.max(abs(samples), axis=1) > 1e-6)
            assert audible.size, name
            samples = samples[max(0, audible[0] - round(.015 * rate)):min(len(samples), audible[-1] + round(.08 * rate))]
            timeline.append({"name": name, "start_seconds": round(cursor / rate, 3)})
            pieces += [samples, np.zeros((round(.28 * rate), 2))]
            cursor += len(samples) + round(.28 * rate)
        write_wave(output / f"{kind}.wav", np.concatenate(pieces[:-1]), rate)
        previews.append({"event": event, "label": label, "changed": changed, "delta_50ms_db": deltas,
                         "preview": f"{kind}.wav", "variants": timeline})

    for name in ["music_01", "music_02", "battle_01", "battle_02", "maximum_stress"]:
        entry = after[name]
        # Stress runs use 100% to test the ceiling. Listening comparisons are
        # always exported at 50% Master, so a stress preview never jumps 6 dB.
        write_wave(output / f"{name}.wav", read_capture(args.after, name) * .5, rate)
        check(entry["sample_peak_dbfs"] <= -.9 and entry["true_peak_dbtp"] < 0, name + " has no clipped output including intersample peaks")
        if entry["type"] == "mix":
            for skill in ["skill_command", "skill_drum", "skill_shield", "skill_breach", "rabbit_dash", "rabbit_seal", "rabbit_recall", "rabbit_burrow"]:
                check(entry["events_played"].get("war_" + skill, 0) >= 1, name + " retains " + skill)
            check(entry["events_played"].get("war_melee", 0) <= 52, name + " rate-limits dense contact requests")
        check(entry["limiter_threshold_frames_percent"] < .1, name + " does not rely on sustained master limiting")

    delta = lambda name: after[name]["max_50ms_rms_dbfs"] - before[name]["max_50ms_rms_dbfs"]
    # These are post-compressor measurements. A +2 dB source adjustment is
    # intentionally smaller at the loudest window, unlike the old hard clamp.
    check(delta("war_skill_command_01") > .5, "positive spatial skill gain now reaches native output")
    for name in ["war_select_01", "war_drag_01", "war_order_01", "menu_select", "war_melee_01", "cannon_shot_01"]:
        check(abs(delta(name)) < .5, name + " retains the approved level")
    check(after["war_march_01"]["max_50ms_rms_dbfs"] < after["war_melee_01"]["max_50ms_rms_dbfs"] - 2, "footsteps sit beneath combat")
    check(abs(after["war_pause_01"]["max_50ms_rms_dbfs"] - after["war_resume_01"]["max_50ms_rms_dbfs"]) < 1, "pause and resume are balanced")
    check(after["war_ratio_01"]["max_50ms_rms_dbfs"] < after["war_order_01"]["max_50ms_rms_dbfs"] - 5, "rapid slider feedback stays behind confirmation")
    for name, minimum_drop in [("war_march_01", 3), ("war_skill_breach_01", 1.5)]:
        # Combat compression narrows near/far differences; Foley is uncompressed.
        check(after[name + "_edge"]["max_50ms_rms_dbfs"] < after[name]["max_50ms_rms_dbfs"] - minimum_drop, name + " remains quieter at the screen edge")

    report = {"date": "2026-09-27", "mix_rate": rate, "approved_source_commit": args.reference,
              "conditions": "Godot 4.6.3 native stereo mixer, Dummy driver; all 44 campaign variants, 2 cannon variants, 4 menu players; source at (8,0,0), listener at (0,6,0), edge (43,0,0). Pre/post limiter captures are before Master fader. Auditions bake 50% Master with no normalization. Battle stress fixtures exercise actual event cooldowns; they are scripted mixes, not human play recordings.",
              "short_cue_metric": "Maximum unweighted 50 ms sliding RMS, both channels averaged; 4x oversampled true peak. Not SPL, not perceived-loudness certification.",
              "long_mix_metric": "FFmpeg ebur128, BS.1770 K-weighted integrated LUFS measured after the specified Master fader. LRA of these short excerpts is descriptive only.",
              "previews": previews, "checks": checks, "before": before, "after": after}
    (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("\nMIX COMPARISON (post-Master LUFS, pre-Master true peak):")
    for name in ["battle_01", "battle_02", "maximum_stress"]:
        print(name, "LUFS", before[name]["integrated_lufs"], "->", after[name]["integrated_lufs"],
              "true peak", before[name]["true_peak_dbtp"], "->", after[name]["true_peak_dbtp"])
    print(f"{len(checks)} checks, {sum(not c['passed'] for c in checks)} failures; {sum(p['changed'] for p in previews)} adjusted cue types")
    assert all(c["passed"] for c in checks), "Loudness regression failed; inspect report.json"


if __name__ == "__main__":
    main()

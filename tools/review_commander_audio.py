"""Measure silent Godot captures and export the eight new spell auditions.

python tools/review_commander_audio.py .local/commander-audio/native
Previews retain shipped spatial attenuation, Combat compression and 50% Master.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import wave

import numpy as np
from scipy import signal
from review_war_loudness import db, read_capture, window_rms, write_wave

ROOT = Path(__file__).resolve().parents[1]
LABELS = {
    "bear_toolbox": "熊 Q · 工具箱", "bear_stomp": "熊 W · 重重跺脚",
    "bear_link": "熊 E · 链式防守", "bear_ward": "熊 R · 不落堡垒",
    "frog_mist": "青蛙 Q · 弱化雾气", "frog_float": "青蛙 W · 浮力薄隔",
    "frog_cloak": "青蛙 E · 隐身", "frog_strike": "青蛙 R · 致命打击",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--reference", default="c229c6a", help="Commit before this sound update")
    args = parser.parse_args()
    capture = json.loads((args.capture / "captures.json").read_text(encoding="utf-8"))
    assert capture["discarded_frames"] == [0, 0], "Capture buffer overrun"
    assert len(capture["captures"]) == 15
    rate = int(capture["mix_rate"])
    output = ROOT / "docs/audio/commanders"
    output.mkdir(parents=True, exist_ok=True)
    rows = []
    previews = []
    for entry in capture["captures"]:
        name = entry["name"]
        raw = read_capture(args.capture, name)
        before = read_capture(args.capture, name, "pre")
        samples = raw * 10 ** (entry["master_db"] / 20)
        peak = db(np.max(abs(signal.resample_poly(samples, 4, 1, axis=0))))
        rms = db(window_rms(samples, rate, .05))
        limited = float(np.mean(np.max(abs(before), axis=1) > 10 ** (-1 / 20)) * 100)
        assert peak < -1.0 and limited < .1, name + " relies on limiting or clips"
        rows.append(dict(entry, default_or_stress_50ms_rms_dbfs=rms,
                         output_true_peak_dbtp=peak, limiter_threshold_frames_percent=round(limited, 4)))
        kind = name.removeprefix("war_").removesuffix("_01")
        if kind in LABELS:
            assert -33 < rms < -24, name + " outside the restrained skill reference range"
            assert np.isclose(entry["master_db"], 20 * np.log10(.5))
            audible = np.flatnonzero(np.max(abs(samples), axis=1) > 1e-6)
            snippet = samples[max(0, audible[0] - round(.015 * rate)):min(len(samples), audible[-1] + round(.08 * rate))]
            # Two identical native readings with breathing room. No normalization.
            preview = np.concatenate([snippet, np.zeros((round(.45 * rate), 2)), snippet])
            write_wave(output / (kind + ".wav"), preview, rate)
            previews.append({"event": "war_" + kind, "label": LABELS[kind], "file": kind + ".wav"})
        elif entry["type"] == "mix":
            for kind in LABELS:
                assert entry["events_played"].get("war_" + kind, 0) >= 1, name + " lost " + kind
            if entry["stress"]:
                assert entry["events_played"]["war_bear_ward"] >= 6, "Simultaneous wards were swallowed"
    assert len(previews) == 8
    assets = ROOT / "assets/audio/block_war"
    manifest = json.loads((assets / "audio_manifest.json").read_text(encoding="utf-8"))
    source_checks = []
    for kind in LABELS:
        path = assets / ("war_" + kind + "_01.wav")
        with wave.open(str(path), "rb") as source:
            assert source.getsampwidth() == 2 and source.getnchannels() == 1 and source.getframerate() == 48000
            samples = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").astype(float) / 32768
        onset = np.flatnonzero(abs(samples) > np.max(abs(samples)) * .02)[0] / 48
        assert onset < 2.0 and samples[0] == samples[-1] == 0
        assert 'compress/mode=0' in Path(str(path) + '.import').read_text(encoding='utf-8')
        source_checks.append({"file": path.name, "onset_ms_at_2percent_peak": round(onset, 3),
                              "duration_seconds": round(len(samples) / 48000, 3),
                              "first_50ms_energy_percent": round(float(np.sum(samples[:2400] ** 2) / np.sum(samples ** 2) * 100), 2)})
    old = json.loads(subprocess.check_output(["git", "show", args.reference + ":assets/audio/block_war/audio_manifest.json"], cwd=ROOT))
    assert len(old["files"]) == 44
    current = {entry["file"]: entry for entry in manifest["files"]}
    for entry in old["files"]:
        assert current[entry["file"]] == entry
        assert hashlib.sha256((assets / entry["file"]).read_bytes()).hexdigest() == entry["sha256"]
    assert old["menu_click"] == manifest["menu_click"]
    for relative in ["assets/audio/ui/soft_click.wav", "assets/audio/block_war/music/battle_bgm_01.mp3", "assets/audio/block_war/music/battle_bgm_02.mp3", "default_bus_layout.tres"]:
        assert (ROOT / relative).read_bytes() == subprocess.check_output(["git", "show", args.reference + ":" + relative], cwd=ROOT)
    report = {"mix_rate": rate, "preview_gain": "Captured at shipped defaults, Master fader baked in; never normalized",
              "previews": previews, "sources": source_checks, "native_mix": rows,
              "unchanged_battle_wavs": 44, "unchanged_menu_click_bgm_and_buses": True,
              "discarded_capture_frames": capture["discarded_frames"]}
    (output / "measurements.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("PASS: 8 fast-onset PCM cues, 15 native captures, six overlapping wards; 44 approved WAVs/click/BGM/buses unchanged")
    for row in rows[:8]:
        print(row["name"], "50 ms RMS", row["default_or_stress_50ms_rms_dbfs"], "dBFS; true peak", row["output_true_peak_dbtp"], "dBTP")


if __name__ == "__main__":
    main()

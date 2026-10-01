"""Measure native pig-skill output and save auditions at the shipped volume."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

import numpy as np
from scipy import signal
from review_war_loudness import db, read_capture, window_rms, write_wave

ROOT = Path(__file__).resolve().parents[1]
NAMES = ["pig_charge", "pig_fly", "pig_airlift", "pig_drop", "pig_impact"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--reference", required=True, help="Commit before this audio update")
    args = parser.parse_args()
    manifest = json.loads((args.capture / "captures.json").read_text(encoding="utf-8"))
    assert manifest["discarded_frames"] == [0, 0], "Native capture dropped frames"
    assert len(manifest["captures"]) == 9, "Incomplete native capture run"
    rate = int(manifest["mix_rate"])
    output = ROOT / "docs/audio/pig"
    output.mkdir(parents=True, exist_ok=True)
    rows, auditions = [], {}
    for entry in manifest["captures"]:
        name = entry["name"]
        assert entry["discarded_frames"] == [0, 0], name + " dropped frames"
        gain = 10 ** (entry["master_db"] / 20)
        samples = read_capture(args.capture, name) * gain
        before = read_capture(args.capture, name, "pre")
        peak = db(np.max(abs(signal.resample_poly(samples, 4, 1, axis=0))))
        rms = db(window_rms(samples, rate, .05))
        assert peak < -1.0, name + " reaches the clipping margin"
        rows.append(dict(entry, rms_50ms_dbfs=rms, true_peak_dbtp=peak,
                         pre_limiter_peak_dbfs=db(np.max(abs(before))),
                         limiter_threshold_frames_percent=round(float(np.mean(np.max(abs(before), axis=1) > 10 ** (-1 / 20))) * 100, 4)))
        kind = name.removeprefix("war_").removesuffix("_01")
        if kind in NAMES or name == "pig_drop_actual_timing":
            assert np.isclose(entry["master_db"], 20 * np.log10(.5)), "Audition must retain default volume"
            if kind in NAMES:
                assert -38 < rms < -21, name + " outside the restrained skill range"
                # Isolated captures select a deterministic native pool voice
                # directly; event dispatch is checked by gameplay below.
                assert entry["kind"] == "war_" + kind and entry["sample"].endswith(name + ".wav")
            else:
                assert entry["cast_accepted"]
                assert entry["events_played"] == {"war_pig_drop": 1, "war_pig_impact": 1}
                timeline = entry["timeline"]
                assert len(timeline) == 2 and timeline[1]["kind"] == "war_pig_impact"
                assert abs(timeline[1]["simulation_seconds"] - .65) < .002
                assert .65 <= timeline[1]["wall_seconds"] <= .75
            audible = np.flatnonzero(np.max(abs(samples), axis=1) > 1e-6)
            snippet = samples[max(0, audible[0] - round(.015 * rate)):min(len(samples), audible[-1] + round(.08 * rate))]
            label = kind if kind in NAMES else name
            auditions[label] = snippet
            write_wave(output / (label + ".wav"), snippet, rate)
        if name in {"pig_battle_default", "pig_maximum_overlap"}:
            assert all(entry["events_played"].get("war_" + kind, 0) > 0 for kind in NAMES)
            if name == "pig_maximum_overlap":
                assert entry["events_played"].get("war_pig_impact", 0) >= 6
    assert set(NAMES + ["pig_drop_actual_timing"]).issubset(auditions)
    levels = {row["name"]: row["rms_50ms_dbfs"] for row in rows}
    assert levels["war_pig_charge_01_edge"] < levels["war_pig_charge_01"], "Spatial attenuation is absent"
    # Q, W, E, then the actual cast-to-impact R timeline; retain in-game gain.
    preview = []
    for name in ["pig_charge", "pig_fly", "pig_airlift", "pig_drop_actual_timing"]:
        if preview:
            preview.append(np.zeros((round(.60 * rate), 2)))
        preview.append(auditions[name])
    write_wave(output / "pig_skills_preview.wav", np.concatenate(preview), rate)

    def committed(path):
        return subprocess.check_output(["git", "show", args.reference + ":" + path], cwd=ROOT)

    old = json.loads(committed("assets/audio/block_war/audio_manifest.json"))
    current = json.loads((ROOT / "assets/audio/block_war/audio_manifest.json").read_text(encoding="utf-8"))
    files = {entry["file"]: entry for entry in current["files"]}
    for entry in old["files"]:
        assert files[entry["file"]] == entry, "Existing audio provenance changed"
        assert hashlib.sha256((ROOT / "assets/audio/block_war" / entry["file"]).read_bytes()).hexdigest() == entry["sha256"]
    for relative in ["assets/audio/ui/soft_click.wav", "assets/audio/block_war/music/battle_bgm_01.mp3", "assets/audio/block_war/music/battle_bgm_02.mp3", "default_bus_layout.tres"]:
        assert (ROOT / relative).read_bytes() == committed(relative), relative + " changed"
    for name in NAMES:
        entry = files["war_" + name + "_01.wav"]
        assert entry["true_peak_db"] <= -3.0
        assert entry["sources"] and all(source["license"] == "CC0-1.0" for source in entry["sources"])
        for source in entry["sources"]:
            assert hashlib.sha256((ROOT / "assets/audio/sources" / source["path"]).read_bytes()).hexdigest() == source["sha256"]
    report = {"mix_rate": rate, "gain": "Native spatial attenuation and default Master 50%; no audition normalization",
              "captures": rows, "retained_wavs": len(old["files"]), "click_bgm_buses_unchanged": True,
              "pig_sources_verified_cc0": True, "discarded_frames": manifest["discarded_frames"],
              "idle_discarded_frames": manifest["idle_discarded_frames"]}
    (output / "measurements.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for row in rows:
        print(row["name"], "50ms RMS", row["rms_50ms_dbfs"], "true peak", row["true_peak_dbtp"])
    print("PIG_AUDIO_REVIEW PASS: five CC0 cues, actual R timeline, retained", len(old["files"]), "WAVs, click, BGM and buses")


if __name__ == "__main__":
    main()

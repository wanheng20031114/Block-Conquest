"""Measure silent native fox captures and export auditions at shipped volume."""
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
NAMES = ["fox_bomb", "fox_steal", "fox_convert", "fox_panic"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--reference", default="ee05523")
    args = parser.parse_args()
    capture = json.loads((args.capture / "captures.json").read_text(encoding="utf-8"))
    assert capture["discarded_frames"] == [0, 0]
    rate = capture["mix_rate"]
    output = ROOT / "docs/audio/fox"
    output.mkdir(parents=True, exist_ok=True)
    rows = []
    for entry in capture["captures"]:
        name = entry["name"]
        samples = read_capture(args.capture, name) * 10 ** (entry["master_db"] / 20)
        peak = db(np.max(abs(signal.resample_poly(samples, 4, 1, axis=0))))
        rms = db(window_rms(samples, rate, .05))
        assert peak < -1.0, name + " clips or relies on limiting"
        rows.append(dict(entry, rms_50ms_dbfs=rms, true_peak_dbtp=peak))
        kind = name.removeprefix("war_").removesuffix("_01")
        if kind in NAMES:
            assert -33 < rms < -24, name + " outside the restrained skill range"
            assert np.isclose(entry["master_db"], 20 * np.log10(.5))
            audible = np.flatnonzero(np.max(abs(samples), axis=1) > 1e-6)
            snippet = samples[max(0, audible[0] - round(.015 * rate)):min(len(samples), audible[-1] + round(.08 * rate))]
            # Repeat twice with a quiet gap. Never normalize above the game mix.
            write_wave(output / (kind + ".wav"), np.concatenate([snippet, np.zeros((round(.45 * rate), 2)), snippet]), rate)
        if entry["type"] == "mix":
            for kind in NAMES:
                assert entry["events_played"].get("war_" + kind, 0) >= 1
            if entry["stress"]:
                assert entry["events_played"]["war_fox_panic"] >= 6
    old = json.loads(subprocess.check_output(["git", "show", args.reference + ":assets/audio/block_war/audio_manifest.json"], cwd=ROOT))
    current = json.loads((ROOT / "assets/audio/block_war/audio_manifest.json").read_text(encoding="utf-8"))
    by_name = {entry["file"]: entry for entry in current["files"]}
    for entry in old["files"]:
        assert by_name[entry["file"]] == entry
        assert hashlib.sha256((ROOT / "assets/audio/block_war" / entry["file"]).read_bytes()).hexdigest() == entry["sha256"]
    for relative in ["assets/audio/ui/soft_click.wav", "assets/audio/block_war/music/battle_bgm_01.mp3", "assets/audio/block_war/music/battle_bgm_02.mp3", "default_bus_layout.tres"]:
        assert (ROOT / relative).read_bytes() == subprocess.check_output(["git", "show", args.reference + ":" + relative], cwd=ROOT)
    report = {"mix_rate": rate, "gain": "Native spatial attenuation and default Master 50%; not normalized", "captures": rows,
              "retained_wavs": len(old["files"]), "click_bgm_buses_unchanged": True, "discarded_frames": capture["discarded_frames"]}
    (output / "measurements.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for row in rows:
        print(row["name"], "50ms RMS", row["rms_50ms_dbfs"], "true peak", row["true_peak_dbtp"])
    print("PASS: four fox auditions; retained", len(old["files"]), "WAVs, click, BGM and buses")


if __name__ == "__main__":
    main()

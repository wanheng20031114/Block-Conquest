"""Validate delivered samples and package every changed variant for chat playback.

The previews concatenate final runtime WAVs with 280 ms between variants. They
do not add music, narration, EQ, gain, or synthesized comparison sounds.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import wave

import numpy as np
from scipy import signal
import build_war_audio as bank

LABELS = {
    "select": "建筑选择／菜单点击", "drag": "拖起技能／拖选", "ratio": "派兵比例／设置滑条",
    "order": "派兵确认／开始对局", "denied": "条件不足", "cancel": "取消／返回",
    "pause": "打开暂停", "resume": "继续游戏",
    "skill_command": "松鼠 Q · 征召军令", "skill_drum": "松鼠 W · 疾行战鼓",
    "skill_shield": "松鼠 E · 防护罩", "skill_breach": "松鼠 R · 火攻",
    "rabbit_dash": "兔子 Q · 蹦蹦小径", "rabbit_seal": "兔子 W · 封条急件",
    "rabbit_recall": "兔子 E · 归巢口哨", "rabbit_burrow": "兔子 R · 兔洞快递",
    "projectile_hit": "炮弹实际命中",
}


def pcm(path):
    with wave.open(str(path), "rb") as reader:
        assert (reader.getnchannels(), reader.getsampwidth(), reader.getframerate()) == (1, 2, bank.SR), path
        return np.frombuffer(reader.readframes(reader.getnframes()), dtype="<i2")


def main():
    manifest = json.loads((bank.OUT / "audio_manifest.json").read_text(encoding="utf-8"))
    old = json.loads(subprocess.check_output(["git", "show", "HEAD:assets/audio/block_war/audio_manifest.json"], cwd=bank.ROOT))
    original = {item["file"]: item["sha256"] for item in old["files"]}
    output = bank.ROOT / "docs/audio/block_war"
    output.mkdir(parents=True, exist_ok=True)
    metrics, previews, retained = [], [], 0
    for item in manifest["files"]:
        path = bank.OUT / item["file"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == item["sha256"], path
        for source in item["sources"]:
            assert hashlib.sha256((bank.SOURCES / source["path"]).read_bytes()).hexdigest() == source["sha256"], source
            assert source["license"] in {"CC0-1.0", "CC-BY-3.0"}, source
        data = pcm(path)
        x = data.astype(float) / 32768.0
        peak = float(np.max(np.abs(signal.resample_poly(x, 4, 1))))
        assert len(data) >= int(.08 * bank.SR) and np.any(data) and data[0] == 0 and data[-1] == 0, path
        assert peak <= 10 ** (-2.9 / 20), path
        key = path.stem[4:-3]
        if key not in LABELS:
            assert original[path.name] == item["sha256"], f"Approved sound changed: {path.name}"
            retained += 1
        else:
            onset = int(np.flatnonzero(abs(x) >= abs(x).max() * .02)[0]) / bank.SR
            assert onset <= .025, f"Late audible onset: {path.name} {onset:.3f}s"
            metrics.append({"file": path.name, "onset_ms": round(onset * 1000, 2), "true_peak_dbfs": round(20 * np.log10(peak), 2)})
    for key, label in LABELS.items():
        files = sorted(bank.OUT.glob(f"war_{key}_[0-9][0-9].wav"))
        assert files, key
        pieces, timeline = [], []
        cursor = 0
        for index, path in enumerate(files):
            data = pcm(path)
            timeline.append({"file": path.name, "start_seconds": round(cursor / bank.SR, 3)})
            pieces.append(data)
            cursor += len(data)
            if index + 1 < len(files):
                gap = np.zeros(round(.28 * bank.SR), dtype="<i2")
                pieces.append(gap)
                cursor += len(gap)
        with wave.open(str(output / f"{key}.wav"), "wb") as writer:
            writer.setnchannels(1)
            writer.setsampwidth(2)
            writer.setframerate(bank.SR)
            writer.writeframes(np.concatenate(pieces).astype("<i2").tobytes())
        previews.append({"event": f"war_{key}", "label": label, "preview": f"{key}.wav", "variants": timeline})
    report = {"date": "2026-09-26", "unchanged_runtime_files": retained, "changed_runtime_files": len(metrics),
              "preview_events": previews, "measurements": metrics,
              "note": "Runtime WAVs at source level, every variant in order; game master volume and spatial attenuation are not baked into auditions."}
    (output / "review.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Verified {len(manifest['files'])} runtime files; preserved {retained}; reviewed {len(metrics)} changed files in {len(previews)} players")
    print(f"Changed-cue onset: {min(m['onset_ms'] for m in metrics):.2f} to {max(m['onset_ms'] for m in metrics):.2f} ms")


if __name__ == "__main__":
    main()

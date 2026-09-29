"""Build the original, dry menu click; no downloaded audio is mixed into it.

Run: python tools/build_ui_click.py
Design references and native mixer audition: docs/ui_click_review.md.
The standalone entry point updates only the menu asset/manifest entry.
"""
from pathlib import Path
import hashlib
import json
import wave

import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/audio/ui/soft_click.wav"
SR = 48000


def design_click():
    t = np.arange(round(0.048 * SR)) / SR
    # A single contact: broad, rapidly damped friction with a faint low body.
    # Fixed seed keeps exports reproducible; there is no pitch sweep or echo.
    noise = np.random.default_rng(927).standard_normal(len(t))
    contact = signal.sosfilt(signal.butter(2, [300, 3200], btype="bandpass", fs=SR, output="sos"), noise)
    contact *= (-np.expm1(-t / 0.00035)) ** 2 * np.exp(-t / 0.010)
    body = np.sin(2 * np.pi * 740 * t) * (-np.expm1(-t / 0.0004)) * np.exp(-t / 0.006)
    x = contact + 0.2 * body
    x = signal.sosfilt(signal.butter(3, 4200, fs=SR, output="sos"), x)
    x = signal.sosfilt(signal.butter(2, 170, btype="highpass", fs=SR, output="sos"), x)
    x[:24] *= np.sin(np.linspace(0, np.pi / 2, 24)) ** 2
    x[-240:] *= np.cos(np.linspace(0, np.pi / 2, 240)) ** 2
    # Short-event energy, with explicit silence padding to 50 ms. A streaming
    # LUFS target is unsuitable for a 48 ms transient.
    x *= 10 ** (-20.5 / 20) / np.sqrt(np.sum(x * x) / (0.05 * SR))
    peak = np.max(np.abs(signal.resample_poly(x, 4, 1)))
    x *= min(1.0, 10 ** (-4.5 / 20) / peak)
    x[0] = x[-1] = 0.0
    return np.round(x * 32767).astype("<i2")


def build_menu_click():
    pcm = design_click()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(SR)
        writer.writeframes(pcm.tobytes())
    x = pcm.astype(float) / 32768.0
    return {
        "file": "../ui/soft_click.wav",
        "source": "Project-original deterministic contact synthesis; no third-party samples",
        "generator": "tools/build_ui_click.py",
        "format": "48 kHz mono PCM16 WAV",
        "duration_seconds": len(pcm) / SR,
        "sha256": hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        "processing": "48 ms dry contact, rounded onset, damped low body, 4.2 kHz low-pass, boundary fades; no reverb, sweep or saturation",
        "license": "LicenseRef-Project-Original",
        "gain_db": -8.0,
        "rms_50ms_dbfs": round(float(20 * np.log10(np.sqrt(np.sum(x * x) / (0.05 * SR)))), 2),
        "true_peak_dbtp": round(float(20 * np.log10(np.max(np.abs(signal.resample_poly(x, 4, 1))))), 2),
    }


if __name__ == "__main__":
    entry = build_menu_click()
    manifest_path = ROOT / "assets/audio/block_war/audio_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["menu_click"] = entry
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(entry, ensure_ascii=False, indent=2))

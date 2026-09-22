"""Build the Block War foley bank from retained CC0 recordings, without oscillators.

Run: python tools/build_war_audio.py
Requires numpy, scipy and ffmpeg on PATH. Does not modify the original-mode bank.
All outputs are 48 kHz mono PCM16 with deterministic edits and source provenance.
"""

from functools import lru_cache
from pathlib import Path
import hashlib
import json
import math
import subprocess
import wave

import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "assets/audio/sources"
OUT = ROOT / "assets/audio/block_war"
SR = 48000
USED = set()

# name, variants, bus, gain dB, priority, minimum gap ms, simultaneous limit
EVENTS = [
    ("select", 2, "UI", -1, 2, 95, 2),
    ("drag", 2, "UI", -4, 1, 140, 2),
    ("ratio", 2, "UI", -3, 2, 75, 2),
    ("order", 2, "UI", 0, 3, 150, 2),
    ("denied", 1, "UI", -1, 4, 350, 1),
    ("cancel", 1, "UI", -2, 2, 130, 1),
    ("pause", 1, "UI", -1, 4, 180, 1),
    ("resume", 1, "UI", -1, 4, 180, 1),
    ("march", 4, "Foley", 2, 1, 190, 2),
    ("melee", 4, "Combat", -1, 2, 130, 3),
    ("capture", 2, "UI", 0, 5, 550, 2),
    ("lost", 1, "UI", 0, 5, 650, 1),
    ("reinforce", 2, "Combat", -2, 2, 280, 2),
    ("upgrade", 2, "Combat", 1, 4, 500, 2),
    ("rebuild", 2, "Combat", 1, 4, 500, 2),
    ("skill_command", 1, "Combat", 2, 5, 550, 1),
    ("skill_drum", 1, "Combat", 2, 5, 650, 1),
    ("skill_shield", 1, "Combat", 1, 5, 650, 1),
    ("skill_breach", 2, "Combat", 1, 6, 500, 2),
    ("victory", 1, "UI", 0, 7, 1200, 1),
    ("defeat", 1, "UI", 0, 7, 1200, 1),
]

DESCRIPTIONS = {
    "select": "Dry carved-wood contact and a small leather buckle",
    "drag": "Short leather and arrow-feather brush while extending a selection",
    "ratio": "Light wooden notch as the dispatch fraction changes",
    "order": "Wooden command stamp followed by an equipment buckle",
    "denied": "Two descending damped wooden knocks",
    "cancel": "Closing leather strap and a low wooden latch",
    "pause": "Descending pair of restrained wooden contacts",
    "resume": "Ascending pair of restrained wooden contacts",
    "march": "A small group of grass and leather footfalls with equipment movement",
    "melee": "Sword contact against wood and armour, with restrained metallic brightness",
    "capture": "Rising struck-bell contacts over a flag-like feather and leather rustle",
    "lost": "Two falling low bell contacts and a soft wooden final impact",
    "reinforce": "Boot arrival, leather movement and equipment settling",
    "upgrade": "Three rising construction hammer contacts, then a short bright bell",
    "rebuild": "Timber release followed by stone placement and a wooden latch",
    "skill_command": "Command stamp followed by a short mustering boot sequence",
    "skill_drum": "Low wooden and soft-contact layers edited into a quickening drum roll",
    "skill_shield": "Armour locking, layered heavy metal resonance and stone contact",
    "skill_breach": "Falling stone scrape, deep impact, and staggered masonry fragments",
    "victory": "Four rising recorded bell strikes with flag and equipment rustle",
    "defeat": "Falling armour and two low fading bell strikes",
}


def rms_active(samples):
    padded = np.pad(samples, (0, (-len(samples)) % 960))
    power = np.mean(padded.reshape(-1, 960) ** 2, axis=1)
    return math.sqrt(float(power[power >= max(float(power.max()) * 0.01, 1e-14)].mean()))


def filt(samples, hz, mode="lowpass"):
    return signal.sosfilt(signal.butter(3, hz, btype=mode, fs=SR, output="sos"), samples)


@lru_cache(maxsize=None)
def decode(relative):
    data = subprocess.run([
        "ffmpeg", "-v", "error", "-i", str(SOURCES / relative),
        "-f", "f32le", "-ac", "1", "-ar", str(SR), "pipe:1",
    ], capture_output=True, check=True).stdout
    samples = np.frombuffer(data, dtype="<f4").astype(np.float64)
    samples -= samples.mean()
    threshold = float(np.max(np.abs(samples))) * 0.014
    indices = np.flatnonzero(np.abs(samples) > threshold)
    assert len(indices), f"Silent source: {relative}"
    return samples[max(0, indices[0] - 96):min(len(samples), indices[-1] + 960)]


def take(pack, name, rate=1.0, seconds=0.45, cutoff=6500):
    relative = f"{pack}/{name}"
    USED.add(relative)
    samples = decode(relative).copy()
    if rate != 1.0:
        samples = signal.resample_poly(samples, 1000, round(rate * 1000))
    samples = filt(filt(samples, 65, "highpass"), cutoff)[:round(seconds * SR)]
    samples /= max(rms_active(samples), 1e-10)
    fade = min(len(samples) // 2, 384)
    samples[:48] *= np.linspace(0, 1, min(len(samples), 48))
    samples[-fade:] *= np.linspace(1, 0, fade)
    return samples


def impact(name, index, **kwargs):
    return take("kenney_impact", f"{name}_{index:03}.ogg", **kwargs)


def apparel(name, index, **kwargs):
    return take("weapons_apparel", f"{name}-{index:02}.wav", **kwargs)


def bell(rate=1.0, seconds=0.55):
    return impact("impactBell_heavy", 2, rate=rate, seconds=seconds, cutoff=5200)


def mix(seconds, layers):
    output = np.zeros(round(seconds * SR))
    for samples, at, gain in layers:
        start = round(at * SR)
        count = min(len(samples), len(output) - start)
        if count > 0:
            output[start:start + count] += samples[:count] * gain
    return output


def make(name, variant):
    n = variant
    wood = lambda rate=1., seconds=.18: impact("impactWood_light", n % 5, rate=rate, seconds=seconds)
    leather = lambda seconds=.3: apparel("quiver-leather-squeeze", [2, 3, 4, 5][n % 4], seconds=seconds)
    buckle = lambda rate=1.: apparel("belt-buckle", n % 3 + 1, rate=rate, seconds=.25)
    foot = lambda i, rate=1.: impact("footstep_grass", i % 4, rate=rate, seconds=.22)
    heavy = lambda rate=.8: impact("impactWood_heavy", n % 5, rate=rate, seconds=.34, cutoff=3700)
    stone = lambda i=0, rate=1.: impact("impactMining", (n+i) % 5, rate=rate, seconds=.34, cutoff=5400)
    if name == "select":
        return mix(.17, [(wood(1.2), 0, .8), (buckle(1.2), .015, .13)])
    if name == "drag":
        return mix(.24, [(leather(.2), 0, .6), (apparel("arrow-feathers", n % 3 + 1, seconds=.2), .018, .4)])
    if name == "ratio":
        return mix(.10, [(wood(1.65, .1), 0, .9)])
    if name == "order":
        return mix(.32, [(heavy(1.18), 0, .65), (buckle(1.2), .08, .32), (foot(n, 1.15), .11, .2)])
    if name == "denied":
        return mix(.34, [(wood(.8), 0, .7), (wood(.62), .14, .85)])
    if name == "cancel":
        return mix(.23, [(leather(.16), 0, .5), (wood(.8), .06, .5)])
    if name in ("pause", "resume"):
        rates = (.95, .70) if name == "pause" else (.80, 1.3)
        return mix(.26, [(wood(rates[0]), 0, .6), (wood(rates[1]), .115, .7)])
    if name == "march":
        return mix(.56, [
            (foot(n, .92 + n * .025), 0, .7),
            (apparel("boots-leather-step", n % 4 + 1, seconds=.23), .025, .3),
            (foot(n+1, 1.10), .16, .62), (foot(n+2, 1.03), .33, .5),
            (leather(.16), .19, .11),
        ])
    if name == "melee":
        sword = apparel("sword-knife-clash", [1, 9, 18, 31][n % 4], rate=.92+n*.035, seconds=.32, cutoff=4300)
        return mix(.44, [(heavy(.95), 0, .60), (sword, .012, .33), (stone(1, 1.1), .07, .13)])
    if name == "capture":
        return mix(.90, [(bell(1.15+n*.04, .42), 0, .55), (bell(1.54+n*.04), .19, .7),
                         (apparel("arrow-feathers", n+1, seconds=.38), .07, .18), (buckle(), .32, .15)])
    if name == "lost":
        return mix(.96, [(bell(.84, .5), 0, .5), (bell(.63, .60), .24, .7), (heavy(.65), .31, .3)])
    if name == "reinforce":
        return mix(.47, [(apparel("boots-leather-jump", n+1, seconds=.32), 0, .7),
                         (leather(.25), .04, .24), (buckle(.85), .16, .28)])
    if name == "upgrade":
        return mix(.95, [(stone(0, .92), 0, .62), (stone(1, 1.1), .17, .64),
                         (stone(2, 1.3), .33, .55), (bell(1.65, .50), .44, .48)])
    if name == "rebuild":
        return mix(.96, [(impact("impactPlank_medium", n+1, rate=.82, seconds=.33), 0, .55),
                         (leather(.35), .03, .18), (stone(2, .84), .24, .55),
                         (heavy(1.12), .52, .50), (buckle(1.35), .57, .15)])
    if name == "skill_command":
        return mix(.80, [(heavy(.75), 0, .8), (buckle(.78), .07, .35),
                         (foot(0), .20, .6), (foot(1), .35, .65), (foot(2), .50, .7)])
    if name == "skill_drum":
        drum = mix(.26, [(impact("impactSoft_heavy", 2, rate=.64, seconds=.26, cutoff=1300), 0, .65),
                          (impact("impactWood_heavy", 2, rate=.64, seconds=.23, cutoff=1700), .008, .35)])
        return mix(.99, [(drum, t, gain) for t, gain in [(0, .8), (.24, .7), (.45, .8), (.62, .7), (.76, 1.)]])
    if name == "skill_shield":
        return mix(.95, [(impact("impactMetal_heavy", 3, rate=.72, seconds=.62, cutoff=4700), .03, .5),
                         (buckle(.72), 0, .4), (bell(.75, .67), .16, .25), (stone(3, .72), .05, .35)])
    if name == "skill_breach":
        fall = apparel("sword-table-leg-scrape", n+1, rate=.64, seconds=.23, cutoff=2800)
        return mix(1.0, [(fall, 0, .16), (stone(0, .64), .16, .8), (heavy(.55), .17, .60),
                         (stone(1, 1.04), .28, .30), (stone(3, 1.28), .39, .18), (stone(4, .9), .54, .11)])
    if name == "victory":
        return mix(1.68, [(bell(rate, .65), at, gain) for rate, at, gain in
                         [(1., 0, .55), (1.26, .24, .62), (1.50, .48, .65), (2.0, .86, .75)]] +
                        [(apparel("arrow-feathers", 2, rate=.82, seconds=.5), .78, .22), (buckle(1.4), 1.12, .2)])
    if name == "defeat":
        return mix(1.53, [(impact("impactMetal_heavy", 1, rate=.67, seconds=.6, cutoff=2500), 0, .3),
                         (bell(.70, .7), .11, .55), (bell(.52, .85), .52, .48),
                         (apparel("boots-leather-jump", 3, rate=.7, seconds=.45), .07, .3)])
    raise ValueError(name)


def export(name, samples, description):
    samples = filt(samples, 60, "highpass")
    # Softly shape exceptional transients, then normalize the audible portion.
    samples = np.tanh(samples / max(rms_active(samples) * 4.5, 1e-10))
    samples *= 10 ** (-17.5 / 20) / max(rms_active(samples), 1e-10)
    true_peak = float(np.max(np.abs(signal.resample_poly(samples, 4, 1))))
    samples *= min(1., 10 ** (-3.0 / 20) / max(true_peak, 1e-10))
    samples[:96] *= np.linspace(0, 1, 96)
    samples[-960:] *= np.linspace(1, 0, 960)
    samples[0] = samples[-1] = 0
    path = OUT / f"{name}.wav"
    pcm = np.round(samples * 32767).astype("<i2")
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(SR)
        file.writeframes(pcm.tobytes())
    return {"file": path.name, "description": description, "seconds": round(len(samples)/SR, 3),
            "active_rms_db": round(20*math.log10(rms_active(samples)), 2),
            "true_peak_db": round(20*math.log10(float(np.max(np.abs(signal.resample_poly(samples, 4, 1))))), 2),
            "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "sources": [{"path": source, "sha256": hashlib.sha256((SOURCES/source).read_bytes()).hexdigest()}
                        for source in sorted(USED)]}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files = []
    bank = ['extends RefCounted', '## Offline CC0 foley; each event uses the shared bounded native voice pool.',
            '## Generated by tools/build_war_audio.py. UI/world call sites must match the bus.', '', 'const EVENTS: Dictionary = {']
    for name, count, bus, gain, priority, gap, limit in EVENTS:
        streams = []
        for index in range(count):
            USED.clear()
            filename = f"war_{name}_{index+1:02}"
            samples = make(name, index)
            files.append(export(filename, samples, DESCRIPTIONS[name]))
            streams.append(f'preload("res://assets/audio/block_war/{filename}.wav")')
        bank.append(f'\t"war_{name}": {{"streams": [{", ".join(streams)}], "gain_db": {gain:.1f}, '
                    f'"bus": &"{bus}", "priority": {priority}, "gap_ms": {gap}, "limit": {limit}}},')
    bank += ['}', '']
    (ROOT / "scripts/block_war/war_sound_bank.gd").write_text("\n".join(bank), encoding="utf-8")
    manifest = {"format": "48 kHz mono PCM16 WAV", "generator": "tools/build_war_audio.py",
                "processing": "Recorded layers, trim, filtering, resampling/pitch, timed edits, gentle transient shaping, active RMS normalization, fades. No generated tone or noise layers.",
                "license": "CC0; original sources and licensing retained in ../sources and ../CREDITS.md",
                "events": len(EVENTS), "files": files}
    (OUT / "audio_manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False)+"\n", encoding="utf-8")
    print(f"Built {len(EVENTS)} events / {len(files)} WAV files / {sum(f['bytes'] for f in files):,} bytes")
    print(f"True peaks: {min(f['true_peak_db'] for f in files):.2f} to {max(f['true_peak_db'] for f in files):.2f} dBFS")


if __name__ == "__main__":
    main()

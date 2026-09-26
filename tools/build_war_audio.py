"""Build Block War audio from retained, commercially reusable source assets.

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
SOURCE_PACKS = json.loads((ROOT / "assets/audio/sources.json").read_text(encoding="utf-8"))["packs"]

# name, variants, bus, gain dB, priority, minimum gap ms, simultaneous limit
EVENTS = [
    ("select", 2, "UI", -6, 2, 95, 2),
    ("drag", 2, "UI", -8, 1, 140, 2),
    ("ratio", 2, "UI", -3, 2, 75, 2),
    ("order", 2, "UI", -3, 3, 150, 2),
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
    ("rabbit_dash", 1, "Combat", 1, 5, 120, 2),
    ("rabbit_seal", 2, "Combat", 1, 5, 120, 2),
    ("rabbit_recall", 1, "Combat", -1, 5, 120, 2),
    ("rabbit_burrow", 2, "Combat", 1, 5, 120, 2),
    ("projectile_hit", 2, "Combat", -3, 3, 120, 3),
    ("victory", 1, "UI", 0, 7, 1200, 1),
    ("defeat", 1, "UI", 0, 7, 1200, 1),
]

DESCRIPTIONS = {
    "select": "Very quiet 80 ms single wood tap for selecting a building; no tonal tail",
    "drag": "Quiet 90 ms single wood tap on skill pickup; marching-line movement is silent",
    "ratio": "Light menu note, shortened for repeated dispatch-ratio changes",
    "order": "One restrained 160 ms dry wood-block contact on dispatch release; no layers or melody",
    "denied": "Existing downward back cue with a clear, restrained rejection tail",
    "cancel": "Quieter, shorter version of the back cue for cancellation",
    "pause": "Recorded book opening; a soft paper-led menu opening gesture",
    "resume": "Recorded book closing; a short, firm menu closing gesture",
    "march": "A small group of grass and leather footfalls with equipment movement",
    "melee": "Sword contact against wood and armour, with restrained metallic brightness",
    "capture": "Rising struck-bell contacts over a flag-like feather and leather rustle",
    "lost": "Two falling low bell contacts and a soft wooden final impact",
    "reinforce": "Boot arrival, leather movement and equipment settling",
    "upgrade": "Three rising construction hammer contacts, then a short bright bell",
    "rebuild": "Timber release followed by stone placement and a wooden latch",
    "skill_command": "Existing bright item jingle for a warm mustering command",
    "skill_drum": "Short excerpt of an existing war-drum composition; no wood-impact imitation",
    "skill_shield": "Clear chime on release followed by an existing warm magical shimmer",
    "skill_breach": "Existing fire impact with immediate ignition, outward rush and burning tail",
    "rabbit_dash": "Existing wind spell and a light paper flutter, beginning on release",
    "rabbit_seal": "Recorded paper placement and brief page movement for the seal",
    "rabbit_recall": "Existing whistle cue for recalling troops",
    "rabbit_burrow": "Existing stone movement and a soft leather drop for opening earth",
    "projectile_hit": "Soft impact and a restrained equipment contact at the projectile collision",
    "victory": "Four rising recorded bell strikes with flag and equipment rustle",
    "defeat": "Falling armour and two low fading bell strikes",
}

# Retain the approved combat/footstep/result assets byte-for-byte. Only these
# cues take the transparent editing path; no saturation or heavy pitch warping.
REFINED = set("select drag ratio order denied cancel pause resume skill_command skill_drum skill_shield skill_breach rabbit_dash rabbit_seal rabbit_recall rabbit_burrow projectile_hit".split())


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


def recorded(relative, seconds, rate=1.0):
    USED.add(relative)
    samples = decode(relative).copy()
    onset = np.flatnonzero(np.abs(samples) >= np.max(np.abs(samples)) * .025)[0]
    samples = samples[max(0, onset - 48):]
    if rate != 1.0:
        samples = signal.resample_poly(samples, 1000, round(rate * 1000))
    samples = samples[:round(seconds * SR)]
    samples /= max(float(np.max(np.abs(samples))), 1e-10)
    # Source transients remain intact; only the edit boundaries receive fades.
    samples[:48] *= np.linspace(0, 1, min(len(samples), 48))
    fade = min(round(.04 * SR), len(samples) // 4)
    samples[-fade:] *= np.linspace(1, 0, fade)
    return samples


def refined(name, n):
    clip = recorded
    if name in ("select", "drag", "order"):
        seconds = {"select": .08, "drag": .09, "order": .16}[name]
        material = "medium" if name == "order" else "light"
        contact = clip(f"kenney_impact/impactWood_{material}_{n + 1:03}.ogg", seconds)
        # A single dry contact, padded only to keep the sample boundary silent.
        return mix(seconds, [(contact, 0, 1.0)])
    if name == "ratio":
        return clip("virix_ui1/Menu1B.wav", .14, 1.0 + n * .025)
    if name in ("denied", "cancel"):
        return clip("virix_ui/MENU B_Back.wav", .56 if name == "denied" else .25)
    if name in ("pause", "resume"):
        return clip(f"kenney_rpg/book{'Open' if name == 'pause' else 'Close'}.ogg", .45 if name == "pause" else .32)
    if name == "skill_command":
        return clip("virix_ui2/Item2A.wav", 1.1)
    if name == "skill_drum":
        return clip("hector_drums/horde_war_drums_by_william_hector.wav", .94)
    if name == "skill_shield":
        return mix(1.65, [(clip("virix_ui1/Item1A.wav", .65), 0, .28),
                          (clip("virix_magic/Healing Full.wav", 1.65), 0, .65)])
    if name == "skill_breach":
        return clip("virix_magic/Fire impact 1.wav", 2.6, 1.0 + n * .025)
    if name == "rabbit_dash":
        return mix(1.05, [(clip("virix_magic/Wind effects 5.wav", 1.05), 0, .8),
                          (clip("kenney_rpg/bookFlip1.ogg", .18), 0, .16)])
    if name == "rabbit_seal":
        return mix(.34, [(clip("kenney_rpg/bookPlace1.ogg", .28, 1.0 + n * .025), 0, .7),
                         (clip(f"kenney_rpg/bookFlip{n + 1}.ogg", .27), .018, .25)])
    if name == "rabbit_recall":
        return clip("dklon_whistles/whistle_1.wav", .85)
    if name == "rabbit_burrow":
        return mix(.78, [(clip(f"rubberduck_rpg/stones_0{n + 1}.ogg", .72), 0, .75),
                         (clip("kenney_rpg/dropLeather.ogg", .3), 0, .25)])
    if name == "projectile_hit":
        return mix(.26, [(clip(f"kenney_impact/impactSoft_heavy_00{n + 1}.ogg", .25), 0, .8),
                         (clip(f"weapons_apparel/belt-buckle-0{n + 1}.wav", .15), .01, .15)])
    raise ValueError(name)


def make(name, variant):
    if name in REFINED:
        return refined(name, variant)
    n = variant
    leather = lambda seconds=.3: apparel("quiver-leather-squeeze", [2, 3, 4, 5][n % 4], seconds=seconds)
    buckle = lambda rate=1.: apparel("belt-buckle", n % 3 + 1, rate=rate, seconds=.25)
    foot = lambda i, rate=1.: impact("footstep_grass", i % 4, rate=rate, seconds=.22)
    heavy = lambda rate=.8: impact("impactWood_heavy", n % 5, rate=rate, seconds=.34, cutoff=3700)
    stone = lambda i=0, rate=1.: impact("impactMining", (n+i) % 5, rate=rate, seconds=.34, cutoff=5400)
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
    event = name[4:-3]
    transparent = event in REFINED
    target_db = -22.0 if event in {"select", "drag", "ratio", "cancel", "pause", "resume"} else -19.5
    target_db = {"select": -24.0, "drag": -26.0, "order": -22.0}.get(event, target_db)
    if not transparent:
        samples = filt(samples, 60, "highpass")
        samples = np.tanh(samples / max(rms_active(samples) * 4.5, 1e-10))
        target_db = -17.5
    samples *= 10 ** (target_db / 20) / max(rms_active(samples), 1e-10)
    true_peak = float(np.max(np.abs(signal.resample_poly(samples, 4, 1))))
    ceiling_db = -7.0 if transparent and event in {"select", "drag", "ratio", "order", "denied", "cancel", "pause", "resume"} else -3.0
    samples *= min(1., 10 ** (ceiling_db / 20) / max(true_peak, 1e-10))
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
            "processing": "Trim, boundary fades, small variant rate change where noted, linear gain/true-peak ceiling; no saturation" if transparent else "Original retained foley recipe",
            "sources": [{"path": source, "sha256": hashlib.sha256((SOURCES/source).read_bytes()).hexdigest(),
                         "license": SOURCE_PACKS[source.split('/')[0]]["license"],
                         "page": SOURCE_PACKS[source.split('/')[0]]["page"]}
                        for source in sorted(USED)]}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files = []
    bank = ['extends RefCounted', '## Licensed source edits; attribution is retained in assets/audio/CREDITS.md.',
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
                "processing": "UI and skills use transparent source editing. Approved combat and result recipes are retained. See each file and tools/build_war_audio.py for exact edits.",
                "license": "CC0-1.0 and CC-BY-3.0, listed per source; see ../CREDITS.md and ../licenses",
                "events": len(EVENTS), "files": files}
    # Keep the user's requested arc-nice click byte-for-byte, including its 44.1 kHz format.
    menu_source = SOURCES / "arc_nice_ui/ui_click.wav"
    menu_path = ROOT / "assets/audio/ui/arc_nice_click.wav"
    menu_path.parent.mkdir(parents=True, exist_ok=True)
    menu_path.write_bytes(menu_source.read_bytes())
    manifest["menu_click"] = {"file": "../ui/arc_nice_click.wav", "source": "arc_nice_ui/ui_click.wav",
                              "sha256": hashlib.sha256(menu_source.read_bytes()).hexdigest(),
                              "processing": "Unmodified copy; native player -8 dB, pitch 0.992..1.008 as in arc-nice",
                              "license": "LicenseRef-User-Project", "gain_db": -8.0}
    (OUT / "audio_manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False)+"\n", encoding="utf-8")
    print(f"Built {len(EVENTS)} events / {len(files)} WAV files / {sum(f['bytes'] for f in files):,} bytes")
    print(f"True peaks: {min(f['true_peak_db'] for f in files):.2f} to {max(f['true_peak_db'] for f in files):.2f} dBFS")


if __name__ == "__main__":
    main()

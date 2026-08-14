"""Author the thirteen sound effects that were still flagged as temporary foley.

Twelve of them were portal hums and all twelve pointed at the same `fountain_loop.ogg`, so every
portal in the game sounded like the same running water regardless of which realm it opened onto.
The thirteenth, `ui_interact_near`, borrowed the ordinary click.

Each portal now gets its own voice built from the fundamental the manifest already declared in its
`fallback_tone` — those frequencies were the design intent, they just had no asset behind them.
A hum is three things layered: the fundamental and its fifth as a slow beating drone, a shimmer an
octave or two up that drifts, and a filtered noise bed for air. The biome character comes from how
those are balanced and filtered — glass and bell for crystal, wet and dark for swamp, wide and cold
for frozen.

Usage:  python tools/generate_sfx.py [--check]
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import audio_synth as A  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[1]
SFX_JSON = ROOT / "content/audio/sfx.json"
SFX_DIR = ROOT / "apps/game/client/assets/audio/sfx"

HUM_SECONDS = 4.0

#: How each realm's portal should read. `shimmer` is the partial the sparkle sits on, `noise` the
#: band of the air bed, `bright` the lowpass on the whole thing, `wobble` the drift rate in Hz.
PORTAL_VOICES = {
    "castle":    {"shimmer": 3.0,  "noise": (400, 2200),  "bright": 2600, "wobble": 0.19, "air": 0.16},
    "crystal":   {"shimmer": 6.0,  "noise": (1800, 7000), "bright": 7200, "wobble": 0.31, "air": 0.10},
    "swamp":     {"shimmer": 2.0,  "noise": (120, 900),   "bright": 1200, "wobble": 0.11, "air": 0.30},
    "frozen":    {"shimmer": 5.0,  "noise": (1400, 6000), "bright": 6200, "wobble": 0.24, "air": 0.22},
    "cathedral": {"shimmer": 4.0,  "noise": (300, 1800),  "bright": 2400, "wobble": 0.09, "air": 0.14},
    "vault":     {"shimmer": 2.0,  "noise": (90, 700),    "bright": 1000, "wobble": 0.07, "air": 0.12},
    "prism":     {"shimmer": 8.0,  "noise": (2200, 9000), "bright": 9000, "wobble": 0.42, "air": 0.09},
    "mire":      {"shimmer": 2.0,  "noise": (140, 1000),  "bright": 1300, "wobble": 0.13, "air": 0.34},
    "hollow":    {"shimmer": 4.0,  "noise": (600, 3200),  "bright": 3400, "wobble": 0.16, "air": 0.26},
    "umbral":    {"shimmer": 3.0,  "noise": (80, 1200),   "bright": 1500, "wobble": 0.06, "air": 0.20},
    "training":  {"shimmer": 3.0,  "noise": (500, 2600),  "bright": 3000, "wobble": 0.21, "air": 0.15},
    "skies":     {"shimmer": 6.0,  "noise": (900, 5200),  "bright": 5600, "wobble": 0.27, "air": 0.24},
}


def portal_hum(fundamental: float, voice: dict, rng: np.random.Generator) -> np.ndarray:
    def render(seconds: float) -> np.ndarray:
        t = np.arange(A.n_samples(seconds)) / A.SAMPLE_RATE
        # Two voices a hair apart beat slowly against each other. That slow pulse is what makes a
        # drone sound alive rather than like a held synth note.
        drone = A.sine(fundamental, seconds) + 0.8 * A.sine(fundamental * 1.006, seconds)
        drone += 0.45 * A.sine(fundamental * 1.5, seconds)
        drift = 1.0 + 0.004 * np.sin(2.0 * math.pi * voice["wobble"] * t)
        shimmer = A.sine(fundamental * voice["shimmer"] * drift, seconds) * 0.16
        shimmer += A.sine(fundamental * voice["shimmer"] * 1.498, seconds) * 0.08
        air = A.bandpass(A.noise(seconds, rng), *voice["noise"]) * voice["air"]
        mix = A.lowpass(drone * 0.55 + shimmer + air, voice["bright"], poles=2)
        # A slow swell keeps a looping hum from sitting flat under the player's attention.
        return (mix * (0.82 + 0.18 * np.sin(2.0 * math.pi * 0.13 * t))).astype(np.float32)

    loop = A.make_loop(render, HUM_SECONDS, tail_seconds=1.4)
    loop = A.reverb(loop, 1.1, 0.28, rng)
    return A.normalize(loop, 0.62)


def ui_interact_near(rng: np.random.Generator) -> np.ndarray:
    """A soft two-note rise for "you can interact with this" — quieter and warmer than a click.

    It fires whenever the player drifts near anything usable, so it has to be unobtrusive; the
    shared click was far too percussive for something that can retrigger as you walk past a shelf.
    """
    seconds = 0.22
    a = A.sine(880.0, seconds) * A.adsr(seconds, 0.006, 0.05, 0.35, 0.14)
    b = A.sine(1320.0, seconds) * A.adsr(seconds, 0.030, 0.06, 0.28, 0.12)
    bell = 0.35 * A.sine(2640.0, seconds) * A.adsr(seconds, 0.004, 0.03, 0.10, 0.10)
    mix = A.lowpass(a * 0.7 + b * 0.5 + bell, 6000.0, poles=1)
    return A.normalize(A.reverb(A.fade(mix, 0.008), 0.35, 0.20, rng), 0.5)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="verify only, write nothing")
    args = ap.parse_args()

    manifest = json.loads(SFX_JSON.read_text(encoding="utf-8"))
    entries = manifest["sfx"]
    rng = np.random.default_rng(0xA17B)
    written: list[str] = []
    problems: list[str] = []

    for key, entry in entries.items():
        if not entry.get("placeholder"):
            continue
        if key == "ui_interact_near":
            sig = None if args.check else ui_interact_near(rng)
            out_name = "ui_interact_near.ogg"
        elif key.startswith("portal_hum_"):
            realm = key[len("portal_hum_") :]
            voice = PORTAL_VOICES.get(realm)
            if voice is None:
                problems.append(f"{key}: no voice defined for realm '{realm}'")
                continue
            freq = float(entry.get("fallback_tone", {}).get("freq", 72.0))
            sig = None if args.check else portal_hum(freq, voice, rng)
            out_name = f"{key}.ogg"
        else:
            problems.append(f"{key}: no generator for this placeholder")
            continue

        out_path = SFX_DIR / out_name
        if not args.check:
            A.write_ogg(out_path, sig, quality=5)
        res_path = f"res://assets/audio/sfx/{out_name}"
        entry["variants"] = [res_path]
        entry.pop("placeholder", None)
        written.append(out_name)

    if problems:
        for p in problems:
            print("PROBLEM", p)
        return 1

    if not args.check:
        SFX_JSON.write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
            newline="\n",
        )

    remaining = [k for k, v in entries.items() if v.get("placeholder")]
    for name in written:
        size = (SFX_DIR / name).stat().st_size if (SFX_DIR / name).exists() else 0
        print(f"  {name:<28} {size:>7} bytes")
    print(f"\nauthored {len(written)} effects; {len(remaining)} placeholders remain")
    return 1 if remaining else 0


if __name__ == "__main__":
    raise SystemExit(main())

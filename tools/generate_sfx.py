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


# --- hurtbox material impacts --------------------------------------------------------------
#
# `hurtbox.gd`/`hit_feedback.gd` picks one of these by the *target's* `hit_material`
# (flesh/armour/stone/crystal/bone/ooze) — flesh and armour already have real foley, these four
# were the placeholders. All four are `A.modal()` bodies (see its docstring: a struck solid rings
# at an inharmonic, unequally-decaying set of partials, which is the entire difference between
# "something was hit" and "a synth played a note") plus `A.transient()` for the initial contact
# click, in the same two-layer shape every other impact in the bank already uses.


def hit_stone(rng: np.random.Generator) -> np.ndarray:
    seconds = 0.22
    body = A.modal(
        [128.0, 184.0, 261.0, 349.0],
        seconds,
        decays=[16.0, 22.0, 34.0, 52.0],
        gains=[1.0, 0.5, 0.28, 0.14],
        detune=0.01,
        rng=rng,
    )
    mix = np.zeros_like(body)
    A.place(mix, body, 0.0)
    A.place(mix, A.transient(0.018, rng, cutoff=2600.0), 0.0, gain=0.55)
    mix = A.lowpass(mix, 2800.0, poles=1)
    return A.normalize(A.fade(mix, 0.002), 0.86)


def hit_crystal(rng: np.random.Generator) -> np.ndarray:
    seconds = 0.55
    body = A.modal(
        [780.0, 1170.0, 1950.0, 2730.0, 4160.0],
        seconds,
        decays=[3.2, 4.6, 7.0, 10.5, 16.0],
        gains=[1.0, 0.62, 0.42, 0.26, 0.15],
        detune=0.012,
        rng=rng,
    )
    mix = np.zeros_like(body)
    A.place(mix, body, 0.0)
    A.place(mix, A.transient(0.008, rng, cutoff=9500.0), 0.0, gain=0.5)
    return A.normalize(A.fade(mix, 0.001), 0.82)


def hit_bone(rng: np.random.Generator) -> np.ndarray:
    seconds = 0.11
    body = A.modal(
        [340.0, 610.0, 890.0],
        seconds,
        decays=[70.0, 100.0, 150.0],
        gains=[1.0, 0.45, 0.22],
        detune=0.02,
        rng=rng,
    )
    mix = np.zeros_like(body)
    A.place(mix, body, 0.0)
    A.place(mix, A.transient(0.012, rng, cutoff=6500.0), 0.0, gain=0.85)
    mix = A.highpass(mix, 90.0, poles=1)
    return A.normalize(A.fade(mix, 0.001), 0.87)


def hit_ooze(rng: np.random.Generator) -> np.ndarray:
    seconds = 0.26
    squelch = A.bandpass(A.noise(seconds, rng), 70.0, 850.0)
    squelch *= A.adsr(seconds, 0.006, 0.07, 0.25, 0.15)
    thump = A.sine(95.0, seconds) * A.adsr(seconds, 0.008, 0.09, 0.0, 0.12) * 0.55
    mix = squelch * 0.8 + thump
    return A.normalize(A.fade(mix, 0.003), 0.78)


def hit_poise_break(rng: np.random.Generator) -> np.ndarray:
    """The stagger moment — bigger and grittier than any single-material hit, since it always
    plays on top of one of the four above rather than instead of it."""
    seconds = 0.5
    body = A.modal(
        [82.0, 165.0, 233.0, 340.0, 470.0],
        seconds,
        decays=[9.0, 12.0, 18.0, 26.0, 38.0],
        gains=[1.0, 0.7, 0.4, 0.26, 0.16],
        detune=0.015,
        rng=rng,
    )
    crunch = A.bandpass(A.noise(0.09, rng), 200.0, 3200.0) * np.exp(
        -np.linspace(0.0, 16.0, A.n_samples(0.09), dtype=np.float32)
    )
    crunch = np.pad(crunch, (0, A.n_samples(seconds) - crunch.shape[0]))
    mix = body * 0.85 + crunch * 0.6
    return A.normalize(A.reverb(A.fade(mix, 0.002), 0.5, 0.14, rng), 0.9)


# --- enemy windup tells ---------------------------------------------------------------------
#
# `castle_enemy_base.gd:_windup_cue()`'s own comment already specifies the read for each class:
# "a rising tone for parryable, a low growl for unblockable, a short grunt for blockable, a
# shout for grab" — these four generators are exactly that, so the ear gets the same triad
# `AX-01`'s ring pattern (solid/dashed/double) gives the eye.


def windup_blockable(rng: np.random.Generator) -> np.ndarray:
    """A short grunt: a plain, unremarkable low body tone -- this is the "nothing special"
    default, so it must read as the least urgent of the four."""
    seconds = 0.16
    body = A.sine(140.0, seconds) * A.adsr(seconds, 0.01, 0.04, 0.55, 0.09)
    body += 0.3 * A.sine(210.0, seconds) * A.adsr(seconds, 0.01, 0.03, 0.4, 0.08)
    grit = A.bandpass(A.noise(seconds, rng), 150.0, 900.0) * A.adsr(seconds, 0.005, 0.05, 0.1, 0.06)
    mix = A.lowpass(body + grit * 0.4, 1400.0, poles=1)
    return A.normalize(A.fade(mix, 0.004), 0.6)


def windup_parryable(rng: np.random.Generator) -> np.ndarray:
    """A rising tone -- pitch sweeps up across the whole windup, so the ear has the same
    "answerable, if you time it" read the dashed telegraph ring gives the eye."""
    seconds = 0.32
    sweep = np.linspace(360.0, 720.0, A.n_samples(seconds), dtype=np.float32)
    body = A.sine(sweep, seconds) * A.adsr(seconds, 0.02, 0.05, 0.6, 0.1)
    body += 0.25 * A.sine(sweep * 2.0, seconds) * A.adsr(seconds, 0.02, 0.05, 0.5, 0.1)
    shimmer = A.bandpass(A.noise(seconds, rng), 1200.0, 4000.0) * 0.06
    mix = body + shimmer
    return A.normalize(A.reverb(A.fade(mix, 0.006), 0.3, 0.16, rng), 0.62)


def windup_unblockable(rng: np.random.Generator) -> np.ndarray:
    """A low growl -- a rough, slowly-souring low tone that never resolves upward, the audio
    equivalent of the double ring: this one is the real threat."""
    seconds = 0.48
    t = np.arange(A.n_samples(seconds), dtype=np.float32) / A.SAMPLE_RATE
    wobble = 1.0 + 0.06 * np.sin(2.0 * math.pi * 7.5 * t)
    body = A.saw(55.0 * wobble, seconds)
    body += 0.6 * A.saw(55.0 * 1.003 * wobble, seconds)
    body = A.lowpass(body, 340.0, poles=2)
    grit = A.bandpass(A.noise(seconds, rng), 60.0, 500.0) * 0.35
    mix = body * 0.8 + grit
    env = A.adsr(seconds, 0.05, 0.1, 0.85, 0.14)
    return A.normalize(A.fade(mix * env, 0.008), 0.68)


def windup_grab(rng: np.random.Generator) -> np.ndarray:
    """A shout -- a sharp-attack, breathy vocal-formant swell, the one windup that should make
    the player flinch and move rather than read the ring at all."""
    seconds = 0.42
    total_n = A.n_samples(seconds)
    rise_n = int(total_n * 0.35)
    sweep = np.concatenate(
        [
            np.linspace(260.0, 460.0, rise_n, dtype=np.float32),
            np.linspace(460.0, 300.0, total_n - rise_n, dtype=np.float32),
        ]
    )
    body = A.sine(sweep, seconds) + 0.5 * A.sine(sweep * 1.5, seconds)
    breath = A.bandpass(A.noise(seconds, rng), 400.0, 2600.0) * 0.5
    mix = A.lowpass(body + breath, 2600.0, poles=2)
    env = A.adsr(seconds, 0.015, 0.08, 0.7, 0.12)
    return A.normalize(A.fade(mix * env, 0.003), 0.75)


# --- one-shot stingers -----------------------------------------------------------------------
#
# Discovery/reward beats: each is a short, bright figure built from `A.pluck()`/`A.modal()`
# rather than a synth pad, so they sit in the same "struck, not played" register as the impact
# bank above instead of sounding like a different instrument family walked in.


def _rising_chime(freqs: list[float], note_seconds: float, rng: np.random.Generator) -> np.ndarray:
    note_len = 0.5
    total = note_seconds * (len(freqs) - 1) + note_len
    track = np.zeros(A.n_samples(total), dtype=np.float32)
    for i, f in enumerate(freqs):
        note = A.pluck(f, note_len, rng, damping=0.55) * 0.8
        note += 0.3 * A.sine(f * 2.0, note_len) * A.adsr(note_len, 0.004, 0.15, 0.0, 0.3)
        A.place(track, note, i * note_seconds, gain=1.0 - 0.08 * i)
    return track


def secret_found(rng: np.random.Generator) -> np.ndarray:
    mix = _rising_chime([660.0, 880.0, 1100.0], 0.075, rng)
    return A.normalize(A.reverb(mix, 0.7, 0.24, rng), 0.66)


def key_taken(rng: np.random.Generator) -> np.ndarray:
    mix = _rising_chime([440.0, 660.0], 0.09, rng)
    return A.normalize(A.reverb(mix, 0.4, 0.16, rng), 0.62)


def lock_opened(rng: np.random.Generator) -> np.ndarray:
    """Tumblers, then the bolt: a few dry mechanical ticks followed by a resonant metal clunk."""
    tick_seconds = 0.35
    ticks = np.zeros(A.n_samples(tick_seconds), dtype=np.float32)
    for i, at in enumerate([0.0, 0.05, 0.095, 0.15]):
        click = A.transient(0.012, rng, cutoff=4500.0) * (0.7 + 0.2 * (i % 2))
        A.place(ticks, click, at)
    clunk_seconds = 0.4
    clunk = A.modal(
        [220.0, 330.0, 495.0],
        clunk_seconds,
        decays=[10.0, 15.0, 22.0],
        gains=[1.0, 0.5, 0.28],
        rng=rng,
    )
    track = np.zeros(A.n_samples(tick_seconds + clunk_seconds), dtype=np.float32)
    A.place(track, ticks, 0.0)
    A.place(track, clunk, 0.16, gain=0.85)
    return A.normalize(A.fade(track, 0.003), 0.72)


def shortcut_opened(rng: np.random.Generator) -> np.ndarray:
    """Heavier than `lock_opened` -- a gate releasing, not a door unlocking: a low mechanical
    thud, a chain-like scrape, then a resonant iron clank as it swings free."""
    seconds = 0.75
    thud = A.sine(70.0, 0.2) * A.adsr(0.2, 0.004, 0.08, 0.0, 0.1) * 0.7
    scrape = A.granular_scrape(0.4, rng, grain_hz=90.0, low=150.0, high=2200.0, jitter=0.7) * 0.5
    clank = A.modal(
        [330.0, 495.0, 660.0, 990.0],
        0.5,
        decays=[7.0, 10.0, 15.0, 22.0],
        gains=[1.0, 0.55, 0.35, 0.2],
        rng=rng,
    )
    track = np.zeros(A.n_samples(seconds), dtype=np.float32)
    A.place(track, thud, 0.0)
    A.place(track, scrape, 0.05, gain=0.9)
    A.place(track, clank, 0.32, gain=0.8)
    return A.normalize(A.reverb(A.fade(track, 0.004), 0.6, 0.2, rng), 0.78)


def rare_drop(rng: np.random.Generator) -> np.ndarray:
    mix = _rising_chime([660.0, 880.0, 1100.0, 1320.0], 0.07, rng)
    sparkle = A.bandpass(A.noise(0.5, rng), 3000.0, 9000.0) * A.adsr(0.5, 0.15, 0.2, 0.1, 0.2) * 0.2
    mix = mix + np.pad(sparkle, (0, max(0, mix.shape[0] - sparkle.shape[0])))[: mix.shape[0]]
    return A.normalize(A.reverb(mix, 0.9, 0.3, rng), 0.7)


def personal_best(rng: np.random.Generator) -> np.ndarray:
    """The biggest fanfare in the bank (`max_concurrent: 1`, the run's single best-hit moment):
    a five-note ascending flourish with the longest tail of any stinger here."""
    mix = _rising_chime([660.0, 831.0, 990.0, 1245.0, 1480.0], 0.09, rng)
    shimmer = A.bandpass(A.noise(0.7, rng), 2500.0, 9000.0) * A.adsr(0.7, 0.3, 0.25, 0.15, 0.25) * 0.22
    mix = mix + np.pad(shimmer, (0, max(0, mix.shape[0] - shimmer.shape[0])))[: mix.shape[0]]
    return A.normalize(A.reverb(mix, 1.1, 0.34, rng), 0.75)


#: Plain generators keyed by their `sfx.json` entry id -- no per-realm/voice branching needed,
#: unlike `portal_hum_*` above.
SIMPLE_GENERATORS = {
    "hit_stone": hit_stone,
    "hit_crystal": hit_crystal,
    "hit_bone": hit_bone,
    "hit_ooze": hit_ooze,
    "hit_poise_break": hit_poise_break,
    "windup_blockable": windup_blockable,
    "windup_parryable": windup_parryable,
    "windup_unblockable": windup_unblockable,
    "windup_grab": windup_grab,
    "secret_found": secret_found,
    "key_taken": key_taken,
    "lock_opened": lock_opened,
    "shortcut_opened": shortcut_opened,
    "rare_drop": rare_drop,
    "personal_best": personal_best,
}


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
        elif key in SIMPLE_GENERATORS:
            sig = None if args.check else SIMPLE_GENERATORS[key](rng)
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

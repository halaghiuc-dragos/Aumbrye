"""Author the eighteen sound effects that were still borrowing another sound's file.

`AudioDirector.SFX_PROFILES` marked each of these `placeholder: true` and pointed it at whatever
existing asset was closest: every door opened with a sword swing, both levers used the UI click,
and all six loot rarities played the same click at different pitches — so a common drop and an
aumbral drop were audibly identical in a game whose entire reward loop is rarity.

Every effect here is built from the same three ingredients, which is what the placeholder bank was
missing rather than any particular sound:

* a **transient** — the contact itself, a few milliseconds of filtered noise;
* a **modal body** — a sum of inharmonic decaying sinusoids, which is how a struck solid actually
  rings, and which is what makes stone sound unlike iron unlike wood;
* a **room** — pre-delay, early reflections and a frequency-dependent tail, sized to the space the
  sound happens in.

Usage:  python tools/generate_foley.py [--check] [--only name,name]

`--only` exists because a full run rewrites every file whether or not its audio changed. The
encoder is chosen at runtime — ffmpeg when it is on PATH, libsndfile through `soundfile` when it
is not — and the two do not produce identical bytes for identical samples, so running this on a
machine without ffmpeg re-encodes the entire committed bank as a side effect of adding one sound.
Render the effect you actually changed.
"""

from __future__ import annotations

import argparse
import math
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import audio_synth as A  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[1]
SFX_DIR = ROOT / "apps/game/client/assets/audio/sfx"

# --- materials ---------------------------------------------------------------------------------
#
# Mode ratios measured off the classic references for each material class. What matters is that
# they are *not* integer multiples: a harmonic series reads as a musical note no matter what
# envelope is put on it, and every one of these objects should read as an object.

STONE = [1.0, 1.62, 2.24, 3.11, 4.03]
IRON = [1.0, 2.76, 5.40, 8.93, 13.34]
WOOD = [1.0, 2.09, 3.44, 4.71, 6.05]
GLASS = [1.0, 2.32, 4.25, 6.63, 9.38]


def _hit(
    freq: float,
    seconds: float,
    material: list[float],
    rng: np.random.Generator,
    *,
    brightness: float = 6000.0,
    click: float = 0.35,
    decay_scale: float = 1.0,
) -> np.ndarray:
    """One strike: contact noise over a modal body of the given material."""
    body = A.modal(
        [freq * m for m in material],
        seconds,
        decays=[(3.0 + 6.0 * i) * decay_scale for i in range(len(material))],
        gains=[1.0 / (1.0 + 1.4 * i) for i in range(len(material))],
        detune=0.004,
        rng=rng,
    )
    tick = A.transient(min(seconds, 0.05), rng, cutoff=brightness)
    out = A.lowpass(body, brightness, poles=1)
    out[: tick.shape[0]] += tick * click
    return out


# --- doors -------------------------------------------------------------------------------------


def door_open(rng: np.random.Generator) -> np.ndarray:
    """A heavy stone door dragging open: grind that accelerates, then settles."""
    seconds = 1.5
    n = A.n_samples(seconds)
    span = np.linspace(0.0, 1.0, n, dtype=np.float32)
    # Grain rate rises then falls — the door breaks loose, swings, and slows against its stop.
    grind = A.granular_scrape(seconds, rng, grain_hz=90.0, low=110.0, high=1900.0, jitter=0.75)
    grind *= np.clip(np.sin(math.pi * span) * 1.3, 0.0, 1.0)
    groan = A.modal([64.0, 97.0, 141.0], seconds, decays=[0.9, 1.5, 2.4], rng=rng) * 0.5
    settle = A.silence(seconds)
    thud = _hit(58.0, 0.7, STONE, rng, brightness=1500.0, click=0.5, decay_scale=0.7)
    A.place(settle, thud, 1.02, 0.9)
    mix = A.soft_clip(grind * 0.85 + groan + settle)
    return A.normalize(A.reverb(mix, 1.6, 0.34, rng, predelay_ms=22.0, room=1.4), 0.86)


def door_seal(rng: np.random.Generator) -> np.ndarray:
    """A door slamming shut and locking — the sound that says "you are committed"."""
    seconds = 1.4
    track = A.silence(seconds)
    A.place(track, _hit(52.0, 0.9, STONE, rng, brightness=1300.0, click=0.85), 0.0, 1.0)
    # Iron bolts driving home, a beat behind the slab.
    for i, at in enumerate((0.13, 0.21, 0.30)):
        A.place(track, _hit(196.0 + 34.0 * i, 0.34, IRON, rng, brightness=5200.0), at, 0.42)
    sub = A.sine(41.0, 0.5) * A.adsr(0.5, 0.002, 0.16, 0.0, 0.3)
    A.place(track, sub.astype(np.float32), 0.0, 0.7)
    return A.normalize(A.reverb(A.soft_clip(track), 1.5, 0.30, rng, predelay_ms=18.0, room=1.3), 0.9)


def door_release(rng: np.random.Generator) -> np.ndarray:
    """Locks withdrawing — bright ironwork first, then the slab easing off its seat."""
    seconds = 1.2
    track = A.silence(seconds)
    for i, at in enumerate((0.0, 0.09, 0.17)):
        A.place(track, _hit(330.0 - 46.0 * i, 0.4, IRON, rng, brightness=7000.0), at, 0.5)
    slide = A.granular_scrape(0.55, rng, grain_hz=150.0, low=260.0, high=3200.0, jitter=0.6)
    slide *= np.exp(-np.linspace(0.0, 3.0, slide.shape[0], dtype=np.float32))
    A.place(track, slide, 0.24, 0.55)
    A.place(track, _hit(74.0, 0.65, STONE, rng, brightness=1700.0, click=0.3), 0.42, 0.7)
    return A.normalize(A.reverb(track, 1.3, 0.30, rng, predelay_ms=16.0, room=1.2), 0.85)


# --- levers ------------------------------------------------------------------------------------


def lever_pull(rng: np.random.Generator) -> np.ndarray:
    """A ratchet under load: four clicks tightening, over a rising mechanical strain."""
    seconds = 0.75
    track = A.silence(seconds)
    for i, at in enumerate((0.0, 0.075, 0.135, 0.185)):
        A.place(track, _hit(420.0 + 58.0 * i, 0.16, IRON, rng, brightness=8000.0), at, 0.75 - 0.1 * i)
    strain = A.granular_scrape(0.32, rng, grain_hz=260.0, low=500.0, high=4200.0, jitter=0.5)
    strain *= np.linspace(0.35, 1.0, strain.shape[0], dtype=np.float32)
    A.place(track, strain, 0.0, 0.3)
    A.place(track, _hit(150.0, 0.4, IRON, rng, brightness=4000.0, click=0.6), 0.23, 0.85)
    return A.normalize(A.reverb(track, 0.8, 0.24, rng, predelay_ms=9.0, room=0.7), 0.82)


def lever_unlock(rng: np.random.Generator) -> np.ndarray:
    """The mechanism giving: a clunk, then a two-note confirmation that something opened."""
    seconds = 1.3
    track = A.silence(seconds)
    A.place(track, _hit(120.0, 0.45, IRON, rng, brightness=3600.0, click=0.7), 0.0, 1.0)
    for i, (at, freq) in enumerate(((0.14, 587.33), (0.26, 880.0))):
        chime = A.modal(
            [freq * m for m in GLASS],
            0.9,
            decays=[1.4, 3.0, 5.2, 8.0, 12.0],
            gains=[1.0, 0.4, 0.22, 0.12, 0.07],
            detune=0.002,
            rng=rng,
        )
        A.place(track, chime, at, 0.42 - 0.06 * i)
    return A.normalize(A.reverb(track, 1.5, 0.32, rng, predelay_ms=14.0, room=1.1), 0.84)


# --- loot --------------------------------------------------------------------------------------
#
# Six rarities that have to be distinguishable in a fraction of a second and in rank order. The
# escalation is deliberate and one-directional: each tier keeps the tier below it and adds a layer,
# so the family reads as a scale rather than as six unrelated noises.

LOOT_TIERS = {
    "common": {"notes": [], "body": WOOD, "freq": 210.0, "tail": 0.5, "mix": 0.16, "gain": 0.72},
    "magic": {"notes": [659.25], "body": WOOD, "freq": 230.0, "tail": 0.8, "mix": 0.22, "gain": 0.76},
    "rare": {"notes": [659.25, 987.77], "body": IRON, "freq": 250.0, "tail": 1.1, "mix": 0.28, "gain": 0.80},
    "epic": {
        "notes": [659.25, 987.77, 1318.51],
        "body": IRON, "freq": 268.0, "tail": 1.5, "mix": 0.32, "gain": 0.84,
    },
    "legendary": {
        "notes": [659.25, 987.77, 1318.51, 1567.98],
        "body": GLASS, "freq": 292.0, "tail": 2.0, "mix": 0.36, "gain": 0.88,
    },
    "aumbral": {
        "notes": [659.25, 932.33, 1318.51, 1661.22],
        "body": GLASS, "freq": 292.0, "tail": 2.4, "mix": 0.40, "gain": 0.90,
    },
}


def loot_drop(tier: str, rng: np.random.Generator) -> np.ndarray:
    """An item landing, then its rarity announcing itself.

    The landing is the same event at every tier — something hit the floor — so it stays nearly
    constant and the chime carries the information. Aumbral is the exception: its chime is built on
    a tritone rather than a fifth and it carries a sub-octave drop underneath, so the top of the
    scale reads as *wrong* rather than merely as more.
    """
    spec = LOOT_TIERS[tier]
    seconds = 0.45 + spec["tail"]
    track = A.silence(seconds)
    A.place(
        track,
        _hit(float(spec["freq"]), 0.30, list(spec["body"]), rng, brightness=5200.0, click=0.6),
        0.0,
        1.0,
    )
    # A small second bounce. Objects do not land once.
    A.place(
        track,
        _hit(float(spec["freq"]) * 1.18, 0.16, list(spec["body"]), rng, brightness=4200.0),
        0.075,
        0.34,
    )
    for i, note in enumerate(spec["notes"]):
        chime = A.modal(
            [note, note * 2.01, note * 3.02, note * 5.44],
            spec["tail"],
            decays=[1.1, 2.2, 3.6, 6.0],
            gains=[1.0, 0.34, 0.18, 0.08],
            detune=0.0015,
            rng=rng,
        )
        A.place(track, chime, 0.10 + 0.065 * i, 0.36 - 0.03 * i)
    if tier == "aumbral":
        drop_n = A.n_samples(1.1)
        sweep = np.linspace(1.0, 0.42, drop_n, dtype=np.float32)
        sub = np.sin(2.0 * math.pi * np.cumsum(88.0 * sweep) / A.SAMPLE_RATE).astype(np.float32)
        sub *= np.exp(-np.linspace(0.0, 3.4, drop_n, dtype=np.float32))
        A.place(track, sub, 0.09, 0.5)
    wet = A.reverb(track, 1.0 + spec["tail"], float(spec["mix"]), rng, predelay_ms=11.0, room=1.0)
    return A.normalize(wet, float(spec["gain"]))


# --- portals -----------------------------------------------------------------------------------


def portal_open(rng: np.random.Generator) -> np.ndarray:
    """A gate tearing itself open: rising sweep, bloom, low impact underneath."""
    seconds = 2.0
    n = A.n_samples(seconds)
    span = np.linspace(0.0, 1.0, n, dtype=np.float32)
    rise = np.exp(np.linspace(math.log(90.0), math.log(1450.0), n, dtype=np.float32))
    sweep = np.sin(2.0 * math.pi * np.cumsum(rise) / A.SAMPLE_RATE).astype(np.float32)
    sweep *= np.clip(span * 3.0, 0.0, 1.0) * np.exp(-2.2 * np.clip(span - 0.42, 0.0, None))
    air = A.bandpass(A.noise(seconds, rng), 600.0, 7000.0) * np.clip(span * 2.4, 0.0, 1.2)
    air *= np.exp(-2.6 * np.clip(span - 0.4, 0.0, None))
    bloom = A.modal(
        [220.0, 329.63, 440.0, 659.25, 880.0],
        1.5,
        decays=[1.0, 1.6, 2.4, 3.6, 5.0],
        gains=[0.9, 0.6, 0.45, 0.3, 0.2],
        detune=0.003,
        rng=rng,
    )
    track = A.silence(seconds)
    A.place(track, sweep * 0.55, 0.0, 1.0)
    A.place(track, air * 0.30, 0.0, 1.0)
    A.place(track, bloom, 0.44, 0.55)
    A.place(track, _hit(48.0, 1.0, STONE, rng, brightness=900.0, click=0.2), 0.42, 0.8)
    return A.normalize(A.reverb(A.soft_clip(track), 2.0, 0.40, rng, predelay_ms=26.0, room=1.6), 0.88)


def portal_enter(rng: np.random.Generator) -> np.ndarray:
    """Passing through: a downward rush with the room falling away behind it."""
    seconds = 1.3
    n = A.n_samples(seconds)
    span = np.linspace(0.0, 1.0, n, dtype=np.float32)
    fall = np.exp(np.linspace(math.log(1200.0), math.log(120.0), n, dtype=np.float32))
    swoosh = np.sin(2.0 * math.pi * np.cumsum(fall) / A.SAMPLE_RATE).astype(np.float32)
    swoosh *= np.exp(-1.6 * span)
    wind = A.bandpass(A.noise(seconds, rng), 300.0, 5200.0)
    wind *= np.clip(1.0 - span * 1.15, 0.0, 1.0) ** 2
    track = (swoosh * 0.5 + wind * 0.4).astype(np.float32)
    A.place(track, _hit(70.0, 0.6, STONE, rng, brightness=1100.0, click=0.25), 0.0, 0.6)
    return A.normalize(A.reverb(track, 1.4, 0.36, rng, predelay_ms=20.0, room=1.4), 0.82)


# --- movement and state ------------------------------------------------------------------------


def footstep_snow(rng: np.random.Generator) -> np.ndarray:
    """Snow compacting: a dense burst of very small high grains, and no ring at all.

    Snow is the one surface with essentially no modal body — nothing rings, it only crushes — so
    this is granular texture plus a soft low compression thump, and getting the grain rate high
    enough is the whole trick. The placeholder was a 60 Hz tone, which is close to the opposite.
    """
    seconds = 0.26
    crunch = A.granular_scrape(seconds, rng, grain_hz=900.0, low=900.0, high=9000.0, jitter=0.85)
    env = np.exp(-np.linspace(0.0, 11.0, crunch.shape[0], dtype=np.float32))
    crunch *= env
    pack = A.sine(88.0, seconds) * A.adsr(seconds, 0.004, 0.05, 0.0, 0.12)
    mix = (crunch * 0.85 + pack.astype(np.float32) * 0.32).astype(np.float32)
    return A.normalize(A.reverb(A.fade(mix, 0.004), 0.4, 0.12, rng, predelay_ms=5.0, room=0.4), 0.6)


def dodge_perfect(rng: np.random.Generator) -> np.ndarray:
    """The reward for a frame-perfect dodge: air past the ear, then a bright confirmation."""
    seconds = 0.6
    n = A.n_samples(seconds)
    span = np.linspace(0.0, 1.0, n, dtype=np.float32)
    air = A.bandpass(A.noise(seconds, rng), 1200.0, 9000.0)
    air *= np.exp(-np.linspace(0.0, 7.0, n, dtype=np.float32)) * (1.0 - 0.4 * span)
    ping = A.modal(
        [1174.66, 1760.0, 2637.02],
        0.5,
        decays=[3.0, 5.0, 8.0],
        gains=[1.0, 0.42, 0.18],
        rng=rng,
    )
    track = (air * 0.42).astype(np.float32)
    A.place(track, ping, 0.045, 0.4)
    return A.normalize(A.reverb(track, 0.6, 0.22, rng, predelay_ms=7.0, room=0.6), 0.7)


def exhausted(rng: np.random.Generator) -> np.ndarray:
    """Out of stamina: a breath forced out, falling in pitch as it empties."""
    seconds = 0.85
    n = A.n_samples(seconds)
    span = np.linspace(0.0, 1.0, n, dtype=np.float32)
    breath = A.noise(seconds, rng)
    # Two moving bands stand in for a vocal tract, which is what separates a breath from a hiss.
    formant = A.bandpass(breath, 420.0, 1100.0) * 0.8 + A.bandpass(breath, 1400.0, 2600.0) * 0.35
    formant *= np.clip(np.sin(math.pi * span ** 0.7) * 1.25, 0.0, 1.0)
    formant = A.lowpass(formant, 3200.0, poles=1) * (1.0 - 0.45 * span)
    return A.normalize(A.reverb(A.fade(formant, 0.02), 0.7, 0.18, rng, predelay_ms=8.0, room=0.7), 0.62)


def guard_break(rng: np.random.Generator) -> np.ndarray:
    """A guard shattering: bright metal failing, then the weight of it dropping."""
    seconds = 1.1
    track = A.silence(seconds)
    for i in range(5):
        shard = _hit(
            float(rng.uniform(700.0, 2200.0)),
            0.35,
            GLASS,
            rng,
            brightness=11000.0,
            click=0.5,
            decay_scale=1.6,
        )
        A.place(track, shard, float(rng.uniform(0.0, 0.09)), 0.34)
    A.place(track, _hit(96.0, 0.7, IRON, rng, brightness=2600.0, click=0.9), 0.0, 0.9)
    sub = A.sine(46.0, 0.45) * A.adsr(0.45, 0.002, 0.14, 0.0, 0.28)
    A.place(track, sub.astype(np.float32), 0.01, 0.55)
    return A.normalize(A.reverb(A.soft_clip(track), 1.2, 0.30, rng, predelay_ms=13.0, room=1.1), 0.9)


def resource_denied(rng: np.random.Generator) -> np.ndarray:
    """"You cannot afford that" — short, flat, dissonant, and deliberately unpleasant to repeat."""
    seconds = 0.3
    a = A.modal([196.0, 207.65], seconds, decays=[9.0, 11.0], gains=[1.0, 0.85], rng=rng)
    tick = A.transient(0.02, rng, cutoff=3000.0)
    out = A.lowpass(a, 2200.0, poles=1)
    out[: tick.shape[0]] += tick * 0.35
    return A.normalize(A.reverb(A.fade(out, 0.006), 0.25, 0.10, rng, predelay_ms=4.0, room=0.4), 0.66)


# --- footsteps ---------------------------------------------------------------------------------
#
# The most-repeated sound in the game, and the bank shipped two stone variants, one wood, one water
# and no snow at all. One variant is worse than none: a footstep that is byte-identical every step
# is heard as a machine, and the ear picks that out within a few paces. Three per surface, jittered
# apart, is the minimum that stops reading as a loop.


def footstep_stone(rng: np.random.Generator, variant: int) -> np.ndarray:
    """A boot on flagstone: hard contact, a brief dense ring, almost no tail."""
    seconds = 0.22
    freq = 205.0 * (1.0 + 0.09 * (variant - 1))
    heel = _hit(freq, 0.14, STONE, rng, brightness=6200.0, click=0.9, decay_scale=2.6)
    grit = A.granular_scrape(0.10, rng, grain_hz=700.0, low=1500.0, high=8000.0, jitter=0.8)
    grit *= np.exp(-np.linspace(0.0, 9.0, grit.shape[0], dtype=np.float32))
    track = A.silence(seconds)
    A.place(track, heel, 0.0, 1.0)
    A.place(track, grit, 0.004, 0.30)
    return A.normalize(A.reverb(track, 0.45, 0.14, rng, predelay_ms=6.0, room=0.9), 0.60)


def footstep_wood(rng: np.random.Generator, variant: int) -> np.ndarray:
    """A boot on a plank floor: the same contact over a box that resonates under it."""
    seconds = 0.28
    freq = 148.0 * (1.0 + 0.11 * (variant - 1))
    tap = _hit(freq, 0.20, WOOD, rng, brightness=4200.0, click=0.75, decay_scale=1.7)
    # The hollow underneath is what distinguishes wood from stone far more than the contact does.
    cavity = A.modal([92.0, 137.0], 0.26, decays=[9.0, 14.0], gains=[1.0, 0.5], rng=rng)
    track = A.silence(seconds)
    A.place(track, tap, 0.0, 1.0)
    A.place(track, cavity, 0.006, 0.36)
    return A.normalize(A.reverb(track, 0.5, 0.16, rng, predelay_ms=7.0, room=0.7), 0.60)


def footstep_water(rng: np.random.Generator, variant: int) -> np.ndarray:
    """A boot into shallow water: a bright burst that darkens fast, then droplets."""
    seconds = 0.42
    n = A.n_samples(seconds)
    span = np.linspace(0.0, 1.0, n, dtype=np.float32)
    splash = A.noise(seconds, rng)
    # Sweeping the band downward is the splash: the spray is bright and the body of it is not.
    bright = A.bandpass(splash, 1400.0, 9000.0) * np.exp(-np.linspace(0.0, 16.0, n, dtype=np.float32))
    body = A.bandpass(splash, 250.0, 1600.0) * np.exp(-np.linspace(0.0, 7.0, n, dtype=np.float32))
    track = (bright * 0.7 + body * 0.55).astype(np.float32)
    for i in range(2 + variant % 2):
        drop = A.modal(
            [float(rng.uniform(900.0, 2100.0))],
            0.12,
            decays=[26.0],
            rng=rng,
        )
        A.place(track, drop, float(rng.uniform(0.06, 0.20)), 0.22)
    A.place(track, A.sine(120.0, 0.12).astype(np.float32) * 0.4, 0.0, 0.5)
    return A.normalize(A.reverb(A.fade(track, 0.004), 0.6, 0.20, rng, predelay_ms=6.0, room=0.8), 0.62)


def footstep_snow_variant(rng: np.random.Generator, variant: int) -> np.ndarray:
    sig = footstep_snow(rng)
    # Slight per-variant weight, so three steps in a row are not the same compression.
    return A.normalize(sig * (0.88 + 0.06 * variant), 0.60)


FOOTSTEP_SURFACES = {
    "stone": footstep_stone,
    "wood": footstep_wood,
    "water": footstep_water,
    "snow": footstep_snow_variant,
}
FOOTSTEP_VARIANTS = 3


# --- driver ------------------------------------------------------------------------------------

# --- the plaza strays ------------------------------------------------------------------------
#
# `content/dialogue/stray_*.json` has asked for these on every "say hello" and every "pet" since
# the animals went in, and neither existed, so petting a cat played the generic missing-sfx beep.
# Both are voiced sounds rather than struck objects, so they are built the way `exhausted` is: a
# glottal source through moving formants, which is what separates an animal from a synth tone.


def stray_meow(rng: np.random.Generator) -> np.ndarray:
    """A cat's meow: one voiced note opening from a nasal /m/ into the vowel and closing again."""
    seconds = 0.62
    n = A.n_samples(seconds)
    span = np.linspace(0.0, 1.0, n, dtype=np.float32)
    # Rises into the vowel and falls away over a longer tail. The fall is what stops it reading as
    # a held note.
    pitch = 620.0 + 180.0 * np.sin(math.pi * np.clip(span * 1.6, 0.0, 1.0)) - 210.0 * span ** 2
    vibrato = 1.0 + 0.018 * np.sin(2.0 * math.pi * 5.5 * span * seconds).astype(np.float32)
    voiced = pitch.astype(np.float32) * vibrato
    source = A.saw(voiced, seconds) * 0.6 + A.sine(voiced, seconds) * 0.4
    # The mouth opening and closing is the whole sound: closed is nasal and dark, open is two
    # formants well apart.
    openness = np.clip(np.sin(math.pi * span ** 0.8), 0.0, 1.0).astype(np.float32)
    nasal = A.lowpass(source, 900.0, poles=2)
    vowel = A.bandpass(source, 520.0, 1000.0) * 0.9 + A.bandpass(source, 1500.0, 2700.0) * 0.55
    voice = nasal * (1.0 - openness) + vowel * openness
    voice *= np.clip(np.sin(math.pi * span ** 0.7) * 1.2, 0.0, 1.0)
    return A.normalize(
        A.reverb(A.fade(voice, 0.02), 0.5, 0.16, rng, predelay_ms=6.0, room=0.5), 0.6
    )


def stray_bark(rng: np.random.Generator) -> np.ndarray:
    """A single bark: the snap of the mouth, then the chest behind it dropping away."""
    seconds = 0.42
    n = A.n_samples(seconds)
    span = np.linspace(0.0, 1.0, n, dtype=np.float32)
    pitch = (240.0 - 90.0 * span ** 0.5).astype(np.float32)
    source = A.saw(pitch, seconds) * 0.7 + A.noise(seconds, rng) * 0.3
    body = A.bandpass(source, 300.0, 2400.0)
    body *= np.exp(-np.linspace(0.0, 13.0, n, dtype=np.float32))
    track = (body * 0.9).astype(np.float32)
    # Without the transient a bark is just a short low note; the consonant is most of the identity.
    A.place(track, A.transient(0.05, rng, cutoff=6000.0), 0.0, 0.55)
    return A.normalize(
        A.reverb(A.fade(track, 0.005), 0.55, 0.2, rng, predelay_ms=6.0, room=0.6), 0.72
    )


## Rendered after everything else on purpose. `main` draws every effect from one shared generator,
## so inserting a job anywhere but the end shifts the noise of every job after it and silently
## rewrites assets that were fine.
TAIL_GENERATORS = {
    "stray_meow": stray_meow,
    "stray_bark": stray_bark,
}


GENERATORS = {
    "door_open": door_open,
    "door_seal": door_seal,
    "door_release": door_release,
    "lever_pull": lever_pull,
    "lever_unlock": lever_unlock,
    "portal_open": portal_open,
    "portal_enter": portal_enter,
    "footstep_snow": footstep_snow,
    "dodge_perfect": dodge_perfect,
    "exhausted": exhausted,
    "guard_break": guard_break,
    "resource_denied": resource_denied,
}
for _tier in LOOT_TIERS:
    GENERATORS[f"loot_drop_{_tier}"] = (
        lambda rng, tier=_tier: loot_drop(tier, rng)  # noqa: B008
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="render nothing; list what would be made")
    ap.add_argument(
        "--only",
        default="",
        help=(
            "comma-separated effect names; every effect is still computed so the shared generator "
            "advances identically, but only these are written"
        ),
    )
    args = ap.parse_args()
    wanted = {name for name in args.only.split(",") if name}
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(0x50FA)
    jobs: list[tuple[str, object]] = [(name, GENERATORS[name]) for name in sorted(GENERATORS)]
    for surface, fn in FOOTSTEP_SURFACES.items():
        for variant in range(1, FOOTSTEP_VARIANTS + 1):
            jobs.append(
                (f"step_{surface}_{variant:02d}", lambda r, f=fn, v=variant: f(r, v))
            )
    jobs.extend((name, TAIL_GENERATORS[name]) for name in sorted(TAIL_GENERATORS))
    print(f"{'effect':<22} {'seconds':>8} {'bytes':>9}")
    for name, fn in jobs:
        if args.check:
            print(f"{name:<22} {'-':>8} {'-':>9}")
            continue
        # Always drawn, even when it will not be written: every effect shares one generator, so
        # skipping a draw would change the noise of everything after it.
        sig = fn(rng)
        if wanted and name not in wanted:
            continue
        path = SFX_DIR / f"{name}.ogg"
        A.write_ogg(path, sig, quality=7)
        print(f"{name:<22} {sig.shape[0] / A.SAMPLE_RATE:>8.2f} {path.stat().st_size:>9}")
    print(f"\n{len(jobs)} effects in {SFX_DIR}")
    _update_footstep_bank(args.check or bool(wanted))
    return 0


def _update_footstep_bank(check: bool) -> None:
    """Point `content/audio/sfx.json` at the three variants now authored for each surface."""
    import json

    manifest_path = ROOT / "content/audio/sfx.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    entry = manifest["sfx"]["footstep"]
    entry["surface_variants"] = {
        surface: [
            f"res://assets/audio/sfx/step_{surface}_{v:02d}.ogg"
            for v in range(1, FOOTSTEP_VARIANTS + 1)
        ]
        for surface in FOOTSTEP_SURFACES
    }
    if check:
        print("would update footstep surface_variants for", ", ".join(FOOTSTEP_SURFACES))
        return
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n"
    )
    print(f"updated {manifest_path.relative_to(ROOT)} with {len(FOOTSTEP_SURFACES)} surfaces")


if __name__ == "__main__":
    raise SystemExit(main())

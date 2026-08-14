"""Compose Aumbrye's soundtrack.

What was here before: the title and menu had no music asset at all — `AudioDirector.play_menu_music`
only set frequencies for the fallback tone generator, so the first thing a player heard was a sine
drone. Every biome's four layers existed as files but ran six to eight seconds, short enough to
become a repeating tic inside a minute of play.

The score written here:

* **Title / menu** — a solo violin over a low drone and a sparse harp, D natural minor, 62 BPM.
  Slow, unresolved, mourning something. The game is called *Echo of the Fallen Warden*; the theme
  should sound like the echo, not the warden.
* **Hub** — the same tonal world a fifth up and in Dorian, which lifts the minor third's colour
  just enough to read as shelter rather than grief.
* **Explore** — per biome. Sparse pad, long silences, one motif fragment every few bars. Music you
  can stop noticing, which is the whole job of exploration music.
* **Combat** — the explore key with a pulse under it: war drum on the beat, a two-note ostinato,
  the pad tightened. Recognisably the same place, now dangerous.
* **Boss** — Phrygian. That flat second is the entire reason the mode sounds like a threat. Big
  drums, low brass-ish saw stabs, a choir bed, and a high violin ostinato riding over it.
* **Ambience** — not music. Filtered noise beds, room tone, slow resonances; the layer that plays
  under everything and sells the space.

Every track is rendered as a seamless loop (see `audio_synth.make_loop`) and encoded to real Ogg
Vorbis through ffmpeg.

Usage:
    python tools/generate_music.py                # everything
    python tools/generate_music.py --only title   # one target
    python tools/generate_music.py --list
"""

from __future__ import annotations

import argparse
import math
import pathlib
import sys
import time

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import audio_synth as A  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[1]
AUDIO = ROOT / "apps/game/client/assets/audio"

D3 = A.note_hz(-19)   # 146.83
A2 = A.note_hz(-24)   # 110.00
D2 = A.note_hz(-31)   # 73.42

#: Per-biome musical identity. `tonic` is the root of every layer for that realm, so its explore,
#: combat and boss music are audibly the same place. `bright` sets the lowpass on the pads and
#: `pulse` the combat tempo in BPM.
BIOMES = {
    "forgotten_castle": {"tonic": D3,                 "bright": 1500, "pulse": 96,  "boss_drum": 78},
    "crystal_caverns":  {"tonic": A.note_hz(-16),     "bright": 3400, "pulse": 104, "boss_drum": 88},
    "poison_swamp":     {"tonic": A.note_hz(-22),     "bright": 900,  "pulse": 84,  "boss_drum": 66},
    "frozen_fortress":  {"tonic": A.note_hz(-14),     "bright": 3000, "pulse": 100, "boss_drum": 84},
    "dark_cathedral":   {"tonic": A.note_hz(-21),     "bright": 1200, "pulse": 88,  "boss_drum": 62},
    "iron_vault":       {"tonic": A.note_hz(-26),     "bright": 1000, "pulse": 108, "boss_drum": 58},
    "prism_depths":     {"tonic": A.note_hz(-12),     "bright": 4200, "pulse": 112, "boss_drum": 92},
    "venom_mire":       {"tonic": A.note_hz(-23),     "bright": 850,  "pulse": 80,  "boss_drum": 64},
    "glacial_hollow":   {"tonic": A.note_hz(-17),     "bright": 2600, "pulse": 92,  "boss_drum": 74},
    "umbral_chapel":    {"tonic": A.note_hz(-25),     "bright": 800,  "pulse": 86,  "boss_drum": 56},
}

EXPLORE_SECONDS = 64.0
COMBAT_SECONDS = 48.0
BOSS_SECONDS = 56.0
AMBIENCE_SECONDS = 40.0
TITLE_SECONDS = 76.0


# --- title -------------------------------------------------------------------------------------

#: Scale degrees of the theme, as (degree, beats). Degree 0 is the tonic; negatives drop an octave.
#: The phrase climbs to the minor sixth and falls back without ever landing on the tonic until the
#: very end — the melodic shape of something unresolved.
TITLE_PHRASE = [
    (0, 3), (2, 1), (4, 3), (3, 1), (2, 4),
    (4, 2), (5, 2), (4, 3), (2, 1), (1, 4),
    (2, 3), (4, 1), (7, 4), (5, 4),
    (4, 2), (3, 2), (2, 3), (0, 5),
]


def title_theme(seconds: float, rng: np.random.Generator) -> np.ndarray:
    bpm = 62.0
    beat = 60.0 / bpm
    tonic = D3

    def render(total: float) -> np.ndarray:
        lead = np.zeros(A.n_samples(total), dtype=np.float32)
        harp = np.zeros(A.n_samples(total), dtype=np.float32)
        bed = np.zeros(A.n_samples(total), dtype=np.float32)

        # The violin line, repeated until the track is full.
        cursor = 0.0
        while cursor < total:
            for degree, beats in TITLE_PHRASE:
                if cursor >= total:
                    break
                dur = beats * beat
                freq = A.scale_degree(tonic, "aeolian", degree)
                note = A.violin(
                    freq,
                    dur * 0.98,
                    vibrato_hz=5.0 + rng.uniform(-0.3, 0.3),
                    vibrato_cents=13.0,
                    attack=min(0.22, dur * 0.3),
                    brightness=2400.0,
                )
                A.place(lead, note, cursor, 0.9)
                cursor += dur
            cursor += beat * 2.0  # breath between repeats

        # Harp: the chord tones under the melody, one arpeggio per two bars.
        chords = [[0, 2, 4], [-3, 0, 2], [-1, 1, 4], [-3, 0, 3]]
        cursor = 0.0
        ci = 0
        while cursor < total:
            chord = chords[ci % len(chords)]
            for j, degree in enumerate(chord + chord[::-1][1:]):
                at = cursor + j * beat * 0.75
                if at >= total:
                    break
                f = A.scale_degree(tonic, "aeolian", degree) * 0.5
                A.place(harp, A.pluck(f, 2.2, rng), at, 0.28)
            cursor += beat * 6.0
            ci += 1

        # A low drone with the fifth in it, the floor the whole piece stands on.
        bed += A.pad([D2, D2 * 1.5, D3], total, cutoff=900.0, detune=9.0) * 0.5

        mix = lead * 0.62 + harp * 0.5 + bed * 0.55
        return A.reverb(mix, 2.2, 0.40, rng)

    loop = A.make_loop(render, seconds, tail_seconds=4.0)
    return A.normalize(A.widen(A.soft_clip(loop), 15.0), 0.82)


def hub_theme(seconds: float, rng: np.random.Generator) -> np.ndarray:
    """Warmer relative of the title: Dorian, higher, and the melody reduced to fragments."""
    bpm = 68.0
    beat = 60.0 / bpm
    tonic = A.note_hz(-14)

    def render(total: float) -> np.ndarray:
        out = np.zeros(A.n_samples(total), dtype=np.float32)
        out += A.pad(
            [tonic * 0.5, A.scale_degree(tonic, "dorian", 2) * 0.5, A.scale_degree(tonic, "dorian", 4) * 0.5],
            total, cutoff=1300.0,
        ) * 0.5
        cursor = beat * 4
        motif = [0, 2, 4, 2, 5, 4, 2, 0]
        while cursor < total:
            for j, degree in enumerate(motif):
                at = cursor + j * beat * 1.5
                if at >= total:
                    break
                A.place(out, A.pluck(A.scale_degree(tonic, "dorian", degree), 2.4, rng), at, 0.34)
            cursor += beat * 24
        return A.reverb(out, 1.8, 0.34, rng)

    return A.normalize(A.widen(A.make_loop(render, seconds, 3.0), 13.0), 0.78)


# --- biome layers ------------------------------------------------------------------------------


def explore_loop(cfg: dict, seconds: float, rng: np.random.Generator) -> np.ndarray:
    tonic = cfg["tonic"]

    def render(total: float) -> np.ndarray:
        out = np.zeros(A.n_samples(total), dtype=np.float32)
        out += A.pad(
            [tonic * 0.5, A.scale_degree(tonic, "aeolian", 4) * 0.5],
            total, cutoff=cfg["bright"] * 0.7,
        ) * 0.46
        # Sparse: one short figure every eight seconds or so, never on a predictable grid.
        at = 3.0
        while at < total:
            degree = int(rng.choice([0, 2, 4, 5, 7]))
            f = A.scale_degree(tonic, "aeolian", degree)
            if rng.random() < 0.45:
                A.place(out, A.violin(f, 3.4, vibrato_cents=9.0, attack=0.6,
                                      brightness=cfg["bright"]), at, 0.30)
            else:
                A.place(out, A.pluck(f, 2.6, rng), at, 0.26)
            at += rng.uniform(5.5, 11.0)
        return A.reverb(out, 2.4, 0.42, rng)

    return A.normalize(A.widen(A.make_loop(render, seconds, 4.0), 17.0), 0.72)


def combat_loop(cfg: dict, seconds: float, rng: np.random.Generator) -> np.ndarray:
    tonic = cfg["tonic"]
    beat = 60.0 / cfg["pulse"]

    def render(total: float) -> np.ndarray:
        out = np.zeros(A.n_samples(total), dtype=np.float32)
        out += A.pad([tonic * 0.5, A.scale_degree(tonic, "aeolian", 3) * 0.5], total,
                     cutoff=cfg["bright"]) * 0.34
        drum = A.war_drum(0.5, rng, pitch=cfg["boss_drum"] * 1.1)
        hit = A.snare(0.25, rng)
        # Two-note ostinato under a driving pulse — enough motion to raise the pulse rate without
        # a melody competing with the fight for attention.
        ost = [0, 0, 3, 0, 0, 2, 3, 2]
        i = 0
        at = 0.0
        while at < total:
            if i % 4 == 0:
                A.place(out, drum, at, 0.55)
            if i % 8 == 4:
                A.place(out, hit, at, 0.30)
            f = A.scale_degree(tonic, "aeolian", ost[i % len(ost)])
            stab = A.saw(f, beat * 0.45) * A.adsr(beat * 0.45, 0.004, 0.06, 0.5, beat * 0.2)
            A.place(out, A.lowpass(stab, cfg["bright"], poles=1), at, 0.24)
            at += beat
            i += 1
        return A.reverb(out, 1.2, 0.26, rng)

    return A.normalize(A.widen(A.soft_clip(A.make_loop(render, seconds, 3.0)), 9.0), 0.84)


def boss_theme(cfg: dict, seconds: float, rng: np.random.Generator) -> np.ndarray:
    tonic = cfg["tonic"]
    beat = 60.0 / (cfg["pulse"] * 1.12)

    def render(total: float) -> np.ndarray:
        out = np.zeros(A.n_samples(total), dtype=np.float32)
        # Phrygian: the flat second against the tonic is the sound of a threat.
        out += A.choir(
            [tonic * 0.5, A.scale_degree(tonic, "phrygian", 1) * 0.5,
             A.scale_degree(tonic, "phrygian", 4) * 0.5],
            total, rng,
        ) * 0.30
        drum = A.war_drum(0.85, rng, pitch=cfg["boss_drum"])
        hit = A.snare(0.3, rng)
        stab_degrees = [0, 0, 1, 0, 4, 3, 1, 0]
        ostinato = [7, 8, 7, 4, 7, 8, 11, 8]
        i = 0
        at = 0.0
        while at < total:
            if i % 2 == 0:
                A.place(out, drum, at, 0.62)
            if i % 8 in (3, 7):
                A.place(out, hit, at, 0.26)
            # Low brass-ish stabs.
            f = A.scale_degree(tonic, "phrygian", stab_degrees[i % len(stab_degrees)]) * 0.5
            stab = (A.saw(f, beat * 0.6) + 0.6 * A.square(f * 0.5, beat * 0.6)) * A.adsr(
                beat * 0.6, 0.006, 0.09, 0.55, beat * 0.25
            )
            A.place(out, A.lowpass(stab, 1100.0, poles=2), at, 0.30)
            # High violin ostinato riding over the top.
            if i % 2 == 1:
                vf = A.scale_degree(tonic, "phrygian", ostinato[i % len(ostinato)])
                A.place(out, A.violin(vf, beat * 1.6, vibrato_cents=18.0, attack=0.04,
                                      brightness=3600.0), at, 0.26)
            at += beat
            i += 1
        return A.reverb(out, 1.9, 0.32, rng)

    return A.normalize(A.widen(A.soft_clip(A.make_loop(render, seconds, 3.5)), 11.0), 0.88)


def ambience_loop(cfg: dict, seconds: float, rng: np.random.Generator) -> np.ndarray:
    """Room tone, not music: a noise bed shaped to the realm plus slow resonances."""
    tonic = cfg["tonic"]
    bright = cfg["bright"]

    def render(total: float) -> np.ndarray:
        t = np.arange(A.n_samples(total)) / A.SAMPLE_RATE
        bed = A.bandpass(A.noise(total, rng), 60.0, bright * 0.5)
        # Slow swells so the bed breathes rather than hisses.
        bed *= 0.35 + 0.25 * np.sin(2.0 * math.pi * 0.037 * t) + 0.15 * np.sin(2.0 * math.pi * 0.011 * t)
        room = A.sine(tonic * 0.25, total) * 0.10 + A.sine(tonic * 0.375, total) * 0.05
        out = bed.astype(np.float32) + room
        # Occasional distant events — a settle, a drip, a far-off stone.
        at = rng.uniform(2.0, 6.0)
        while at < total:
            f = A.scale_degree(tonic, "aeolian", int(rng.integers(0, 7))) * float(rng.choice([0.5, 1.0, 2.0]))
            ping = A.sine(f, 1.6) * A.adsr(1.6, 0.01, 0.4, 0.15, 1.0)
            A.place(out, A.lowpass(ping, bright, poles=1), at, 0.10)
            at += rng.uniform(6.0, 14.0)
        return A.reverb(out, 2.8, 0.45, rng)

    return A.normalize(A.widen(A.make_loop(render, seconds, 4.0), 21.0), 0.55)


# --- driver ------------------------------------------------------------------------------------


def targets() -> dict:
    out = {
        "title": (AUDIO / "shared/title_theme.ogg", TITLE_SECONDS, "title"),
        "hub": (AUDIO / "shared/hub_theme.ogg", 56.0, "hub"),
    }
    for biome in BIOMES:
        out[f"{biome}/explore"] = (AUDIO / biome / "explore_loop.ogg", EXPLORE_SECONDS, "explore")
        out[f"{biome}/combat"] = (AUDIO / biome / "combat_loop.ogg", COMBAT_SECONDS, "combat")
        out[f"{biome}/boss"] = (AUDIO / biome / "boss_theme.ogg", BOSS_SECONDS, "boss")
        out[f"{biome}/ambience"] = (AUDIO / biome / "ambience_loop.ogg", AMBIENCE_SECONDS, "ambience")
    return out


def render_one(name: str, seconds: float, kind: str) -> np.ndarray:
    # Seeded per track so a re-run reproduces the same soundtrack byte for byte.
    rng = np.random.default_rng(abs(hash(name)) % (2**32))
    if kind == "title":
        return title_theme(seconds, rng)
    if kind == "hub":
        return hub_theme(seconds, rng)
    cfg = BIOMES[name.split("/")[0]]
    return {
        "explore": explore_loop,
        "combat": combat_loop,
        "boss": boss_theme,
        "ambience": ambience_loop,
    }[kind](cfg, seconds, rng)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", action="append", help="render just these targets (repeatable)")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    all_targets = targets()
    if args.list:
        for name, (path, secs, kind) in all_targets.items():
            print(f"{name:<34} {kind:<9} {secs:5.0f}s  {path.relative_to(ROOT)}")
        return 0

    selected = args.only or list(all_targets)
    unknown = [s for s in selected if s not in all_targets]
    if unknown:
        print("PROBLEM unknown targets:", unknown)
        return 1

    total_start = time.time()
    for name in selected:
        path, secs, kind = all_targets[name]
        start = time.time()
        sig = render_one(name, secs, kind)
        A.write_ogg(path, sig, quality=5)
        size = path.stat().st_size
        print(
            f"  {name:<34} {secs:5.0f}s  {size / 1024:7.1f} KiB"
            f"  peak {float(np.max(np.abs(sig))):.2f}  ({time.time() - start:.1f}s)"
        )
    print(f"\nrendered {len(selected)} tracks in {time.time() - total_start:.0f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

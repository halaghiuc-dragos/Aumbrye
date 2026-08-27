"""Author the ambience loops for wind and rain, and the murmurs the hub's NPCs make.

`WindService` and `WeatherService` gave the world weather that could be seen and not heard, and the
hub's ten authored NPCs stood in silence while the two stray-animal sounds already in the bank were
wired to nothing at all. Every asset here is a seamless loop or a short one-shot, built from the
same subtractive toolkit the rest of the audio bank uses.

What matters for each:

* **wind** — filtered noise whose *cutoff* moves, not just its gain. Wind changes timbre as it
  gusts (more high end as it accelerates past an edge); a noise bed with a volume envelope on it
  reads as someone turning a dial.
* **rain** — a dense bed of very short high-passed grains over a low hiss. The grains are what stop
  it sounding like static: rain is thousands of discrete impacts, and the ear hears the density.
* **murmurs** — formant-filtered noise bursts at speech cadence. Deliberately wordless and short;
  anything closer to actual speech turns ten shopkeepers into ten looping voice lines.

Usage:  python tools/generate_weather_audio.py [--only name,name]
"""

from __future__ import annotations

import argparse
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import audio_synth as A  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[1]
SFX_DIR = ROOT / "apps/game/client/assets/audio/sfx"

WIND_SECONDS = 12.0
RAIN_SECONDS = 10.0


def _wind(rng: np.random.Generator) -> np.ndarray:
    def render(seconds: float) -> np.ndarray:
        n = A.n_samples(seconds)
        t = np.arange(n) / A.SAMPLE_RATE
        base = A.noise(seconds, rng)
        # Three slow, mutually prime swells, so the bed never repeats inside the loop.
        swell = (
            0.55
            + 0.22 * np.sin(2 * np.pi * t / 7.3)
            + 0.14 * np.sin(2 * np.pi * t / 11.9 + 1.1)
            + 0.09 * np.sin(2 * np.pi * t / 3.7 + 2.3)
        )
        # Cutoff rides the swell: louder wind is also brighter wind.
        low = A.lowpass(base, 420.0, poles=2)
        mid = A.bandpass(base, 300.0, 1600.0)
        high = A.bandpass(base, 1600.0, 5200.0)
        sig = low * 0.85 + mid * swell * 0.5 + high * np.clip(swell - 0.45, 0.0, 1.0) * 0.55
        # A hint of the whistle an edge makes, well down in the mix.
        sig += A.sine(190.0 + 40.0 * np.sin(2 * np.pi * t / 9.1), seconds) * 0.012 * swell
        return sig

    loop = A.make_loop(render, WIND_SECONDS, tail_seconds=2.5)
    return A.normalize(A.widen(loop), 0.62)


def _rain(rng: np.random.Generator) -> np.ndarray:
    def render(seconds: float) -> np.ndarray:
        n = A.n_samples(seconds)
        bed = A.highpass(A.noise(seconds, rng), 900.0, poles=2) * 0.35
        bed += A.bandpass(A.noise(seconds, rng), 200.0, 900.0) * 0.22
        # Discrete impacts on top of the bed. Sparse individually, dense together — this is the
        # difference between rain and hiss.
        grains = np.zeros(n, dtype=np.float32)
        count = int(seconds * 2600)
        idx = rng.integers(0, n - 64, size=count)
        env = np.exp(-np.arange(64) / 7.0).astype(np.float32)
        amps = rng.random(count).astype(np.float32) ** 3.0
        for i, start in enumerate(idx):
            grains[start : start + 64] += env * amps[i] * rng.standard_normal()
        grains = A.highpass(grains, 1800.0, poles=1)
        return bed + grains * 0.5

    loop = A.make_loop(render, RAIN_SECONDS, tail_seconds=2.0)
    return A.normalize(A.widen(loop), 0.7)


def _murmur(rng: np.random.Generator, pitch: float, syllables: int) -> np.ndarray:
    """A few wordless syllables at speech cadence.

    Formants rather than pitch carry the read: a voice is a buzz through two resonances, and moving
    those two around is what makes one burst read as a different vowel from the next.
    """
    seconds = 0.18 * syllables + 0.25
    out = np.zeros(A.n_samples(seconds), dtype=np.float32)
    at = 0.05
    for _ in range(syllables):
        dur = float(rng.uniform(0.1, 0.19))
        src = A.saw(pitch * float(rng.uniform(0.94, 1.08)), dur) * 0.5
        src += A.noise(dur, rng) * 0.06
        f1 = float(rng.uniform(320.0, 720.0))
        f2 = float(rng.uniform(1000.0, 2100.0))
        voiced = A.bandpass(src, f1 * 0.7, f1 * 1.4) + A.bandpass(src, f2 * 0.8, f2 * 1.25) * 0.6
        voiced *= A.adsr(dur, 0.02, 0.05, 0.6, 0.06)
        A.place(out, voiced, at, 1.0)
        at += dur + float(rng.uniform(0.03, 0.09))
    out = A.reverb(out, 0.5, 0.16, rng, predelay_ms=9.0, damping_hz=2600.0, room=0.4)
    return A.normalize(out, 0.5)


BUILDERS = {
    "weather_wind_loop": lambda rng: _wind(rng),
    "weather_rain_loop": lambda rng: _rain(rng),
    "npc_murmur_01": lambda rng: _murmur(rng, 132.0, 3),
    "npc_murmur_02": lambda rng: _murmur(rng, 108.0, 2),
    "npc_murmur_03": lambda rng: _murmur(rng, 168.0, 4),
    "npc_murmur_04": lambda rng: _murmur(rng, 96.0, 3),
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    wanted = [n for n in args.only.split(",") if n] or list(BUILDERS)
    for name in wanted:
        if name not in BUILDERS:
            print(f"unknown asset {name}", file=sys.stderr)
            return 1
        rng = np.random.default_rng(abs(hash(name)) % (2**32))
        sig = BUILDERS[name](rng)
        path = A.write_ogg(SFX_DIR / f"{name}.ogg", sig)
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

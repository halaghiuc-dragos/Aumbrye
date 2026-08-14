"""Small synthesis toolkit for authoring Aumbrye's music and foley.

The game had no menu music at all — `play_menu_music()` only set oscillator frequencies for the
fallback tone generator — and every biome's four music layers were six-to-eight-second stubs that
become maddening inside a minute. This module is the instrument rack the generators draw on.

Everything is float32 mono or stereo in [-1, 1] at SAMPLE_RATE. Write with `write_ogg`, which goes
through ffmpeg so the result is real Vorbis rather than a WAV with the wrong extension.

Design notes that matter for the result:

* Loops are seamless by construction. `make_loop` renders `bars + tail` worth of audio and folds
  the overhang back over the opening with an equal-power crossfade, so the loop point is inaudible
  rather than a click.
* Instruments are subtractive and deliberately cheap — detuned saws through a one-pole ladder,
  Karplus-Strong plucks, noise through resonant bandpasses. That suits a pixel game far better
  than sampled realism would, and it keeps every asset reproducible from source.
"""

from __future__ import annotations

import math
import pathlib
import shutil
import subprocess
import tempfile
import wave

import numpy as np
from scipy.signal import fftconvolve

SAMPLE_RATE = 44100

#: Semitone offsets from the tonic for the scales the soundtrack uses. Aeolian for melancholy,
#: Phrygian for dread (that flat second is the whole reason boss themes sound threatening),
#: Dorian for the hub's slightly warmer, less hopeless colour.
SCALES = {
    "aeolian": [0, 2, 3, 5, 7, 8, 10],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "harmonic_minor": [0, 2, 3, 5, 7, 8, 11],
}


def note_hz(semitones_from_a4: float) -> float:
    return 440.0 * (2.0 ** (semitones_from_a4 / 12.0))


def scale_degree(tonic_hz: float, scale: str, degree: int) -> float:
    """Frequency of a scale degree, wrapping into octaves for degrees outside 0..6."""
    steps = SCALES[scale]
    octave, index = divmod(degree, len(steps))
    return tonic_hz * (2.0 ** (octave + steps[index] / 12.0))


def n_samples(seconds: float) -> int:
    return int(round(seconds * SAMPLE_RATE))


def silence(seconds: float) -> np.ndarray:
    return np.zeros(n_samples(seconds), dtype=np.float32)


def _t(seconds: float) -> np.ndarray:
    return np.arange(n_samples(seconds), dtype=np.float64) / SAMPLE_RATE


# --- envelopes ---------------------------------------------------------------------------------


def adsr(seconds: float, attack: float, decay: float, sustain: float, release: float) -> np.ndarray:
    total = n_samples(seconds)
    a, d, r = (n_samples(x) for x in (attack, decay, release))
    a, d, r = min(a, total), min(d, total), min(r, total)
    s = max(0, total - a - d - r)
    parts = [
        np.linspace(0.0, 1.0, a, endpoint=False) if a else np.empty(0),
        np.linspace(1.0, sustain, d, endpoint=False) if d else np.empty(0),
        np.full(s, sustain),
        np.linspace(sustain, 0.0, r) if r else np.empty(0),
    ]
    env = np.concatenate(parts)[:total]
    if env.size < total:
        env = np.pad(env, (0, total - env.size))
    return env.astype(np.float32)


def fade(sig: np.ndarray, seconds: float = 0.01) -> np.ndarray:
    k = min(n_samples(seconds), sig.shape[0] // 2)
    if k <= 0:
        return sig
    ramp = np.linspace(0.0, 1.0, k, dtype=np.float32)
    sig = sig.copy()
    sig[:k] *= ramp
    sig[-k:] *= ramp[::-1]
    return sig


# --- oscillators -------------------------------------------------------------------------------


def _phase(freq: float | np.ndarray, seconds: float) -> np.ndarray:
    t = _t(seconds)
    if np.isscalar(freq):
        return 2.0 * math.pi * float(freq) * t
    freq = np.asarray(freq, dtype=np.float64)[: t.size]
    return 2.0 * math.pi * np.cumsum(freq) / SAMPLE_RATE


def sine(freq, seconds: float) -> np.ndarray:
    return np.sin(_phase(freq, seconds)).astype(np.float32)


def saw(freq, seconds: float) -> np.ndarray:
    ph = _phase(freq, seconds) / (2.0 * math.pi)
    return (2.0 * (ph - np.floor(ph + 0.5))).astype(np.float32)


def square(freq, seconds: float, duty: float = 0.5) -> np.ndarray:
    ph = _phase(freq, seconds) / (2.0 * math.pi)
    return np.where((ph - np.floor(ph)) < duty, 1.0, -1.0).astype(np.float32)


def triangle(freq, seconds: float) -> np.ndarray:
    ph = _phase(freq, seconds) / (2.0 * math.pi)
    frac = ph - np.floor(ph)
    return (4.0 * np.abs(frac - 0.5) - 1.0).astype(np.float32)


def noise(seconds: float, rng: np.random.Generator) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, n_samples(seconds)).astype(np.float32)


# --- filters -----------------------------------------------------------------------------------


def one_pole_lowpass(sig: np.ndarray, cutoff_hz: float) -> np.ndarray:
    """Cheap and stable. Cascade it when a steeper slope is wanted."""
    x = np.exp(-2.0 * math.pi * max(1.0, cutoff_hz) / SAMPLE_RATE)
    b = 1.0 - x
    out = np.empty_like(sig, dtype=np.float32)
    acc = 0.0
    for i in range(sig.shape[0]):
        acc = b * sig[i] + x * acc
        out[i] = acc
    return out


def lowpass(sig: np.ndarray, cutoff_hz: float, poles: int = 2) -> np.ndarray:
    # Vectorised single-pole via lfilter-equivalent recursion is the bottleneck for long tracks,
    # so use an FFT-domain brick wall with a soft knee instead: same musical intent, far cheaper.
    n = sig.shape[0]
    spec = np.fft.rfft(sig)
    freqs = np.fft.rfftfreq(n, 1.0 / SAMPLE_RATE)
    resp = 1.0 / np.sqrt(1.0 + (freqs / max(1.0, cutoff_hz)) ** (2 * poles))
    return np.fft.irfft(spec * resp, n).astype(np.float32)


def highpass(sig: np.ndarray, cutoff_hz: float, poles: int = 2) -> np.ndarray:
    n = sig.shape[0]
    spec = np.fft.rfft(sig)
    freqs = np.fft.rfftfreq(n, 1.0 / SAMPLE_RATE)
    with np.errstate(divide="ignore"):
        resp = 1.0 / np.sqrt(1.0 + (max(1.0, cutoff_hz) / np.maximum(freqs, 1e-6)) ** (2 * poles))
    return np.fft.irfft(spec * resp, n).astype(np.float32)


def bandpass(sig: np.ndarray, low_hz: float, high_hz: float) -> np.ndarray:
    return highpass(lowpass(sig, high_hz), low_hz)


# --- instruments -------------------------------------------------------------------------------


def violin(
    freq: float,
    seconds: float,
    *,
    vibrato_hz: float = 5.2,
    vibrato_cents: float = 14.0,
    attack: float = 0.10,
    brightness: float = 2600.0,
    detune_cents: float = 5.0,
) -> np.ndarray:
    """A bowed string: two slightly detuned saws, vibrato, and a slow bow-pressure swell.

    Not remotely a real violin — but the sawtooth's odd-and-even harmonic stack under a lowpass is
    the classic subtractive approximation, and with vibrato and a soft attack the ear reads it as
    bowed rather than synthetic, which is all a pixel game needs.
    """
    t = _t(seconds)
    vib = (vibrato_cents / 1200.0) * np.sin(2.0 * math.pi * vibrato_hz * t)
    # Vibrato eases in — a string player does not start a note already wobbling.
    vib *= np.clip(t / max(1e-6, attack + 0.18), 0.0, 1.0)
    f = freq * (2.0 ** vib)
    a = saw(f, seconds)
    b = saw(f * (2.0 ** (detune_cents / 1200.0)), seconds)
    body = 0.6 * a + 0.4 * b
    body = lowpass(body, brightness, poles=2)
    # A touch of the octave above adds the rosin edge the lowpass takes away.
    body += 0.12 * lowpass(saw(f * 2.0, seconds), brightness * 1.4, poles=1)
    env = adsr(seconds, attack, 0.12, 0.82, min(0.35, seconds * 0.4))
    swell = 1.0 + 0.10 * np.sin(2.0 * math.pi * 0.7 * t)
    return (body * env * swell).astype(np.float32)


def pluck(freq: float, seconds: float, rng: np.random.Generator, damping: float = 0.496) -> np.ndarray:
    """Karplus-Strong. Used for the harp figures under the title melody."""
    total = n_samples(seconds)
    period = max(2, int(SAMPLE_RATE / max(20.0, freq)))
    buf = rng.uniform(-1.0, 1.0, period).astype(np.float32)
    buf = lowpass(buf, 5000.0, poles=1)
    out = np.empty(total, dtype=np.float32)
    idx = 0
    for i in range(total):
        out[i] = buf[idx]
        nxt = (idx + 1) % period
        buf[idx] = damping * (buf[idx] + buf[nxt])
        idx = nxt
    return (out * adsr(seconds, 0.002, 0.05, 0.7, seconds * 0.6)).astype(np.float32)


def pad(freqs: list[float], seconds: float, *, cutoff: float = 1400.0, detune: float = 7.0) -> np.ndarray:
    """Sustained chord bed: each voice doubled and detuned so it breathes instead of sitting still."""
    out = np.zeros(n_samples(seconds), dtype=np.float32)
    for i, f in enumerate(freqs):
        drift = 1.0 + 0.0015 * np.sin(2.0 * math.pi * (0.05 + 0.017 * i) * _t(seconds))
        out += saw(f * drift, seconds)
        out += saw(f * (2.0 ** (detune / 1200.0)) * drift, seconds)
    out /= max(1.0, len(freqs) * 1.6)
    out = lowpass(out, cutoff, poles=2)
    return (out * adsr(seconds, seconds * 0.25, 0.1, 0.9, seconds * 0.35)).astype(np.float32)


def choir(freqs: list[float], seconds: float, rng: np.random.Generator) -> np.ndarray:
    """Breathy vowel bed for boss themes — filtered noise formants over soft triangles."""
    out = np.zeros(n_samples(seconds), dtype=np.float32)
    for f in freqs:
        out += 0.5 * triangle(f, seconds)
        out += 0.25 * sine(f * 2.0, seconds)
    out /= max(1.0, len(freqs))
    breath = bandpass(noise(seconds, rng), 500.0, 2400.0) * 0.18
    body = lowpass(out + breath, 2200.0, poles=2)
    return (body * adsr(seconds, seconds * 0.3, 0.15, 0.85, seconds * 0.4)).astype(np.float32)


def kick(seconds: float = 0.5) -> np.ndarray:
    t = _t(seconds)
    sweep = 120.0 * np.exp(-t * 22.0) + 42.0
    body = np.sin(2.0 * math.pi * np.cumsum(sweep) / SAMPLE_RATE)
    return (body * adsr(seconds, 0.001, 0.10, 0.25, seconds * 0.7)).astype(np.float32)


def war_drum(seconds: float, rng: np.random.Generator, pitch: float = 82.0) -> np.ndarray:
    """Big taiko-ish hit for boss themes: tuned body plus a skin transient."""
    t = _t(seconds)
    sweep = pitch * (1.0 + 0.7 * np.exp(-t * 30.0))
    body = np.sin(2.0 * math.pi * np.cumsum(sweep) / SAMPLE_RATE)
    skin = bandpass(noise(seconds, rng), 180.0, 1800.0) * np.exp(-t * 26.0)
    mix = 0.85 * body + 0.35 * skin
    return (mix * adsr(seconds, 0.001, 0.14, 0.3, seconds * 0.6)).astype(np.float32)


def snare(seconds: float, rng: np.random.Generator) -> np.ndarray:
    t = _t(seconds)
    body = bandpass(noise(seconds, rng), 900.0, 6500.0)
    tone = 0.3 * np.sin(2.0 * math.pi * 210.0 * t)
    return ((body + tone) * np.exp(-t * 24.0)).astype(np.float32)


# --- space -------------------------------------------------------------------------------------


def reverb(sig: np.ndarray, seconds: float, mix: float, rng: np.random.Generator) -> np.ndarray:
    """Convolution with an exponentially decaying noise tail — a cheap, convincing stone room.

    FFT convolution, not direct: a minute of audio against a one-second tail is 2.6M x 48k
    multiply-adds the direct way, which turns a whole soundtrack render into an overnight job.
    """
    length = n_samples(seconds)
    ir = rng.uniform(-1.0, 1.0, length).astype(np.float32)
    ir *= np.exp(-np.linspace(0.0, 6.0, length, dtype=np.float32))
    ir = lowpass(ir, 4200.0, poles=1)
    ir[0] = 1.0
    wet = fftconvolve(sig, ir)[: sig.shape[0]]
    peak = float(np.max(np.abs(wet))) or 1.0
    wet = wet / peak * (float(np.max(np.abs(sig))) or 1.0)
    return ((1.0 - mix) * sig + mix * wet).astype(np.float32)


def stereo(left: np.ndarray, right: np.ndarray) -> np.ndarray:
    n = min(left.shape[0], right.shape[0])
    return np.stack([left[:n], right[:n]], axis=1)


def widen(sig: np.ndarray, delay_ms: float = 11.0) -> np.ndarray:
    """Haas-effect widening: the same signal a few milliseconds later in the other ear."""
    d = n_samples(delay_ms / 1000.0)
    right = np.concatenate([np.zeros(d, dtype=np.float32), sig])[: sig.shape[0]]
    return stereo(sig, 0.92 * right)


# --- arrangement -------------------------------------------------------------------------------


def place(track: np.ndarray, sig: np.ndarray, at_seconds: float, gain: float = 1.0) -> None:
    """Mix `sig` into `track` in place, clipped to the track's length."""
    start = n_samples(at_seconds)
    if start >= track.shape[0]:
        return
    end = min(track.shape[0], start + sig.shape[0])
    track[start:end] += gain * sig[: end - start]


def make_loop(render, loop_seconds: float, tail_seconds: float = 2.0) -> np.ndarray:
    """Render `loop_seconds + tail_seconds` and fold the tail back over the opening.

    A loop that simply stops at the bar line clicks, and one that fades out at both ends pumps.
    Folding the overhang back in means the reverb tail and any note still ringing at the loop point
    continue into the start, which is what makes the seam inaudible.
    """
    full = render(loop_seconds + tail_seconds)
    body = np.array(full[: n_samples(loop_seconds)], dtype=np.float32)
    tail = full[n_samples(loop_seconds) :]
    k = min(tail.shape[0], body.shape[0])
    if k > 0:
        ramp = np.linspace(0.0, 1.0, k, dtype=np.float32)
        # Equal power, so the sum keeps a constant perceived level through the seam.
        body[:k] = body[:k] * np.sqrt(ramp) + tail[:k] * np.sqrt(1.0 - ramp)
    return align_zero_crossing(body)


def align_zero_crossing(loop: np.ndarray, search_seconds: float = 0.05) -> np.ndarray:
    """Rotate a loop so it begins at a zero crossing.

    The crossfade makes the *content* continuous across the seam, but the last sample and the
    first still have to meet: if the waveform is mid-swing at both ends the step between them is a
    click on every repeat. Rotating costs nothing musically — the loop is cyclic, so any starting
    offset plays the same material — and it drops the step to near zero without the level dip a
    micro-fade at each end would introduce.
    """
    if loop.ndim != 1 or loop.shape[0] == 0:
        return loop
    window = min(n_samples(search_seconds), loop.shape[0] // 4)
    if window <= 1:
        return loop
    head = loop[:window]
    rising = np.where((head[:-1] <= 0.0) & (head[1:] > 0.0))[0]
    if rising.size == 0:
        return loop
    return np.roll(loop, -int(rising[0])).astype(np.float32)


def normalize(sig: np.ndarray, peak: float = 0.89) -> np.ndarray:
    m = float(np.max(np.abs(sig))) or 1.0
    return (sig / m * peak).astype(np.float32)


def soft_clip(sig: np.ndarray) -> np.ndarray:
    return np.tanh(sig * 1.15).astype(np.float32)


# --- output ------------------------------------------------------------------------------------


def _ffmpeg() -> str:
    exe = shutil.which("ffmpeg") or "C:/ffmpeg/ffmpeg/bin/ffmpeg.exe"
    if not pathlib.Path(exe).exists() and shutil.which("ffmpeg") is None:
        raise RuntimeError("ffmpeg not found; needed to encode Ogg Vorbis")
    return exe


def write_ogg(path: str | pathlib.Path, sig: np.ndarray, quality: int = 5) -> pathlib.Path:
    """Write float audio as Ogg Vorbis. Mono in, mono out; (n, 2) in, stereo out."""
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.asarray(sig, dtype=np.float32)
    if data.ndim == 1:
        channels = 1
    else:
        channels = data.shape[1]
    pcm = np.clip(data, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = pathlib.Path(tmp) / "render.wav"
        with wave.open(str(wav_path), "wb") as w:
            w.setnchannels(channels)
            w.setsampwidth(2)
            w.setframerate(SAMPLE_RATE)
            w.writeframes(pcm.tobytes())
        subprocess.run(
            [
                _ffmpeg(), "-y", "-loglevel", "error",
                "-i", str(wav_path),
                "-c:a", "libvorbis", "-q:a", str(quality),
                str(path),
            ],
            check=True,
        )
    return path

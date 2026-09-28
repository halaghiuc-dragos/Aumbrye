# Dark synth audio edition

Generate the entire existing game audio bank:

```sh
python3 tools/generate_dark_audio.py --force
python3 tools/validate_dark_audio.py
```

Requires Python, NumPy, SciPy, FFmpeg and FFprobe. No downloaded samples or external music are used. Existing foley synthesis is reused as source code with new deterministic performances and darker processing. The score is original.

The authoritative replacement generator is `generate_dark_audio.py`. Older generators remain historical tools; running them can replace parts of this edition with their previous designs. Asset ownership and source fingerprints are recorded in `.generated-manifest.json`.

## Direction

Low bowed synth strings and cello-register motifs sit above open fifths, moving minor harmony, and understated pulse-wave arpeggios. Band-limited harmonic synthesis supplies retro colour without reducing the fidelity of the output. Boss arrangements develop across four eight-bar sections, adding drum fills and choir layers. The hub is restrained; exploration leaves breathing room. No music samples are taken from Dark Souls.

Each realm has its own key, tempo, room decay and motif family: cathedral/chapel use organ-like vowels, ice realms use descending phrases, crystal realms use soft bell accents, mire realms use close intervals, and the vault has the fastest percussion. Exploration and combat share tempo and harmony within each realm.

Combat effects combine dry transients, low modal bodies and short reflections. Material-specific impacts and footsteps remain distinct. Weather, portals, rewards, interactions, voices and animal sounds are also regenerated. Original asset paths and Godot import identities are retained.

## Rendering

- 48,000 Hz stereo float synthesis, direct float PCM input to FFmpeg.
- Ogg Vorbis quality 10; no intermediate 16-bit conversion.
- Open stereo placement with centered low voices and decorrelated chamber reflections.
- Music arranged on complete bars, with note overhang and reverb folded into the opening.
- Circular frequency-domain EQ preserves loop continuity.
- Gain-only mastering retains dynamics and reserves peak headroom; in-game bus/profile gains still apply.
- Digest-derived random seeds keep each asset's synthesis stable independently of render order.

`--only shared/title_theme --dry-run --force` renders and checks one candidate without replacing it. Completed candidates are cached under the system temporary directory using a fingerprint of all synthesis sources, so an interrupted run can resume without reusing stale compositions. Ogg container serials can differ on repeated encodes even when the underlying synthesis is deterministic.

The render report records coverage, durations and before/after hashes. Validation decodes every result through FFmpeg, checks format, peak headroom, silence, duration, distinct hashes and loop boundary jumps. These are signal/integration checks, not a substitute for listening in the game with music, ambience and combat effects playing together.

# Castle audio (AUDIO-2.1)

Authoring targets (streamed loops):

- `ambience_loop.ogg` — dungeon ambience
- `boss_theme.ogg` — boss fight music

Legacy `.wav` copies remain for reference; profiles and `AudioDirector` prefer `.ogg`.

Convert authored WAV sources with:

```bash
ffmpeg -i ambience_loop.wav -c:a libvorbis -q:a 4 ambience_loop.ogg
ffmpeg -i boss_theme.wav -c:a libvorbis -q:a 4 boss_theme.ogg
```

If files are missing, `AudioDirector` falls back to procedural tones using per-biome
frequencies from `content/audio_profiles/*.json`.

Per-biome alias loops live under `res://assets/audio/<biome_id>/` until bespoke tracks ship.

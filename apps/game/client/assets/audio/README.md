# Biome audio

Each biome folder holds procedurally generated placeholder `.ogg` loops (unique per-biome
frequency profile). Regenerate with:

```bash
node scripts/tools/generate-biome-audio.mjs
```

Profiles reference these paths in `content/audio_profiles/<biome_id>.json`. Short combat SFX
use procedural tones via `AudioDirector`; add `.wav` under `res://assets/audio/sfx/` when authored.

Replace per-biome files when real stems are ready.

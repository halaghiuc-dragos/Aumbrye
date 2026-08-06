# Biome audio

Each biome folder holds procedurally generated placeholder `.ogg` loops (unique per-biome
frequency profile). Regenerate with:

```bash
node scripts/tools/generate-biome-audio.mjs
```

Combat SFX are authored as `.ogg`/`.wav` under `res://assets/audio/sfx/` and wired through
`content/audio/sfx.json` and `AudioDirector.SFX_PROFILES`. Regenerate with:

```bash
node scripts/tools/generate-combat-sfx.mjs
```

Replace per-biome files when real stems are ready.

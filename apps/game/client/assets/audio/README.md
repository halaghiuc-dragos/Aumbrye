# Biome audio

Each biome folder holds procedurally generated placeholder `.ogg` loops (unique per-biome
frequency profile). Generation uses a reproducible PRNG (`--seed N`), stages and validates the full
candidate set before publishing, and records source/output hashes in `tools/.generated-manifest.json`.
An unregistered or manually changed existing file is never overwritten silently; inspect the
candidate and pass `--force` only when replacement is intentional. Check references without writing:

```bash
node scripts/tools/generate-game-audio.mjs --check
```

Generate with an explicit seed; pass `--force` only after reviewing the complete candidate set:

```bash
node scripts/tools/generate-biome-audio.mjs --seed 20260923 --force
```

Combat SFX are authored as `.ogg`/`.wav` under `res://assets/audio/sfx/` and wired through
`content/audio/sfx.json` and `AudioDirector.SFX_PROFILES`. Generation is seeded and uses the same
staged, provenance-tracked publication path. It refuses to overwrite unregistered or manually
changed assets unless `--force` is explicit. Its no-output FFmpeg smoke check is:

```bash
node scripts/tools/generate-combat-sfx.mjs --self-test --seed 20260923
```

After reviewing candidates, publish them with:

```bash
node scripts/tools/generate-combat-sfx.mjs --seed 20260923 --force
```

Replace per-biome files when real stems are ready.

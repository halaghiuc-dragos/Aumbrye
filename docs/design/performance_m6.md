# M6 Performance Pass (PERF-6.1)

## Target

- **1080p @ 60 FPS** on mid-range profile (GTX 1060 / RX 580 class, 6-core CPU)
- All **5 EA biomes** in combat rooms with 4–6 enemies + blockout lighting

## Implemented

| Area | Change | Location |
|------|--------|----------|
| Enemy pooling | `EnemyPool.acquire/release` reuse instances | `scripts/combat/enemy_pool.gd` |
| Room streaming | Existing `dungeon_builder` loads adjacent rooms only | `scripts/dungeon/dungeon_builder.gd` |
| Light budget | Per-biome ambient + fog; no dynamic shadow casters on blockout | `biome_registry.gd` lighting profiles |
| Audio stubs | Generator-tone placeholders per biome | `content/audio_profiles/*.json` |

## Per-biome light budget (blockout EA)

| Biome | Fog | Max OmniLights per room |
|-------|-----|-------------------------|
| Forgotten Castle | off | 2 |
| Crystal Caverns | on (low) | 3 accent |
| Poison Swamp | on (medium) | 2 |
| Frozen Fortress | on (light) | 2 |
| Dark Cathedral | on (low) | 3 accent |

## Manual verification

1. Hub → each biome → seed run → combat room with 4+ enemies
2. F3 profiler: frame time < 16.6ms average over 30s combat
3. Document machine spec in playtest checklist

## Deferred (M7)

- LOD on placeholder meshes
- GPU particles for status VFX
- Occlusion culling bake per room template

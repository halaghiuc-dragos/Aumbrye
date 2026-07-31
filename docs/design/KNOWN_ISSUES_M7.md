# Known Issues — M7

> Published subset for store page / EA ship. Full deferred list: [M7_IMPLEMENTATION_LOG.md](M7_IMPLEMENTATION_LOG.md).

## Steam / platform

| Issue | Workaround | Owner |
|-------|------------|-------|
| GodotSteam not bundled in repo | `SteamService` runs in **stub mode**; achievements sync locally only | Needs Steam App ID + SDK path |
| Steam overlay untested | Launch via Steam client after GodotSteam build | STEAM-7.1 manual (`M7.steam.overlay`) |
| Steam Cloud not wired to file I/O | Backend cloud + local cache remain source of truth | STEAM-7.3 (`M7.steam.cloud`) |
| Steam depot / public branch not live | Use local export until SHIP-7.3 | Manual ship gate |

## Gameplay

| Issue | Notes |
|-------|-------|
| Final boss phases 2–3 are simplified | Spike burst + crystal collect; cannon interact stub |
| Non-castle final bosses not implemented | Use theme boss on floor 10 for other biomes until themed puzzles ship |
| Descend requires Shift+interact | Document in manual checklist; **disabled in endless mode** |
| Endless mode has no retreat lever | Player must die to exit; no hub escape portal mid-run |
| Waves equip UI is minimal | Chest loot goes to `waves_inventory`; no full equip panel (`M7.waves.equip_feel`) |
| Umbral visual theme is a stub | Waves arena uses `dark_cathedral` materials; dedicated umbral palette post-EA |
| Waves early exit | No items transfer to main inventory before wave 50 clear |

## Chunking / saves

| Issue | Notes |
|-------|-------|
| Descend regenerates prior floor | Prior floor not cached in memory; seed must match for identical layout |
| v2 saves with `floorDefinitions` | Migrated to v3 on load; blob stripped |

## Performance

| Issue | Notes |
|-------|-------|
| No GPU profiling pass in CI | `M7.perf.1080p60` manual on mid-range PC |
| Floor transition unloads/rebuilds chunk | Acceptable for EA; only one floor loaded at a time |

## Inherited deferred (tracked during M7)

| Issue | Notes |
|-------|-------|
| Gamepad-only full loop feel | Structural nav done; feel gate `M7.gamepad.*` |
| Cloud save E2E second device | `M4.cloud_e2e` + `M7.steam.cloud` |
| Online procgen default-off | Enable when API dev session stable |
| M5/M6 art/audio polish | OGG tracks, status icons, pixel-diorama rooms |

## User input needed

1. **Steam App ID** for `steam_appid.txt` (gitignored) and depot config
2. **GodotSteam** plugin path or CI build step
3. **Crash report upload** destination (SaaS optional per PERF-7.2)
4. **Waves early-exit policy** — confirm for EA store copy
5. **Umbral art pass** — dedicated palette vs reusing dark_cathedral

# Audio director

`AudioDirector` is the `res://scripts/audio/audio_director.gd` autoload (`project.godot`) that owns four music/ambience layers, a stinger player, an eight-player SFX pool, four `AudioStreamPlayer3D` SFX slots, five audio buses, per-biome reverb, and a sidechain duck. **Authored OGG stems are the default path** for every biome layer and SFX bank entry; synthesis is a fallback when a source file is absent.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/audio/audio_director.gd` | Autoload: layers, SFX bank, generators, buses, reverb, duck, emitters |
| `apps/game/client/scripts/audio/audio_settings.gd` | Persisted bus volumes (`master`, `music`, `sfx`, `ambience`, `ui`) |
| `content/audio_profiles/*.json` | Ten per-biome profiles with `layers` and `stingers` |
| `content/schemas/audio-profile.v1.json` | Draft-07 schema; `layers` and `stingers` keys |
| `content/audio/sfx.json` | SFX bank: variants, surface sets, concurrency, fallback tones |
| `content/schemas/sfx-bank.v1.json` | Schema for the SFX bank |
| `apps/game/client/assets/audio/<biome_id>/*.ogg` | Four layer stems per biome (40 files) |
| `apps/game/client/assets/audio/shared/*.ogg` | Shared stingers (`sting_boss`, `sting_clear`) |
| `apps/game/client/assets/audio/sfx/*.ogg` | Combat and ambient SFX samples (17 OGG files) |
| `apps/game/client/assets/audio/default_bus_layout.tres` | Five buses, all at 0 dB, all sending to `Master` |
| `scripts/tools/generate-biome-audio.mjs` | Delegates to `generate-game-audio.mjs`; supports `--check` |
| `scripts/tools/generate-game-audio.mjs` | Generates procedural OGG stems and SFX when sources are missing |
| `apps/game/client/scripts/validation/suites/audio_suite.gd` | Content validation suite (22 assertions) |

## How it works

### Layers and setup

`_ready()` sets `PROCESS_MODE_ALWAYS`, loads `AudioSettings`, installs bus effects, then creates four `AudioStreamPlayer` layers pre-loaded with an `AudioStreamGenerator` at 44100 Hz and a 0.25 s buffer, plus a fifth `StingerPlayer` on the `Music` bus:

| Node | Bus | Default freq | Role |
|------|-----|--------------|------|
| `AmbiencePlayer` | `Ambience` | 110.0 | Ambient bed |
| `MusicPlayer` | `Music` | 196.0 | Boss / menu theme |
| `ExplorePlayer` | `Music` | 110.0 | Non-combat dungeon layer |
| `CombatPlayer` | `Music` | 130.0 | Combat dungeon layer |
| `StingerPlayer` | `Music` | — | One-shot stingers (non-looping) |

Then eight `AudioStreamPlayer` (`SfxPlayer0..7`) and four `AudioStreamPlayer3D` (`Sfx3dPlayer0..3`, `max_distance = 24.0`), all on the `SFX` bus. The SFX bank loads from `content/audio/sfx.json`; fallback tones are pre-baked into `AudioStreamWAV` at `_ready`. In debug builds, `_report_audio_content()` logs one line per biome listing which stems resolved from disk.

### Per-frame synthesis (fallback only)

`_process()` returns immediately when `_current_mode == "none"`. For each playing layer whose stream is an `AudioStreamGenerator`, it calls `_fill_generator_for_mode(player, freq, phase, mode, layer_id)`.

`_fill_generator_for_mode()` takes an explicit `LayerId` enum (`AMBIENCE`, `MUSIC`, `EXPLORE`, `COMBAT`) rather than reading `player.name`. The base waveform is `sin(phase) * 0.22 + sin(phase * 0.5) * 0.08`. `menu`, `hub`, `dungeon`, and `boss` modes each branch by `layer_id`, so explore/combat crossfades are distinguishable even without stems.

When all four layers hold file-backed streams, `_process` performs zero `sin()` evaluations.

### Modes

| Entry point | `_current_mode` | Behaviour |
|-------------|-----------------|-----------|
| `play_dungeon_ambience()` | `dungeon` | `_ensure_layer_streams()`, then crossfades ambience in over music and explore in over combat |
| `play_menu_music()` | `menu` | `set_biome("dark_cathedral")`, `_apply_mode_fallback_freqs(MENU_FALLBACK_FREQS)` for generator-backed layers only, `_ensure_layer_streams()`, `cathedral` reverb, fades music and explore in |
| `play_hub_ambience()` | `hub` | `set_biome("umbral_chapel")`, hub fallback freqs, `_ensure_layer_streams()`, `umbral` reverb, fades ambience and music in |
| `play_boss_music()` | `boss` | No generator restore; fades combat and explore out, crossfades music in over ambience |
| `play_stinger(key)` | — | Loads stinger from profile `stingers` map, plays on `StingerPlayer`, ducks `Music` layer by 4 dB for duration |
| `register_combat_engagement()` | — | Only acts in `dungeon` mode; on first engagement crossfades combat in over explore |
| `unregister_combat_engagement()` | — | On last disengagement crossfades explore back in |
| `stop_all(fade)` | `none` | Fades all four out |

Callers: `hub.gd`, `main_menu.gd`, `title_screen.gd`, `run_flow.gd`, `castle_run.gd`, boss scripts, `castle_enemy_base.gd`, `waves_run.gd`.

### Stream preservation

`_ensure_layer_streams()` only installs a generator when a layer's stream is null or already a generator. File-backed streams loaded by `set_biome()` survive `play_dungeon_ambience()` and subsequent mode changes.

Run start order:

1. `castle_run.gd` → `_apply_biome_presentation()` → `BiomeRegistry.apply_run_presentation()` → `AudioDirector.set_biome(biome_id)`, which loads four layer stems via `_load_layer_stems()`.
2. `castle_run.gd` → `AudioDirector.play_dungeon_ambience()` → `_ensure_layer_streams()` leaves file streams intact.
3. `_crossfade_to()` starts playback.

### Biome profiles

`set_biome(biome_id)`:

1. Loads `content/audio_profiles/<biome_id>.json` via `ContentLoader.load_json(BiomeRegistry.get_audio_profile_path(...))`.
2. Normalizes legacy profiles (missing `layers`) into the v2 shape via `_normalize_profile()`.
3. Applies fallback frequencies from `layers.*.fallback_freq` (or legacy `*Freq` keys); `combatFreq` defaults to `DEFAULT_COMBAT_FALLBACK_FREQ` (130.0), not the previous biome's `_music_freq`.
4. Calls `_load_layer_stems()` for `ambience`, `explore`, `combat`, and `boss` paths.
5. Applies the reverb preset from `reverbPreset`, falling back to `BIOME_REVERB_PRESETS[biome_id]` and then `indoor_castle`.

`_load_audio_stream(path)` requires `FileAccess.file_exists()` on the globalized path before calling `ResourceLoader.load()`, so a missing source file cannot pass validation via the `.import` remap alone.

Profile v2 shape (all ten profiles migrated):

```json
{
  "layers": {
    "ambience": { "path": "res://assets/audio/forgotten_castle/ambience_loop.ogg", "volume_db": -6.0, "fallback_freq": 110.0 },
    "explore":  { "path": "res://assets/audio/forgotten_castle/explore_loop.ogg",  "volume_db": -9.0, "fallback_freq": 110.0 },
    "combat":   { "path": "res://assets/audio/forgotten_castle/combat_loop.ogg",   "volume_db": -6.0, "fallback_freq": 130.0 },
    "boss":     { "path": "res://assets/audio/forgotten_castle/boss_theme.ogg",    "volume_db": -4.0, "fallback_freq": 196.0 }
  },
  "stingers": {
    "boss_reveal": "res://assets/audio/shared/sting_boss.ogg",
    "floor_clear": "res://assets/audio/shared/sting_clear.ogg"
  }
}
```

Legacy `ambiencePath`/`bossPath`/`*Freq` keys remain accepted and are mapped into `layers` by `_normalize_profile()`.

### SFX bank

`play_sfx(kind, world_pos, surface)` resolves the entry from `content/audio/sfx.json`:

- Unknown keys warn once and fall back to `"hit"`.
- `variants` rotate round-robin; `surface_variants` select by floor material (`stone`, `wood`, `water`).
- `pitch_jitter`, `max_concurrent`, and `cooldown_ms` are enforced per entry.
- Missing files fall back to pre-baked `fallback_tone` WAVs baked at `_ready`.
- `world_pos is Vector3` routes through the 3D pool; otherwise the 2D pool.

Legacy keys: `hit`, `block`, `parry`, `swing`, `death`, `footstep`, `windup`, `ui`. Additional keys: `hit_armor`, `heal_raise`, `heal_gulp`, `heal_commit`, `brazier`, `fountain`.

Combat callers invoke `AudioDirector` directly — `hit_feedback.gd`, `weapon_controller.gd`, `castle_enemy_base.gd`, `locomotion.gd`, `player_anim_director.gd`. `VfxService` handles particles only; it does not call `AudioDirector`.

### Positional emitters

`attach_loop_emitter(host, key, radius)` creates an `AudioStreamPlayer3D` child on `host`, resolves the stream from the SFX bank, sets `unit_size` and `max_distance`, and autoplays. Wired from `diorama_room_dressing.gd` (braziers) and `pixel_diorama_style.gd` (hub fountain).

### Buses, reverb, duck

`_setup_bus_effects()` adds an `AudioEffectReverb` to `Ambience` and `SFX` (idempotent) and an `AudioEffectCompressor` on `Ambience` sidechained from `Music` at threshold −20 dB, ratio 5, attack 120 ms, release 750 ms.

`_apply_reverb_preset(id)` looks the id up in `REVERB_PRESETS` (eight presets) and writes `wet`, `room_size`, `damping`, `spread` onto both reverbs, scaling the `SFX` wet by 0.55.

`AudioSettings` holds five static floats in 0–1, persists them under the `audio` key in `LocalSave` meta, and `apply()` writes `linear_to_db()` (or −80 dB at zero) onto the five buses.

### Assets

`apps/game/client/assets/audio/` contains 61 committed OGG files:

| Category | Count | Location |
|----------|-------|----------|
| Biome layer stems | 40 | `<biome_id>/{ambience,explore,combat}_loop.ogg` + `boss_theme.ogg` × 10 biomes |
| Shared stingers | 2 | `shared/sting_boss.ogg`, `shared/sting_clear.ogg` |
| SFX samples | 17 | `sfx/*.ogg` |
| Legacy castle | 2 | `castle/{ambience_loop,boss_theme}.ogg` (orphaned; not referenced by profiles) |

All `*_loop.ogg.import` sidecars carry `loop=true`. Heal SFX (`heal_raise`, `heal_gulp`, `heal_commit`) remain WAV files referenced from the bank.

`generate-biome-audio.mjs` delegates to `generate-game-audio.mjs`, which checks `ffmpeg` up front, uses `node:fs.rmSync` for temp cleanup, and supports `--check` to assert every profile and bank path exists on disk. CI runs `node scripts/tools/generate-biome-audio.mjs --check` in `.github/workflows/ci.yml`.

## Contracts

- Autoload name `AudioDirector`; asserted by `setup_suite.gd`.
- Bus names `Master`, `Music`, `SFX`, `Ambience`, `UI` are the contract between `default_bus_layout.tres`, `AudioSettings`, the SFX bank `bus` fields, and `_ensure_sidechain_compressor(&"Ambience", &"Music")`.
- `LayerId` enum drives generator waveform selection; player node names are no longer read for mix branching.
- Audio-profile keys: `id`, `biomeId`, `layers`, `stingers`, `reverbPreset`, `crossfadeSeconds`; legacy `ambiencePath`/`bossPath`/`*Freq` accepted.
- `reverbPreset` values must be one of the eight `REVERB_PRESETS` keys; the schema enumerates the same eight.
- SFX bank keys validated by `audio_suite.gd`; heal keys used by `player_heal.gd`.
- `LocalSave` meta key `audio` with the five volume floats.
- `_current_mode` values: `none`, `dungeon`, `menu`, `hub`, `boss`. Combat engagement counting only applies in `dungeon`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Four-layer mode machine with crossfades and combat layering | IMPLEMENTED | `audio_director.gd:183-258` |
| File-backed stems preserved across mode changes | IMPLEMENTED | `_ensure_layer_streams()` `:475-479`; `audio_suite.gd` `audio.file_stream_survives_mode_change` |
| Ten biome profiles with `layers` and `stingers` | IMPLEMENTED | `content/audio_profiles/*.json`; `audio-profile.v1.json` |
| 61 OGG assets on disk | IMPLEMENTED | `apps/game/client/assets/audio/**/*.ogg` |
| SFX bank with variants, surface sets, concurrency, cooldown | IMPLEMENTED | `content/audio/sfx.json`; `play_sfx()` `:274-293` |
| Pre-baked fallback tones (no per-shot synthesis) | IMPLEMENTED | `_bake_fallback_tones()` `:639-648` |
| Stinger player with music duck | IMPLEMENTED | `play_stinger()` `:226-242`; `castle_run.gd` boss reveal |
| Positional loop emitters | IMPLEMENTED | `attach_loop_emitter()` `:299-319`; brazier/fountain callers |
| Waves runs start audio | IMPLEMENTED | `waves_run.gd:55-56` `set_biome` + `play_dungeon_ambience` |
| Per-layer generator waveforms in dungeon/boss | IMPLEMENTED | `_fill_generator_for_mode()` `:789-798` |
| `combatFreq` from profile, not previous biome | IMPLEMENTED | `_apply_profile_freqs()` `:590-593`; `DEFAULT_COMBAT_FALLBACK_FREQ` |
| VFX decoupled from audio | IMPLEMENTED | `vfx_service.gd` has no `AudioDirector` calls; combat scripts call `play_sfx` directly |
| Loop imports enabled | IMPLEMENTED | `*_loop.ogg.import` `loop=true`; `audio_suite.gd` `audio.loop_imports_loop` |
| Debug content report | IMPLEMENTED | `_report_audio_content()` `:671-687` |
| CI stem check | IMPLEMENTED | `.github/workflows/ci.yml` `generate-biome-audio.mjs --check` |
| Validation suite | IMPLEMENTED | `audio_suite.gd` (22 tests); registered in `validation_runner.gd` |
| Generator synthesis fallback | IMPLEMENTED | `_fill_generator_for_mode()` when stems absent |
| Synthesis skipped when stems present | IMPLEMENTED | `_process()` generator guard `:144-158`; `audio.no_process_synthesis_with_stems` |

## Related

- Improvement plan: [`../actual_improvements/audio-director.md`](../actual_improvements/audio-director.md)
- [`biome-registry.md`](biome-registry.md) — resolves the profile path and calls `set_biome()`
- [`vfx-service.md`](vfx-service.md) — combat particles only; audio fired separately
- [`castle-run.md`](castle-run.md), [`waves-run.md`](waves-run.md), [`run-flow.md`](run-flow.md) — mode-change call sites
- [`hub.md`](hub.md), [`ui/main_menu.md`](ui/main_menu.md), [`ui/title_screen.md`](ui/title_screen.md) — other mode callers
- [`bosses.md`](bosses.md) — `play_boss_music()` and stinger callers
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — brazier emitters
- [`ui/settings.md`](ui/settings.md) — the five volume sliders
- [`local-save.md`](local-save.md) — the `audio` meta block
- [`content-data.md`](content-data.md), [`content-catalog.md`](content-catalog.md) — profile and bank schemas
- [`tools-scripts.md`](tools-scripts.md) — `generate-biome-audio.mjs`
- [`ci-cd.md`](ci-cd.md) — stem check job

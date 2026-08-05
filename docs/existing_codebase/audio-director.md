# Audio director

`AudioDirector` is the `*res://scripts/audio/audio_director.gd` autoload (`project.godot:42`) that owns four music/ambience layers, a 12-player SFX pool, five audio buses, per-biome reverb, and a sidechain duck. **All game audio is synthesized sine waves.** Every combat, footstep, and UI sound is a decaying sine burst pushed into an `AudioStreamGenerator` at play time. Every ambience and music layer is a two-partial sine generated per frame in `_process`. The ten biome audio profiles point at 20 `.ogg` files, **none of which exist in the repository** — only their `.import` sidecars are committed — and even if they did, `_restore_generator_streams()` replaces every loaded stream with a fresh generator before playback starts.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/audio/audio_director.gd` | The autoload: layers, SFX pool, generators, buses, reverb, duck |
| `apps/game/client/scripts/audio/audio_settings.gd` | Persisted bus volumes (`master`, `music`, `sfx`, `ambience`, `ui`) |
| `content/audio_profiles/*.json` | Ten per-biome profiles |
| `content/schemas/audio-profile.v1.json` | Draft-07 schema, `additionalProperties: false`, requires `id` and `biomeId` |
| `apps/game/client/assets/audio/default_bus_layout.tres` | The five buses, all at 0 dB, all sending to `Master` |
| `apps/game/client/assets/audio/<biome_id>/*.ogg.import` | 22 import sidecars with no source files |
| `apps/game/client/assets/audio/castle/*.wav` | The only two audio source files in the repo |
| `scripts/tools/generate-biome-audio.mjs` | Node script that writes the placeholder loops and needs `ffmpeg` |

## How it works

### Layers and setup

`_ready()` (`:70-95`) sets `PROCESS_MODE_ALWAYS`, loads `AudioSettings`, installs bus effects, then creates four `AudioStreamPlayer` layers, each pre-loaded with an `AudioStreamGenerator` at 44100 Hz and a 0.25 s buffer:

| Node | Bus | Default freq | Role |
|------|-----|--------------|------|
| `AmbiencePlayer` | `Ambience` | 110.0 | Ambient bed |
| `MusicPlayer` | `Music` | 196.0 | Boss / menu theme |
| `ExplorePlayer` | `Music` | 110.0 | Non-combat dungeon layer |
| `CombatPlayer` | `Music` | 130.0 | Combat dungeon layer |

Then eight `AudioStreamPlayer` (`SfxPlayer0..7`) and four `AudioStreamPlayer3D` (`Sfx3dPlayer0..3`, `max_distance = 24.0`), all on the `SFX` bus.

### Per-frame synthesis

`_process()` (`:98-106`) checks each of the four layers and, when it is playing **and** its stream is an `AudioStreamGenerator`, calls `_fill_generator_for_mode()`.

`_fill_generator_for_mode(player, freq, phase, mode)` (`:434-468`) reads `get_frames_available()` and pushes that many frames. The base waveform is `sin(phase) * 0.22 + sin(phase * 0.5) * 0.08`. In `menu` mode the mix branches by node name — `MusicPlayer` gets `sin + sin*2`, `ExplorePlayer` gets `sin + sin*1.5`, everything else gets a quieter `sin + sin*0.5`. In `hub` mode `AmbiencePlayer` and `MusicPlayer` get their own two-partial mixes. No other mode has a branch, so `dungeon` and `boss` use the base waveform for all four layers.

At 44100 Hz per playing layer this is up to 176 400 GDScript `sin()` evaluations per second on the main thread when all four layers play.

`_fill_generator()` (`:430-431`) is a one-line wrapper with no callers.

### Modes

| Entry point | `_current_mode` | Behaviour |
|-------------|-----------------|-----------|
| `play_dungeon_ambience()` (`:137-142`) | `dungeon` | `_restore_generator_streams()`, then crossfades ambience in over music and explore in over combat |
| `play_menu_music()` (`:145-161`) | `menu` | Overwrites all four freqs (98 / 392 / 523 / 294), `_restore_generator_streams()`, `cathedral` reverb, fades music and explore in |
| `play_hub_ambience()` (`:164-181`) | `hub` | Overwrites all four freqs (110 / 220 / 165 / 87.5), `_restore_generator_streams()`, `umbral` reverb, fades ambience and music in |
| `play_boss_music()` (`:184-189`) | `boss` | No generator restore; fades combat and explore out, crossfades music in over ambience |
| `register_combat_engagement()` (`:192-197`) | — | Only acts in `dungeon` mode; on the first engagement crossfades combat in over explore |
| `unregister_combat_engagement()` (`:200-205`) | — | On the last disengagement crossfades explore back in |
| `stop_all(fade)` (`:208-214`) | `none` | Fades all four out |

Callers: `hub.gd:79`, `main_menu.gd:22`, `title_screen.gd:17`, `run_flow.gd:702-703`, `castle_run.gd:57` and `:475`, the four boss scripts, and `castle_enemy_base.gd:698,705`.

`_crossfade_to()` (`:288-290`) fades the outgoing player then `call_deferred`s the fade-in. `_fade_in_player()` (`:293-303`) returns early when `stream == null`, sets `-40 dB`, plays, and tweens to 0 dB over `_crossfade`. `_fade_out_player()` (`:306-318`) tweens to `-80 dB` then stops and resets to 0 dB. `_active_tweens` maps player to tween, killed on re-entry by `_kill_tween()` (`:321-326`).

### Biome profiles

`set_biome(biome_id)` (`:109-134`):
1. Loads `content/audio_profiles/<biome_id>.json` via `ContentLoader.load_json(BiomeRegistry.get_audio_profile_path(...))`, defaulting to `{ambienceFreq: 110, bossFreq: 196, crossfadeSeconds: 0.8}` when empty.
2. Reads `ambienceFreq`, `exploreFreq` (defaults to `ambienceFreq`), `combatFreq` (defaults to the **current** `_music_freq`, not the profile's `bossFreq`), `bossFreq`, `crossfadeSeconds`; mirrors each into a `freq` meta on the corresponding player.
3. Calls `_try_load_file_stream()` for `ambiencePath` into `_ambience` and `bossPath` into `_music`.
4. Applies the reverb preset from `reverbPreset`, falling back to `BIOME_REVERB_PRESETS[biome_id]` and then `indoor_castle`.

`_try_load_file_stream()` (`:343-350`) walks `_audio_path_candidates()` (`:353-361`), which appends the `.wav`/`.ogg` sibling of the requested path, and assigns the first candidate that `ResourceLoader.exists()` and loads as an `AudioStream`.

Callers of `set_biome()`: `biome_registry.gd:245` (from `apply_run_presentation`), `waves_run.gd:55`, `m5_suite.gd:519`.

### The generator restore, precisely

`_restore_generator_streams()` (`:471-476`):

```gdscript
for player in [_ambience, _music, _explore, _combat_layer]:
    var generator := AudioStreamGenerator.new()
    generator.mix_rate = MIX_RATE
    generator.buffer_length = GENERATOR_BUFFER_SEC
    player.stream = generator
```

It is unconditional: it does not check whether the player currently holds a file stream, and it has no "only if generator" guard. It is called from `play_dungeon_ambience()` (`:140`), `play_menu_music()` (`:156`), and `play_hub_ambience()` (`:175`).

The run start order settles the question:

1. `castle_run.gd:45` → `_apply_biome_presentation()` → `biome_registry.gd:196` `apply_run_presentation()` → `biome_registry.gd:245` `AudioDirector.set_biome(biome_id)`, which loads `ambiencePath` into `_ambience` and `bossPath` into `_music`.
2. `castle_run.gd:57` → `AudioDirector.play_dungeon_ambience()` → `_restore_generator_streams()` replaces both.
3. Only then does `_crossfade_to()` start playback.

So the file streams `set_biome()` installs are always discarded before any layer plays. `play_boss_music()` does not restore, but by then step 2 has already replaced `_music`, so boss music is also a generator. `_on_boss_defeated()` (`castle_run.gd:475`) calls `play_dungeon_ambience()` again and restores again.

`waves_run.gd:55` calls `set_biome()` and no `play_*` entry point, so the streams it installs are never started at all.

### Combat SFX, precisely

`play_sfx(kind, world_pos)` (`:221-226`) looks `kind` up in `SFX_PROFILES` (`:34-43`) with `hit` as the fallback for any unknown key, then routes to `_play_sfx_3d()` when `world_pos is Vector3` and `_play_sfx_2d()` otherwise. `play_combat_sfx()` (`:217-218`) is an alias; `play_ui_sfx()` (`:229-230`) plays the `ui` key.

`SFX_PROFILES` has eight entries, each `{freq, duration, bus}`: `hit` 220 Hz / 0.08 s, `block` 160 / 0.10, `parry` 440 / 0.12, `swing` 130 / 0.06, `death` 90 / 0.35, `footstep` 80 / 0.05, `windup` 72 / 0.22, `ui` 520 / 0.04 on the `UI` bus.

`_prime_tone_burst(player, profile)` (`:263-285`) is the only sound generator for SFX. It assigns the bus, creates a fresh `AudioStreamGenerator` with `buffer_length = max(duration, 0.25)`, assigns it, calls `play()`, then synchronously pushes `duration * 44100` frames of `sin(phase) * 0.35 * (1 - i / frame_count)` — a pure sine with a linear decay envelope, identical in both channels. For `death` that is 15 435 frames pushed inside one function call on the main thread.

There is no file-based SFX anywhere: no `res://assets/audio/sfx/` directory exists, and `_try_load_file_stream()` is never called for an SFX player.

### Buses, reverb, duck

`_setup_bus_effects()` (`:364-367`) adds an `AudioEffectReverb` to `Ambience` and to `SFX` (idempotent — it returns the index of an existing reverb if present) and an `AudioEffectCompressor` on `Ambience` sidechained from `Music` at threshold −20 dB, ratio 5, attack 120 ms, release 750 ms.

`_apply_reverb_preset(id)` (`:407-410`) looks the id up in `REVERB_PRESETS` (`:10-19`, eight presets) and writes `wet`, `room_size`, `damping`, `spread` onto both reverbs, scaling the `SFX` wet by 0.55.

`AudioSettings` (`audio_settings.gd`) holds five static floats in 0–1, persists them under the `audio` key in `LocalSave` meta, and `apply()` writes `linear_to_db()` (or −80 dB at zero) onto the five buses.

### Assets

`apps/game/client/assets/audio/` contains, in full: `README.md`, `castle/README.md`, `default_bus_layout.tres`, 22 `*.ogg.import` files across 11 folders, 2 `*.wav.import`, and 2 `*.wav`. A repository-wide glob for `**/*.ogg` returns zero files. `.gitignore` contains no audio pattern.

The two real files are `castle/ambience_loop.wav` and `castle/boss_theme.wav`. No profile references `assets/audio/castle/` — `forgotten_castle.json:8-9` points at `assets/audio/forgotten_castle/` — so the folder is orphaned. Both `.wav.import` files carry `edit/loop_mode=0` and all `.ogg.import` files carry `loop=false`, so none of the intended loops would loop even if they existed.

`generate-biome-audio.mjs` writes an 8 s ambience and a 6 s boss loop per profile: a base sine at the profile frequency plus two harmonics, windowed by a full-cycle `sin` envelope and a 50 ms fade, then shelled out to `ffmpeg -c:a libvorbis` and the temp WAVs deleted. It requires `ffmpeg` on `PATH` and is not wired into CI.

## Contracts

- Autoload name `AudioDirector` (`project.godot:42`); asserted by `setup_suite.gd:27`.
- Bus names `Master`, `Music`, `SFX`, `Ambience`, `UI` are the contract between `default_bus_layout.tres`, `AudioSettings._set_bus_volume()`, `SFX_PROFILES[*].bus`, and `_ensure_sidechain_compressor(&"Ambience", &"Music")`.
- Player node names `AmbiencePlayer`, `MusicPlayer`, `ExplorePlayer`, `CombatPlayer` are read back inside `_fill_generator_for_mode()` to select a waveform, so renaming a player silently changes the mix.
- Audio-profile keys: `id`, `biomeId`, `ambienceFreq`, `exploreFreq`, `combatFreq`, `bossFreq`, `ambiencePath`, `bossPath`, `reverbPreset`, `crossfadeSeconds`. The schema forbids any other key.
- `reverbPreset` values must be one of the eight `REVERB_PRESETS` keys; the schema enumerates the same eight.
- SFX keys in use across the codebase: `hit`, `block`, `parry`, `swing`, `death`, `footstep`, `windup`, `ui`.
- `LocalSave` meta key `audio` with the five volume floats.
- `_current_mode` values: `none`, `dungeon`, `menu`, `hub`, `boss`. Combat engagement counting only applies in `dungeon`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Four-layer mode machine with crossfades and combat layering | IMPLEMENTED | `audio_director.gd:137-214` |
| Eight-preset reverb, per-biome mapping, sidechain duck | IMPLEMENTED | `:10-32`, `:364-427` |
| Persisted five-bus volume settings | IMPLEMENTED | `audio_settings.gd:15-52` |
| Ten schema-validated biome profiles | IMPLEMENTED | `content/audio_profiles/*.json`; `content/schemas/audio-profile.v1.json` |
| All music and ambience are generated two-partial sine waves | PLACEHOLDER | `:434-468` |
| All SFX are generated decaying sine bursts | PLACEHOLDER | `:263-285`; no `res://assets/audio/sfx/` exists |
| `_restore_generator_streams()` discards loaded file streams unconditionally | BROKEN | `:471-476`, called `:140`, `:156`, `:175`; run order `castle_run.gd:45` then `:57` via `biome_registry.gd:245` |
| No `.ogg` file exists in the repository | ABSENT | `**/*.ogg` glob returns 0 files; 22 `*.ogg.import` sidecars present; `.gitignore` has no audio pattern |
| The only two audio source files sit in an unreferenced folder | PLACEHOLDER | `assets/audio/castle/*.wav`; profiles point at `assets/audio/<biome_id>/` (`forgotten_castle.json:8-9`) |
| Import settings disable looping on every intended loop | BROKEN | `forgotten_castle/ambience_loop.ogg.import:15` `loop=false`; `castle/ambience_loop.wav.import:21` `edit/loop_mode=0` |
| Waves runs never start audio | PARTIAL | `waves_run.gd:55` calls `set_biome()` with no following `play_*`; `_fade_in_player` is never reached |
| `combatFreq` falls back to the live `_music_freq`, not the profile's `bossFreq` | PARTIAL | `:120` reads `_music_freq` before `:121` overwrites it, so the fallback depends on the previously loaded biome |
| Only `menu` and `hub` modes have per-layer waveforms | PARTIAL | `:450-465` — `dungeon` and `boss` share one waveform across all four layers |
| Per-frame synthesis on the main thread | PARTIAL | `:98-106`, `:448-467` — up to 176 400 GDScript `sin()` calls per second with four layers playing |
| `_prime_tone_burst` pushes an entire burst synchronously | PARTIAL | `:281-285` — 15 435 iterations for `death`, on every death |
| A fresh `AudioStreamGenerator` per SFX | PARTIAL | `:269-272` — one allocation per footstep and per hit |
| `_fill_generator()` | STUB | defined `:430-431`; no caller |
| `_ambience_duck_idx` | STUB | assigned `:367`; never read |
| Combat SFX are triggered from the VFX layer | PARTIAL | `vfx_service.gd:86,91,96,198,231` |
| No music stems, stingers, or transitions; no positional ambience emitters | ABSENT | only the four layers exist; no `AudioStreamPlayer3D` is created outside the SFX pool (`:89-95`) |
| Validation coverage | PARTIAL | `content_suite.gd:126-148` asserts ten method names exist; `content_suite.gd:152-181` asserts each profile's `ambiencePath`/`bossPath` resolves through `ResourceLoader.exists()`, which is satisfied by the `.import` remap even with the source file absent; `m5_suite.gd:505-528` asserts each profile loads and `set_biome()` is callable. No suite asserts that a stream survives a mode change, that anything audible is produced, or that a source file exists on disk |

## Related
- Improvement plan: [`../actual_improvements/audio-director.md`](../actual_improvements/audio-director.md)
- [`biome-registry.md`](biome-registry.md) — resolves the profile path and calls `set_biome()`
- [`vfx-service.md`](vfx-service.md) — fires five of the eight SFX keys
- [`castle-run.md`](castle-run.md), [`waves-run.md`](waves-run.md), [`run-flow.md`](run-flow.md) — the mode-change call sites and the clobber ordering
- [`hub.md`](hub.md), [`ui/main_menu.md`](ui/main_menu.md), [`ui/title_screen.md`](ui/title_screen.md) — the other mode callers
- [`bosses.md`](bosses.md) — `play_boss_music()` callers
- [`ui/settings.md`](ui/settings.md) — the five volume sliders
- [`local-save.md`](local-save.md) — the `audio` meta block
- [`content-data.md`](content-data.md), [`content-catalog.md`](content-catalog.md) — the profile schema
- [`tools-scripts.md`](tools-scripts.md) — `generate-biome-audio.mjs`
- [`00-PLACEHOLDER-INVENTORY.md`](00-PLACEHOLDER-INVENTORY.md)

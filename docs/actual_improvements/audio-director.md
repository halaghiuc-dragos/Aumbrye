# Audio director — improvement plan

## Current state

Everything you can hear in Aumbrye is a sine wave computed in GDScript. Ambience and music are two-partial sines pushed into `AudioStreamGenerator`s every frame; every hit, block, parry, swing, death, footstep, and UI click is a single decaying sine burst synthesized at play time. The ten biome audio profiles reference 20 `.ogg` loops, and none of those files exist in the repository — only their `.import` sidecars are committed. Even if they did exist, `_restore_generator_streams()` overwrites every loaded stream with a fresh generator before any layer starts playing, and every `.import` sidecar has looping disabled. See [`../existing_codebase/audio-director.md`](../existing_codebase/audio-director.md).

The architecture around the synthesis is sound: four crossfaded layers, engagement-counted combat layering, eight reverb presets mapped per biome, a sidechain duck, five persisted bus volumes, and a schema-validated profile format. What is missing is any actual audio content and the plumbing to prefer it over the fallback.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| AUD-01 | P0 | `_restore_generator_streams()` unconditionally replaces all four layer streams with fresh `AudioStreamGenerator`s and is called from `play_dungeon_ambience()`, `play_menu_music()`, and `play_hub_ambience()`. A run loads its OGGs at `castle_run.gd:45` and clobbers them at `castle_run.gd:57`, before any layer plays. Authored music can never be heard, no matter what is shipped. | `audio_director.gd:471-476`, called `:140`, `:156`, `:175`; order `castle_run.gd:45` → `biome_registry.gd:245` → `castle_run.gd:57` |
| AUD-02 | P0 | No audio content exists. A repo-wide glob for `**/*.ogg` returns zero files against 22 committed `*.ogg.import` sidecars. The only two real audio files are `castle/ambience_loop.wav` and `castle/boss_theme.wav`, in a folder no profile references. `.gitignore` has no audio pattern, so this is absence, not exclusion. | `apps/game/client/assets/audio/` contents; `forgotten_castle.json:8-9` points at `assets/audio/forgotten_castle/` |
| AUD-03 | P0 | All combat SFX are generated tones. `_prime_tone_burst()` is the only sound source for the eight SFX keys: a pure sine at one frequency with a linear decay. A sword hit, a parry, and a footstep differ only in pitch and length. No `res://assets/audio/sfx/` directory exists. | `audio_director.gd:34-43`, `:263-285` |
| AUD-04 | P1 | Every intended loop has looping disabled at import. `loop=false` in all `.ogg.import` files and `edit/loop_mode=0` in both `.wav.import` files, so authored ambience would play once and stop. | `forgotten_castle/ambience_loop.ogg.import:15`; `castle/ambience_loop.wav.import:21` |
| AUD-05 | P1 | Waves runs are silent. `waves_run.gd:55` calls `set_biome()` and never calls any `play_*` entry point, so no layer is ever faded in. | `waves_run.gd:55`; `audio_director.gd:293-303` |
| AUD-06 | P1 | Synthesis runs on the main thread every frame. With four layers playing, `_fill_generator_for_mode()` evaluates up to 176 400 GDScript `sin()` calls per second, and `_prime_tone_burst()` pushes an entire burst synchronously — 15 435 iterations for a death, on every death, plus a fresh `AudioStreamGenerator` allocation per SFX. | `audio_director.gd:98-106`, `:448-467`, `:269-285` |
| AUD-07 | P1 | Only `menu` and `hub` modes have per-layer waveforms; `dungeon` and `boss` push the identical base waveform to all four layers, so the explore/combat crossfade during a run is inaudible — the same tone fades into the same tone. | `audio_director.gd:449-465` |
| AUD-08 | P1 | The profile format cannot describe music. It has four frequencies and two file paths — no stingers, no loop points, no intro/outro, no layer stems, no per-biome SFX overrides, no volume trims. | `content/schemas/audio-profile.v1.json`; `additionalProperties: false` at `:6` |
| AUD-09 | P2 | `combatFreq` defaults to the live `_music_freq` rather than the profile's `bossFreq`, and `_music_freq` is overwritten on the next line, so a profile omitting `combatFreq` inherits the *previous* biome's boss frequency. | `audio_director.gd:120-121` |
| AUD-10 | P2 | `_fill_generator_for_mode()` selects its waveform by reading `player.name`, so renaming a layer node silently changes the mix. `_fill_generator()` has no caller and `_ambience_duck_idx` is assigned and never read. | `audio_director.gd:451`, `:459`, `:430-431`, `:367` |
| AUD-11 | P2 | Combat SFX are fired from the VFX layer, so audio and visuals cannot be triggered or muted independently. | `vfx_service.gd:86`, `:91`, `:96`, `:198`, `:231` |
| AUD-12 | P2 | There is no positional ambience: no emitter for a brazier, a waterfall, or a fountain. The only `AudioStreamPlayer3D`s in the game are the four SFX pool players. | `audio_director.gd:89-95` |
| AUD-13 | P2 | `generate-biome-audio.mjs` requires `ffmpeg` on `PATH`, is not wired into CI, and cleans up with `rm` before falling back to `del`. Its output is the placeholder the whole system is built around, and nothing verifies it ran. | `scripts/tools/generate-biome-audio.mjs:63-69`, `:105-113` |
| AUD-14 | P2 | Validation cannot detect any of the above. It asserts ten method names exist and that profile paths resolve through `ResourceLoader.exists()`, which the `.import` remap satisfies with the source file absent. Nothing asserts a stream survives a mode change or that anything audible is produced. | `content_suite.gd:126-181`; `m5_suite.gd:505-528` |

## Target design

### 1. Stop the clobber

`_restore_generator_streams()` becomes a fallback installer that only touches layers with no usable stream:

```gdscript
## Ensures every layer has a playable stream. A layer that already holds a
## file-backed AudioStream is left alone; only layers with a null stream or a
## generator get a (re)built generator. This is the fallback path, not the
## default path.
func _ensure_layer_streams() -> void:
    for player in [_ambience, _music, _explore, _combat_layer]:
        if player.stream is AudioStream and not player.stream is AudioStreamGenerator:
            continue
        player.stream = _make_generator()
```

`set_biome()` records which layers it filled from disk in a `_file_backed: Dictionary[AudioStreamPlayer, bool]`, and the mode entry points call `_ensure_layer_streams()` instead of `_restore_generator_streams()`. `play_menu_music()` and `play_hub_ambience()` additionally must **not** overwrite the four frequencies when a file stream is present, since the frequencies only mean anything to the generator; they move into an `_apply_fallback_freqs()` helper called only for generator-backed layers.

The synthesized fallback stays. It is the correct behaviour for a missing stem and it is what keeps the game audible in a fresh clone. What changes is that it stops being the only outcome. Closes AUD-01.

### 2. Ship audio, and make the absence visible

Commit real `.ogg` stems under `apps/game/client/assets/audio/<biome_id>/`, and fix the import settings: `loop=true` on every `*_loop.ogg`, `loop=false` on stingers.

Because the current state is invisible, add a boot-time content check:

```gdscript
## Logs one line per biome naming which stems resolved from disk and which fell
## back to synthesis. Runs once at _ready in debug builds only.
func _report_audio_content() -> void
```

and a validation assertion that a source file exists on disk via `FileAccess.file_exists()`, not `ResourceLoader.exists()` — the latter is satisfied by the `.import` remap alone, which is exactly why the current suite passes. Closes AUD-02, AUD-04, and the `ResourceLoader` half of AUD-14.

Rejected alternative: keeping procedural generation as the shipping plan and improving the synthesis (more partials, filtered noise, an LFO). Rejected because no amount of synthesis in GDScript on the main thread will produce music, and the effort is better spent on the loader that lets authored stems in.

### 3. Authored SFX with variation

New `content/audio/sfx.json`, validated by `content/schemas/sfx-bank.v1.json`:

```json
{
  "version": 1,
  "sfx": {
    "hit": {
      "bus": "SFX",
      "variants": [
        "res://assets/audio/sfx/hit_flesh_01.ogg",
        "res://assets/audio/sfx/hit_flesh_02.ogg",
        "res://assets/audio/sfx/hit_flesh_03.ogg"
      ],
      "volume_db": -2.0,
      "pitch_jitter": 0.08,
      "max_concurrent": 3,
      "cooldown_ms": 40,
      "fallback_tone": { "freq": 220.0, "duration": 0.08 }
    },
    "footstep": {
      "bus": "SFX",
      "surface_variants": {
        "stone": ["res://assets/audio/sfx/step_stone_01.ogg", "res://assets/audio/sfx/step_stone_02.ogg"],
        "wood":  ["res://assets/audio/sfx/step_wood_01.ogg"],
        "water": ["res://assets/audio/sfx/step_water_01.ogg"]
      },
      "volume_db": -8.0,
      "pitch_jitter": 0.12,
      "max_concurrent": 4,
      "cooldown_ms": 60,
      "fallback_tone": { "freq": 80.0, "duration": 0.05 }
    }
  }
}
```

`fallback_tone` keeps the current behaviour for any key whose files are missing, so the bank can be filled in one sound at a time. `pitch_jitter` and multiple `variants` are what stop 200 identical hits in a wave fight sounding like a machine. `max_concurrent` and `cooldown_ms` stop a swarm death from stacking eight copies of the same sample into clipping — the single most common cause of a game sounding broken.

```gdscript
## Plays a banked SFX. `surface` selects a surface_variants set when the entry
## declares one. Falls back to the entry's tone, then to the "hit" entry, then
## to silence, warning once per unknown key.
func play_sfx(kind: String, world_pos: Variant = null, surface: String = "") -> void
```

Surface comes from the floor material's palette slot, resolved once per room by the dressing pass. Closes AUD-03.

### 4. Real music layering

Extend the profile schema to describe stems rather than frequencies:

```json
{
  "id": "forgotten_castle",
  "biomeId": "forgotten_castle",
  "reverbPreset": "indoor_castle",
  "crossfadeSeconds": 0.8,
  "layers": {
    "ambience": { "path": "res://assets/audio/forgotten_castle/ambience_loop.ogg", "volume_db": -6.0, "fallback_freq": 110.0 },
    "explore":  { "path": "res://assets/audio/forgotten_castle/explore_loop.ogg",  "volume_db": -9.0, "fallback_freq": 110.0 },
    "combat":   { "path": "res://assets/audio/forgotten_castle/combat_loop.ogg",   "volume_db": -6.0, "fallback_freq": 130.0 },
    "boss":     { "path": "res://assets/audio/forgotten_castle/boss_theme.ogg",    "volume_db": -4.0, "fallback_freq": 196.0 }
  },
  "stingers": {
    "boss_reveal": "res://assets/audio/forgotten_castle/sting_boss.ogg",
    "floor_clear": "res://assets/audio/shared/sting_clear.ogg"
  }
}
```

`ambiencePath`/`bossPath`/`*Freq` remain accepted for one release as a legacy shape, mapped into `layers` by the loader, so nothing breaks while the ten profiles are migrated. Stingers play on a fifth, non-looping `AudioStreamPlayer` on the `Music` bus that ducks the layers by 4 dB for their duration.

Because `explore` and `combat` become distinct stems, the crossfade during a run finally has something to cross. For a profile with no `explore`/`combat` stems the generator fallback gains per-layer branches so the four layers are at least distinguishable, matching what `menu` and `hub` already do. Closes AUD-07, AUD-08.

### 5. Cost

- `_process` only fills a layer when its stream is a generator (already true) **and** `_current_mode != "none"`. Once authored stems land, the common case does no synthesis at all.
- `_prime_tone_burst()` is only reached for keys without files. It also caches one `AudioStreamGenerator` per pool player instead of allocating per call, and pre-bakes each fallback tone into an `AudioStreamWAV` once at `_ready` so the per-shot synthesis loop disappears entirely.
- Pool players get `max_concurrent` and `cooldown_ms` enforcement, which reduces both the sound problem and the cost.

Closes AUD-06.

### 6. Positional ambience

`AudioDirector` gains an emitter helper used by room dressing:

```gdscript
## Attaches a looping positional emitter to `host`. Returns the player so the
## caller can free it with the prop. `radius` sets unit_size; the stream is
## resolved through the SFX bank so a missing file is a no-op, not an error.
func attach_loop_emitter(host: Node3D, key: String, radius: float = 6.0) -> AudioStreamPlayer3D
```

Consumers: braziers, the hub fountain, waterfalls, portals. See [`diorama-room-dressing.md`](diorama-room-dressing.md) and [`portal-ellipse-shader.md`](portal-ellipse-shader.md). Closes AUD-12.

### 7. Decoupling and cleanup

`VfxService` stops calling `AudioDirector` directly; the `sfx` layer kind in the VFX effect data carries the key and the generic dispatcher fires it — see [`vfx-service.md`](vfx-service.md). `waves_run.gd` calls `play_dungeon_ambience()` after `set_biome()`. `combatFreq` falls back to `layers.combat.fallback_freq`, resolved from the profile rather than from live state. `_fill_generator_for_mode()` takes an explicit `layer_id` enum instead of reading `player.name`. `_fill_generator()` and `_ambience_duck_idx` are deleted. `generate-biome-audio.mjs` checks for `ffmpeg` up front with a clear error, uses `node:fs.rmSync` instead of shelling out, and gains a `--check` mode that CI runs to assert every profile has its stems on disk. Closes AUD-05, AUD-09, AUD-10, AUD-11, AUD-13.

## Work plan

1. **Stop the clobber** — `_ensure_layer_streams()`, `_file_backed` tracking, frequency writes moved behind a generator check. Independent, and the prerequisite for every content step. Closes AUD-01.
2. **Waves audio and small fixes** — `waves_run.gd` play call, `combatFreq` fallback, explicit layer id, delete the two dead members. Independent. Closes AUD-05, AUD-09, AUD-10.
3. **Import settings and content report** — `loop=true` on the loop imports, `_report_audio_content()`, `FileAccess`-based validation. Depends on 1 so the report is meaningful. Closes AUD-04.
4. **SFX bank** — `content/schemas/sfx-bank.v1.json`, `content/audio/sfx.json` with the eight existing keys and their `fallback_tone`s transcribed, variant selection, pitch jitter, concurrency and cooldown limits, pre-baked fallback tones. Independent of 5. Closes AUD-03, and the `_prime_tone_burst` half of AUD-06.
5. **Profile v2 with layer stems and stingers** — schema, loader with the legacy shape mapped in, five profiles migrated then all ten, per-layer generator fallback branches. Depends on 1. Closes AUD-07, AUD-08.
6. **Ship stems and samples** — content work: 10 biomes × 4 layers plus stingers, and the SFX bank's variants. Depends on 3, 4, 5.
7. **Positional emitters** — `attach_loop_emitter()`, wired from room dressing and the hub fountain. Depends on 4. Closes AUD-12.
8. **VFX decoupling** — depends on the `sfx` layer kind in [`vfx-service.md`](vfx-service.md). Closes AUD-11.
9. **Tool hardening and validation** — `--check` mode, CI wiring, the new suite. Closes AUD-13, AUD-14.

Step 1 is small and unblocks everything; step 6 is the only step that is not engineering work.

## Data and schema changes

- `content/schemas/audio-profile.v1.json` gains `layers` and `stingers`, keeps `ambiencePath`/`bossPath`/`*Freq` as deprecated, and must drop `additionalProperties: false` or enumerate the new keys.
- New `content/schemas/sfx-bank.v1.json` and `content/audio/sfx.json`.
- Ten `content/audio_profiles/*.json` migrated to `layers`.
- 22 `*.ogg.import` files change `loop` to `true` for `*_loop.ogg`; new `.import` files for the new stems and samples.
- New assets: 40 biome layer stems, roughly 12 stingers, roughly 40 SFX samples, all `.ogg`.
- `apps/game/client/assets/audio/castle/` is deleted (orphaned) or its two `.wav` files are moved to `forgotten_castle/` and referenced.
- No `LocalSave` change — the `audio` meta block keeps its five keys — so no `save_migrator.gd` version bump.
- `scripts/tools/generate-biome-audio.mjs` gains `--check`.

## Acceptance criteria

- [ ] With a stem present at `forgotten_castle/ambience_loop.ogg`, entering a castle run plays that file and not a sine wave; deleting the file falls back to the sine with one log line and no error. (AUD-01, AUD-02)
- [ ] Twenty consecutive hits produce audibly different sounds and never more than `max_concurrent` overlapping. (AUD-03)
- [ ] A biome ambience loop plays continuously for five minutes with no gap. (AUD-04)
- [ ] Starting a waves run plays audio. (AUD-05)
- [ ] With authored stems present in every layer, `_process` performs zero `sin()` evaluations. (AUD-06)
- [ ] Engaging combat in a dungeon produces an audibly different bed than exploring, both with stems and with the generator fallback. (AUD-07)
- [ ] A boss reveal plays a stinger that ducks the music layer. (AUD-08)
- [ ] A profile omitting `combatFreq` produces the same combat fallback frequency regardless of which biome was loaded before it. (AUD-09)
- [ ] Standing next to a brazier plays a crackle that attenuates with distance and stops when the prop is freed. (AUD-12)
- [ ] `node scripts/tools/generate-biome-audio.mjs --check` fails when a stem is missing and CI runs it. (AUD-13)

## Validation

New suite `apps/game/client/scripts/validation/suites/audio_suite.gd`, category `content`, replacing the method-name checks in `content_suite.gd:126-148`:

| Test id | Assertion |
|---------|-----------|
| `audio.profiles_load` | all ten profiles parse and validate against `audio-profile.v1.json` |
| `audio.profile_biome_coverage` | every `BiomeRegistry.ALL_BIOMES` id has a profile whose `biomeId` matches its filename |
| `audio.layer_stems_on_disk` | every `layers.*.path` passes `FileAccess.file_exists()` — not `ResourceLoader.exists()`, which the `.import` remap satisfies with the source absent |
| `audio.loop_imports_loop` | every `.import` sidecar for a file named `*_loop.ogg` contains `loop=true` |
| `audio.reverb_presets_valid` | every `reverbPreset` is one of the eight `REVERB_PRESETS` keys, and the schema enum matches the constant exactly |
| `audio.no_orphan_folders` | every folder under `assets/audio/` other than `shared/` is referenced by some profile |
| `audio.file_stream_survives_mode_change` | load a stem into `_ambience`, call `play_dungeon_ambience()`, and assert the stream is still the file stream and not an `AudioStreamGenerator` |
| `audio.generator_fallback_installs` | with `_ambience.stream = null`, `play_dungeon_ambience()` installs a generator and the layer plays |
| `audio.fallback_freqs_from_profile` | a profile omitting `layers.combat.fallback_freq` yields the documented default, independent of the previously loaded biome |
| `audio.sfx_bank_loads` | `content/audio/sfx.json` parses and validates against `sfx-bank.v1.json` |
| `audio.sfx_keys_complete` | all eight legacy keys plus every key referenced from VFX effect data exist in the bank |
| `audio.sfx_variants_on_disk` | every declared variant path passes `FileAccess.file_exists()`, or the entry declares a `fallback_tone` |
| `audio.sfx_unknown_key_safe` | `play_sfx("nope")` warns once, plays the `hit` entry, and does not warn on a second call |
| `audio.sfx_concurrency_capped` | 20 `play_sfx("hit")` calls in one frame leave at most `max_concurrent` players playing |
| `audio.sfx_cooldown_respected` | two `play_sfx("footstep")` calls 10 ms apart start one sound |
| `audio.sfx_variant_rotation` | 12 `play_sfx("hit")` calls use every declared variant at least once |
| `audio.buses_present` | `Master`, `Music`, `SFX`, `Ambience`, `UI` all resolve, and every `bus` in the SFX bank is one of them |
| `audio.bus_effects_idempotent` | calling `_setup_bus_effects()` twice adds no second reverb or compressor |
| `audio.volume_roundtrip` | setting `sfx_volume = 0.5`, saving, reloading, and applying restores the same bus dB within 0.01 |
| `audio.mute_is_silent` | `master_volume = 0.0` yields −80 dB on `Master` |
| `audio.stinger_ducks` | playing a stinger lowers the `Music` layer volume by the documented amount and restores it |
| `audio.emitter_frees_with_host` | `attach_loop_emitter()` on a node that is then freed leaves no orphaned player |
| `audio.no_process_synthesis_with_stems` | with all four layers file-backed, `_process` returns without calling `_fill_generator_for_mode()` |

Manual checklist:

- Play a full castle floor: ambience, explore, combat, and boss must each be identifiable, and every transition must be a crossfade rather than a cut.
- Kill a swarm of eight enemies at once: the result must not clip or sound like one sound played eight times.
- Delete one biome's stems and replay that biome: audible fallback, one log line, no error spam.

## Related
- Existing behaviour: [`../existing_codebase/audio-director.md`](../existing_codebase/audio-director.md)
- [`vfx-service.md`](vfx-service.md) — the `sfx` layer kind that decouples combat audio from the VFX layer
- [`biome-registry.md`](biome-registry.md) — resolves the profile path and calls `set_biome()`
- [`castle-run.md`](castle-run.md) — the clobber ordering; [`waves-run.md`](waves-run.md) — the missing `play_*` call
- [`bosses.md`](bosses.md) — stinger and boss-layer consumers
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — positional emitters on braziers and props
- [`portal-ellipse-shader.md`](portal-ellipse-shader.md) — the portal hum and enter sound
- [`ui/settings.md`](ui/settings.md) — the five volume sliders; [`accessibility.md`](accessibility.md) — audio-only cue considerations
- [`local-save.md`](local-save.md) — the `audio` meta block
- [`content-data.md`](content-data.md), [`content-catalog.md`](content-catalog.md) — the profile and bank schemas
- [`tools-scripts.md`](tools-scripts.md) — `generate-biome-audio.mjs` and its `--check` mode
- [`ci-cd.md`](ci-cd.md) — where the stem check runs

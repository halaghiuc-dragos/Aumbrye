# Character appearance

`CharacterAppearance` is a 102-line static `RefCounted` helper that defines the appearance profile shape, sanitises it, and converts between the save document and `CharacterService`. It is the only appearance schema in the game: five keys, chosen once at character creation, consumed by one function in the diorama skin builder.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/save/character_appearance.gd` | `CharacterAppearance` — presets, labels, `default_profile`, `profile_from_indices`, `sanitize`, `apply_to_service`, `from_character_dict`, `from_service`, `theme_from_service` |
| `apps/game/client/scripts/art/characters/diorama_character_skin.gd` | `build_player_body` reads the profile; `_apply_player_appearance` is the only consumer |
| `apps/game/client/scripts/ui/character_create_ui.gd` | Only producer; builds a profile from five `OptionButton` indices (see [`ui/character_create.md`](ui/character_create.md)) |
| `apps/game/client/scripts/save/character_service.gd` | Holds `appearance_theme` and `appearance_profile` at runtime |
| `apps/game/client/scripts/save/local_save.gd` | Persists it to `character.appearanceTheme` and `character.appearance` |
| `apps/game/client/scripts/player/locomotion.gd` | Rebuilds the body via `build_player_body` / `refresh_appearance_visual` |
| `apps/game/client/scripts/art/style/pixel_diorama_style.gd` | `PaletteTheme` enum and the `PALETTES` table the `theme` value indexes |

## How it works

### Profile shape
`default_profile()` (lines 23-30) defines every key:

| Key | Type | Default | Allowed values |
|-----|------|---------|----------------|
| `theme` | int | `PixelStyle.PaletteTheme.CASTLE` (0) | Not constrained by `sanitize` (see gaps) |
| `height` | float | `1.0` | Clamped to `0.82 .. 1.18` (line 63); presets `[0.9, 1.0, 1.1]` |
| `bulk` | float | `1.0` | Clamped to `0.82 .. 1.22` (line 64); presets `[0.88, 1.0, 1.14]` |
| `head` | String | `HEAD_VISOR` = `"visor"` | `"open"`, `"visor"`, `"hood"` (lines 8-10, 66) |
| `trim` | int | `1` | Clamped to `0 .. 2` (line 68) |

Label arrays for the creation UI: `HEIGHT_LABELS` = Compact / Standard / Tall, `BULK_LABELS` = Lean / Standard / Heavy, `HEAD_LABELS` = Open face / Visor helm / Hooded, `TRIM_LABELS` = Plain / Trimmed / Pauldrons (lines 13-20).

### Construction and sanitising
`profile_from_indices(theme, height_idx, bulk_idx, head_idx, trim_idx)` (lines 33-46) maps UI indices to preset values, clamping each index into range and routing `head_idx` through `_head_from_index` (lines 49-56), which maps 0 -> open, 1 -> visor, anything else -> hood.

`sanitize(profile)` (lines 59-69) starts from `default_profile()` and overwrites each key from the input. `theme` is only copied when the key is present, and is passed through `int()` with **no range clamp**. The other four are clamped.

### Conversions
| Function | Lines | Behaviour | Callers |
|----------|-------|-----------|---------|
| `apply_to_service(profile)` | 72-77 | Sanitises, writes `CharacterService.appearance_theme` and `.appearance_profile` | None found in `apps/`, `scripts/`, or `tools/` |
| `from_character_dict(character)` | 80-91 | Reads `appearanceTheme` with a fallback to the nested `appearance.theme`, then the four nested keys, then sanitises | `local_save.gd:132` only |
| `from_service()` | 94-97 | `sanitize(CharacterService.appearance_profile)` | `diorama_character_skin.gd:95` only |
| `theme_from_service()` | 100-101 | `int(from_service().theme)` | None found |

### Where the profile comes from
Exactly one path writes a profile in normal play:

1. `character_create_ui.gd:197` emits `completed(class_id, name, _build_appearance_profile())`.
2. `LocalSave.queue_boot_new_game(class_id, name, appearance)` sanitises it into `_pending_new_game` (`local_save.gd:167-173`).
3. `_apply_new_game_boot` re-sanitises and calls `set_appearance_profile` (`local_save.gd:227-231`).
4. `LocalSave.set_appearance_profile` writes `character.appearanceTheme` and `character.appearance`, mirrors both onto `CharacterService`, and autosaves (`local_save.gd:117-128`).

On load, `local_save.gd:546-547` feeds `character.appearanceTheme` and `character.appearance` into `CharacterService.from_save_dict`, which sanitises again (`character_service.gd:150-154`). On save, `local_save.gd:572-573` reads the service fields back out.

There is no post-creation appearance editor: `LocalSave.set_appearance_theme` (line 113) and `LocalSave.get_appearance_profile` / `get_appearance_theme` (lines 131-136) have no callers anywhere in the repository.

### How the skin consumes it
`build_player_body(facing, theme = -1)` (`diorama_character_skin.gd:89-98`):
1. Removes the previous visual and hides legacy meshes.
2. Resolves `theme` from `CharacterService.appearance_theme` when the argument is negative, falling back to `PaletteTheme.HUB`.
3. Reads the profile with `CharacterAppearance.from_service()` — the profile's own `theme` is fetched but never used, because materials come from the `theme` argument.
4. Builds the base humanoid from `PROFILES["player"]`, then calls `_apply_player_appearance`.

`_apply_player_appearance(visual, profile, mats)` (lines 101-151) is the entire visual effect of the appearance system:

| Profile key | Effect | Lines |
|-------------|--------|-------|
| `height`, `bulk` | `root.scale = Vector3(bulk, height, bulk)` on the part named `ROOT_NAME` | 105-107 |
| `head == "visor"` | Shows the existing `Head/Mesh/Visor` node | 111-113 |
| `head == "hood"` | Shows the existing `Head/Hood` node, or builds one with `PixelStyle.add_box` sized from `PROFILES["player"].head` when absent | 114-126 |
| `head == "open"` | Both visor and hood hidden | 111-116 |
| `trim >= 1` | Adds a `BeltTrim` box on `Torso` in the accent material | 127-139 |
| `trim >= 2` | Adds a `Pauldron` box on `ArmL` and `ArmR` in the accent material | 140-151 |

`theme` is not read by `_apply_player_appearance` at all.

### Rebuild triggers
`build_player_body` is called from `locomotion.gd:39` (`_ready`, via `facing_path`), `locomotion.gd:54` (`refresh_appearance_visual`), and `diorama_character_rig_player.gd:16` (passing `PaletteTheme.CASTLE` explicitly). `refresh_appearance_visual` is reached only through `PlayerControls.sync_player_loadout` (`player_controls.gd:75-77`), which returns early for waves mode (`player_controls.gd:70-71`) and is itself called from `player_controls.gd:56` and `combat_arena.gd:42`.

## Contracts
**Save keys:** `character.appearanceTheme` (int), `character.appearance` (Dictionary of the five keys above).

**Runtime holders:** `CharacterService.appearance_theme`, `CharacterService.appearance_profile`.

**Node names the skin depends on:** `ROOT_NAME` (from `diorama_character_skin.gd`), `Head`, `Head/Mesh/Visor`, `Head/Hood`, `Torso`, `ArmL`, `ArmR`. A rename in the humanoid builder silently disables the corresponding appearance feature.

**Material keys required from `_body_materials`:** `body`, `accent`.

**Enum dependency:** `theme` is an index into `PixelStyle.PALETTES` (`pixel_diorama_style.gd:75`), whose valid range is `0 .. 10` per the `PaletteTheme` enum (lines 25-37).

**Signals:** none. `CharacterAppearance` has no signals and appearance changes emit nothing.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Five-key profile with clamped ranges | IMPLEMENTED | `character_appearance.gd:59-69` |
| Index-to-preset construction from the creation UI | IMPLEMENTED | `character_appearance.gd:33-46`, `character_create_ui.gd:176-183` |
| Save round-trip of all five keys | IMPLEMENTED | `local_save.gd:572-573` write, `local_save.gd:546-547` read, `character_service.gd:150-154` sanitise |
| Height and bulk applied to the visual | IMPLEMENTED | `diorama_character_skin.gd:105-107` |
| Head style (open / visor / hood) | IMPLEMENTED | `diorama_character_skin.gd:108-126` |
| Trim tiers (belt, pauldrons) | IMPLEMENTED | `diorama_character_skin.gd:127-151` |
| `theme` range validation | BROKEN | `sanitize` does not clamp `theme` (`character_appearance.gd:61-62`); `PixelStyle.get_palette` indexes `PALETTES[theme]` with no bounds check (`pixel_diorama_style.gd:224-232`), so a save with `appearanceTheme: 42` raises an index error when the body is built |
| `theme` effect on the player body | PARTIAL | `build_player_body` takes materials from its own `theme` argument, not from the profile (`diorama_character_skin.gd:93-97`); `diorama_character_rig_player.gd:16` hardcodes `PaletteTheme.CASTLE`, so that rig ignores the saved theme entirely |
| `apply_to_service(profile)` | FAKE | Defined at `character_appearance.gd:72-77`, zero callers |
| `theme_from_service()` | FAKE | Defined at `character_appearance.gd:100-101`, zero callers |
| `LocalSave.set_appearance_theme` | FAKE | `local_save.gd:113-114`, zero callers |
| `LocalSave.get_appearance_profile` / `get_appearance_theme` | FAKE | `local_save.gd:131-136`, zero callers; `from_character_dict` exists only to serve the first of these |
| Post-creation appearance editing | ABSENT | No UI writes a profile after `_apply_new_game_boot`; searched `apps/game/client/scripts/ui/` for `set_appearance_profile` and `apply_to_service` |
| Creation-screen preview of height / bulk / head / trim | FAKE | `character_create_ui.gd:159-162` updates only a `ColorRect` accent swatch; the silhouette is built once with fixed parameters at `character_create_ui.gd:63` and never re-driven by the selections |
| Appearance effect on collision, hurtbox, or camera height | ABSENT | `profile.height` and `profile.bulk` are read only at `diorama_character_skin.gd:105-107`; no collider, hurtbox, or camera pivot is rescaled, so a `Tall` warden's visual head sits above its hurtbox |
| Appearance refresh in waves mode | BROKEN | `player_controls.gd:70-71` returns before `refresh_appearance_visual` for waves runs |
| Colour or palette customisation beyond the five themes | ABSENT | `APPEARANCE_OPTIONS` offers five of the eleven `PaletteTheme` rows (`character_create_ui.gd:13-19`); no per-slot colour picking exists |
| JSON schema for the appearance profile | ABSENT | `content/schemas/character-state.v1.json` declares `character` without an `appearance` sub-object; searched all of `content/schemas/` |

## Related
- Improvement plan: [`../actual_improvements/character-appearance.md`](../actual_improvements/character-appearance.md)
- [`character-service.md`](character-service.md), [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`pixel-style.md`](pixel-style.md), [`ui/character_create.md`](ui/character_create.md), [`locomotion.md`](locomotion.md)

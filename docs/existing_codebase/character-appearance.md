# Character appearance

`CharacterAppearance` is a static `RefCounted` helper that defines the warden appearance profile, sanitises it, describes it for UI, and converts between the save document and `CharacterService`. The profile drives palette theme, stature archetype, build offsets, skin tone, hair, face accent, head style, and trim tier. `DioramaCharacterSkin` is the sole visual consumer; `character_create_ui.gd` is the producer at creation and through the hub mirror.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/save/character_appearance.gd` | `CharacterAppearance` — variants, labels, `sanitize`, `is_valid`, `describe`, `apply_to_service`, `from_character_dict`, `from_service`, `available_theme_options` |
| `apps/game/client/scripts/art/characters/diorama_character_skin.gd` | `build_player_body`, `build_preview_body`, `_apply_player_appearance`, `_require_part` |
| `apps/game/client/scripts/art/characters/character_rig_catalog.gd` | Maps `heightVariant` to `player_warden` / `player_warden_compact` / `player_warden_tall` manifests |
| `apps/game/client/scripts/ui/character_create_ui.gd` | Creation UI and mirror edit mode; SubViewport 3D preview via `build_preview_body` |
| `apps/game/client/scripts/hub/hub.gd` | `appearance_mirror` interact handler; hosts mirror UI |
| `apps/game/client/scenes/hub/hub.tscn` | `Mirror` landmark with `interact_id = appearance_mirror` |
| `apps/game/client/scripts/save/character_service.gd` | `appearance_theme`, `appearance_profile`, `appearance_changed` signal |
| `apps/game/client/scripts/save/local_save.gd` | `set_appearance_profile`, `get_appearance_profile`; persists `character.appearance` and `character.appearanceTheme` |
| `apps/game/client/scripts/player/locomotion.gd` | Subscribes to `appearance_changed`; `refresh_appearance_visual` rebuilds the body |
| `apps/game/client/scripts/art/style/pixel_diorama_style.gd` | `PaletteTheme`, `PALETTES`, defensive `get_palette` / `get_palette_color` clamps |
| `content/schemas/character-state.v2.json` | `appearanceProfile` sub-schema under `$defs` |
| `content/fixtures/character_state_sample.v2.json` | Fixture with a valid `appearance` block |

## How it works

### Profile shape
`default_profile()` defines every key:

| Key | Type | Default | Allowed values |
|-----|------|---------|----------------|
| `profileVersion` | int | `1` | `PROFILE_VERSION` const |
| `theme` | int | `PaletteTheme.CASTLE` (0) | Clamped `0 .. PALETTES.size() - 1` |
| `heightVariant` | String | `"standard"` | `"compact"`, `"standard"`, `"tall"` |
| `bulkVariant` | String | `"standard"` | `"lean"`, `"standard"`, `"heavy"` |
| `skinTone` | String | `"neutral"` | `"warm"`, `"neutral"`, `"cool"` |
| `hair` | String | `"none"` | `"none"`, `"short"`, `"long"` |
| `face` | String | `"open"` | `"open"`, `"stern"`, `"kind"` |
| `head` | String | `"visor"` | `"open"`, `"visor"`, `"hood"` |
| `trim` | int | `1` | `0 .. 2` |

Legacy float keys `height` and `bulk` are accepted by `sanitize` and mapped into `heightVariant` / `bulkVariant` via `height_variant_from_legacy` and `bulk_variant_from_legacy`. `HEIGHT_MIN` / `HEIGHT_MAX` and `BULK_MIN` / `BULK_MAX` bound those legacy floats during migration.

Label arrays for the creation UI: `HEIGHT_LABELS`, `BULK_LABELS`, `SKIN_TONE_LABELS`, `HAIR_LABELS`, `FACE_LABELS`, `HEAD_LABELS`, `TRIM_LABELS`.

### Construction and sanitising
`profile_from_indices(theme, height_idx, bulk_idx, head_idx, trim_idx, skin_idx, hair_idx, face_idx)` maps UI indices to profile values.

`sanitize(profile)` repairs any input: clamps `theme`, normalises variants and enums, stamps `profileVersion`. Unknown types log one `push_warning` and yield the default profile.

`is_valid(profile)` is strict (no repair) for save writes and validation suites.

`describe(profile)` returns a one-line summary, e.g. `Tall / Heavy / Hooded / Pauldrons / Castle iron`.

`available_theme_options()` returns `THEME_OPTIONS` entries that are always available or unlocked via `DungeonCatalog.get_clear_flag` and `CharacterService.has_flag`.

### Conversions and service mirroring
| Function | Behaviour | Callers |
|----------|-----------|---------|
| `apply_to_service(profile)` | Sanitises, writes `CharacterService.appearance_theme` and `.appearance_profile`, emits `appearance_changed` | `LocalSave.set_appearance_profile` |
| `from_character_dict(character)` | Merges `appearanceTheme` and nested `appearance`, then sanitises | `LocalSave.get_appearance_profile`, save load |
| `from_service()` | `sanitize(CharacterService.appearance_profile)` | `DioramaCharacterSkin.build_player_body` |

`set_appearance_theme`, `theme_from_service`, and `get_appearance_theme` were removed; theme is edited only through the full profile.

### Where the profile comes from
**Creation:** `character_create_ui.gd` emits `completed` with `_build_appearance_profile()` → `LocalSave.queue_boot_new_game` → `_apply_new_game_boot` → `set_appearance_profile`.

**Mirror:** Hub `Mirror` interactable (`interact_id = appearance_mirror`) opens `character_create_ui.open_edit_mode()` (class and name hidden). Confirm calls `LocalSave.set_appearance_profile`; success emits `appearance_saved` and hub message.

**Load:** `local_save` reads `character.appearanceTheme` and `character.appearance` into `CharacterService.from_save_dict`.

**Save:** `local_save` writes both keys from `CharacterService` fields; `appearanceTheme` mirrors `appearance.theme`.

### Preview and in-game body
`build_preview_body(parent, profile)` clears `parent`, builds the same manifest/box body as gameplay, and runs `_apply_player_appearance` against the explicit profile (not `from_service()`).

`character_create_ui` hosts the preview in a `SubViewportContainer` with camera, light, and slow turntable rotation. `_on_appearance_selected` calls `_rebuild_preview()`.

`build_player_body(facing, theme = -1)` reads the profile from service; when `theme < 0`, uses `profile.theme`. `diorama_character_rig_player.gd` passes `-1` so the saved theme applies in-editor.

### How the skin applies the profile
`_apply_player_appearance` uses named-part constants and `_require_part` (warns once per missing part):

| Profile key | Effect |
|-------------|--------|
| `heightVariant` | `CharacterRigCatalog.archetype_for_player` selects compact / standard / tall manifest |
| `bulkVariant` | `_apply_bulk_joint_offsets` shifts leg and arm pivot X by ±`VoxelGrid.EDGE` for lean / heavy |
| `skinTone` | `skin_tint` shader parameter on head mesh |
| `hair` | Voxel hair mesh from `assets/characters/player_warden/hair_{style}.voxels.json` |
| `face` | Stern or kind accent boxes on head |
| `head` | Visor visibility, hood visibility or procedural hood box |
| `trim` | `BeltTrim` on torso (trim ≥ 1), `Pauldron` boxes on arms (trim ≥ 2) |

Root scale stays `Vector3.ONE`; collider and hurtbox are unchanged. Stature is expressed through archetype manifests, not scale.

`CharacterService.class_id` still drives `_apply_class_armor` on the torso during preview and in-game builds.

### Rebuild triggers
- `locomotion._ready` → `build_player_body`
- `CharacterService.appearance_changed` → `locomotion.refresh_appearance_visual` (hub mirror, creation boot, any `apply_to_service` path)
- `player_controls.sync_player_loadout` → `refresh_appearance_visual` for non-waves modes only; waves rely on the signal subscription because `sync_player_loadout` returns early in waves mode

## Contracts
**Save keys:** `character.appearanceTheme` (int), `character.appearance` (full profile per `appearanceProfile` schema).

**Runtime:** `CharacterService.appearance_theme`, `CharacterService.appearance_profile`, signal `appearance_changed(profile)`.

**Node names:** `Root`, `Head`, `Head/Mesh/Visor`, `Head/Hood`, `Torso`, `ArmL`, `ArmR` — missing nodes log via `_require_part` and skip that feature.

**Save version:** Appearance profile clamping and variant migration run in `SaveMigrator._migrate_v4_to_v5` when bumping to schema v5.

## Current state
| Surface | Status |
|---------|--------|
| Profile with clamped theme and variants | IMPLEMENTED |
| `is_valid`, `describe`, `PROFILE_VERSION` | IMPLEMENTED |
| 3D creation preview via `build_preview_body` | IMPLEMENTED |
| Hub mirror post-creation editing | IMPLEMENTED |
| Stature via archetype manifests (not collider scale) | IMPLEMENTED |
| Build via joint offsets (not root scale) | IMPLEMENTED |
| Theme from profile in `build_player_body` | IMPLEMENTED |
| `appearance_changed` + locomotion subscription | IMPLEMENTED |
| Waves runs use saved profile (signal path) | IMPLEMENTED |
| `appearanceProfile` JSON schema + fixture | IMPLEMENTED |
| Gated theme roster via dungeon clear flags | IMPLEMENTED |
| `_require_part` warnings on rename | IMPLEMENTED |
| Validation suites (`save_suite`, `hub_m4_suite`, `content_suite`) | IMPLEMENTED |

## Related
- Improvement plan: [`../actual_improvements/character-appearance.md`](../actual_improvements/character-appearance.md)
- [`character-service.md`](character-service.md), [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md), [`hub.md`](hub.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`pixel-style.md`](pixel-style.md), [`ui/character_create.md`](ui/character_create.md), [`locomotion.md`](locomotion.md)

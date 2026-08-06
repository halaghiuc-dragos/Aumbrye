# Character appearance — improvement plan

## Status: FINISHED

## Current state
`CharacterAppearance` defines a versioned profile — `theme`, `heightVariant`, `bulkVariant`, `skinTone`, `hair`, `face`, `head`, `trim` — sanitises every key, and round-trips through `character.appearanceTheme` / `character.appearance`. See [`../existing_codebase/character-appearance.md`](../existing_codebase/character-appearance.md). Creation and the hub mirror preview and apply the real diorama body via `build_preview_body` / `build_player_body`. Post-creation editing uses the hub `Mirror` interactable. Stature uses compact/standard/tall manifests; build uses joint offsets inside the fixed collider. `appearance_changed` refreshes the body in hub and waves without relying on `sync_player_loadout`.

## Gaps
| ID | Sev | Gap | Evidence | Status |
|----|-----|-----|----------|--------|
| CHA-01 | P0 | `sanitize` does not clamp `theme`; `PixelStyle.get_palette` indexes `PALETTES[theme]` unchecked | `character_appearance.gd`, `pixel_diorama_style.gd` | FINISHED |
| CHA-02 | P0 | Creation screen previews only accent colour; stature, build, head, trim invisible before commit | `character_create_ui.gd` | FINISHED |
| CHA-03 | P1 | Appearance cannot be changed after creation | `local_save.gd`, hub mirror | FINISHED |
| CHA-04 | P1 | `height` and `bulk` scale only the visual; collider unchanged | `diorama_character_skin.gd`, `character_rig_catalog.gd` | FINISHED |
| CHA-05 | P1 | `build_player_body` ignores profile theme; player rig hardcodes `CASTLE` | `diorama_character_skin.gd`, `diorama_character_rig_player.gd` | FINISHED |
| CHA-06 | P1 | Waves runs never refresh appearance because `sync_player_loadout` returns early | `player_controls.gd`, `locomotion.gd` | FINISHED |
| CHA-07 | P2 | No JSON schema for appearance profile | `character-state.v2.json`, fixture | FINISHED |
| CHA-08 | P2 | Five of eleven themes offered with no unlock path | `character_create_ui.gd`, `available_theme_options` | FINISHED |
| CHA-09 | P2 | Dead functions: `apply_to_service`, `theme_from_service`, `set_appearance_theme`, etc. | grep | FINISHED |
| CHA-10 | P2 | Skin depends on node names with silent no-ops on rename | `diorama_character_skin.gd` `_require_part` | FINISHED |

## Target design

### A validated, self-describing profile
`theme` joins the other keys as a clamped value, and the profile gains an explicit version so future keys can be added without guessing:

```gdscript
const PROFILE_VERSION := 1
const THEME_MIN := 0
const THEME_MAX := 10   ## PixelStyle.PaletteTheme.HUB

static func sanitize(profile: Dictionary) -> Dictionary   ## now clamps theme and stamps version
static func is_valid(profile: Dictionary) -> bool         ## strict check, no repair; for validation suites
static func describe(profile: Dictionary) -> String       ## "Tall / Heavy / Hooded / Pauldrons / Castle iron"
```

`THEME_MAX` is derived, not literal: `PixelStyle.PaletteTheme.size() - 1` where available, otherwise `PALETTES.size() - 1`, so adding a palette row cannot leave the clamp behind. `PixelStyle.get_palette` and `get_palette_color` additionally clamp their argument and push a warning, because a crash in a static art helper is the worst possible failure mode for a bad save.

`describe()` gives the character-select roster and the results screen a one-line summary without every caller re-deriving labels from indices.

### Real preview at creation
The creation screen builds the same body the game builds. `DioramaCharacterSkin` gains a profile-driven entry point so nothing has to be duplicated:

```gdscript
## diorama_character_skin.gd
static func build_player_body(facing: Node3D, theme: int = -1) -> Node3D   ## unchanged signature
static func build_preview_body(parent: Node3D, profile: Dictionary) -> Node3D
```

`build_preview_body` runs the same `_build_humanoid` + `_apply_player_appearance` pair against an explicit profile rather than `CharacterAppearance.from_service()`, so the preview cannot drift from the in-game result. The creation screen hosts it in a `SubViewportContainer` with a fixed camera and a slow idle turntable, replacing the static silhouette at `character_create_ui.gd:63`. `_on_appearance_selected` rebuilds the preview from `_build_appearance_profile()` instead of recolouring a swatch. The UI work lives in [`ui/character_create.md`](ui/character_create.md); this plan owns the `build_preview_body` contract it depends on.

Chosen over rendering the silhouette with parameters derived from the profile: a 2D approximation is a second implementation of the appearance rules and will disagree with the 3D body eventually. Rendering the real body is the only preview that stays honest.

### Post-creation editing through the mirror
Appearance becomes editable in the hub. The profile is cosmetic, so there is no balance reason to lock it, and a permanent choice made behind a fake preview is the worst version of both:

```gdscript
## LocalSave
func set_appearance_profile(profile: Dictionary) -> bool   ## returns false and warns on an invalid profile
func get_appearance_profile() -> Dictionary                ## already exists, gains its first caller

## CharacterService
signal appearance_changed(profile: Dictionary)
```

`LocalSave.set_appearance_profile` emits `CharacterService.appearance_changed` after mirroring the sanitised profile onto the service. `Locomotion` subscribes and calls `refresh_appearance_visual()`, which removes the dependency on `sync_player_loadout` and therefore fixes waves mode at the same time. `apply_to_service` becomes the single mirroring implementation that `LocalSave.set_appearance_profile` calls, so it stops being dead code rather than being deleted. `set_appearance_theme` and `theme_from_service` are deleted; `theme` is never edited independently of the profile.

The hub interactable is a `HubInteractable` named `Mirror` with `interaction_id = "appearance_mirror"`, opening the same control the creation screen uses in an edit mode that omits class and name. See [`hub.md`](hub.md) for the placement and [`npc-hub-services.md`](npc-hub-services.md) for the interactable contract.

### Height and bulk affect the body, not just the paint
`height` scaling the visual while the collider stays fixed is a correctness problem, not a cosmetic one: it decides whether a projectile aimed at a visible head connects. Two options, and the cheap one is wrong:

- Scale the collider with the visual. Rejected: it makes Compact a hitbox advantage and Tall a disadvantage, turning a cosmetic slider into a balance decision.
- Keep the collider fixed and constrain the visual to it. Chosen: stature uses compact/standard/tall manifests; build uses joint offsets within the capsule instead of root scale.

```gdscript
## character_appearance.gd — variants instead of float scale
const HEIGHT_VARIANTS := ["compact", "standard", "tall"]
const BULK_VARIANTS := ["lean", "standard", "heavy"]

## diorama_character_skin.gd — _apply_bulk_joint_offsets shifts arm/leg pivots
## character_rig_catalog.gd — archetype_for_player selects manifest by heightVariant
```

Legacy `height` / `bulk` floats migrate into variants in `_migrate_v4_to_v5`. `character-floor-snap` owns the floor-plane contract; see [`character-floor-snap.md`](character-floor-snap.md).

### Theme applied consistently
`build_player_body` reads the theme from the profile when its argument is negative instead of from `CharacterService.appearance_theme` directly, so there is one source:

```gdscript
static func build_player_body(facing: Node3D, theme: int = -1) -> Node3D:
    var profile := CharacterAppearance.from_service()
    if theme < 0:
        theme = int(profile.get("theme", PixelStyle.PaletteTheme.CASTLE))
    ...
```

`diorama_character_rig_player.gd:16` drops its hardcoded `PaletteTheme.CASTLE` and passes `-1`.

### Named part contract
The six node names the skin reaches for become constants with a single lookup helper that warns once per missing part, so a rename produces a log line instead of a silently missing pauldron:

```gdscript
const PART_ROOT := ROOT_NAME
const PART_HEAD := "Head"
const PART_VISOR := "Mesh/Visor"
const PART_HOOD := "Hood"
const PART_TORSO := "Torso"
const PART_ARM_L := "ArmL"
const PART_ARM_R := "ArmR"

static func _require_part(visual: Node3D, path: String) -> Node3D   ## push_warning when absent
```

## Work plan

1. **Clamp `theme` in `sanitize`, derive `THEME_MAX` from the palette table, add `PROFILE_VERSION`, `is_valid`, `describe`** — `character_appearance.gd`. Add defensive clamps plus a warning to `PixelStyle.get_palette` and `get_palette_color`. Closes CHA-01. **DONE**
2. **Replace float height/bulk scale with variants and joint offsets / archetype manifests** — `character_appearance.gd`, `diorama_character_skin.gd`, `character_rig_catalog.gd`. Closes CHA-04. **DONE**
3. **Add `build_preview_body(parent, profile)` and route `_apply_player_appearance` through the named-part constants and `_require_part`** — `diorama_character_skin.gd`. Closes CHA-10, unblocks CHA-02. **DONE**
4. **Read the theme from the profile in `build_player_body`; drop the hardcoded theme in the player rig** — `diorama_character_skin.gd`, `diorama_character_rig_player.gd`. Closes CHA-05. **DONE**
5. **Add `CharacterService.appearance_changed`, make `LocalSave.set_appearance_profile` return `bool` and emit it through `CharacterAppearance.apply_to_service`, subscribe `Locomotion`** — Closes CHA-06, CHA-09 in part. **DONE**
6. **Delete `set_appearance_theme` and `theme_from_service`; give `get_appearance_profile` its caller in the mirror UI** — Closes CHA-03, CHA-09. **DONE**
7. **Add the `appearance` sub-schema and its fixture** — `content/schemas/character-state.v2.json`, `content/fixtures/character_state_sample.v2.json`. Closes CHA-07. **DONE**
8. **Gate extra palette themes behind `DungeonCatalog.get_clear_flag` unlocks** — `available_theme_options`. Closes CHA-08. **DONE**

## Data and schema changes

**Save version bump: `save_migrator.gd` `CURRENT_VERSION` 4 -> 5** — the same shared bump described in [`save-migrator.md`](save-migrator.md). The appearance-owned part of `_migrate_v4_to_v5`:

```gdscript
## character.appearance: clamp into variants, clamp theme, stamp the profile version
var character: Dictionary = copy.get("character", {})
var profile: Variant = character.get("appearance", {})
character["appearance"] = CharacterAppearance.sanitize(
    profile if profile is Dictionary else {"theme": character.get("appearanceTheme", 0)}
)
character["appearanceTheme"] = int(character["appearance"]["theme"])
copy["character"] = character
```

Because `sanitize` now clamps `theme` and maps legacy floats to variants, this step repairs every out-of-range profile in existing saves. `appearanceTheme` becomes a derived mirror of `appearance.theme` rather than an independent value; it stays in the payload because roster summaries read it without loading the nested profile.

**Schema: the `appearanceProfile` object inside `content/schemas/character-state.v2.json`**:

```json
"appearanceProfile": {
  "type": "object",
  "additionalProperties": false,
  "required": ["profileVersion", "theme", "heightVariant", "bulkVariant", "skinTone", "hair", "face", "head", "trim"],
  "properties": {
    "profileVersion": { "const": 1 },
    "theme": { "type": "integer", "minimum": 0, "maximum": 10 },
    "heightVariant": { "enum": ["compact", "standard", "tall"] },
    "bulkVariant": { "enum": ["lean", "standard", "heavy"] },
    "skinTone": { "enum": ["warm", "neutral", "cool"] },
    "hair": { "enum": ["none", "short", "long"] },
    "face": { "enum": ["open", "stern", "kind"] },
    "head": { "enum": ["open", "visor", "hood"] },
    "trim": { "type": "integer", "minimum": 0, "maximum": 2 }
  }
}
```

`content/fixtures/character_state_sample.v2.json` carries a matching `appearance` block, and `scripts/validate-content/validate.mjs` maps the fixture to the v2 schema so a drift between the GDScript clamps and the JSON bounds fails the content check rather than a playtest.

**Failure and recovery behaviour:**

| Situation | Behaviour |
|-----------|-----------|
| `character.appearance` missing | `sanitize({})` yields the default profile; `from_character_dict` falls back to `appearanceTheme`; no error |
| `character.appearance` is not a Dictionary | Replaced with the default profile, one `push_warning` naming the observed type |
| `theme` out of `0..10` | Clamped by `sanitize`, one `push_warning`; `PixelStyle.get_palette` clamps again as a second line of defence |
| `head` is an unknown String | Falls back to `HEAD_VISOR`, unchanged |
| A required visual part is missing (renamed mesh) | `_require_part` returns null and warns once; the body still builds without that feature |
| `set_appearance_profile` receives an invalid profile from the mirror UI | Returns `false`, the profile is not written, no autosave, the UI keeps the previous selection |
| `PALETTES` gains a row | `THEME_MAX` is derived, so the clamp and the schema bound both need one update; `content.appearance.theme_bound_matches_palettes` catches a missed schema edit |

## Acceptance criteria
- [x] A save with `character.appearanceTheme: 42` loads, is clamped to a valid theme, logs one warning, and builds the player body without an error. (CHA-01)
- [x] Changing Stature, Build, Head, or Trim on the creation screen visibly changes a live 3D preview that matches the body spawned in the hub. (CHA-02)
- [x] The hub mirror changes an existing character's appearance, the change is visible without a scene reload, and it survives a save and reload. (CHA-03)
- [x] Tall and Compact wardens use distinct archetype manifests with the collider unchanged and feet on the floor plane. (CHA-04)
- [x] `diorama_character_rig_player` renders a Crystal-theme character in the crystal palette. (CHA-05)
- [x] Entering a waves run shows the saved appearance, not the default body. (CHA-06)
- [x] `content/fixtures/character_state_sample.v2.json` validates against the `appearance` sub-schema, and a fixture with invalid variant fails. (CHA-07)
- [x] Every theme offered by the creation screen is either always available or backed by a `DungeonCatalog` clear flag, with no unreachable option. (CHA-08)
- [x] Grep finds no zero-caller function in `character_appearance.gd` or the appearance section of `local_save.gd`. (CHA-09)
- [x] Renaming the `Torso` part produces one warning naming the missing part instead of a silently missing belt trim. (CHA-10)

## Validation
Extend `apps/game/client/scripts/validation/suites/save_suite.gd`:

| Assertion id | Checks | Status |
|--------------|--------|--------|
| `appearance.sanitize_clamps_theme` | `sanitize({"theme": 42})` returns a theme within `0..PALETTES.size() - 1` | DONE |
| `appearance.sanitize_clamps_height_and_bulk` | Legacy floats migrate into valid variants | DONE |
| `appearance.sanitize_stamps_profile_version` | Every sanitised profile carries `profileVersion == PROFILE_VERSION` | DONE |
| `appearance.is_valid_rejects_out_of_range` | `is_valid({"theme": 42, ...})` is false while `sanitize` of the same input is valid | DONE |
| `appearance.presets_inside_clamps` | Every entry of `HEIGHT_PRESETS` and `BULK_PRESETS` is inside its clamp range | DONE |
| `appearance.round_trip_through_save` | A non-default profile survives `to_save_dict` -> `from_save_dict` unchanged in key fields | DONE |
| `appearance.migrate_v4_clamps_profile` | A v4 save with `theme: 42` and `height: 1.18` migrates to in-range values | DONE |
| `appearance.palette_lookup_never_throws` | `PixelStyle.get_palette(-3)` and `get_palette(99)` return the castle row and warn | DONE |

Extend `apps/game/client/scripts/validation/suites/hub_m4_suite.gd`:

| Assertion id | Checks | Status |
|--------------|--------|--------|
| `appearance.mirror_applies_and_persists` | `LocalSave.set_appearance_profile` emits `appearance_changed` and reloads identically | DONE |
| `appearance.mirror_rejects_invalid` | An invalid profile returns `false` and leaves the stored profile untouched | DONE |
| `appearance.skin_applies_every_key` | `build_preview_body` with hood / trim / tall variant produces expected nodes and archetype | DONE |
| `appearance.skin_warns_on_missing_part` | Removing `Torso` before `_apply_player_appearance` produces a warning and no crash | DONE |
| `appearance.waves_run_uses_saved_profile` | Compact saved profile maps to `player_warden_compact` archetype for waves spawn | DONE |

Extend `apps/game/client/scripts/validation/suites/content_suite.gd`:

| Assertion id | Checks | Status |
|--------------|--------|--------|
| `content.appearance.theme_bound_matches_palettes` | Schema `appearance.theme.maximum` equals `PALETTES.size() - 1` | DONE |
| `content.appearance.schema_bounds_match_clamps` | Schema variant enums match GDScript `HEIGHT_VARIANTS` / `BULK_VARIANTS` | DONE |

## Related
- Existing state: [`../existing_codebase/character-appearance.md`](../existing_codebase/character-appearance.md)
- [`character-service.md`](character-service.md), [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md), [`hub.md`](hub.md), [`npc-hub-services.md`](npc-hub-services.md), [`ui/character_create.md`](ui/character_create.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`pixel-style.md`](pixel-style.md), [`character-floor-snap.md`](character-floor-snap.md)

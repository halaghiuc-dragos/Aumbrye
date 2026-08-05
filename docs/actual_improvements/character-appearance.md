# Character appearance — improvement plan

## Current state
`CharacterAppearance` (`apps/game/client/scripts/save/character_appearance.gd`, 102 lines) defines a five-key profile — `theme`, `height`, `bulk`, `head`, `trim` — sanitises four of them, and round-trips through `character.appearanceTheme` / `character.appearance`. See [`../existing_codebase/character-appearance.md`](../existing_codebase/character-appearance.md). All four visual features work: height and bulk scale the visual root, the head style toggles a visor or hood, and trim adds a belt and pauldrons. Around that working core sit five dead functions, an unclamped `theme` that can crash palette lookup, a creation-screen preview that only recolours a swatch, no post-creation editor, and no schema for the profile.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| CHA-01 | P0 | `sanitize` does not clamp `theme`; `PixelStyle.get_palette` indexes `PALETTES[theme]` unchecked, so a save with `appearanceTheme` outside `0..10` raises an index error the moment the player body is built | `character_appearance.gd:61-62`, `pixel_diorama_style.gd:224-232` |
| CHA-02 | P0 | The creation screen previews nothing but the accent colour; stature, build, head, and trim selections produce no visible change before the player commits to them permanently | `character_create_ui.gd:63`, `character_create_ui.gd:159-162` |
| CHA-03 | P1 | Appearance cannot be changed after creation; the five accessor functions that would enable it all have zero callers | `local_save.gd:113-114`, `local_save.gd:131-136`, `character_appearance.gd:72-77`, `character_appearance.gd:100-101` |
| CHA-04 | P1 | `height` and `bulk` scale only the visual; no collider, hurtbox, or camera pivot changes, so a Tall warden's head is outside its own hurtbox and a Compact warden's is inside it | Only consumer of `profile.height` is `diorama_character_skin.gd:105-107`; grep of `apps/` finds no other reader |
| CHA-05 | P1 | `build_player_body` takes its materials from its `theme` argument, not from the profile, and `diorama_character_rig_player.gd:16` hardcodes `PaletteTheme.CASTLE`, so that rig ignores the saved theme | `diorama_character_skin.gd:93-97`, `diorama_character_rig_player.gd:16` |
| CHA-06 | P1 | Waves runs never refresh the appearance visual because `sync_player_loadout` returns early | `player_controls.gd:70-71` -> `player_controls.gd:75-77` |
| CHA-07 | P2 | No JSON schema describes the appearance profile, so a malformed `character.appearance` in a save or fixture is only caught by `sanitize` silently replacing it | `content/schemas/character-state.v1.json` has no `appearance` sub-object |
| CHA-08 | P2 | The creation screen offers five of eleven palette themes with no stated reason, and there is no unlock path for the other six | `character_create_ui.gd:13-19` vs `pixel_diorama_style.gd:25-37` |
| CHA-09 | P2 | Five functions across two files are dead: `apply_to_service`, `theme_from_service`, `LocalSave.set_appearance_theme`, `get_appearance_profile`, `get_appearance_theme`; `from_character_dict` exists only to serve one of them | Grep of the repository finds no callers |
| CHA-10 | P2 | The skin depends on the node names `ROOT_NAME`, `Head/Mesh/Visor`, `Head/Hood`, `Torso`, `ArmL`, `ArmR` with silent no-ops when any is missing, so a rename disables a feature without an error | `diorama_character_skin.gd:102-151`, every branch guarded by a null check that returns quietly |

## Target design

### A validated, self-describing profile
`theme` joins the other four keys as a clamped value, and the profile gains an explicit version so future keys can be added without guessing:

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
- Keep the collider fixed and constrain the visual to it. Chosen: `height` and `bulk` are clamped to a range whose extremes still fit the capsule, and the visual root is offset so the feet stay on the floor plane rather than the centre staying fixed.

```gdscript
## character_appearance.gd
const HEIGHT_MIN := 0.92
const HEIGHT_MAX := 1.08
const BULK_MIN := 0.90
const BULK_MAX := 1.12

## diorama_character_skin.gd — _apply_player_appearance
root.scale = Vector3(bulk, height, bulk)
root.position.y = _root_base_y(visual) * height   ## feet stay planted as height changes
```

The narrowed ranges replace the current `0.82 .. 1.18` / `0.82 .. 1.22` clamps, which exceed what the capsule can contain. `_migrate_v4_to_v5` re-clamps existing profiles into the new range, which changes at most 8 percent of a saved character's visual height and cannot invalidate a save. `character-floor-snap` owns the floor-plane contract; see [`character-floor-snap.md`](character-floor-snap.md).

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

1. **Clamp `theme` in `sanitize`, derive `THEME_MAX` from the palette table, add `PROFILE_VERSION`, `is_valid`, `describe`** — `character_appearance.gd:59-69`. Add defensive clamps plus a warning to `PixelStyle.get_palette` and `get_palette_color` (`pixel_diorama_style.gd:224-232`). Closes CHA-01.
2. **Narrow `HEIGHT_*` / `BULK_*` ranges, update `HEIGHT_PRESETS` / `BULK_PRESETS` to sit inside them, and offset the visual root by height** — `character_appearance.gd:12-16`, `character_appearance.gd:63-64`, `diorama_character_skin.gd:105-107`. Closes CHA-04.
3. **Add `build_preview_body(parent, profile)` and route `_apply_player_appearance` through the named-part constants and `_require_part`** — `diorama_character_skin.gd:101-151`. Closes CHA-10, unblocks CHA-02.
4. **Read the theme from the profile in `build_player_body`; drop the hardcoded theme in the player rig** — `diorama_character_skin.gd:89-98`, `diorama_character_rig_player.gd:16`. Closes CHA-05.
5. **Add `CharacterService.appearance_changed`, make `LocalSave.set_appearance_profile` return `bool` and emit it through `CharacterAppearance.apply_to_service`, subscribe `Locomotion`** — `character_service.gd`, `local_save.gd:117-128`, `character_appearance.gd:72-77`, `locomotion.gd:51-57`. Closes CHA-06, CHA-09 in part.
6. **Delete `set_appearance_theme` and `theme_from_service`; give `get_appearance_profile` its caller in the mirror UI** — `local_save.gd:113-114`, `character_appearance.gd:100-101`. Closes CHA-03, CHA-09.
7. **Add the `appearance` sub-schema and its fixture** — `content/schemas/character-state.v2.json`, `content/fixtures/character_state_sample.v2.json`. Closes CHA-07.
8. **Decide and document the theme roster** — either expose all eleven `PaletteTheme` rows in `APPEARANCE_OPTIONS` or gate the extra six behind `DungeonCatalog.get_clear_flag` unlocks from [`character-service.md`](character-service.md). Preferred: gate them, because a palette named after a dungeon is a natural clear reward. Closes CHA-08.

## Data and schema changes

**Save version bump: `save_migrator.gd` `CURRENT_VERSION` 4 -> 5** — the same shared bump described in [`save-migrator.md`](save-migrator.md). The appearance-owned part of `_migrate_v4_to_v5`:

```gdscript
## character.appearance: clamp into the new ranges, clamp theme, stamp the profile version
var character: Dictionary = copy.get("character", {})
var profile: Variant = character.get("appearance", {})
character["appearance"] = CharacterAppearance.sanitize(
    profile if profile is Dictionary else {"theme": character.get("appearanceTheme", 0)}
)
character["appearanceTheme"] = int(character["appearance"]["theme"])
copy["character"] = character
```

Because `sanitize` now clamps `theme` and the narrowed height and bulk ranges, this step repairs every out-of-range profile in existing saves. `appearanceTheme` becomes a derived mirror of `appearance.theme` rather than an independent value; it stays in the payload because `local_save.gd:136` and the roster summary read it without loading the nested profile.

**New schema: the `appearance` object inside `content/schemas/character-state.v2.json`** (the v2 file itself is defined in [`local-save.md`](local-save.md)):

```json
"appearance": {
  "type": "object",
  "additionalProperties": false,
  "required": ["profileVersion", "theme", "height", "bulk", "head", "trim"],
  "properties": {
    "profileVersion": { "const": 1 },
    "theme": { "type": "integer", "minimum": 0, "maximum": 10 },
    "height": { "type": "number", "minimum": 0.92, "maximum": 1.08 },
    "bulk": { "type": "number", "minimum": 0.90, "maximum": 1.12 },
    "head": { "enum": ["open", "visor", "hood"] },
    "trim": { "type": "integer", "minimum": 0, "maximum": 2 }
  }
}
```

`content/fixtures/character_state_sample.v2.json` gains a matching `appearance` block, and `scripts/validate-content/validate.mjs` maps the fixture to the v2 schema so a drift between the GDScript clamps and the JSON bounds fails the content check rather than a playtest.

**Failure and recovery behaviour:**

| Situation | Behaviour |
|-----------|-----------|
| `character.appearance` missing | `sanitize({})` yields the default profile; `from_character_dict` already falls back to `appearanceTheme` (`character_appearance.gd:86`); no error |
| `character.appearance` is not a Dictionary | Replaced with the default profile, one `push_warning` naming the observed type |
| `theme` out of `0..10` | Clamped by `sanitize`, one `push_warning`; `PixelStyle.get_palette` clamps again as a second line of defence so no build path can throw |
| `head` is an unknown String | Falls back to `HEAD_VISOR` (`character_appearance.gd:66`), unchanged |
| A required visual part is missing (renamed mesh) | `_require_part` returns null and warns once; the body still builds without that feature |
| `set_appearance_profile` receives an invalid profile from the mirror UI | Returns `false`, the profile is not written, no autosave, the UI keeps the previous selection |
| `PALETTES` gains a row | `THEME_MAX` is derived, so the clamp and the schema bound both need one update; `content.appearance.theme_bound_matches_palettes` catches a missed schema edit |

## Acceptance criteria
- [ ] A save with `character.appearanceTheme: 42` loads, is clamped to a valid theme, logs one warning, and builds the player body without an error. (CHA-01)
- [ ] Changing Stature, Build, Head, or Trim on the creation screen visibly changes a live 3D preview that matches the body spawned in the hub. (CHA-02)
- [ ] The hub mirror changes an existing character's appearance, the change is visible without a scene reload, and it survives a save and reload. (CHA-03)
- [ ] Tall and Compact wardens have their visual head inside the same hurtbox volume, and both have their feet on the floor plane. (CHA-04)
- [ ] `diorama_character_rig_player` renders a Crystal-theme character in the crystal palette. (CHA-05)
- [ ] Entering a waves run shows the saved appearance, not the default body. (CHA-06)
- [ ] `content/fixtures/character_state_sample.v2.json` validates against the `appearance` sub-schema, and a fixture with `height: 1.5` fails. (CHA-07)
- [ ] Every theme offered by the creation screen is either always available or backed by a `DungeonCatalog` clear flag, with no unreachable option. (CHA-08)
- [ ] Grep finds no zero-caller function in `character_appearance.gd` or the appearance section of `local_save.gd`. (CHA-09)
- [ ] Renaming the `Torso` part produces one warning naming the missing part instead of a silently missing belt trim. (CHA-10)

## Validation
Extend `apps/game/client/scripts/validation/suites/save_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `appearance.sanitize_clamps_theme` | `sanitize({"theme": 42})` returns a theme within `0..PALETTES.size() - 1` |
| `appearance.sanitize_clamps_height_and_bulk` | `sanitize({"height": 5.0, "bulk": -1.0})` returns values inside `HEIGHT_MIN..HEIGHT_MAX` and `BULK_MIN..BULK_MAX` |
| `appearance.sanitize_stamps_profile_version` | Every sanitised profile carries `profileVersion == PROFILE_VERSION` |
| `appearance.is_valid_rejects_out_of_range` | `is_valid({"theme": 42, ...})` is false while `sanitize` of the same input is valid |
| `appearance.presets_inside_clamps` | Every entry of `HEIGHT_PRESETS` and `BULK_PRESETS` is inside its clamp range |
| `appearance.round_trip_through_save` | A non-default profile survives `to_save_dict` -> `from_save_dict` unchanged in all five keys |
| `appearance.migrate_v4_clamps_profile` | A v4 save with `theme: 42` and `height: 1.18` migrates to in-range values |
| `appearance.palette_lookup_never_throws` | `PixelStyle.get_palette(-3)` and `get_palette(99)` return the castle row and warn |

Extend `apps/game/client/scripts/validation/suites/hub_m4_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `appearance.mirror_applies_and_persists` | `LocalSave.set_appearance_profile` with a Hooded / Pauldrons profile emits `appearance_changed`, rebuilds the body, and reloads identically |
| `appearance.mirror_rejects_invalid` | An invalid profile returns `false`, emits no signal, and leaves the stored profile untouched |
| `appearance.skin_applies_every_key` | After `build_preview_body` with `{"head": "hood", "trim": 2}`, the visual contains a `Hood`, a `BeltTrim`, and two `Pauldron` nodes, and the root scale matches the profile |
| `appearance.skin_warns_on_missing_part` | Removing `Torso` before `_apply_player_appearance` produces a warning and no crash |
| `appearance.waves_run_uses_saved_profile` | A waves run spawns a body whose root scale matches the saved profile |

Extend `apps/game/client/scripts/validation/suites/content_suite.gd` with `content.appearance.theme_bound_matches_palettes`, asserting the `maximum` in the `appearance.theme` schema equals `PixelStyle.PALETTES.size() - 1`, and `content.appearance.schema_bounds_match_clamps`, asserting the schema `minimum`/`maximum` for `height` and `bulk` equal the GDScript constants.

## Related
- Existing state: [`../existing_codebase/character-appearance.md`](../existing_codebase/character-appearance.md)
- [`character-service.md`](character-service.md), [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md), [`hub.md`](hub.md), [`npc-hub-services.md`](npc-hub-services.md), [`ui/character_create.md`](ui/character_create.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`pixel-style.md`](pixel-style.md), [`character-floor-snap.md`](character-floor-snap.md)

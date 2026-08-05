# Project config and autoloads — improvement plan

## Current state

`apps/game/client/project.godot` declares 21 autoloads, 35 input actions, 1920x1080 `canvas_items` + integer stretch, nearest-neighbour texture filtering, and four named physics layers (see [`../existing_codebase/project-config-autoloads.md`](../existing_codebase/project-config-autoloads.md)). The project file says `config/features=PackedStringArray("4.7", "Forward Plus")` while both GitHub workflows install Godot 4.4.0, so CI validates a build the editor cannot produce. There is no runtime input rebinding anywhere in `apps/game/client/scripts`, and five gamepad/keyboard bindings collide across action pairs.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| CFG-01 | P0 | Engine version skew: project features declare `4.7`, CI and release install Godot `4.4.0`. CI parses the project with an engine three minor versions behind what the editor writes, and the release export uses 4.4.0 templates. | `apps/game/client/project.godot:20` vs `.github/workflows/ci.yml:115`, `.github/workflows/release.yml:48` |
| CFG-02 | P0 | No input rebinding. A shipping action game with mouse-button attacks and no remap screen is unplayable for left-handed players and anyone with a non-QWERTY-position keyboard or a non-Xbox pad. | No `InputMap.action_erase_events` / `action_add_event` / `add_action` call anywhere under `apps/game/client/scripts` |
| CFG-03 | P1 | `talents` and `heal` both bind gamepad button 7. Pressing button 7 fires both actions in the same frame. | `apps/game/client/project.godot:274` and `project.godot:286` |
| CFG-04 | P1 | `lock_on` binds Enter (`4194309`), which is also `ui_accept`. Pressing Enter in a menu that is not fully modal also toggles lock-on. | `apps/game/client/project.godot:85` and `project.godot:181` |
| CFG-05 | P1 | `zoom_in`/`ui_up` share gamepad button 11 and `zoom_out`/`ui_down` share button 12, so D-pad up/down changes camera zoom during menu navigation. | `apps/game/client/project.godot:110,116,195,201` |
| CFG-06 | P1 | No explicit vsync, window mode, or MSAA settings. The game ships whatever Godot defaults to, and there is no project-level anchor for the display settings UI to reset to. | No `window/vsync/*`, `window/size/mode`, `rendering/anti_aliasing/*` keys in `project.godot` |
| CFG-07 | P2 | `setup_suite.gd` asserts 8 of the 21 autoloads. Deleting `AttackTokenService`, `WavesRunService`, `DungeonTierService`, `GameFacade`, `SteamService`, `CrashLogger`, `PixelDioramaViewport`, `RunBuffs`, `StorageService`, `QuestService`, `AchievementService`, `CharacterService`, or `ProgressionService` from the project file would not fail validation. | `apps/game/client/scripts/validation/suites/setup_suite.gd:26-28` vs `project.godot:33-53` |
| CFG-08 | P2 | Physics layers 5-32 are unnamed, so any collision mask beyond `hurtbox` is a bare integer in the inspector. | `apps/game/client/project.godot:305-310` |
| CFG-09 | P2 | The `godot_mcp` development plugin is enabled in the committed project file, so it loads for every contributor and in any editor-mode CI step. | `apps/game/client/project.godot:64` |
| CFG-10 | P2 | Only `en` is registered. `strings.csv` exists but there is no second locale column pipeline, and no `TranslationServer.set_locale` call driven by a settings key. | `apps/game/client/project.godot:303`, `apps/game/client/translations/` contains only `strings.csv`, `strings.csv.import`, `strings.en.translation` |

## Target design

**One pinned engine version, one source of truth.** Add `apps/game/client/.godot-version` containing the exact patch version (for example `4.7.1`), have both workflows read it, and keep `config/features` in sync. Chosen over hardcoding `4.7.1` in both YAML files because the version then appears once and a validation suite can assert the project file agrees with it. Rejected alternative: downgrading `config/features` to `4.4` — the project was authored in 4.7 and downgrading risks silent resource-format loss.

**Input rebinding as a data-driven overlay.** Ship the `project.godot` InputMap as the default set. Add `apps/game/client/scripts/app/input_rebind_service.gd` as autoload 22 that:

- On `_ready()`, snapshots every action in `InputMap.get_actions()` that does not start with `ui_` into `_defaults: Dictionary[StringName, Array[InputEvent]]`.
- Loads `user://input_bindings.json` and reapplies overrides via `InputMap.action_erase_events(action)` then `InputMap.action_add_event(action, event)`.
- Exposes `rebind(action: StringName, event: InputEvent) -> Dictionary` returning `{"ok": bool, "conflict": StringName}`. Rebinding refuses events already bound to another action in the same context group and returns the conflicting action name so the UI can offer "swap" or "cancel".
- Exposes `reset_action(action)` and `reset_all()`.
- Emits `bindings_changed(action: StringName)`.

Save format `user://input_bindings.json`:

```json
{
  "schemaVersion": 1,
  "bindings": {
    "light_attack": [
      { "device": "keyboard", "physicalKeycode": 74 },
      { "device": "joypad_button", "buttonIndex": 2 }
    ]
  }
}
```

Only overridden actions are written; anything absent falls back to the `project.godot` default. This is a `user://` file, not part of `aumbrye_save.json`, so it does not require a `save_migrator.gd` bump.

**Context groups for conflict detection.** Three groups, declared as a constant in `input_rebind_service.gd`:

| Group | Actions |
|-------|---------|
| `menu` | `ui_accept`, `ui_cancel`, `ui_left`, `ui_right`, `ui_up`, `ui_down`, `pause`, `inventory`, `talents` |
| `gameplay` | `move_*`, `look_*`, `sprint`, `jump`, `dodge`, `light_attack`, `heavy_attack`, `block`, `lock_on`, `interact`, `heal`, `two_hand`, `weapon_art`, `quick_slot_*`, `zoom_in`, `zoom_out`, `toggle_camera` |
| `debug` | `debug_toggle`, `debug_hitboxes`, `toggle_damage_numbers`, `reset_duel` |

A binding may repeat across groups (`ui_cancel` and `pause` both on Escape is deliberate) but must be unique within a group. The three current within-group collisions (CFG-03, CFG-04, CFG-05) are fixed in the default map before the service ships:

| Action | Current | Target default |
|--------|---------|----------------|
| `heal` | `H`, joypad button 7 | `H`, joypad button 3 held with `block` modifier removed — bind to joypad **D-pad right** (button 14) |
| `talents` | `K`, joypad button 7 | `K`, joypad button 7 (keeps 7) |
| `lock_on` | Enter, mouse button 3, joypad button 5 | mouse button 3, joypad button 5 (drop Enter) |
| `zoom_in` | mouse wheel up, joypad button 11 | mouse wheel up only |
| `zoom_out` | mouse wheel down, joypad button 12 | mouse wheel down only |

**Explicit display settings.** Add to `project.godot`:

```ini
[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/mode=0
window/stretch/mode="canvas_items"
window/stretch/scale_mode="integer"
window/vsync/vsync_mode=1

[rendering]
anti_aliasing/quality/msaa_3d=0
anti_aliasing/quality/screen_space_aa=0
textures/canvas_textures/default_texture_filter=0
textures/default_filters/anisotropic_filtering_level=0
textures/default_filters/texture_filter=0
```

`msaa_3d=0` and `screen_space_aa=0` are stated explicitly because the pixel-diorama art direction (see [`../existing_codebase/pixel-style.md`](../existing_codebase/pixel-style.md)) requires hard pixel edges; leaving them at Godot defaults means a future default change silently softens the whole game.

## Work plan

1. **Pin the engine version once** — add `apps/game/client/.godot-version` with the exact patch version. Change `.github/workflows/ci.yml:115` and `.github/workflows/release.yml:48` to read it (`version: ${{ steps.godot_version.outputs.value }}` fed by a `run: echo "value=$(cat apps/game/client/.godot-version)" >> $GITHUB_OUTPUT` step). Confirm `config/features` first element matches. (CFG-01)
2. **Resolve binding collisions in `project.godot`** — apply the five default changes in the table above. This is a pure data edit to `project.godot:110,116,181,195,201,286`. (CFG-03, CFG-04, CFG-05)
3. **Add explicit display and rendering keys** — edit `project.godot` `[display]` and `[rendering]` per the block above. (CFG-06)
4. **Name physics layers 5-8** — add `3d_physics/layer_5="interactable"`, `layer_6="trap"`, `layer_7="projectile"`, `layer_8="camera_blocker"` to `[layer_names]`, then replace bare mask integers in scripts that use those layers. (CFG-08)
5. **Add `InputRebindService`** — new `apps/game/client/scripts/app/input_rebind_service.gd`, registered as autoload 22 in `project.godot` after `GameFacade`. Implements snapshot, load, `rebind`, `reset_action`, `reset_all`, `bindings_changed`. Persists to `user://input_bindings.json`. Game is fully runnable after this step even with no UI. (CFG-02)
6. **Add the rebinding screen** — extend the settings UI (see [`ui/settings.md`](ui/settings.md)) with a Controls tab listing every `gameplay` and `menu` action, its current keyboard and gamepad glyph, a "Press any key" capture state, a per-row reset, and a "Reset all" button. Conflicts surface the conflicting action name returned by `rebind`. (CFG-02)
7. **Move `godot_mcp` out of the committed enabled-plugin list** — remove `project.godot:64`, and document enabling it locally in `docs/MCP_AGENT_GUIDE.md`. Update `setup_suite.gd:44-49` `setup.mcp_plugin_present` to assert the plugin file exists rather than that it is enabled. (CFG-09)
8. **Extend autoload validation to all 21** — replace the eight-name list in `setup_suite.gd:26-28` with the full 21-name list. (CFG-07)
9. **Add a second locale column** — extend `translations/strings.csv` with a `ro` column, regenerate `strings.ro.translation`, register it in `project.godot:303`, and add a locale setting that calls `TranslationServer.set_locale`. (CFG-10)

## Data and schema changes

- New file `user://input_bindings.json`, `schemaVersion: 1`, shape above. It is written by `InputRebindService`, not by `LocalSave`, so **no `save_migrator.gd` version bump is required**.
- New schema `content/schemas/input-bindings.v1.json` describing the file, so `scripts/validate-content/validate.mjs` can validate a checked-in default fixture at `content/fixtures/input_bindings_sample.v1.json`. Add the mapping to `resolveSchemaForFile` in `scripts/validate-content/validate.mjs:106` alongside the existing `character_state_sample` case.

## Acceptance criteria

- [ ] `apps/game/client/.godot-version` exists and its content equals the first element of `config/features` in `project.godot`.
- [ ] `.github/workflows/ci.yml` and `release.yml` install the version read from `.godot-version`, and neither file contains a hardcoded `4.4.0`.
- [ ] No two actions within the same context group share an `InputEvent`, asserted by a validation test.
- [ ] `project.godot` contains explicit `window/vsync/vsync_mode`, `window/size/mode`, `anti_aliasing/quality/msaa_3d`, and `anti_aliasing/quality/screen_space_aa` keys.
- [ ] `[layer_names]` names at least layers 1-8.
- [ ] Rebinding `light_attack` to `J` in the Controls tab, quitting, and relaunching keeps `J` bound.
- [ ] "Reset all" restores every action to the `project.godot` default and deletes `user://input_bindings.json`.
- [ ] Attempting to bind `dodge` to a key already used by `sprint` returns `{"ok": false, "conflict": "sprint"}` and the UI shows the conflict.
- [ ] `setup_suite.gd` asserts all 21 autoloads.
- [ ] `project.godot` does not enable `godot_mcp` in `[editor_plugins]`.

## Validation

Extend `apps/game/client/scripts/validation/suites/setup_suite.gd`:

- `setup.autoloads` — assert all 21 names from `project.godot:33-53`, not 8.
- `setup.engine_version_pin` — read `apps/game/client/.godot-version` and assert it equals `ProjectSettings.get_setting("application/config/features")[0]` plus a patch suffix.
- `input.no_intra_group_conflicts` — for each of the three context groups, build a set of `InputEvent.as_text()` values across the group's actions and assert no duplicates.
- `input.rebind_roundtrip` — call `InputRebindService.rebind("light_attack", <InputEventKey J>)`, assert `InputMap.action_has_event("light_attack", ...)`, call `reset_all()`, assert the original mouse-button-1 event is restored and `user://input_bindings.json` is deleted.
- `input.rebind_conflict_reported` — call `rebind("dodge", <sprint's event>)` and assert the returned `conflict` is `"sprint"`.
- `setup.display_settings_explicit` — assert `ProjectSettings.has_setting` is true for `display/window/vsync/vsync_mode`, `display/window/size/mode`, `rendering/anti_aliasing/quality/msaa_3d`.

Manual only: confirming that the chosen gamepad defaults feel correct on a physical pad. Everything else above is automatable headless.

## Related

- Existing behavior: [`../existing_codebase/project-config-autoloads.md`](../existing_codebase/project-config-autoloads.md)
- [`ci-cd.md`](ci-cd.md) — CFG-01 is also gap CID-01
- [`ui/settings.md`](ui/settings.md) — the Controls tab host
- [`ui/input_glyphs.md`](ui/input_glyphs.md) — glyph rendering for rebound actions
- [`accessibility.md`](accessibility.md) — rebinding is an accessibility requirement
- [`validation-suites.md`](validation-suites.md) — CFG-07

# Combat HUD — improvement plan

## Status: FINISHED

## Current state
`scenes/ui/combat_hud.tscn` is the single authored HUD tree; `castle_run.tscn`, `hub.tscn`, `forgotten_castle_slice.tscn`, `combat_arena.tscn`, and `waves_run.gd` all instance it. `combat_hud.gd` uses `@onready` node references only — no `_ensure_*` scaffolding. Guard indicators, lock reticle, status pips with stacks/duration, boss phase pips from `phaseCount`, camera-relative objective marker, minimap anchor, localized strings, and device-reactive control hints are wired. See [`../existing_codebase/ui/combat_hud.md`](../existing_codebase/ui/combat_hud.md).

## Gaps
| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| HUD-01 | P0 | Guard feedback invisible outside debug arena | FINISHED — `GuardIndicators` in `combat_hud.tscn`; parry `max_value` from `guard.gd:get_parry_window_duration()` |
| HUD-02 | P0 | Lock-on reticle missing in hub/waves/slice | FINISHED — `LockReticle` authored in `combat_hud.tscn` |
| HUD-03 | P0 | Status stacks/duration not drawn | FINISHED — `status_pip.tscn` with `StackLabel` + `DurationArc`; keyed diff in `_refresh_status_icons` |
| HUD-04 | P1 | Boss phase count from script path heuristic | FINISHED — `phaseCount` in `content/bosses/*.json` + `EnemyCatalog` |
| HUD-05 | P1 | Objective marker ignores camera yaw | FINISHED — `unproject_position` + edge clamp + rotation |
| HUD-06 | P1 | Minimap positioned from frame-one `size.x` | FINISHED — `MinimapAnchor` (`PRESET_TOP_RIGHT`) |
| HUD-07 | P1 | Vignette on every low-HP health change | FINISHED — `_last_health` + `VIGNETTE_COOLDOWN` damage-only gate |
| HUD-08 | P1 | Controls hint static / never hides | FINISHED — `InputGlyphWatcher` + `AccessibilitySettings.show_control_hints` + 60 s auto-hide |
| HUD-09 | P1 | Boss pips and objective as `ColorRect` | FINISHED — `hud_pips.png` atlas + `hud_objective.png` |
| HUD-10 | P1 | `KEY_F8` burn in release builds | FINISHED — `OS.is_debug_build()` guard |
| HUD-11 | P2 | Hand-computed layout in three places | FINISHED — `StatusRow` inside `ResourcePanel/VBox`; `MinimapAnchor` |
| HUD-12 | P2 | Per-frame attack `StyleBoxFlat` allocation | FINISHED — `_attack_styles` cached in `_ready()` |
| HUD-13 | P2 | Unused `BAR_BORDER` constant | FINISHED — removed |
| HUD-14 | P2 | Hardcoded English HUD strings | FINISHED — `HUD_*` keys in `translations/strings.csv` |

## Target design
Delivered as implemented: one `combat_hud.tscn`, `status_pip.tscn`, `hud_icon_atlas.gd` + `content/ui/hud_atlas.json`, `InputGlyphWatcher` autoload, `AccessibilitySettings.show_control_hints`, boss `phaseCount` schema field.

## Work plan
All eight steps from the original plan are complete (authored scene, guard tuning, status pips, boss data, objective marker, vignette, hints, cleanup).

## Data and schema changes
- `content/schemas/enemy-definition.v1.json`: `phaseCount` integer ≥ 1.
- `content/bosses/*.json`: `phaseCount` per boss (knight 2, final sovereign 3, minibosses 1).
- `translations/strings.csv`: `HUD_PARRY`, `HUD_LEVEL`, `HUD_BRANCH_AHEAD`, `HUD_BRANCH_REWARD`, `HUD_BRANCH_DANGER`, `HUD_BOSS_FALLBACK`.
- `AccessibilitySettings.show_control_hints` persisted under `accessibility` meta key.
- Assets: `assets/ui/hud_reticle.png`, `hud_objective.png`, `hud_pips.png`.

## Acceptance criteria
- [x] `scenes/ui/combat_hud.tscn` exists and every gameplay scene instances it.
- [x] `combat_hud.gd` contains no `_ensure_*` functions.
- [x] Parry and block bars appear in hub, castle, waves, and slice scenes.
- [x] Lock-on reticle appears in all four scenes above.
- [x] Two stacks of `burn` render `x2` on one pip with duration arc.
- [x] Adding a second status reuses the first pip instance.
- [x] Parry bar `max_value` equals `guard.gd` parry window, not `0.18` literal in script.
- [x] Boss JSON `phaseCount: 4` would show four pips (catalog-driven).
- [x] Objective marker uses camera projection and rotation.
- [x] Healing under 25 % HP does not pulse vignette; damage does, cooldown-gated.
- [x] `device_family_changed` rebuilds controls hint.
- [x] Settings checkbox hides `ControlsHint` and persists.
- [x] `KEY_F8` gated on debug builds.
- [x] HUD display strings use `tr("HUD_*")`.

## Validation
`m5_suite.gd` `_test_combat_hud()` — 15 assertions: `hud.scene_exists`, `hud.no_ensure_functions`, `hud.guard_nodes_present`, `hud.reticle_present`, `hud.scene_instanced_everywhere`, `hud.guard_window_from_guard`, `hud.status_pip_stacks`, `hud.status_pip_reuse`, `hud.boss_phase_from_data`, `hud.objective_camera_relative`, `hud.vignette_not_on_heal`, `hud.hint_rebuilds_on_device`, `hud.debug_key_guarded`, `hud.strings_localized`, `hud.no_dead_constants`.

## Related
- Current behavior: [`../existing_codebase/ui/combat_hud.md`](../existing_codebase/ui/combat_hud.md)
- [`minimap.md`](minimap.md) · [`status_icons_glyphs.md`](status_icons_glyphs.md) · [`input_glyphs.md`](input_glyphs.md) · [`game_ui_skin.md`](game_ui_skin.md) · [`waves_hud.md`](waves_hud.md)
- [`../guard.md`](../guard.md) · [`../statuses-and-buffs.md`](../statuses-and-buffs.md) · [`../bosses.md`](../bosses.md)

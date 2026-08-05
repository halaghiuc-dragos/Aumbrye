# Combat HUD — improvement plan

## Current state
`combat_hud.gd` builds most of its own control tree at runtime with `get_node_or_null` + `_ensure_*` fallbacks (`combat_hud.gd:60-96`), so each scene ships a different HUD: only `scenes/debug/combat_arena.tscn` authors `GuardIndicators`, only `castle_run.tscn` and `combat_arena.tscn` author `LockReticle`, and `waves_run.gd:270-277` creates the HUD from a bare `Control` with no authored children at all. Resource bars, the attack-phase bar, and XP work correctly; status icons, boss phase pips, and the objective marker are `ColorRect`/procedural placeholders; the minimap is instantiated everywhere but configured only by `castle_run.gd:107`. See [`../existing_codebase/ui/combat_hud.md`](../existing_codebase/ui/combat_hud.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| HUD-01 | P0 | Guard feedback is invisible in real play: `_update_guard_indicators` returns immediately unless all three of `ParryBar`, `BlockBar`, `ParryLabel` exist, and only the debug arena authors them. Parry timing is a core combat skill with no HUD signal in the castle, hub, waves, or slice scenes. | `combat_hud.gd:418-425`; `GuardIndicators` appears only at `scenes/debug/combat_arena.tscn:163` |
| HUD-02 | P0 | Lock-on has no reticle in the hub, the waves run, or `forgotten_castle_slice.tscn`, because `LockReticle` is authored in only two scenes and never created as a fallback. | `combat_hud.gd:387-392`; `LockReticle` at `castle_run.tscn:61`, `combat_arena.tscn:204` only |
| HUD-03 | P0 | Status effects show no stacks and no remaining duration. The only carrier is `tooltip_text`, which cannot be hovered because gameplay holds `Input.MOUSE_MODE_CAPTURED`. A player cannot tell a 1-stack burn from a 5-stack burn. | `combat_hud.gd:202`; `inventory_ui.gd:302` sets `MOUSE_MODE_CAPTURED` on close |
| HUD-04 | P1 | Boss phase count is inferred from the script filename containing `final_boss`, so any new multi-phase boss silently gets 2 pips. | `combat_hud.gd:310-313` |
| HUD-05 | P1 | The objective marker's direction ignores camera yaw: `Vector2(to_target.x, -to_target.z)` is a world-space vector drawn in screen space, so the arrow points the wrong way whenever the camera is not facing world `-Z`. | `combat_hud.gd:602` |
| HUD-06 | P1 | The minimap is positioned once from `size.x` inside `_ready()` — before the first layout pass — and never repositioned, so its placement depends on frame-one geometry and breaks on window resize. | `combat_hud.gd:557` |
| HUD-07 | P1 | The damage vignette pulses on *every* `health_changed` at or below 25 %, including heals and each damage-over-time tick, producing continuous flashing at low HP. | `combat_hud.gd:461-463` |
| HUD-08 | P1 | The controls hint is built once in `_ready()` and never rebuilt, so plugging in a gamepad mid-session leaves keyboard glyphs on screen; it also never hides, permanently occupying the bottom strip. | `combat_hud.gd:222-241` |
| HUD-09 | P1 | Boss phase pips and the objective marker are `ColorRect` rectangles, not authored art. | `combat_hud.gd:322-326`, `:581-584` |
| HUD-10 | P1 | `KEY_F8` applies the `burn` status in shipped builds with no debug-build guard. | `combat_hud.gd:354-359` |
| HUD-11 | P2 | Layout is hand-computed pixel arithmetic in three places that must agree (`_apply_screen_layout`, `_update_status_row_position`, `_ensure_minimap`); changing a bar height silently misplaces the status row. | `combat_hud.gd:117`, `:177-180`, `:557` |
| HUD-12 | P2 | Every attack frame rebuilds two `StyleBoxFlat` objects via `_apply_bar_style`, allocating during combat. | `combat_hud.gd:500` |
| HUD-13 | P2 | `BAR_BORDER` is declared and never read. | `combat_hud.gd:23` |
| HUD-14 | P2 | Every HUD string is hardcoded English (`"PARRY"`, `"Lv %d"`, `"Branch ahead — "`); none appear in `translations/strings.csv`. | `combat_hud.gd:381,437,543`; `translations/strings.csv:1-26` |

## Target design

### One authored HUD scene, no runtime scaffolding
Add `apps/game/client/scenes/ui/combat_hud.tscn` containing the complete control tree, and make every gameplay scene instance it instead of duplicating a partial `CombatHUD` node. `combat_hud.gd` keeps `@onready` references and drops all seven `_ensure_*` functions. Rejected alternative: keeping the `_ensure_*` fallbacks as a safety net — they are precisely what let three scenes ship without guard indicators for as long as they have.

```
CombatHUD (Control, mouse_filter = IGNORE, PRESET_FULL_RECT)
├── ResourcePanel (MarginContainer, PRESET_TOP_LEFT, margins = HUD_MARGIN)
│   └── VBox (VBoxContainer, separation = 6)
│       ├── HealthBar (ProgressBar)
│       ├── StaminaBar (ProgressBar)
│       ├── ManaBar (ProgressBar)
│       ├── AttackBar (ProgressBar, visible = false)
│       ├── XpBar (ProgressBar)
│       └── LevelLabel (Label, theme_type_variation = "StatValue")
├── StatusRow (HBoxContainer, anchored under ResourcePanel via a spacer in VBox)
├── GuardIndicators (VBoxContainer, PRESET_CENTER_BOTTOM, offset_top = -140)
│   ├── ParryLabel (Label, theme_type_variation = "MenuTitle")
│   ├── ParryBar (ProgressBar)
│   └── BlockBar (ProgressBar)
├── LockReticle (Control, 24×24)
│   └── Reticle (TextureRect, texture = ui/hud_reticle.png)
├── BossBar (VBoxContainer, PRESET_CENTER_TOP, offset_top = 52, visible = false)
│   ├── BossName (Label, theme_type_variation = "MenuTitle")
│   ├── BossHealthBar (ProgressBar, 420×18)
│   └── BossPhaseRow (HBoxContainer, alignment = CENTER)
├── BranchBanner (Label, PRESET_TOP_WIDE, theme_type_variation = "HintText", visible = false)
├── ObjectiveMarker (TextureRect, 18×18, texture = ui/hud_objective.png, visible = false)
├── MinimapAnchor (MarginContainer, PRESET_TOP_RIGHT, margins = HUD_MARGIN)
│   └── Minimap (Control, script = minimap.gd)
└── ControlsHint (Label, PRESET_BOTTOM_WIDE, theme_type_variation = "HintText")
```

`MinimapAnchor` replaces the `size.x - 156.0` arithmetic (HUD-06) and `StatusRow` inside the `VBox` replaces `_update_status_row_position` (HUD-11).

### Status pips with stacks and duration
Replace the bare `TextureRect` per status with a reusable `StatusPip` scene at `apps/game/client/scenes/ui/status_pip.tscn`:

```
StatusPip (Control, 24×28)
├── Icon (TextureRect, 24×24, texture_filter = NEAREST)
├── DurationArc (TextureProgressBar, fill_mode = COUNTER_CLOCKWISE, radial, 24×24)
└── StackLabel (Label, theme_type_variation = "StatValue", font size 10, bottom-right, visible when stacks > 1)
```

`StatusController.get_active_statuses()` already returns `id` and `stacks`; extend each entry with `remaining` and `duration` floats so the arc has a denominator (see [`../statuses-and-buffs.md`](../statuses-and-buffs.md)). `_refresh_status_icons` becomes a diff against a `Dictionary[String, StatusPip]` keyed by status id — reuse existing pips, free only removed ones, and update `StackLabel.text` and `DurationArc.value` in `_process` at 10 Hz rather than freeing the whole row.

Pip colors and glyphs come from the authored atlas defined in [`status_icons_glyphs.md`](status_icons_glyphs.md); the HUD only asks `StatusIconAtlas.get_icon(status_id)` and never picks a fallback color itself.

### Guard indicator tuning from `Guard`
Replace the hardcoded `max_value = 0.18` / `0.65` with values read from the guard node:

```gdscript
func _update_guard_indicators() -> void:
    _parry_bar.max_value = _guard.get_parry_window_duration()
    _block_bar.max_value = _guard.get_block_window_duration()
```

Add `get_parry_window_duration()` and `get_block_window_duration()` to `apps/game/client/scripts/combat/guard.gd`, returning its existing window constants. `ParryLabel` text becomes `tr("HUD_PARRY")`.

### Boss phase count from data
Add `"phaseCount"` to `content/schemas/enemy-definition.v1.json` (`{"type":"integer","minimum":1,"default":1}`) and to each boss JSON under `content/enemies/`. `_resolve_boss_phase_count` becomes:

```gdscript
func _resolve_boss_phase_count(boss: Node) -> int:
    var id := str(boss.call("get_enemy_id")) if boss.has_method("get_enemy_id") else ""
    return maxi(1, int(EnemyCatalog.get_definition(id).get("phaseCount", 1)))
```

Phase pips become `TextureRect`s using two cells of the HUD atlas (`pip_filled`, `pip_empty`), 14×8 px each.

### Camera-relative objective marker
Project the objective into screen space and clamp to a screen-space ellipse, matching what `_update_lock_reticle` already does:

```gdscript
var screen_pos := camera.unproject_position(_objective_world_pos)
var center := get_viewport_rect().size * 0.5
if camera.is_position_behind(_objective_world_pos) or not Rect2(Vector2.ZERO, get_viewport_rect().size).has_point(screen_pos):
    screen_pos = center + (screen_pos - center).normalized() * minf(viewport.x, viewport.y) * 0.42
_objective_marker.position = (screen_pos - _objective_marker.size * 0.5).floor()
_objective_marker.rotation = (screen_pos - center).angle() + PI * 0.5
```

### Vignette on damage only
Track the previous health value and pulse only on a decrease that crosses or stays under the threshold, with a cooldown:

```gdscript
const LOW_HP_RATIO := 0.25
const VIGNETTE_COOLDOWN := 0.8
```

`_on_health_changed` pulses when `current < _last_health` and `current / max_value <= LOW_HP_RATIO` and `_vignette_cooldown <= 0.0`.

### Input-device-reactive hints
`InputGlyphService` gains a `device_family_changed` signal (see [`input_glyphs.md`](input_glyphs.md)). `combat_hud.gd` connects it to `_rebuild_controls_hint()`. Add `hint_visible` driven by a new `AccessibilitySettings.show_control_hints` bool (default `true`), surfaced as a checkbox in the settings overlay, and auto-hide the strip after 60 s of play in a session where the player has already used all four actions once.

### Cached bar styles
Build the four attack-phase styleboxes once in `_ready()` into `Dictionary[String, StyleBoxFlat]` and swap with `add_theme_stylebox_override("fill", _attack_styles[phase])`, removing the per-frame allocation.

### Localization
Add keys to `apps/game/client/translations/strings.csv`: `HUD_PARRY`, `HUD_LEVEL` (`Lv %d`), `HUD_BRANCH_AHEAD`, `HUD_BRANCH_REWARD` (`%d reward path(s)`), `HUD_BRANCH_DANGER` (`%d danger path(s)`), `HUD_BOSS_FALLBACK` (`Boss`). Use `tr()` at every site.

## Work plan
1. **Authored HUD scene** — add `scenes/ui/combat_hud.tscn` with the tree above; repoint `castle_run.tscn`, `hub.tscn`, `forgotten_castle_slice.tscn`, `combat_arena.tscn`, and `waves_run.gd:270-277` to instance it; delete `_ensure_mana_bar`, `_ensure_attack_bar`, `_ensure_progression_widgets`, `_ensure_controls_hint`, `_ensure_minimap`, `_ensure_branch_banner`, `_ensure_objective_marker`, `_ensure_boss_bar`, `_apply_screen_layout`, `_update_status_row_position` (HUD-01, HUD-02, HUD-06, HUD-11).
2. **Guard tuning** — add `get_parry_window_duration()` / `get_block_window_duration()` to `guard.gd`; consume them in `_update_guard_indicators` (HUD-01).
3. **Status pips** — add `scenes/ui/status_pip.tscn`; extend `StatusController.get_active_statuses()` with `remaining` / `duration`; rewrite `_refresh_status_icons` as a keyed diff (HUD-03).
4. **Boss data** — add `phaseCount` to `content/schemas/enemy-definition.v1.json` and every boss JSON; rewrite `_resolve_boss_phase_count`; convert pips to atlas `TextureRect`s (HUD-04, HUD-09).
5. **Objective marker** — camera-relative projection plus rotation; authored `hud_objective.png` (HUD-05, HUD-09).
6. **Vignette** — add `_last_health`, `_vignette_cooldown`, `LOW_HP_RATIO`, `VIGNETTE_COOLDOWN` (HUD-07).
7. **Hints** — connect `InputGlyphService.device_family_changed`; add `AccessibilitySettings.show_control_hints` plus its settings checkbox (HUD-08).
8. **Cleanup** — cache attack styleboxes, gate `KEY_F8` behind `OS.is_debug_build()`, delete `BAR_BORDER`, route all strings through `tr()` (HUD-10, HUD-12, HUD-13, HUD-14).

## Data and schema changes
- `content/schemas/enemy-definition.v1.json`: add `"phaseCount": {"type": "integer", "minimum": 1}`.
- Boss definitions under `content/enemies/` gain `phaseCount` (`boss_castle_knight` 2, final boss 3, matching today's inferred values so behavior is unchanged on landing).
- `apps/game/client/translations/strings.csv`: add `HUD_PARRY`, `HUD_LEVEL`, `HUD_BRANCH_AHEAD`, `HUD_BRANCH_REWARD`, `HUD_BRANCH_DANGER`, `HUD_BOSS_FALLBACK`.
- `AccessibilitySettings` gains `show_control_hints: bool = true`, persisted under the existing `accessibility` meta key (`accessibility_settings.gd:26-32`). This is a meta-block key, not run save data, so no `save_migrator.gd` version bump is required.
- New assets: `assets/ui/hud_reticle.png` (24×24), `assets/ui/hud_objective.png` (18×18), `assets/ui/hud_pips.png` (2 cells of 14×8), all `filter=false`, `mipmaps=false`.

## Acceptance criteria
- [ ] `scenes/ui/combat_hud.tscn` exists and every scene that shows a HUD instances it.
- [ ] `combat_hud.gd` contains no function whose name starts with `_ensure_`.
- [ ] Parry and block bars appear in the hub, castle run, waves run, and slice scenes.
- [ ] A lock-on reticle appears in all four scenes above.
- [ ] Applying two stacks of `burn` renders `x2` on the pip and a duration arc that empties to zero as the status expires.
- [ ] Removing one of two active statuses does not recreate the surviving pip's node.
- [ ] Parry bar `max_value` equals `guard.gd`'s parry window constant, not `0.18`.
- [ ] A boss whose JSON declares `phaseCount: 4` shows four pips.
- [ ] With the camera rotated 180°, the objective marker sits on the screen edge nearest the objective.
- [ ] Healing while under 25 % HP does not pulse the vignette; taking a hit does, at most once per `0.8` s.
- [ ] Connecting a gamepad while the HUD is visible switches the controls hint to controller glyphs without a scene change.
- [ ] Unchecking "Show control hints" in settings hides `ControlsHint` and the state survives a restart.
- [ ] `KEY_F8` does nothing in an exported release build.
- [ ] `combat_hud.gd` contains no bare English string literal assigned to a `.text` property.

## Validation
Extend `apps/game/client/scripts/validation/suites/m5_suite.gd` (which already asserts on `combat_hud.gd` at `:299-305`):

| Test id | Assertion |
|---|---|
| `hud.scene_exists` | `ResourceLoader.exists("res://scenes/ui/combat_hud.tscn")` |
| `hud.no_ensure_functions` | `combat_hud.gd` contains no `func _ensure_` |
| `hud.guard_nodes_present` | instancing `combat_hud.tscn` yields non-null `GuardIndicators/ParryBar`, `BlockBar`, `ParryLabel` |
| `hud.reticle_present` | the same instance yields a non-null `LockReticle` |
| `hud.scene_instanced_everywhere` | `castle_run.tscn`, `hub.tscn`, `forgotten_castle_slice.tscn`, `combat_arena.tscn` each contain `combat_hud.tscn`, and `waves_run.gd` contains `combat_hud.tscn` |
| `hud.guard_window_from_guard` | `combat_hud.gd` contains no literal `0.18` and calls `get_parry_window_duration` |
| `hud.status_pip_stacks` | drive `StatusController.debug_apply("burn")` twice, then assert the `StatusRow` child count is 1 and its `StackLabel.text == "x2"` |
| `hud.status_pip_reuse` | record the pip's `get_instance_id()`, apply a second distinct status, assert the first id is unchanged |
| `hud.boss_phase_from_data` | a stub definition with `phaseCount: 4` makes `_resolve_boss_phase_count` return 4 |
| `hud.objective_camera_relative` | with the camera yawed 180°, the marker's screen position lies on the opposite side of center from the unrotated case |
| `hud.vignette_not_on_heal` | count `pulse_damage_vignette` calls across `heal(1.0)` at 10 % HP; expect 0 |
| `hud.hint_rebuilds_on_device` | emitting `InputGlyphService.device_family_changed` changes `ControlsHint.text` |
| `hud.debug_key_guarded` | `combat_hud.gd` contains `OS.is_debug_build()` within 6 lines of `KEY_F8` |
| `hud.strings_localized` | every `tr("HUD_` key used in `combat_hud.gd` resolves to a value different from the key |
| `hud.no_dead_constants` | `combat_hud.gd` does not contain `BAR_BORDER` |

## Related
- Existing behavior: [`../existing_codebase/ui/combat_hud.md`](../existing_codebase/ui/combat_hud.md)
- [`minimap.md`](minimap.md) · [`status_icons_glyphs.md`](status_icons_glyphs.md) · [`input_glyphs.md`](input_glyphs.md) · [`game_ui_skin.md`](game_ui_skin.md) · [`waves_hud.md`](waves_hud.md)
- [`../guard.md`](../guard.md) · [`../statuses-and-buffs.md`](../statuses-and-buffs.md) · [`../bosses.md`](../bosses.md)

# Combat HUD

The combat HUD is the only in-world gameplay overlay: player resource bars, attack-phase bar, XP/level readout, status icon row, lock-on reticle, guard indicators, boss bar, minimap host, branch banner, objective marker, and a permanent controls hint. It is on the live play path in every gameplay scene. Roughly half of its control tree is created in `_ready()` at runtime rather than authored in the scene, so different scenes ship different subsets of the authored nodes.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/combat_hud.gd` | `extends Control` — 605 lines, whole HUD |
| `apps/game/client/scripts/ui/training_dummy_health_bar.gd` | `extends EnemyHealthBar`, overrides `_on_died()` with `pass` so respawning dummies keep their bar |
| `apps/game/client/scenes/dungeon/castle_run.tscn:21-84` | `CombatHUD` node: `Margin/VBox/{HealthBar,StaminaBar}`, `LockReticle/{Reticle,ReticleInner}` |
| `apps/game/client/scenes/debug/combat_arena.tscn:118-228` | the only scene with `GuardIndicators/{ParryLabel,ParryBar,BlockBar}` |
| `apps/game/client/scenes/hub/hub.tscn:269-304` | `CombatHUD` with `Margin/VBox/{HealthBar,StaminaBar}` only |
| `apps/game/client/scenes/dungeon/forgotten_castle_slice.tscn:101-141` | same two authored bars |

`waves_run.gd:270-277` builds its `CombatHUD` from a bare `Control` plus `set_script`, so the waves run has no authored child nodes at all.

## How it works

### Entry point
`_ready()` (`combat_hud.gd:60-96`) runs in fixed order:
1. `GameUISkin.apply_pixel_theme(self)`.
2. Fetches `Margin/VBox/HealthBar`, `StaminaBar`, `ManaBar`, `AttackBar`, `XpBar`, `LevelLabel` with `get_node_or_null` — every one may be `null`.
3. `_apply_screen_layout()` (`:109`) forces `Margin` to `PRESET_TOP_LEFT` at `HUD_MARGIN = 20.0` and sets `offset_right = 20 + BAR_WIDTH(280)`, `offset_bottom = 20 + 22 + 16 + 16 + 10 + 34`.
4. `_ensure_mana_bar()` (`:140`) and `_ensure_attack_bar()` (`:157`) create missing `ProgressBar`s; the mana bar is inserted directly after `StaminaBar`.
5. `_style_resource_bars()` (`:125`) sets `custom_minimum_size` and calls `GameUISkin.style_progress_bar`.
6. `_ensure_progression_widgets()` (`:206`) creates `XpBar` (`280×12`) and `LevelLabel`.
7. `_ensure_controls_hint()` (`:222`) creates a permanent bottom-anchored `Label` (see below).
8. `_ensure_minimap()` (`:552`), `_ensure_objective_marker()` (`:574`), `_ensure_boss_bar()` (`:329`).
9. Binds `player_path` → `Guard`, `WeaponController`, `StatusController`, and resources; binds `lock_on_path` → `lock_changed`; connects `ProgressionService.progression_changed`.

### Bar geometry and colors
`combat_hud.gd:8-23`: `BAR_WIDTH 280.0`, heights `HEALTH 22.0 / STAMINA 16.0 / MANA 16.0 / ATTACK 10.0`, `HUD_MARGIN 20.0`. Fills: health `(0.82,0.14,0.12)`, stamina `(0.22,0.78,0.28)`, mana `(0.22,0.42,0.92)`, attack startup `(0.95,0.55,0.18)` / active `(0.85,0.18,0.12)` / recovery `(0.45,0.45,0.48)`. `BAR_BORDER` (`:23`) is declared and never read — `style_progress_bar` uses `GameUISkin.FRAME_BORDER` instead.

### Resource binding
`_bind_player_resources()` (`:362`) connects `Health.health_changed`, `Stamina.stamina_changed`, `Mana.mana_changed`, seeding each with `Health.MAX_HEALTH` / `Stamina.MAX_STAMINA` / `Mana.MAX_MANA`. `_on_health_changed` (`:456`) additionally calls `PixelDioramaViewport.pulse_damage_vignette(0.22)` whenever the ratio is at or below `0.25` — on every health change, including heals and every tick of a damage-over-time status.

### Attack-phase bar
`_update_attack_bar()` (`:480`) runs every frame from `_process`. It reads `_weapon_controller.get("is_attacking")`, then `get_attack_phase_progress()` for a `{"progress": float, "phase": String}` dictionary, and rebuilds the bar stylebox each frame via `_apply_bar_style` when the phase color changes.

### Status row
`_ensure_status_row()` (`:99`) creates an `HBoxContainer` named `StatusRow` and positions it manually at `y = 20 + 22 + 16 + 16 + 10 + 22` (`_update_status_row_position`, `:174`). `_refresh_status_icons()` (`:183`) frees all children and rebuilds one `TextureRect` per entry from `StatusController.get_active_statuses()`, sized `22×22`, textured by `StatusIconAtlas.get_icon(status_id, Color.from_string(def.get("iconColor", "#ffffff")))`, with `tooltip_text = "<name> x<stacks>"`. Stack count and remaining duration are not drawn — they exist only in the tooltip, which is unreachable while the mouse is captured during gameplay.

`_unhandled_input` (`:354`) applies the `burn` status on `KEY_F8` via `StatusController.debug_apply`, unconditionally, in release builds.

### Controls hint
`_ensure_controls_hint()` (`:222`) creates a `Label` anchored `PRESET_BOTTOM_WIDE` at `offset_top = -32`, text built from `InputGlyphService.format_action_hint` for `dodge`, `jump`, `lock_on`, `inventory` joined by `"  |  "` — for example `Dash Space  |  Jump F  |  Lock Tab  |  Inventory I`. It is built once in `_ready()` and never hidden, refreshed, or rebuilt when a controller is connected mid-session.

### Lock-on reticle
`_update_lock_reticle()` (`:387`) runs every frame. It requires an authored `LockReticle` node (present only in `castle_run.tscn` and `combat_arena.tscn`), reads `_lock_on.get("is_locked")` and `current_target`, projects `LockOn.get_target_aim_point(target)` with `Camera3D.unproject_position`, lerps alpha toward `1.0` on-screen or `0.35` off-screen at rate `0.22`, clamps off-screen positions to a circle of radius `min(viewport.x, viewport.y) * 0.42` around center, and floors the final position to whole pixels.

### Guard indicators
`_update_guard_indicators()` (`:418`) needs all three of `GuardIndicators/ParryBar`, `BlockBar`, `ParryLabel`; if any is missing it returns immediately. It reads `Guard.get_parry_time_remaining()` / `get_block_time_remaining()` and hardcodes `max_value = 0.18` for parry and `0.65` for block. The label text is the literal `"PARRY"`.

### Boss bar
`_ensure_boss_bar()` (`:329`) builds `BossBar` (`VBoxContainer`, `PRESET_CENTER_TOP`, `offset_top = 52`, `420×48`) containing a name `Label`, a `420×18` `ProgressBar`, and a phase `HBoxContainer`. `bind_boss(boss)` (`:251`) resolves `Health`, connects `health_changed`, `phase_changed`, `boss_defeated`, `enemy_died`, and titles the bar from `EnemyCatalog.get_definition(get_enemy_id()).title`. `_resolve_boss_phase_count()` (`:310`) returns `3` when the boss script's `resource_path` contains `final_boss`, else `2`. `_refresh_boss_phase_pips()` (`:316`) draws `14×8` `ColorRect` pips, gold `(0.95,0.78,0.25)` when `i < _boss_current_phase`, else dark `(0.2,0.18,0.16)`.

### Minimap, branch banner, objective marker
- `_ensure_minimap()` (`:552`) instantiates `minimap.gd` and positions it at `Vector2(size.x - 156.0, 20.0)`. `size.x` is read in `_ready()` before the first layout pass.
- `configure_minimap`, `mark_room_visited`, `set_current_room`, `set_branch_previews` (`:508-544`) are called only from `castle_run.gd:107-149`.
- `set_branch_previews(hints)` (`:524`) counts `hint == "reward"` versus everything else and writes `"Branch ahead — N reward path(s), M danger path(s)"` into a top-anchored `Label`.
- `_update_objective_marker()` (`:588`) hides the marker when the target is within `2.0` m (`length_squared() < 4.0`), otherwise places an `18×18` gold `ColorRect` on a fixed `120 px` radius circle around screen center along `Vector2(to_target.x, -to_target.z)`. The direction ignores camera yaw, so the arrow points at a world-space direction rather than a screen-space one.

## Contracts
- Node-name contract for authored children: `Margin/VBox/{HealthBar,StaminaBar,ManaBar,AttackBar,XpBar,LevelLabel}`, `LockReticle`, `GuardIndicators/{ParryBar,BlockBar,ParryLabel}`, `StatusRow`, `ControlsHint`, `Minimap`, `BranchBanner`, `ObjectiveMarker`, `BossBar`.
- `@export var player_path` and `lock_on_path` must be set in the scene; `castle_run.gd:15` and `forgotten_castle_slice.gd:17` locate the HUD by `NodePath("CombatHUD")`.
- Player child-node contract: `Health`, `Stamina`, `Mana`, `Guard`, `WeaponController`, `StatusController`.
- `Guard` must expose `get_parry_time_remaining()` and `get_block_time_remaining()`; `WeaponController` must expose the `is_attacking` property and `get_attack_phase_progress()`.
- Boss contract: a `Health` child, optional `phase_changed(int)`, `boss_defeated`, `enemy_died` signals, and `get_enemy_id()`.
- Autoload dependencies: `ProgressionService`, `StatusCatalog`, `EnemyCatalog`, `PixelDioramaViewport`, `LockOn` (static `get_target_aim_point`).
- Public API used by other systems: `bind_boss`, `unbind_boss`, `configure_minimap`, `mark_room_visited`, `set_current_room`, `set_branch_previews`, `set_objective_world_position`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Health / stamina / mana bars | IMPLEMENTED | `combat_hud.gd:362-374`, `:456-477` |
| Attack-phase bar | IMPLEMENTED | `combat_hud.gd:480-500` |
| XP bar and level label | IMPLEMENTED | `combat_hud.gd:377-384` |
| Status icon row | PLACEHOLDER — icons are procedurally drawn circles/diamonds/bolts from `status_icon_atlas.gd`, not authored art | `combat_hud.gd:195-198`; `status_icon_atlas.gd:31-46` |
| Status stack count and duration | ABSENT from the drawn HUD — only in `tooltip_text`, unreachable while the mouse is captured | `combat_hud.gd:202` |
| Guard indicators | PARTIAL — only `scenes/debug/combat_arena.tscn` authors `GuardIndicators`, so parry/block feedback never appears in castle, hub, waves, or slice scenes | `combat_hud.gd:418-425`; grep `GuardIndicators` matches only `combat_arena.tscn:163` |
| Lock-on reticle | PARTIAL — needs an authored `LockReticle`; present in `castle_run.tscn:61` and `combat_arena.tscn:204`, absent in `hub.tscn`, `forgotten_castle_slice.tscn`, and the waves HUD | `combat_hud.gd:387-392` |
| Boss bar phase count | FAKE — derived from whether the script path contains `final_boss`, not from boss data | `combat_hud.gd:310-313` |
| Boss phase pips | PLACEHOLDER — `14×8` `ColorRect` rectangles | `combat_hud.gd:322-326` |
| Objective marker | PLACEHOLDER — an `18×18` gold `ColorRect` on a fixed-radius ring, direction not camera-relative | `combat_hud.gd:581-584`, `:601-604` |
| Branch banner | PARTIAL — text-only counts, no per-path iconography, no styling call | `combat_hud.gd:524-544`, `:561-571` |
| Minimap in hub and waves | PARTIAL — the `Minimap` control is created in every scene but only `castle_run.gd` ever calls `configure_minimap`, so it draws nothing elsewhere | `combat_hud.gd:552-558`; `minimap.gd:48-49`; only caller `castle_run.gd:107` |
| Minimap anchoring | BROKEN — positioned from `size.x` during `_ready()`, before the first layout pass, and never repositioned on viewport resize | `combat_hud.gd:557` |
| Controls hint strip | IMPLEMENTED but permanent — never hidden and never rebuilt when the input device changes | `combat_hud.gd:222-241` |
| Damage vignette trigger | PARTIAL — fires on every health change at or below 25 %, including heals and DoT ticks | `combat_hud.gd:461-463` |
| `KEY_F8` debug status injection | PARTIAL — active in release builds, not gated on `OS.is_debug_build()` | `combat_hud.gd:354-359` |
| `BAR_BORDER` constant | STUB — declared, never read | `combat_hud.gd:23` |
| Localization | ABSENT — all strings are hardcoded English; `"PARRY"`, `"Lv %d"`, `"Branch ahead — ..."` are not in `apps/game/client/translations/strings.csv` | `combat_hud.gd:381,437,543`; `translations/strings.csv:1-26` |

## Related
- Improvement plan: [`../actual_improvements/ui/combat_hud.md`](../actual_improvements/ui/combat_hud.md)
- [`minimap.md`](minimap.md) · [`status_icon_atlas.md`](status_icon_atlas.md) · [`input_glyphs.md`](input_glyphs.md) · [`enemy_health_bar.md`](enemy_health_bar.md) · [`waves_hud.md`](waves_hud.md)
- [`../stamina-mana.md`](../stamina-mana.md) · [`../guard.md`](../guard.md) · [`../bosses.md`](../bosses.md) · [`../lock-on.md`](../lock-on.md)

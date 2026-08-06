# Combat HUD

## Status: FINISHED

The combat HUD is the in-world gameplay overlay: resource bars, attack-phase bar, XP/level, status pips, lock-on reticle, guard indicators, boss bar, minimap host, branch banner, objective marker, quest tracker, and controls hint. Every gameplay scene instances the authored `scenes/ui/combat_hud.tscn`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scenes/ui/combat_hud.tscn` | Full HUD control tree (entry scene) |
| `apps/game/client/scripts/ui/combat_hud.gd` | `extends Control` â€” binds player, drives all HUD widgets |
| `apps/game/client/scenes/ui/status_pip.tscn` | Reusable status icon with stack label + duration arc |
| `apps/game/client/scripts/ui/status_pip.gd` | `StatusPip` â€” `configure`, `set_stacks`, `update_timer` |
| `apps/game/client/scripts/ui/hud_icon_atlas.gd` | Reticle/objective textures + boss pip atlas regions |
| `apps/game/client/scripts/ui/minimap.gd` | Minimap draw logic (child of `MinimapAnchor`) |
| `apps/game/client/scripts/ui/input_glyph_watcher.gd` | Autoload â€” emits `device_family_changed` |
| `content/ui/hud_atlas.json` | Pip region manifest for `hud_pips.png` |
| `apps/game/client/assets/ui/hud_reticle.png` | 24Ã—24 lock-on reticle |
| `apps/game/client/assets/ui/hud_objective.png` | 18Ã—18 objective chevron |
| `apps/game/client/assets/ui/hud_pips.png` | 14Ã—8 filled/empty boss phase cells |

Scene consumers: `castle_run.tscn`, `hub.tscn`, `forgotten_castle_slice.tscn`, `combat_arena.tscn` instance `combat_hud.tscn`; `waves_run.gd:285-295` instantiates the same scene at runtime.

## How it works

### Entry point
`_ready()` (`combat_hud.gd:79-108`) applies `GameUISkin.apply_pixel_theme`, styles bars, caches attack-phase styleboxes, rebuilds the controls hint, connects `InputGlyphWatcher.device_family_changed` and `AccessibilitySettings.settings_changed`, then binds `player_path` resources and `lock_on_path`.

### Node tree (authored)
```
CombatHUD
â”œâ”€â”€ ResourcePanel/VBox/{HealthBar,StaminaBar,ManaBar,AttackBar,XpBar,LevelLabel,StatusRow}
â”œâ”€â”€ GuardIndicators/{ParryLabel,ParryBar,BlockBar}
â”œâ”€â”€ LockReticle/Reticle (TextureRect â†’ hud_reticle.png)
â”œâ”€â”€ BossBar/{BossName,BossHealthBar,BossPhaseRow}
â”œâ”€â”€ BranchBanner
â”œâ”€â”€ ObjectiveMarker (TextureRect â†’ hud_objective.png)
â”œâ”€â”€ MinimapAnchor/Minimap (minimap.gd)
â”œâ”€â”€ ControlsHint
â”œâ”€â”€ QuestTrackerUI (instanced)
â”œâ”€â”€ WarningBanner
â””â”€â”€ RespawnOutcomeOverlay/Panel/...
```

### Resource binding
`_bind_player_resources()` connects `Health`, `Stamina`, `Mana` signals. `_on_health_changed` (`combat_hud.gd:438-452`) pulses `PixelDioramaViewport.pulse_screen(DAMAGE)` only when `current < _last_health` and ratio â‰¤ `LOW_HP_RATIO` (0.25), with `VIGNETTE_COOLDOWN` (0.8 s).

### Status pips
`_refresh_status_icons()` diffs `_status_pips: Dictionary` against `StatusController.get_active_statuses()` (entries include `id`, `stacks`, `remaining`, `duration`). Reuses `StatusPip` nodes; `_update_status_timers` refreshes arcs at 10 Hz (`STATUS_REFRESH_INTERVAL` 0.1 s).

### Guard indicators
`_update_guard_indicators()` reads `get_parry_time_remaining()` / `get_block_time_remaining()` and sets bar `max_value` from `get_parry_window_duration()` / `get_block_window_duration()` on `guard.gd` (`PARRY_WINDOW` 0.18, `BLOCK_DISPLAY_MAX` 9.99). Label text: `tr("HUD_PARRY")`.

### Lock-on reticle
`_update_lock_reticle()` projects aim point, lerps alpha, clamps off-screen to radius `min(viewport) * 0.42`.

### Boss bar
`bind_boss(boss)` connects health/phase signals. `_resolve_boss_phase_count()` reads `EnemyCatalog.get_definition(id).phaseCount` (default 1). `_refresh_boss_phase_pips()` uses `HudIconAtlas.get_pip_filled()` / `get_pip_empty()`.

### Objective marker
`_update_objective_marker()` uses `camera.unproject_position`, clamps to screen edge when behind/off-screen, sets `rotation` toward objective.

### Controls hint
`_rebuild_controls_hint()` formats dodge/jump/lock_on/inventory via `InputGlyphService`. Visibility follows `AccessibilitySettings.show_control_hints`; auto-hides after 60 s once all four actions were pressed (`HINT_AUTO_HIDE_SECONDS`).

### Public API
`bind_boss`, `unbind_boss`, `configure_minimap`, `mark_room_visited`, `set_current_room`, `set_branch_previews`, `set_objective_world_position`, `show_run_warning`, `show_respawn_outcome`.

## Contracts
- `@export var player_path` and `lock_on_path` set by parent scene.
- Player children: `Health`, `Stamina`, `Mana`, `Guard`, `WeaponController`, `StatusController`.
- Boss: `Health`, optional `phase_changed`, `boss_defeated`, `enemy_died`, `get_enemy_id()`.
- Autoloads: `ProgressionService`, `StatusCatalog`, `EnemyCatalog`, `PixelDioramaViewport`, `LockOn`, `InputGlyphWatcher`, `AccessibilitySettings`, `AudioDirector`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Authored HUD scene | IMPLEMENTED | `scenes/ui/combat_hud.tscn`; no `_ensure_*` in `combat_hud.gd` |
| Health / stamina / mana / attack bars | IMPLEMENTED | `combat_hud.gd:438-477`, `:486-503` |
| XP / level | IMPLEMENTED | `tr("HUD_LEVEL")` at `:421-426` |
| Status pips (stacks + duration) | IMPLEMENTED | `status_pip.tscn`; `_refresh_status_icons` keyed diff |
| Guard indicators (all scenes) | IMPLEMENTED | `GuardIndicators` in `combat_hud.tscn`; guard window from `guard.gd` |
| Lock-on reticle (all scenes) | IMPLEMENTED | `LockReticle` + `hud_reticle.png` |
| Boss phase count | IMPLEMENTED | `phaseCount` in `content/bosses/*.json`; `_resolve_boss_phase_count` |
| Boss phase pips | IMPLEMENTED | `hud_pips.png` via `HudIconAtlas` |
| Objective marker | IMPLEMENTED | Camera-relative `unproject_position` + `hud_objective.png` |
| Minimap anchor | IMPLEMENTED | `MinimapAnchor` top-right; no frame-one `size.x` math |
| Branch banner | IMPLEMENTED | Localized `HUD_BRANCH_*` keys |
| Damage vignette | IMPLEMENTED | Damage-only with cooldown |
| Controls hint | IMPLEMENTED | Device-change rebuild + settings toggle + auto-hide |
| Debug `KEY_F8` burn | IMPLEMENTED | `OS.is_debug_build()` guard |
| Localization | IMPLEMENTED | `translations/strings.csv` `HUD_*` keys |

## Related
- Improvement plan: [`../actual_improvements/ui/combat_hud.md`](../actual_improvements/ui/combat_hud.md) - **FINISHED**
- [`minimap.md`](minimap.md) Â· [`status_icon_atlas.md`](status_icon_atlas.md) Â· [`input_glyphs.md`](input_glyphs.md) Â· [`enemy_health_bar.md`](enemy_health_bar.md)
- [`../stamina-mana.md`](../stamina-mana.md) Â· [`../guard.md`](../guard.md) Â· [`../bosses.md`](../bosses.md) Â· [`../lock-on.md`](../lock-on.md)

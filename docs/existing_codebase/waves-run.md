# Waves run

Umbral Waves is a separate run mode: lobby with six chests, then up to 50 combat waves in a procedural outdoors arena. Wave composition, chest pools, and milestones are authored in `content/waves/umbral_waves.json` (schema `waves-definition.v1.json`). On the live play path from the hub Umbral Waves portal. `umbral_endless_menu.gd` belongs to endless dungeon mode, not waves.

## Files

| Path | Role |
|------|------|
| `content/waves/umbral_waves.json` | Milestones, enemy formula, roster unlocks, lobby chest tables |
| `content/schemas/waves-definition.v1.json` | JSON schema for wave definitions |
| `apps/game/client/scripts/dungeon/waves_run.gd` | Scene controller: lobby, walls, spawn, death, victory |
| `apps/game/client/scripts/dungeon/waves_run_service.gd` | Autoload state: chests, inventory, wave data load, save |
| `apps/game/client/scripts/dungeon/waves_chest.gd` | Lobby chest interactable |
| `apps/game/client/scripts/dungeon/waves_outdoors_diorama.gd` | Procedural 210Ã—210 outskirts + 34 arena |
| `apps/game/client/scenes/dungeon/waves_run.tscn` | Root script + light + Player (geometry is code-built) |
| `apps/game/client/scripts/ui/umbral_waves_menu.gd` | Hub portal: new / continue |
| `apps/game/client/scripts/ui/umbral_endless_menu.gd` | Endless portal menu (not waves) |
| `apps/game/client/scripts/ui/waves_run_ui.gd` | In-run lobby/combat/prep/reward UI |
| `apps/game/client/scripts/app/run_flow.gd` | `start_waves_run`, `complete_waves_run`, `on_waves_failed`, `quit_waves_run` |
| `apps/game/client/scripts/app/run_lifecycle.gd` | `build_results` for waves outcomes |
| `apps/game/client/scripts/ui/results_screen.gd` | Waves Cleared / Waves Failed titles |

## How it works

### Entry

`umbral_waves_menu.gd` â†’ `RunFlow.start_waves_run` / `continue_waves_run` (`hub.gd:67-68`, `:303-310`). `_start_waves_run` sets `run_mode = waves`, calls `WavesRunService.begin_new_run` or `restore_from_save`, loads `waves_run.tscn` (`run_flow.gd:907-926`). Status copy: "Open 6 chests, survive 50 waves" (`umbral_waves_menu.gd:59`).

### Lobby and combat (`waves_run.gd`)

- Six chests on a ring (`:100-161`); `WavesRunService.open_chest` rolls rarity/item into isolated `waves_inventory` from JSON chest defs (`waves_run_service.gd:113-154`).
- Ready â†’ combat walls (34Ã—34, `ARENA_HALF`) â†’ `_start_wave`.
- Milestones `[5, 10, 20, 50]` from `umbral_waves.json` (`waves_run_service.gd`): after clear, 5s prep via `enter_prep`, then advance.
- Wave 50 clear â†’ reward pick (â‰¤3 items, confirm requires â‰¥1 when inventory non-empty) â†’ `RunFlow.complete_waves_run`.
- Death â†’ 1.5s â†’ `RunFlow.on_waves_failed` (`waves_run.gd:376-379`).

### Wave data â€” JSON-driven

`WavesRunService` loads `content/waves/umbral_waves.json` on ready (`waves_run_service.gd:29-46`). `get_enemies_for_wave` (`:288-305`):

| Rule | Value (default JSON) |
|------|----------------------|
| Count | `mini(base + (wave >> 1) * per_half_wave, cap)` + `milestone_bonus` on milestones |
| Roster | `base_roster`; `roster_unlocks` add `castle_knight` at wave â‰¥ 5 |
| Milestone add | Random of `milestone_bosses` |

`waves_run.gd:5-12` `ENEMY_SCENES` maps castle ids + `boss_castle_knight` + `miniboss_castle_captain` â†’ `castle_knight.tscn`. Boss/miniboss ids call `set_catalog_id` before spawn (`:186-192`) so `miniboss_castle_captain` uses 350 HP from `content/bosses/miniboss_castle_captain.json`.

Chest types, labels, rarity weights, and item pools are in `umbral_waves.json` `chests` array.

### Outcomes and results honesty

| Path | Behaviour | Honesty |
|------|-----------|---------|
| `complete_waves_run` (`run_flow.gd:1081-1113`) | Grants `WAVES_COMPLETION_XP` (500), adds chosen loot, `RunLifecycle.build_results` | `levels_gained` from `grant_xp` via `build_results` |
| `on_waves_failed` (`:1116-1148`) | Empty loot, 0 XP, `OUTCOME_WAVES_FAILED` | Includes `run_relics_lost` from `_had_run_relics()` |
| `quit_waves_run` (`:929-948`) | Milestone keep-fraction transfer â†’ hub | No results screen |
| `results_screen.gd` | `OUTCOME_WAVES_COMPLETE` â†’ "Waves Cleared"; `OUTCOME_WAVES_FAILED` â†’ "Waves Failed" | Level-up line when `levels_gained > 0` |

### Diorama

`waves_outdoors_diorama.gd` builds floor, castle backdrop, grass/trees/birds; `VisualLighting.apply_waves_outdoors`. Birds animated from `waves_run`.

## Contracts

| Contract | Detail |
|----------|--------|
| Autoload | `WavesRunService` (`project.godot`) |
| Group | `"waves_run"` |
| Save | `LocalSave` waves active run schema v1 via service `74-85` |
| Content | `content/waves/umbral_waves.json`; validated by `waves-definition.v1.json` |
| Enemy ids | Must exist in `ENEMY_SCENES`; boss/miniboss use `set_catalog_id` |
| Results keys | `RunLifecycle.build_results` (parity with escape/death) |
| Prep | `prep_active` only during post-milestone countdown (`enter_prep` / `leave_prep`) |

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Lobby â†’ 50 waves â†’ reward pick | IMPLEMENTED | `waves_run.gd` + service |
| Wave composition | IMPLEMENTED | `content/waves/umbral_waves.json` + `get_enemies_for_wave` |
| Milestone `miniboss_castle_captain` | IMPLEMENTED | `ENEMY_SCENES` + `set_catalog_id` (`waves_run.gd:11-12`, `:186-192`) |
| Completion XP / levels | IMPLEMENTED | `run_flow.gd:1086-1105` |
| Failure results schema | IMPLEMENTED | `run_relics_lost` in `on_waves_failed` (`:1136`) |
| Results titles | IMPLEMENTED | `results_screen.gd:94-97` |
| Reward confirm gate | IMPLEMENTED | `waves_run_ui.gd` confirm disabled + hint |
| Outdoors diorama | IMPLEMENTED | Procedural, seeded |
| `umbral_endless_menu` | N/A (other mode) | Endless skip-floor UI only |

## Related

- Improvement plan: [`../actual_improvements/waves-run.md`](../actual_improvements/waves-run.md) - **FINISHED**
- [`run-flow.md`](run-flow.md), [`ui/waves_hud.md`](ui/waves_hud.md), [`ui/run_outcome.md`](ui/run_outcome.md), [`enemies.md`](enemies.md), [`bosses.md`](bosses.md)

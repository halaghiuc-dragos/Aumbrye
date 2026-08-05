# Waves run

Umbral Waves is a separate run mode: lobby with six chests, then up to 50 combat waves in a procedural outdoors arena. Wave composition, chest pools, and milestones are **formula/hardcoded in GDScript** — there is no wave-definition JSON. On the live play path from the hub Umbral Waves portal. `umbral_endless_menu.gd` belongs to endless dungeon mode, not waves.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/waves_run.gd` | Scene controller: lobby, walls, spawn, death, victory |
| `apps/game/client/scripts/dungeon/waves_run_service.gd` | Autoload state: chests, inventory, wave formula, save |
| `apps/game/client/scripts/dungeon/waves_chest.gd` | Lobby chest interactable |
| `apps/game/client/scripts/dungeon/waves_outdoors_diorama.gd` | Procedural 210×210 outskirts + 34 arena |
| `apps/game/client/scenes/dungeon/waves_run.tscn` | Root script + light + Player (geometry is code-built) |
| `apps/game/client/scripts/ui/umbral_waves_menu.gd` | Hub portal: new / continue |
| `apps/game/client/scripts/ui/umbral_endless_menu.gd` | Endless portal menu (not waves) |
| `apps/game/client/scripts/ui/waves_run_ui.gd` | In-run lobby/combat/prep/reward UI |
| `apps/game/client/scripts/app/run_flow.gd` | `start_waves_run`, `complete_waves_run`, `on_waves_failed`, `quit_waves_run` |

## How it works

### Entry

`umbral_waves_menu.gd` → `RunFlow.start_waves_run` / `continue_waves_run` (`hub.gd:67-68`, `:303-310`). `_start_waves_run` sets `run_mode = waves`, calls `WavesRunService.begin_new_run` or `restore_from_save`, loads `waves_run.tscn` (`run_flow.gd:907-926`). Status copy: "Open 6 chests, survive 50 waves" (`umbral_waves_menu.gd:59`).

### Lobby and combat (`waves_run.gd`)

- Six chests on a ring (`:100-161`); `WavesRunService.open_chest` rolls rarity/item into isolated `waves_inventory` (`waves_run_service.gd:113-154`).
- Ready → combat walls (34×34, `ARENA_HALF`) → `_start_wave`.
- Milestones `[5, 10, 20, 50]` (`waves_run_service.gd:8`): after clear, 5s prep, then advance.
- Wave 50 clear → reward pick (≤3 items) → `RunFlow.complete_waves_run`.
- Death → 1.5s → `RunFlow.on_waves_failed` (`waves_run.gd:362-364`).

### Wave data — formula, not authored JSON

`get_enemies_for_wave` (`waves_run_service.gd:280-297`):

| Rule | Value |
|------|-------|
| Count | `mini(2 + (wave >> 1), 12)` +2 on milestones |
| Roster | grunt/archer/shield/hound; +`castle_knight` at wave ≥ 5 |
| Milestone add | Random of `boss_castle_knight`, `miniboss_castle_captain` |

`waves_run.gd:5-12` `ENEMY_SCENES` maps six castle ids + `boss_castle_knight` → `castle_knight.tscn`. **`miniboss_castle_captain` is missing** — spawn returns early when that id is rolled (`:186-188`).

Chest types, labels, rarity weights, and item pools are consts in `waves_run_service.gd:10-37`.

### Outcomes and results honesty

| Path | Behaviour | Honesty |
|------|-----------|---------|
| `complete_waves_run` (`run_flow.gd:951-966`) | Grants `WAVES_COMPLETION_XP` (500), adds chosen loot, outcome `waves_complete` | `xp_gained` real; **`levels_gained` hardcoded `0`** despite `grant_xp` returning levels |
| `on_waves_failed` (`:975-988`) | Empty loot, 0 XP, outcome `waves_failed` | Omits `run_relics_lost`; waves inventory discarded via clear save |
| `quit_waves_run` (`:929-948`) | Milestone keep-fraction transfer → hub | No results screen |
| `results_screen.gd` | Generic "Run Complete" for non-death | No waves-specific title; level-up line never shows for waves |

### Diorama

`waves_outdoors_diorama.gd` builds floor, castle backdrop, grass/trees/birds; `VisualLighting.apply_waves_outdoors`. Birds animated from `waves_run`.

## Contracts

| Contract | Detail |
|----------|--------|
| Autoload | `WavesRunService` (`project.godot`) |
| Group | `"waves_run"` |
| Save | `LocalSave` waves active run schema v1 via service `81-92` |
| Enemy ids | Must exist in `ENEMY_SCENES` or spawn is skipped |
| Results keys | Hand-built dicts in `RunFlow` (not `RunLifecycle`) |

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Lobby → 50 waves → reward pick | IMPLEMENTED | `waves_run.gd` + service |
| Wave composition | PLACEHOLDER | Formula in `get_enemies_for_wave`; no JSON |
| Milestone `miniboss_castle_captain` | BROKEN | Rolled but absent from `ENEMY_SCENES` |
| Completion XP | PARTIAL | 500 XP granted; `levels_gained` always 0 (`run_flow.gd:961-962`) |
| Failure results schema | PARTIAL | Missing `run_relics_lost` (`:979-988`) |
| Outdoors diorama | IMPLEMENTED | Procedural, seeded |
| `umbral_endless_menu` | N/A (other mode) | Endless skip-floor UI only |

## Related

- Improvement plan: [`../actual_improvements/waves-run.md`](../actual_improvements/waves-run.md)
- [`run-flow.md`](run-flow.md), [`ui/waves_hud.md`](ui/waves_hud.md), [`ui/run_outcome.md`](ui/run_outcome.md), [`enemies.md`](enemies.md), [`bosses.md`](bosses.md)

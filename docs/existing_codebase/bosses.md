# Bosses

Bosses are `CastleEnemyBase` subclasses (or 4-line id shims) spawned into the floor's `boss` room by `DungeonBuilder._setup_boss`. Three bosses have real multi-phase kits; the final castle boss has a three-phase spike/puzzle fight; frost and cathedral bosses are stubs without `boss_defeated`. On the live play path for every castle/endless floor that carries a `placements.boss` entry.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/bosses/castle_knight.gd` | 2-phase knight: SLASH/THRUST/SWEEP + GROUND_SLAM arena hazard |
| `apps/game/client/scripts/bosses/swamp_hydra.gd` | 2-phase hydra: bite/sweep + poison spit/mire; spawns arena hazard + cleanse zones |
| `apps/game/client/scripts/bosses/crystal_sovereign.gd` | 2-phase sovereign: slash/arcane + PILLAR_CALL crystal pillars |
| `apps/game/client/scripts/bosses/arena_hazard.gd` | Telegraph → active → fade zone; damage via child `trap_damage_area` |
| `apps/game/client/scripts/bosses/crystal_pillar_hazard.gd` | Same lifecycle as arena hazard; crystal visual |
| `apps/game/client/scripts/bosses/swamp_cleanse_zone.gd` | Visual fade timer; `is_cleanse_active()` has no callers |
| `apps/game/client/scripts/enemies/final_boss_forgotten_castle.gd` | 3-phase final boss: COMBAT → SPIKES → PUZZLE |
| `apps/game/client/scripts/enemies/final_boss_crystal.gd` | Puzzle collectible `Area3D` |
| `apps/game/client/scripts/dungeon/final_boss_cannon.gd` | Puzzle interactable; fires into boss |
| `apps/game/client/scripts/enemies/boss_frost_warlord.gd` | Stub: `get_enemy_id()` only |
| `apps/game/client/scripts/enemies/boss_cathedral_hollow.gd` | Stub: `get_enemy_id()` only |
| `apps/game/client/scripts/enemies/miniboss_cathedral_bell.gd` | Stub: `get_enemy_id()` only |
| `apps/game/client/scripts/enemies/crystal_guardian.gd` | Light phase-2 at 45% HP; no `boss_defeated` |
| `apps/game/client/scripts/ui/boss_intro_ui.gd` | Title/lore card from catalog definition |
| `apps/game/client/scripts/ui/epilogue_card.gd` | Final-floor story card |
| `content/bosses/*.json` | 11 boss/miniboss definitions |
| `apps/game/client/scripts/content/enemy_catalog.gd` | Loads `content/bosses` with enemies; alias `castle_knight` → `boss_castle_knight` |

## How it works

### Spawn

`DungeonBuilder._setup_boss` (`dungeon_builder.gd:533-564`) reads `definition.placements.boss`, defaults `enemyId` to `"boss_castle_knight"`, and on final floor + `BIOME_CASTLE` forces `"final_boss_forgotten_castle"`. Scene comes from `EnemyCatalog.get_scene(enemy_id)`. If the instance has a `boss_defeated` signal, it is connected; otherwise stair unlock / exit portal never fire from that path (`dungeon_builder.gd:562-563`, `602-607`).

Stats load in `CastleEnemyBase._ready` via `get_enemy_id()` → `EnemyCatalog.get_definition`. `DungeonBuilder` calls `set_catalog_id(enemy_id)` before `add_child` (`dungeon_builder.gd:635-636,722-723`) so placement ids override script defaults.

### Implemented phase bosses

| Boss | Phase trigger | Real effects | Hazards |
|------|---------------|--------------|---------|
| `castle_knight` | `phase2_threshold` (default 0.5) | Unlocks GROUND_SLAM, 1.3× damage, 1.2× poise (`castle_knight.gd:106-125`) | `arena_hazard.tscn` on slam |
| `swamp_hydra` | 50% HP | Adds POISON_SPIT / MIRE_BURST, 1.3× melee, cleanse spawn every 8s (`swamp_hydra.gd:122-145`) | `arena_hazard` pools + visual cleanse |
| `crystal_sovereign` | 50% HP | Adds PILLAR_CALL, 1.35× damage, 1.2× poise, 3 pillars vs 2 (`crystal_sovereign.gd:108-140`) | `crystal_pillar_hazard.tscn` |
| `final_boss_forgotten_castle` | 25% HP → SPIKES; after 8 bursts → PUZZLE; cannon → COMBAT | Sets `_immune`, spawns `spike_trap` / crystals / cannon (`final_boss_forgotten_castle.gd:67-141`) | Spikes + puzzle props |

`phase_changed` drives HUD phase pips (`combat_hud.gd:305-313`). Final boss returns to COMBAT without re-emitting phase 1 (`final_boss_forgotten_castle.gd:140-141`).

### Final boss immunity

`is_immune()` is true during SPIKES and PUZZLE+shield (`final_boss_forgotten_castle.gd:46-47`). `Hurtbox.receive_hit` checks `is_immune()` before mitigation (`hurtbox.gd:72-75`) and emits `hit_resolved` with `outgoing = 0` — HP is not reduced while immune.

### Stub bosses

`boss_frost_warlord.gd` and `boss_cathedral_hollow.gd` extend base AI, emit `boss_defeated` on death, and return their catalog ids. No custom phase kits beyond the shared state machine. `miniboss_cathedral_bell` remains a four-line id shim.

### UI

On first entry to room `"boss"`, `castle_run.gd:128-139` shows `BossIntro.show_intro(boss_id)` from placement `enemyId` (default `"boss_castle_knight"`) and binds the HUD boss bar. On final castle boss defeat, `castle_run.gd:477-484` sets `story_completed` and shows `EpilogueCard` with a hardcoded body string.

### Hazard damage path

`arena_hazard` / `crystal_pillar_hazard` forward `@export damage` to the child `trap_damage_area` in `_ready` (`arena_hazard.gd:27-30`). Hydra `_spawn_poison_pool` instantiates `poison_pool.tscn` (`swamp_hydra.gd:9,149-154`).

## Contracts

| Contract | Detail |
|----------|--------|
| Signals | `boss_defeated`, `phase_changed(phase: int)` on implemented bosses |
| Placement | `placements.boss.enemyId` + position; room id `"boss"` |
| Catalog | `content/bosses` merged into `EnemyCatalog`; alias `castle_knight` → `boss_castle_knight` |
| Collision (hazards) | `trap_damage_area` layer 4 / mask 8 → player Hurtbox |
| Save | Only final boss extends `capture_state` / `apply_state` with phase/shield/cannon |

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Knight / hydra / sovereign kits | IMPLEMENTED | Phase scripts + hazard scenes |
| Final boss 3-phase fight + real immunity | IMPLEMENTED | `final_boss_forgotten_castle.gd`, `hurtbox.gd:72-75` |
| Frost / cathedral `boss_defeated` | IMPLEMENTED | `boss_frost_warlord.gd`, `boss_cathedral_hollow.gd` |
| Placement catalog id override | IMPLEMENTED | `set_catalog_id` in `dungeon_builder.gd` |
| Swamp cleanse zones | IMPLEMENTED | `swamp_cleanse_zone.gd:35-48` clears poison on overlap |
| Hydra poison pools | IMPLEMENTED | `POISON_POOL_SCENE` in `swamp_hydra.gd:9,149` |
| Hazard damage export forwarding | IMPLEMENTED | `arena_hazard.gd:27-30` |
| Frost / cathedral phase kits | STUB | Base AI only — no custom attacks |
| Multi-phase boss save state | PARTIAL | Only final boss extends `capture_state` |
| Boss intro / epilogue | IMPLEMENTED | `castle_run.gd:128-139`, `:477-484` |

## Related

- Improvement plan: [`../actual_improvements/bosses.md`](../actual_improvements/bosses.md) — **FINISHED**
- [`enemies.md`](enemies.md), [`combat-hazards.md`](combat-hazards.md), [`dungeon-traps.md`](dungeon-traps.md), [`castle-run.md`](castle-run.md), [`hit-hurtboxes.md`](hit-hurtboxes.md)

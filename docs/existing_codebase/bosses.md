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

Stats load in `CastleEnemyBase._ready` via `get_enemy_id()` → `EnemyCatalog.get_definition`, not from the placement id. Floor tier HP scaling is applied after spawn (`dungeon_builder.gd:561`).

### Implemented phase bosses

| Boss | Phase trigger | Real effects | Hazards |
|------|---------------|--------------|---------|
| `castle_knight` | `phase2_threshold` (default 0.5) | Unlocks GROUND_SLAM, 1.3× damage, 1.2× poise (`castle_knight.gd:106-125`) | `arena_hazard.tscn` on slam |
| `swamp_hydra` | 50% HP | Adds POISON_SPIT / MIRE_BURST, 1.3× melee, cleanse spawn every 8s (`swamp_hydra.gd:122-145`) | `arena_hazard` pools + visual cleanse |
| `crystal_sovereign` | 50% HP | Adds PILLAR_CALL, 1.35× damage, 1.2× poise, 3 pillars vs 2 (`crystal_sovereign.gd:108-140`) | `crystal_pillar_hazard.tscn` |
| `final_boss_forgotten_castle` | 25% HP → SPIKES; after 8 bursts → PUZZLE; cannon → COMBAT | Sets `_immune`, spawns `spike_trap` / crystals / cannon (`final_boss_forgotten_castle.gd:67-141`) | Spikes + puzzle props |

`phase_changed` drives HUD phase pips (`combat_hud.gd:305-313`). Final boss returns to COMBAT without re-emitting phase 1 (`final_boss_forgotten_castle.gd:140-141`).

### Final boss immunity

`is_immune()` is true during SPIKES and PUZZLE+shield (`final_boss_forgotten_castle.gd:46-47`). It is checked only in `_on_hurt` (`:50-53`), which is connected to `Hurtbox.damaged` — emitted **after** `Health.take_damage` (`hurtbox.gd:55-61`, `castle_enemy_base.gd:79`). Immunity skips flinch, not HP loss.

### Stub bosses

`boss_frost_warlord.gd` and `boss_cathedral_hollow.gd` are four lines each: extend base AI, return their catalog id. No `boss_defeated`, no custom attacks. `miniboss_cathedral_bell` is the same pattern and is listed in biome `enemyPool`, not `bossPool`.

### UI

On first entry to room `"boss"`, `castle_run.gd:128-139` shows `BossIntro.show_intro(boss_id)` from placement `enemyId` (default `"boss_castle_knight"`) and binds the HUD boss bar. On final castle boss defeat, `castle_run.gd:477-484` sets `story_completed` and shows `EpilogueCard` with a hardcoded body string.

### Hazard damage path

`arena_hazard` / `crystal_pillar_hazard` toggle `$DamageArea.monitoring` while ACTIVE. The child script is `trap_damage_area.gd`, which calls `Hurtbox.receive_hit` — i-frames, guard, and defense apply. Parent `@export var damage` is never read; scene child values (8 / 10) win. `swamp_hydra` `hazard.set("damage", 6.0)` therefore does nothing to the trap.

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
| Final boss 3-phase fight | PARTIAL | Phases real; immunity does not block damage (`final_boss_forgotten_castle.gd:50-53`) |
| Frost / cathedral bosses | STUB | `boss_frost_warlord.gd:1-4`; no `boss_defeated` |
| Swamp cleanse zones | PLACEHOLDER | Visual only; `is_cleanse_active` unused (`swamp_cleanse_zone.gd:29-30`) |
| Biome `boss_*` JSON vs script ids | BROKEN | Script `get_enemy_id` ignores placement id — wrong stats load |
| `miniboss_castle_captain` | FAKE | Points at `castle_knight.tscn`; loads 600 HP knight stats |
| Boss intro / epilogue | IMPLEMENTED | `castle_run.gd:128-139`, `:477-484` |

## Related

- Improvement plan: [`../actual_improvements/bosses.md`](../actual_improvements/bosses.md)
- [`enemies.md`](enemies.md), [`combat-hazards.md`](combat-hazards.md), [`dungeon-traps.md`](dungeon-traps.md), [`castle-run.md`](castle-run.md), [`hit-hurtboxes.md`](hit-hurtboxes.md)

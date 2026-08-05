# Bosses — improvement plan

## Current state

Three biome bosses (knight, hydra, sovereign) and the forgotten-castle final boss have real phase transitions and hazard kits. Frost warlord and cathedral hollow are 4-line stubs without `boss_defeated`, so defeating them never unlocks stairs or the exit portal. Final-boss `is_immune()` only gates `_on_hurt` flinch after `Hurtbox` has already applied HP loss. Multiple biome JSON ids (`boss_swamp_devourer`, `boss_crystal_sovereign`, `miniboss_castle_captain`, `miniboss_crystal_guardian`) point at scenes whose scripts load a different catalog id, so authored HP/poise never apply. See [`../existing_codebase/bosses.md`](../existing_codebase/bosses.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| BOS-01 | P0 | `boss_frost_warlord` and `boss_cathedral_hollow` lack `boss_defeated`; kill does not unlock stairs / exit portal | `boss_frost_warlord.gd:1-4`; `dungeon_builder.gd:562-563`, `:602-607` |
| BOS-02 | P0 | Final boss `is_immune()` does not block damage — `_on_hurt` runs after `Health.take_damage` | `final_boss_forgotten_castle.gd:50-53`; `hurtbox.gd:55-61` |
| BOS-03 | P1 | Swamp cleanse zones are visual-only; `is_cleanse_active()` has zero callers | `swamp_cleanse_zone.gd:29-30` |
| BOS-04 | P1 | `swamp_hydra` / hazard `@export damage` never reach `trap_damage_area` child values | `swamp_hydra.gd:153-154`; `arena_hazard.gd:9`; `arena_hazard.tscn` |
| BOS-05 | P1 | Placement / biome `boss_*` and `miniboss_*` ids do not match `get_enemy_id()` — wrong stats at runtime | `castle_knight.gd:19-20`; `swamp_hydra.gd:24-25`; `crystal_sovereign.gd:20-21`; `crystal_guardian.gd:12-13` |
| BOS-06 | P1 | Frost / cathedral / bell bosses are stubs despite JSON `phase2_threshold` and `enemy_type: boss` | `boss_frost_warlord.gd`; `boss_cathedral_hollow.gd`; `miniboss_cathedral_bell.gd` |
| BOS-07 | P2 | Final boss keeps base melee AI during SPIKES and PUZZLE | `final_boss_forgotten_castle.gd:56-64` |
| BOS-08 | P2 | `swamp_hydra._poison_phase_timer` is written and never read for decisions | `swamp_hydra.gd:50-51`, `:134` |
| BOS-09 | P2 | Hydra "poison pools" spawn fire-styled `arena_hazard`, not `poison_hazard` | `swamp_hydra.gd:148-155`; `arena_hazard.gd:3` |
| BOS-10 | P2 | `swamp_hag` has phase logic but appears in no biome pool | `swamp_hag.gd`; no biome JSON reference |
| BOS-11 | P2 | Returning to COMBAT after cannon does not re-emit `phase_changed(1)` — HUD pips stay stale | `final_boss_forgotten_castle.gd:140-141`; `combat_hud.gd:305-307` |
| BOS-12 | P2 | Only the final boss persists phase/shield/cannon in `capture_state`; other multi-phase bosses reset on continue | `final_boss_forgotten_castle.gd:158-181`; `castle_enemy_base.gd` base capture |

## Target design

### Spawn-time catalog id (BOS-05)

Chosen over renaming every `get_enemy_id()`: `DungeonBuilder._setup_boss` (and enemy placement) pass the placement id into the instance before `_ready` finishes loading stats.

```gdscript
# castle_enemy_base.gd
var _catalog_id_override: String = ""

func set_catalog_id(id: String) -> void:
    _catalog_id_override = id

func get_enemy_id() -> String:
    if not _catalog_id_override.is_empty():
        return _catalog_id_override
    return _default_enemy_id()  # virtual; variants override this
```

Call `set_catalog_id(enemy_id)` immediately after `instantiate()`, before `add_child`, so `_ready` loads the JSON that the biome/placement named. Duplicate content files (`swamp_hydra` vs `boss_swamp_devourer`) stay valid as distinct balance rows. Rejected alternative: force every script to return the biome id — breaks waves/arena that spawn by script id, and collapses the alias table.

### Real immunity (BOS-02)

Add an optional query on the hurtbox owner before damage:

```gdscript
# hurtbox.gd — inside receive_hit, before take_damage
var owner_body := get_parent()
if owner_body and owner_body.has_method("is_immune") and owner_body.is_immune():
    return
```

Chosen over healing back HP in `_on_hurt` (that still triggers poise, status, and feedback) and over a separate invuln flag on `Health` (would collide with dodge i-frames semantics). Final boss keeps `is_immune()` as the single source of truth.

### Stub bosses emit `boss_defeated` (BOS-01) then gain kits (BOS-06)

Step 1 (landable alone): on death, every boss-typed enemy emits `boss_defeated` from `CastleEnemyBase._die` when `enemy_type == "boss"` or when the scene declares the signal. That unblocks frost/cathedral floors immediately.

Step 2: each stub gets a biome kit matching knight/hydra/sovereign depth — frost: ice arena hazard + chill status; cathedral: bell shockwave + silence windows. Data-driven attack lists preferred where the enemy moveset work (ENE-01) lands first; otherwise copy the knight pattern with distinct hazard scenes.

### Cleanse and poison honesty (BOS-03, BOS-04, BOS-09)

- Hydra phase-2 pools spawn `poison_pool.tscn` (`poison_hazard.gd`), not `arena_hazard`.
- `swamp_cleanse_zone` gains an `Area3D` and, while `is_cleanse_active()`, calls `StatusController.clear_status("poison")` on overlapping players and sets a short `cleanse_immunity` flag that `poison_hazard._apply_poison` respects.
- Hazard controllers forward `@export damage` / `poise_damage` onto `$DamageArea` in `_ready`.

### Final boss phase polish (BOS-07, BOS-11, BOS-12)

During SPIKES/PUZZLE: skip `_process_chase` / attack windup (override `_physics_process` to not call `super` attack branches, or set `_state = State.IDLE` and early-return from chase). Emit `phase_changed(1)` on return to COMBAT. Extend `capture_state` for knight/hydra/sovereign with `_phase` / `_phase_transition_done`.

## Work plan

1. **Hurtbox immunity gate** — `hurtbox.gd`: check `is_immune()` before `take_damage`. Closes BOS-02.
2. **Catalog id override** — `castle_enemy_base.gd` + `dungeon_builder.gd` / enemy placement: `set_catalog_id` before add_child. Closes BOS-05 for boss and miniboss placements.
3. **Emit `boss_defeated` from base death for boss-typed enemies** — `castle_enemy_base.gd` + declare signal on frost/cathedral scenes. Closes BOS-01.
4. **Hazard damage forwarding + hydra poison pools** — `arena_hazard.gd`, `crystal_pillar_hazard.gd`, `swamp_hydra.gd`. Closes BOS-04, BOS-09.
5. **Wire cleanse zones** — `swamp_cleanse_zone.gd`, `poison_hazard.gd`. Closes BOS-03.
6. **Final boss AI suppression + phase HUD + save** — `final_boss_forgotten_castle.gd`; phase fields on knight/hydra/sovereign capture. Closes BOS-07, BOS-11, BOS-12.
7. **Biome boss kits for frost and cathedral** — new hazard scenes + scripts. Closes BOS-06.
8. **Add `swamp_hag` to a swamp biome `enemyPool` or retire the content** — biome JSON. Closes BOS-10. Delete unused `_poison_phase_timer` (BOS-08) in the same hydra pass as step 4.

## Data and schema changes

| Change | Schema |
|--------|--------|
| Keep distinct `boss_*` / base id JSON rows; no merge required once override works | `content/schemas/enemy-definition.v1.json` unchanged |
| Optional `cleanse_clears: ["poison"]` on cleanse zones — runtime only unless elevated to content | ABSENT today |
| No save-migrator bump — boss phase fields live inside enemy snapshot dictionaries already versioned by run schema | — |

## Acceptance criteria

- [ ] Killing `boss_frost_warlord` or `boss_cathedral_hollow` unlocks the stair lever (or opens the exit portal on a final floor). (BOS-01)
- [ ] While final boss `is_immune()` is true, HP does not decrease from player hits; poise and status also do not apply. (BOS-02)
- [ ] Standing in an active cleanse zone clears poison and blocks new poison_hazard applications for the zone duration. (BOS-03)
- [ ] Hydra-spawned pools apply poison status (or documented direct damage matching the export), and `set("damage", N)` on a hazard updates the child `trap_damage_area`. (BOS-04, BOS-09)
- [ ] Spawning placement id `boss_swamp_devourer` loads `boss_swamp_devourer.json` HP/poise, not `swamp_hydra.json`. (BOS-05)
- [ ] Frost and cathedral bosses each have at least one phase transition that changes attack set or hazard spawn. (BOS-06)
- [ ] Final boss does not melee during SPIKES/PUZZLE; HUD phase pip returns to 1 after cannon. (BOS-07, BOS-11)
- [ ] Continuing a mid-phase knight/hydra/sovereign fight restores the same phase. (BOS-12)

## Validation

Extend `apps/game/client/scripts/validation/suites/` (boss or combat suite):

| Assertion id | Checks |
|--------------|--------|
| `boss.defeat.signal_on_stub` | Instantiate frost warlord, force death, assert `boss_defeated` emitted |
| `boss.immune.blocks_damage` | Enter SPIKES, call `hurtbox.receive_hit`, assert HP unchanged |
| `boss.catalog_id.override` | `set_catalog_id("boss_swamp_devourer")`, assert loaded max HP matches that JSON |
| `boss.cleanse.clears_poison` | Apply poison, enter cleanse area, assert status absent |
| `boss.hazard.damage_forward` | Set hazard `damage = 6`, assert child `trap_damage_area.damage == 6` |

## Related

- Existing state: [`../existing_codebase/bosses.md`](../existing_codebase/bosses.md)
- [`enemies.md`](enemies.md), [`combat-hazards.md`](combat-hazards.md), [`dungeon-traps.md`](dungeon-traps.md), [`castle-run.md`](castle-run.md)
- Owned elsewhere: [`ui/combat_hud.md`](ui/combat_hud.md), [`hit-hurtboxes.md`](hit-hurtboxes.md)

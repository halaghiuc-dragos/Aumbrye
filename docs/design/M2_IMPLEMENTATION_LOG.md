# M2 implementation log

> **M2 closed:** 2026-07-30 — KB/M playtest signed off.  
> **Phase:** [M2-VERTICAL-SLICE.md](../plan/phases/M2-VERTICAL-SLICE.md)  
> **Depends on:** M1 closed — [M1_IMPLEMENTATION_LOG.md](M1_IMPLEMENTATION_LOG.md)  
> **Controls:** M1 combat locked — [M1_CONTROLS.md](M1_CONTROLS.md) · M2 interact/inventory — [M2_CONTROLS.md](M2_CONTROLS.md)

**Last updated:** 2026-07-30

---

## Status

All M2 milestones implemented. KB/M vertical slice playtest signed off 2026-07-30.

| Milestone | Status | Notes |
|-----------|--------|-------|
| ART-2.1 | ✅ | 8 castle room templates + [CASTLE_ROOM_SOCKETS.md](CASTLE_ROOM_SOCKETS.md) |
| DUNGEON-2.1 | ✅ | Hand-wired layout in `forgotten_castle_slice.tscn` (reference) |
| DUNGEON-2.2 | ✅ | `content/fixtures/forgotten_castle_slice.json` — validates |
| BUILDER-2.1 | ✅ | `dungeon_builder.gd` — authoritative via `castle_run.tscn`; L-shaped shortcut |
| SCHEMA-2.1 | ✅ | `item-instance.v1.json`, `inventory.v1.json` + CI validator |
| INV-2.1 | ✅ | 6×4 grid, Tab toggle, arrow/D-pad cursor, Enter equip |
| LOOT-2.1 | ✅ | 4 chests; secret vault = knight relic + 3 potions |
| ENEMY-2.1 | ✅ | `castle_grunt` — patrol/chase/deaggro from JSON |
| ENEMY-2.2 | ✅ | `castle_archer` — draw telegraph, keep distance, rollable projectile |
| ENEMY-2.3 | ✅ | `castle_shield` — `shield_hurtbox.gd` frontal block, rear/parry weakness |
| TRAP-2.1 | ✅ | Spike (stairs) + falling (hall); `trap_damage_area.gd` |
| BOSS-2.1 | ✅ | Castle Knight — multi-attack, arena bounds, telegraphs |
| BOSS-2.2 | ✅ | Phase 2 at 50% HP; ground slam + arena fire hazards |
| FLOW-2.1 | ✅ | Hub → castle → boss → exit portal → results → hub; death → hub |
| SAVE-2.1 | ✅ | `user://aumbrye_save.json`; corrupt JSON/schema → fresh start |
| AUDIO-2.1 | ✅ | `audio_director.gd` — WAV ambience/boss loops |
| HUB-2.1 | ✅ | Portal + arena door; arena west **E** return to hub |

---

## Playtest sign-off (KB/M, 2026-07-30)

| Area | Result |
|------|--------|
| Hub, training arena, castle layout | ✅ |
| Combat (walls, grunt, archer, shield, lock-on + LOS) | ✅ |
| Traps (spike, falling) | ✅ |
| Inventory, chests, potions, sword equip | ✅ |
| Boss (2-phase, door, exit portal) | ✅ |
| Full loop + local save | ✅ |
| Audio (dungeon + boss) | ✅ |
| Gamepad | ⬜ Deferred — bindings in `project.godot`, manual verify later |
| External friend playtest | ⬜ Optional exit criterion — not blocking M2 code gate |

**Save file:** `%APPDATA%\Godot\app_userdata\Aumbrye\aumbrye_save.json` (Godot: **Project → Open User Data Folder**).

---

## Play / dev

| Scene | Path | Notes |
|-------|------|-------|
| **Hub (main scene)** | `scenes/hub/hub.tscn` | M2 slice entry; superseded by full `hub.tscn` in M4 |
| Castle run | `scenes/dungeon/castle_run.tscn` | Builder-driven from fixture |
| Combat arena | `scenes/debug/combat_arena.tscn` | M1 tuning via hub door |
| Hand layout (reference) | `scenes/dungeon/forgotten_castle_slice.tscn` | Iteration reference only |

**New bindings (M2 only):** [M2_CONTROLS.md](M2_CONTROLS.md) — **E** interact, **Tab** inventory.

---

## Key paths

| Area | Path |
|------|------|
| Dungeon builder | `scripts/dungeon/dungeon_builder.gd` |
| Fixture | `content/fixtures/forgotten_castle_slice.json` |
| Run flow | `scripts/app/run_flow.gd` |
| Local save | `scripts/save/local_save.gd` |
| Inventory | `scripts/inventory/` + `scripts/ui/inventory_ui.gd` |
| Enemies | `scripts/enemies/castle_*.gd` |
| Boss | `scripts/bosses/castle_knight.gd` + `arena_hazard.gd` |
| Traps | `scripts/dungeon/traps/` |
| Audio | `scripts/audio/audio_director.gd` |
| Lock-on | `scripts/camera/lock_on.gd` + `scripts/player/lock_on_movement.gd` |

---

## Autoloads

| Name | Script |
|------|--------|
| RunFlow | `scripts/app/run_flow.gd` |
| LocalSave | `scripts/save/local_save.gd` |
| InventoryService | `scripts/inventory/inventory_service.gd` |
| AudioDirector | `scripts/audio/audio_director.gd` |

---

## Session fixes (playtest → close)

| Issue | Fix |
|-------|-----|
| Exit portal / results scene change during physics | Deferred in `exit_portal.gd` + `run_flow.gd` |
| Health potions did nothing on Enter | `inventory_ui.gd` + `healAmount` on item |
| Archer homing / wall shots | Fixed trajectory; projectile stops on walls |
| Boss gate blocked entry | Door opens on **E**; seals 4 m inside |
| Boss door **Press E** invisible | Billboard + label placement in `dungeon_builder.gd` |
| Lock-on through walls | Closest visible enemy; breaks on LOS loss |
| Lock-on orbit in castle | Shared `LockOnMovement` + typed `LockOn` |
| Castle sword wrong weapon id | `content/weapons/castle_sword.json` |
| Enemy slow tracking / frozen during attacks | Turn speed 22; move during windup/attack |
| Boss slam windup too long | Reduced in `castle_knight.gd` + JSON |
| Stamina too generous | Light 12/15/20, heavy/dodge 32, block 18/hit |
| GDScript warnings | `results_screen`, `lock_on_movement`, `locomotion`, `castle_enemy_base` |

---

## Deferred / open (post-M2)

Tracked in [MANUAL_PLAYTEST_CHECKLIST.md](MANUAL_PLAYTEST_CHECKLIST.md):

| Item | Target | Notes |
|------|--------|-------|
| **Gamepad playtest** | M7 (`POLISH-7.1`) | Bindings in `project.godot`; `M2.gamepad.full_loop` |
| **External friend playtest** | M7 (`SHIP-7.1`) | Optional per [M2-VERTICAL-SLICE.md](../plan/phases/M2-VERTICAL-SLICE.md) exit criteria |
| **Castle art pass** | M5+ | Blockout layout accepted; tighter room rework when final assets land |
| **Save JSON integers** | M4+ | `quantity`/`x`/`y` sometimes serialize as floats (`1.0`); loads fine; tighten serializer later |
| **Corrupt-save edge case** | M4+ | Optional: bad JSON → fresh start + starter sword — `M2.save.corrupt_json` |
| **Combat tuning** | ongoing | Stamina costs raised 2026-07-30 — see [combat_tuning_m1.md](combat_tuning_m1.md) |

---

## Audit fixes (2026-07-29)

| Issue | Fix |
|-------|-----|
| Builder shortcut misaligned | L-shaped corridor at (0,31) + (9,43) matching hand layout |
| Corrupt save (invalid JSON) | `local_save.gd` resets to defaults + warning |
| Boss defeat audio | `castle_run.gd` returns to dungeon ambience |
| Arena hub-return label | `combat_arena.tscn` Label3D restored |
| Inventory schema in CI | `content/fixtures/inventory_sample.v1.json` |

# M1 implementation log (closed)

> **M1 closed:** 2026-07-29 — user confirmed KB/M combat, controls, lock-on, and dodge behavior.  
> **Phase file removed:** `docs/plan/phases/M1-COMBAT.md` (milestones archived below).  
> **Controls permanently locked:** [M1_CONTROLS.md](M1_CONTROLS.md) — do not change without explicit user request.  
> **Next phase:** [M2-VERTICAL-SLICE.md](../plan/phases/M2-VERTICAL-SLICE.md)

---

## Exit criteria (final)

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Walk, sprint, jump, dodge, block, parry (KB/M) | ✅ User signed off |
| 2 | Third-person camera + lock-on (KB/M) | ✅ User signed off |
| 3 | Sword light/heavy + stamina | ✅ User signed off |
| 4 | Training enemy; skilled duel (roll / parry / spacing) | ✅ User signed off |
| 5 | Debug combat arena | ✅ |
| 6 | 60 FPS in arena | ✅ User reported >120 FPS (F1) |

---

## Deferred (not blocking M2)

| Item | Status | Where to track |
|------|--------|----------------|
| **Gamepad full playtest** | Bindings in `project.godot`; not verified on hardware | [MANUAL_PLAYTEST_CHECKLIST.md](MANUAL_PLAYTEST_CHECKLIST.md) — `TEST-M1-GPAD` |
| SFX files for hit feedback | Hook points only (`hit_feedback.gd`) | M2+ audio |
| Full VFX polish | Hitstop + camera punch only | M7 feel polish |

---

## Milestone archive (was M1-COMBAT.md)

All implemented unless noted.

| ID | Title | Paths |
|----|-------|-------|
| MOVE-1.1 | Locomotion base | `scripts/player/locomotion.gd` |
| MOVE-1.2 | Jump + dodge/roll | `scripts/player/dodge.gd` |
| CAM-1.1 | Orbit camera + zoom | `scripts/camera/orbit_camera.gd` |
| CAM-1.2 | Lock-on (orbit strafe, no camera takeover) | `scripts/camera/lock_on.gd` |
| COMBAT-1.1 | Health / Stamina / Poise | `scripts/combat/` |
| COMBAT-1.2 | Sword moveset | `weapon_controller.gd`, `content/weapons/sword_basic.json` |
| COMBAT-1.3 | Block (tap Q) | `guard.gd` |
| COMBAT-1.4 | Parry window | `guard.gd` |
| COMBAT-1.5 | Hit feedback + damage numbers | `hit_feedback.gd`, `damage_number.gd` |
| WPN-1.1 | Hitbox pipeline | `hitbox.gd`, `hurtbox.gd` |
| ENEMY-1.1–1.3 | Training grunt + duel tuning | `training_grunt.gd`, `combat_tuning_m1.md` |
| UI-1.1 | Combat HUD | `combat_hud.gd` |
| DBG-1.1 | Combat arena + overlays | `combat_arena.tscn`, `debug_overlay.gd` |

---

## Locked controls summary

Full table: **[M1_CONTROLS.md](M1_CONTROLS.md)**

| Action | KB/M | Gamepad |
|--------|------|---------|
| Roll / dodge | **Space** | B |
| Jump | **F** | A |
| Block + parry (tap) | **Q** | LT |
| Lock-on | Middle mouse | RB |
| Sprint | Left Shift | L3 |

Guard: tap → 0.18s parry → 0.65s block → idle. Move while attacking and while blocking.

---

## Key paths

| Area | Path |
|------|------|
| Controls (authoritative) | `docs/design/M1_CONTROLS.md` |
| Arena | `apps/game/client/scenes/debug/combat_arena.tscn` |
| Player | `apps/game/client/scenes/player/player.tscn` |
| Guard | `apps/game/client/scripts/combat/guard.gd` |
| Dodge | `apps/game/client/scripts/player/dodge.gd` |
| Lock-on | `apps/game/client/scripts/camera/lock_on.gd` |
| Playtest record | `docs/design/M1_PLAYTEST_CHECKLIST.md` |
| Tuning | `docs/design/combat_tuning_m1.md` |

---

## Out of scope (not M1)

SFX assets, full VFX, elemental damage, skills, multiple enemies, loot/XP, inventory UI, arena art.

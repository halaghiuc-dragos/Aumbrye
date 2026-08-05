# Player combat (scene wiring)

This document is the authority on **what the player scene actually contains** and how the combat nodes are wired to each other. The rules each node implements live in the per-system docs; this one traces node paths, exported `NodePath`s, and signal wiring in `player.tscn`. It is on the live play path: `player.tscn` is the only player scene in the repo.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scenes/player/player.tscn` | The scene. 19 `ext_resource` scripts, 4 `sub_resource` shapes |
| `apps/game/client/scripts/player/locomotion.gd` | Script on the root node; creates `AnimDirector` at runtime |
| `apps/game/client/scripts/combat/weapon_controller.gd` | Attack state machine |
| `apps/game/client/scripts/combat/hitbox.gd`, `hurtbox.gd` | Damage exchange |
| `apps/game/client/scripts/combat/hit_feedback.gd` | Hitstop, camera punch, damage numbers |

Scenes that instance it: `scenes/hub/hub.tscn:4`, `scenes/dungeon/castle_run.tscn:4`, `scenes/dungeon/waves_run.tscn:4`, `scenes/dungeon/forgotten_castle_slice.tscn:12`, `scenes/debug/combat_arena.tscn:3`, `scenes/debug/empty_world.tscn:3`.

## Actual node tree

Nodes marked `[runtime]` do not exist in the `.tscn` and are created in code.

```
Player                       CharacterBody3D, collision_layer = 2, script = locomotion.gd
├─ CollisionShape3D          CapsuleShape3D r=0.4 h=1.6, offset y=0.8  (so the body origin is at the feet)
├─ Facing                    Node3D, the only node that yaws; the body never rotates
│  ├─ MeshInstance3D         CapsuleMesh blockout, hidden at runtime by hide_legacy_meshes
│  ├─ WeaponPivot            Node3D at (0, 0.75, 0.75)
│  │  └─ Hitbox              Area3D, layer 4 (hitbox), mask 8 (hurtbox), team = "player", script = hitbox.gd
│  │     └─ CollisionShape3D BoxShape3D 1.2 x 0.8 x 1.4 at (0, -0.12, 0.55)
│  └─ DioramaVisual  [runtime]  built by DioramaCharacterSkin.build_player_body
│     └─ DioramaAnimPlayer [runtime]  AnimationPlayer, root_node = ".."
├─ Health                    script = health.gd
├─ Stamina                   script = stamina.gd
├─ Mana                      script = mana.gd
├─ Poise                     script = poise.gd
├─ Dodge                     script = dodge.gd        (owns both dodge and jump)
├─ Guard                     script = guard.gd
├─ CombatReactions           script = player_combat_reactions.gd
├─ PlayerHeal                script = player_heal.gd
├─ StatusController          script = status_controller.gd, health_path = "../Health"
├─ WeaponController          script = weapon_controller.gd, hitbox_path = "../Facing/WeaponPivot/Hitbox"
├─ HitFeedback               script = hit_feedback.gd, camera_path = "CameraPivot/SpringArm3D/Camera3D"
├─ LockOn                    script = lock_on.gd, player_path = "..", facing_path = "Facing"
├─ CameraPivot               Node3D at (0, 1.6, 0)
│  └─ SpringArm3D            spring_length = 4.0, collision_mask = 1, script = orbit_camera.gd, yaw_pivot_path = ".."
│     ├─ Camera3D            current = true
│     └─ Viewmodel  [runtime]  built by DioramaViewmodel.build
├─ Hurtbox                   Area3D at y=0.8, layer 8 (hurtbox), mask 4 (hitbox), team = "player",
│  │                         health_path = "../Health", poise_path = "../Poise"
│  └─ CollisionShape3D       BoxShape3D 0.9 x 1.6 x 0.9
└─ AnimDirector  [runtime]   PlayerAnimDirector, added by locomotion.gd:40-42
```

There is no `Locomotion` child node. There is no `PlayerCombat` node: the player's offence is `WeaponController` + `Facing/WeaponPivot/Hitbox`, and its defence is `Hurtbox` + `Guard` + `Poise` + `CombatReactions`.

## Collision layers

Named in `project.godot:307-310`: layer 1 `world`, 2 `player_body`, 3 `hitbox`, 4 `hurtbox`.

| Node | `collision_layer` | `collision_mask` |
|------|-------------------|------------------|
| `Player` | 2 | default |
| `Facing/WeaponPivot/Hitbox` | 4 (`hitbox`) | 8 (`hurtbox`) |
| `Hurtbox` | 8 (`hurtbox`) | 4 (`hitbox`) |
| `CameraPivot/SpringArm3D` | n/a | 1 (`world`) |

Enemy scenes mirror this with `team = "enemy"` (for example `scenes/enemies/castle_knight.tscn:59-72`).

## Control flow

**Attack.** `WeaponController._physics_process` (`weapon_controller.gd:109`) returns early if `_is_action_blocked()` — dodging, `Guard.is_guard_active`, `CombatReactions.can_act()` false without hyperarmor, or `StatusController.is_stunned()` (`:564-576`). Otherwise it polls `two_hand`, `weapon_art`, `light_attack`, `heavy_attack`. `_try_attack` charges stamina, calls `_snap_soft_lock_facing()`, and enters `STARTUP` → `ACTIVE` → `RECOVERY` on `_phase_timer` (`:316-333`). Entering `ACTIVE` calls `_enable_hitbox_for_attack()`, which sets damage/poise/status on the hitbox, enables it, sets `_hyperarmor_active`, and fires `VfxService.play_attack_swing` (`:336-357`).

**Facing snap.** `_snap_soft_lock_facing()` (`:460`) prefers the lock-on target; otherwise `_find_soft_lock_target()` scans group `lockable` within `SOFT_LOCK_RANGE = 14.0` m and `SOFT_LOCK_CONE_DEG = 100.0` (tightened to 70 deg while moving) using the `CameraPivot` forward vector, then sets `Facing.rotation.y` directly.

**Damage out.** `hitbox.gd:151-153` finds `HitFeedback` on the attacker and calls `on_hit(target, damage, direction)`.

**Damage in.** `Hurtbox` resolves `Health` and `Poise` by exported path, and calls `HitFeedback.on_hit_received` / `on_hit_blocked` on its own body (`hurtbox.gd:125-127`, `:140-142`).

**Reactions.** `CombatReactions` listens to `Health.died` and `Poise.poise_broken` and gates all movement through `is_movement_locked()`; see [`player-combat-reactions.md`](player-combat-reactions.md).

**Animation.** No combat script talks to the rig. `PlayerAnimDirector` subscribes to `Dodge`, `Guard`, `WeaponController`, `CombatReactions`, `Health`, and `Poise` signals; see [`player-anim-director.md`](player-anim-director.md).

## Contracts

- Child node names are a hard contract, resolved with `get_node_or_null` by string in at least ten scripts: `Health`, `Stamina`, `Mana`, `Poise`, `Dodge`, `Guard`, `CombatReactions`, `PlayerHeal`, `StatusController`, `WeaponController`, `HitFeedback`, `LockOn`, `CameraPivot/SpringArm3D`, `Facing`, `Facing/WeaponPivot/Hitbox`, `Facing/DioramaVisual`, `AnimDirector`.
- The player must be in group `player` — added by `locomotion.gd:28` and again by `dungeon_builder.gd:444`.
- The player is deliberately **not** in group `lockable`; `_find_soft_lock_target` and `LockOn._get_lockable_targets` both scan that group.
- `VfxService.resolve_combat_anchor` expects the exact path `Facing/WeaponPivot/Hitbox` (`vfx_service.gd:72`).
- Weapon data defaults to `content/weapons/sword_basic.json` (`weapon_controller.gd:6`) and is replaced by `InventoryService.apply_equipment_to_player_node` (`inventory_service.gd:199-205`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Attack phase machine, stamina cost, combo index, buffered input | IMPLEMENTED | `weapon_controller.gd:109-138`, `:255-280` |
| Hitbox profile per weapon archetype | IMPLEMENTED | `weapon_controller.gd:531-561` |
| Soft-lock facing snap | IMPLEMENTED | `weapon_controller.gd:460-528` |
| Two-hand stance | PARTIAL | `TWO_HAND_DAMAGE_MULT = 1.25` and a 1.1x hitbox apply; `TWO_HAND_POISE_MULT = 1.35` is declared at `weapon_controller.gd:16` and never read |
| Camera punch, camera shake, FOV kick on the player | BROKEN | `player.tscn:99` sets `camera_path = "CameraPivot/SpringArm3D/Camera3D"`, but `hit_feedback.gd:31` resolves it from the `HitFeedback` node, so it needs `../CameraPivot/...`; `_camera` stays `null` and `_apply_camera_punch` / `_apply_camera_shake` do nothing (`hit_feedback.gd:119-153`) |
| Hitstop on the player rig | BROKEN | `hit_feedback.gd:34` caches `AnimDirector` during its own `_ready`, which runs before the parent `_ready` that creates that node |
| Animation-driven hitbox windows | BROKEN | `enable_hitbox_from_anim` / `disable_hitbox_from_anim` exist (`weapon_controller.gd:242-248`) but the method tracks that call them are never compiled; see [`player-anim-director.md`](player-anim-director.md) |
| Blockout capsule mesh | PLACEHOLDER | `player.tscn:48-50` ships a `CapsuleMesh`, hidden at runtime by `hide_legacy_meshes` (`diorama_character_skin.gd:91`) |
| Attack lunge | STUB | `get_attack_lunge_velocity()` returns `Vector3.ZERO` and has no call site (`weapon_controller.gd:238-239`) |
| Backstab, riposte prompt, guard-break punish animation | ABSENT | `Guard` exposes `get_riposte_damage_multiplier` / `consume_riposte` used at `weapon_controller.gd:341-346`, but no positional or prompt logic exists in the player scripts |
| Mana spending by the player | ABSENT | `Mana` node exists (`player.tscn:71-72`); no player script consumes it |

## Related
- Improvement plan: [`../actual_improvements/player-combat.md`](../actual_improvements/player-combat.md)
- [`combat-core.md`](combat-core.md), [`weapons.md`](weapons.md), [`guard.md`](guard.md), [`dodge.md`](dodge.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`hit-feedback.md`](hit-feedback.md), [`stamina-mana.md`](stamina-mana.md), [`statuses-and-buffs.md`](statuses-and-buffs.md)
- [`player-combat-reactions.md`](player-combat-reactions.md), [`player-anim-director.md`](player-anim-director.md), [`locomotion.md`](locomotion.md), [`lock-on.md`](lock-on.md)

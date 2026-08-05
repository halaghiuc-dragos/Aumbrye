# Enemies

Every non-boss enemy in the game is one shared 641-line AI state machine (`CastleEnemyBase`) driven by
a flat JSON stat block. It is on the live play path: `DungeonBuilder._place_enemy` instantiates enemy
scenes from `content/biomes/*.json` `enemyPool` entries, and `waves_run.gd` spawns from a hardcoded
dictionary. Of 29 enemy definitions, **24 variant scripts contain no behaviour at all** — they only
return an id string. Differentiation between archetypes is numeric only (health, speed, ranges) plus
one ranged override and one shield stat pair.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/enemies/castle_enemy_base.gd` | The entire shared AI: 9-state machine, aggro/LOS, attack, death, save state (641 lines) |
| `apps/game/client/scripts/enemies/castle_archer.gd` | Only real behaviour override: kite movement + projectile fire (80 lines) |
| `apps/game/client/scripts/enemies/training_grunt.gd` | Standalone 235-line copy of the state machine for the arena dummy; does **not** extend `CastleEnemyBase` |
| `apps/game/client/scripts/enemies/<21 others>.gd` | 3-14 line shims: `get_enemy_id()`, optional `_apply_mesh_tint()` / `scale` / `get_hp_bar_height()` |
| `apps/game/client/scenes/enemies/*.tscn` | 36 scenes; each is `CharacterBody3D` + `CollisionShape3D` + `MeshInstance3D` + `Health` + `Poise` + `AttackPivot/Hitbox` + `Hurtbox` + `TelegraphMesh` |
| `content/enemies/*.json` | 29 flat stat blocks |
| `content/schemas/enemy-definition.v1.json` | Schema, `additionalProperties: false`, 14 required keys |
| `apps/game/client/scripts/content/enemy_catalog.gd` | Loads `content/enemies` + `content/bosses` into one id-keyed dictionary; `LEGACY_ALIASES` |
| `apps/game/client/scripts/combat/enemy_pool.gd` | `EnemyPool.acquire` / `release` / `clear_all` — no call site |
| `apps/game/client/scripts/dungeon/procgen/procgen_placements.gd` | Weighted enemy selection against a threat budget |
| `apps/game/client/scripts/art/characters/diorama_character_skin.gd` | `profile_for_enemy_data()`, `theme_for_enemy_id()`, `build_enemy_body()` |

## How it works

### Spawn and data binding

`DungeonBuilder._place_enemy` (`dungeon_builder.gd:460`) resolves a scene through
`EnemyCatalog.get_scene(enemy_id)`, instantiates it, snaps feet to floor, calls `set_player`, adds it to
the room, then calls `_apply_floor_scaling` (`dungeon_builder.gd:921`).

`CastleEnemyBase._ready` (`castle_enemy_base.gd:57`):

1. Adds itself to groups `lockable` and `enemy`; records `_spawn_origin`.
2. `_data = EnemyCatalog.get_definition(get_enemy_id())`. Subclasses supply the id; the base returns `""`,
   in which case it falls back to `ContentLoader.load_json(DATA_PATH)` and `DATA_PATH` is `""`
   (`castle_enemy_base.gd:12`, `:93`).
3. Fetches child nodes by **fixed name**: `Health`, `Poise`, `AttackPivot/Hitbox`, `Hurtbox`
   (`castle_enemy_base.gd:66-69`).
4. `_health.configure(_data.health)`, `_poise.configure(_data.poise)`.
5. Copies `block_mitigation` / `block_angle_deg` onto the `Hurtbox` via `set()` if present
   (`_apply_hurtbox_data`, `:202`).
6. `_setup_diorama_visual()` hides `MeshInstance3D`, builds a procedural box body, and attaches a
   `DioramaAnimController`.
7. Attaches an `EnemyHealthBar` and hides `TelegraphMesh`.

### State machine

`enum State { PATROL, CHASE, INVESTIGATE, RETREAT, WINDUP, ATTACK, RECOVERY, STAGGER, DEAD }`
(`castle_enemy_base.gd:6`). `_physics_process` (`:374`) drains cooldowns, short-circuits on stagger,
runs `_update_ai`, turns to face, applies gravity, `move_and_slide()`, then pushes a locomotion clip.

| State | Entry | Behaviour | Exit |
|-------|-------|-----------|------|
| `PATROL` | default; `RECOVERY`/`INVESTIGATE`/`RETREAT`/`STAGGER` end without aggro | Walk to `_patrol_target` at `move_speed`; on arrival wait `randf_range(1.0, 2.5)` s and pick a new one (`:449`) | `_has_aggro()` → `CHASE` |
| `CHASE` | aggro acquired | `_apply_chase_velocity` closes to `attack_range * 0.85` then stops (`:523`) | `_can_attack()` → `WINDUP`; `_should_retreat()` → `RETREAT`; aggro lost → `INVESTIGATE` (timer 2.5 s) |
| `INVESTIGATE` | aggro lost from `CHASE` | Walk to `_last_known_player_pos` at `move_speed * 0.75` (`:483`) | timer 0 → `PATROL`; re-aggro → `CHASE` |
| `RETREAT` | `_health.current / max <= retreat_threshold` | Walk directly away at `move_speed` for 1.8 s (`:500`) | timer 0 → `CHASE`/`PATROL` |
| `WINDUP` | `_start_windup()` (`:608`) | Keeps closing at `0.9x` speed; drives the HP-bar telegraph fill (`:427`) | timer 0 → `_start_attack()` |
| `ATTACK` | `_start_attack()` (`:635`) | Keeps closing at `0.7x`; `Hitbox` enabled with the selected attack values | timer = `active_duration` → `_end_attack()` |
| `RECOVERY` | `_end_attack()` (`:654`) | Keeps closing at `0.85x` | timer = `recovery_duration` → `CHASE`/`PATROL`, sets `_cooldown = attack_cooldown` |
| `STAGGER` | `apply_stagger()` from `Poise.poise_broken` (`:742`) | `_physics_process` returns early — no movement, no gravity, no `move_and_slide` (`:383-390`) | timer 0 → `PATROL` (not `CHASE`) |
| `DEAD` | `_finalize_death()` (`:282`) | Hitbox/hurtbox off, body collision disabled, dissolve + sink tween | `respawn_at_rest()` only |

### Aggro

`_has_aggro()` (`:537`) is a two-stage latch:

- Unlatched: within `aggro_range` (default 10.0) **and** `_has_line_of_sight_to_player()` → registers combat
  engagement with `AudioDirector`, sets `_aggro_locked = true`.
- Latched: drops aggro if distance exceeds `deaggro_range` (default `aggro_range * 1.6`), or if LOS is
  broken continuously for `DEAGGRO_LOS_TIMEOUT := 3.0` s (`:54`).

LOS is a single ray from `origin + (0, 1.2, 0)` to `player + (0, 1.0, 0)` on `collision_mask = 1`, excluding
both bodies (`:581`).

`_can_attack()` (`:570`) additionally requires `_cooldown <= 0`, distance within `attack_range`, and that
attacker and player are not on opposite sides of the boss-room boundary
(`castle_run.is_cross_boss_boundary`, `:599`).

### Attack selection and concurrency

`_start_windup` requests a token from `AttackTokenService` keyed on `_data.attack_token_group`
(default `"room_default"`, `:612`). If the token is refused the enemy stays in `CHASE` and retries next
frame. `_select_attack_data` (`:676`) reads `_data["attacks"]` and picks one at random; **no JSON file in
`content/` contains an `attacks` key**, so `_current_attack_data` is always `_data` itself and every
enemy has exactly one attack. `_end_attack` reads `_current_attack_data["combo_followups"]` to chain a
second windup; that key is also absent from all content.

### Telegraph

Three channels fire on `_start_windup`:

1. `begin_attack_windup_bar(_state_timer)` → `EnemyHealthBar.begin_attack_telegraph`
   (`enemy_health_bar.gd:88`): a billboarded orange `Sprite3D` fill bar (`Color(0.95, 0.55, 0.15)`) above
   the health bar, advanced each frame by `set_attack_telegraph_progress` (`castle_enemy_base.gd:427-433`).
2. `AudioDirector.play_sfx("windup", ...)` — a **synthesized 72 Hz / 0.22 s generator tone**
   (`audio_director.gd:41`), not an authored sample.
3. `_animator.play_attack(windup, active, recovery)` — the procedural box-body attack clip.

`TelegraphMesh` is present in every enemy scene (`castle_grunt.tscn:77`, `visible = false`) and is
referenced at `castle_enemy_base.gd:25`, but it is **only ever set to `false`** (lines 85, 244, 303, 366).
No code path in `scripts/enemies/` sets it visible. `castle_archer.gd:44` scales it and `crystal_shade.gd`
/ `swamp_witch.gd` recolor its material, all while it stays hidden.

The signals `attack_telegraph_started` and `attack_active` (`castle_enemy_base.gd:9-10`) are emitted but
have **no `connect()` call anywhere** under `apps/game/client/scripts/`.

### Per-variant differentiation (verified)

| Variant script | Lines | What it actually adds |
|----------------|-------|-----------------------|
| `castle_archer.gd` | 80 | Real: `_process_chase` kiting between `retreat_range` and `preferred_range`, `_lock_shot_trajectory()` at windup start, `_fire_projectile()` into `get_tree().current_scene` |
| `crystal_guardian.gd` | 48 | `phase_changed` at `phase2_threshold`, 1.2x damage in phase 2, poise x1.15, mesh tint, `scale 1.2` |
| `swamp_hag.gd` | 48 | Same shape as above: 1.15x damage, 2 poison stacks in phase 2, tint, `scale 1.15` |
| `crystal_shade.gd` | 14 | `extends castle_archer.gd`; tint + telegraph material recolor (on the hidden mesh) |
| `swamp_witch.gd` | 14 | `extends castle_archer.gd`; tint + telegraph material recolor |
| `crystal_golem.gd` | 10 | Tint, `scale 1.35`, `get_hp_bar_height() -> 2.6` |
| `swamp_toad.gd` | 10 | Tint, `scale (1.15, 0.95, 1.15)`, hp bar 2.4 |
| `crystal_bat.gd` | 8 | `extends castle_archer.gd`; tint + `scale 0.7` |
| `crystal_slime.gd` | 8 | Tint + `scale 0.85` |
| `swamp_leech.gd` | 8 | Tint + `scale (0.75, 0.6, 0.75)` |
| `swamp_bogling.gd` | 7 | Tint only |
| `castle_grunt.gd`, `castle_shield.gd` | 4 | `get_enemy_id()` only |
| `castle_hound.gd`, `cathedral_acolyte.gd`, `cathedral_shade.gd`, `cathedral_warden.gd`, `crystal_crawler.gd`, `crystal_spitter.gd`, `crystal_wisp.gd`, `frost_archer.gd`, `frost_hound.gd`, `frost_knight.gd`, `frost_raider.gd`, `swamp_brute.gd`, `swamp_slasher.gd`, `swamp_spitter.gd`, `swamp_swarm.gd` | 3 | `get_enemy_id()` only |

**19 scripts are pure id shims (3-4 lines). 5 more only recolor and rescale.** The tint calls are
themselves inert: `_apply_mesh_tint` (`castle_enemy_base.gd:211`) writes a surface override onto
`$MeshInstance3D`, which `_setup_diorama_visual` set to `visible = false` at line 112.

### Scene differentiation

`git diff --no-index apps/game/client/scenes/enemies/castle_grunt.tscn apps/game/client/scenes/enemies/swamp_brute.tscn`
returns 8 changed lines: the `uid`, the script path, the `ext_resource`/`sub_resource` ids, the root node
name, and the albedo of the hidden legacy capsule material. Geometry, `CapsuleShape3D` (radius 0.45,
height 1.8), `BoxShape3D_hit` (1.0 x 0.8 x 1.2 at z +0.45 under `AttackPivot` at y 1.0 / z 0.8),
`BoxShape3D_hurt` (1.0 x 1.8 x 1.0), collision layers, and `TelegraphMesh` are identical. `crystal_golem`
at `scale 1.35` and `crystal_bat` at `scale 0.7` therefore share the same authored hurtbox proportions.

### Visual profile resolution

`profile_for_enemy_data` (`diorama_character_skin.gd:210`) returns `"hound"` for ids containing `hound`,
`"brute"` for ids containing `brute`/`golem`/`guardian`, otherwise `_data.enemy_type` verbatim.
`build_enemy_body` (`:154`) falls back to `"melee"` when the profile is not a key of `PROFILES`
(`:32`, keys: `player`, `melee`, `ranged`, `shield`, `brute`, `dummy`). `enemy_type: "boss"` is therefore
rendered with the plain melee silhouette. `_default_weapon_for_profile` (`castle_enemy_base.gd:124`) has
`"caster"`, `"beast"` branches that no profile resolver can produce.

### Death, rewards, save

`_finalize_death(silent)` (`:282`). When `silent == false` it calls
`RunFlow.register_kill(get_enemy_id())`, `_award_kill_coins()` (`_data.coinReward` → `goldReward` → 5,
`:336`), `_try_roll_global_drop()` (skipped in `waves` mode, `:345`), then emits `enemy_died`.
`capture_state()` returns `{"alive": bool, "health": float}`; `apply_state()` restores or force-kills
(`:260-279`). `respawn_at_rest()` (`:226`) is called from `run_flow.gd:460` at bonfire rest.
`_force_dead_silent()` (`:354`) has no call site.

## Contracts

| Contract | Detail |
|----------|--------|
| Node names | `Health`, `Poise`, `AttackPivot/Hitbox`, `Hurtbox`, `MeshInstance3D`, `TelegraphMesh`, `CollisionShape3D` are looked up by literal path |
| Groups | `enemy`, `lockable` added in `_ready`; re-asserted by `DungeonBuilder._ensure_enemy_groups` (`:860`) |
| Signals out | `enemy_died` (consumed by `DungeonBuilder._on_tracked_enemy_died`, `waves_run._on_enemy_died`, `combat_hud.unbind_boss`); `attack_telegraph_started`, `attack_active` — **no consumers** |
| Methods in | `set_player(Node3D)`, `apply_stagger(float)`, `respawn_at_rest()`, `capture_state()`, `apply_state(Dictionary)`, `get_lock_aim_point()`, `get_hp_bar_height()`, `get_diorama_visual()`, `is_dead()` |
| Collision layers | Hitbox layer 4 / mask 8, `team = "enemy"`; Hurtbox layer 8 / mask 4, `team = "enemy"` |
| Autoloads used | `EnemyCatalog` (static), `ContentLoader`, `AttackTokenService`, `AudioDirector`, `VfxService`, `RunFlow`, `CharacterService`, `InventoryService` |
| JSON keys read | `id`, `name`, `scene`, `health`, `poise`, `move_speed`, `attack_damage`, `attack_poise_damage`, `windup_duration`, `windup_variance`, `active_duration`, `recovery_duration`, `attack_range`, `attack_cooldown`, `stagger_duration`, `aggro_range`, `deaggro_range`, `patrol_radius`, `preferred_range`, `retreat_range`, `retreat_threshold`, `projectile_speed`, `block_mitigation`, `block_angle_deg`, `damage_type`, `status_on_hit`, `status_stacks_on_hit`, `resistances`, `enemy_type`, `threat_cost`, `coinReward`/`goldReward`, `weapon_kit`, `attack_token_group`, `attacks`, `combo_followups`, `phase2_threshold` |
| Resistances | Applied in `hurtbox.gd:150` via `EnemyCatalog.get_definition(get_enemy_id()).resistances`, not from `_data` on the enemy |

## Content-to-scene-to-script wiring

All 29 `content/enemies/*.json` ids have a matching `.tscn` under `scenes/enemies/` and a matching `.gd`
under `scripts/enemies/`. There are no filename orphans in `content/enemies`.

Reachability is a different matter. `procgen_placements._place_enemies` (`:85`) only ever picks ids from
the current biome's `enemyPool`. Cross-referencing `content/biomes/*.json`:

| Enemy id | In any `enemyPool`? | Consequence |
|----------|---------------------|-------------|
| `crystal_shade` | No | Never spawns in any run |
| `swamp_hag` | No | Never spawns; its 48-line phase logic never executes |
| `swamp_toad` | No | Never spawns |
| `swamp_witch` | No | Never spawns |
| `crystal_guardian` | Only via `miniboss_crystal_guardian` (`crystal_caverns`, `prism_depths`) | Reached, but the spawned script self-identifies as `crystal_guardian`, so it loads `content/enemies/crystal_guardian.json` (350 HP), not `content/bosses/miniboss_crystal_guardian.json` (320 HP) |
| `swamp_hydra` | Yes — `venom_mire` `enemyPool` (`venom_mire.json:38`) | A 620 HP two-phase boss is eligible as a normal combat-room enemy; `_is_reserved_boss_enemy` (`procgen_placements.gd:271`) does not catch it because the id has no `boss_`/`miniboss_` prefix and `venom_mire` `bossPool` lists `boss_swamp_devourer` |
| `training_grunt` | No | Arena-only; hardcoded in `combat_arena.tscn` |
| all others | Yes | Reachable |

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Shared patrol/chase/attack state machine | IMPLEMENTED | `castle_enemy_base.gd:417-511` |
| Per-archetype AI behaviour | ABSENT | 19 of 24 variant scripts are `get_enemy_id()` only, e.g. `castle_hound.gd:3`, `frost_knight.gd:3`, `swamp_brute.gd:3` |
| Ranged kiting | IMPLEMENTED | `castle_archer.gd:16-37` |
| Shield archetype behaviour | PARTIAL | Only `block_mitigation: 0.75` / `block_angle_deg: 100.0` in `castle_shield.json:20-21` piped into `Hurtbox`; `castle_shield.gd` has no behaviour, and there is no shield-raise/guard-break state |
| Multi-attack / combo movesets | STUB | `_select_attack_data` and `combo_followups` read `attacks` (`castle_enemy_base.gd:665-685`); no `content/**/*.json` defines it |
| `TelegraphMesh` windup visual | BROKEN | Declared `castle_enemy_base.gd:25`, set `false` at lines 85/244/303/366, never set `true` anywhere |
| Windup audio | PLACEHOLDER | `audio_director.gd:41` — 72 Hz generator tone |
| `attack_telegraph_started` / `attack_active` | STUB | Emitted at `castle_enemy_base.gd:632`, `:651`; zero `connect()` call sites |
| Per-variant meshes | PLACEHOLDER | `diorama_character_skin.gd:154` builds one of 5 box silhouettes; scenes are byte-identical apart from name/script |
| `_apply_mesh_tint` colour differentiation | STUB | Writes to `$MeshInstance3D` which is hidden at `castle_enemy_base.gd:112` |
| `enemy_type: "boss"` visual profile | FAKE | Falls back to `"melee"` at `diorama_character_skin.gd:167`; `PROFILES` has no `boss` key (`:32-86`) |
| `caster` / `beast` weapon profiles | ABSENT | `castle_enemy_base.gd:130` branches unreachable — `profile_for_enemy_data` can only return `hound`, `brute`, or a schema `enemy_type` value |
| Endless / tier damage scaling on enemies | BROKEN | `dungeon_builder.gd:929`, `:938` call `set_damage_multiplier`; no enemy script defines it (only `weapon_controller.gd:189`). HP scales, damage does not |
| Hurtbox sized per enemy | ABSENT | Every scene uses `BoxShape3D_hurt` 1.0 x 1.8 x 1.0, including `crystal_golem` at `scale 1.35` |
| Patrol routes | PLACEHOLDER | `_pick_patrol_target` picks a uniform random point in a `patrol_radius` square around spawn (`castle_enemy_base.gd:732`) |
| Pathfinding | ABSENT | No `NavigationAgent3D` in any enemy scene; movement is `velocity = to_target.normalized() * speed` + `move_and_slide()` |
| Group aggro / alert propagation | ABSENT | `_has_aggro()` is per-instance; no code shares aggro between enemies |
| `EnemyPool` | STUB | `enemy_pool.gd:9-38`; no call site under `apps/game/client/scripts/` |
| `_force_dead_silent()` | STUB | `castle_enemy_base.gd:354`; no call site |
| `training_grunt.gd` | PARTIAL | 235-line duplicate of the base machine with its own 6-state enum (`training_grunt.gd:3`); diverges (no `RETREAT`, no aggro, no LOS, no attack tokens) |
| Schema coverage of read keys | BROKEN | `enemy-definition.v1.json:7` sets `additionalProperties: false` and omits `retreat_threshold`, `windup_variance`, `attack_token_group`, `weapon_kit`, `attacks`, `combo_followups`, `coinReward`, `goldReward` — all read by `castle_enemy_base.gd` |
| Unreachable authored enemies | BROKEN | `crystal_shade`, `swamp_hag`, `swamp_toad`, `swamp_witch` are absent from every `content/biomes/*.json` `enemyPool` |
| Boss leaking into trash pool | BROKEN | `content/biomes/venom_mire.json:38` lists `swamp_hydra` |

## Related

- Improvement plan: [`../actual_improvements/enemies.md`](../actual_improvements/enemies.md)
- [`bosses.md`](bosses.md) — boss subclasses of the same base
- [`combat-core.md`](combat-core.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`statuses-and-buffs.md`](statuses-and-buffs.md)
- [`combat-hazards.md`](combat-hazards.md) — `enemy_projectile.gd`
- [`content-catalog.md`](content-catalog.md), [`biome-registry.md`](biome-registry.md)
- [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-anim-controller.md`](diorama-anim-controller.md)
- [`ui/enemy_health_bar.md`](ui/enemy_health_bar.md) — the only working telegraph surface

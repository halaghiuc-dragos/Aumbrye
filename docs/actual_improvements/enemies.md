# Enemies — improvement plan

## Current state

Twenty-nine enemy definitions share one 641-line state machine
([`castle_enemy_base.gd`](../../apps/game/client/scripts/enemies/castle_enemy_base.gd)); 19 variant
scripts are 3-4 line `get_enemy_id()` shims and 5 more only tint a hidden mesh. See
[`../existing_codebase/enemies.md`](../existing_codebase/enemies.md). Scenes are byte-identical apart
from name and script path, so a `crystal_golem` and a `swamp_leech` differ only in stat numbers and
`scale`. The multi-attack path (`attacks`, `combo_followups`) is read but no content defines it, the
`TelegraphMesh` is never made visible, and floor damage scaling calls a method that does not exist.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| ENE-01 | P0 | Every enemy has exactly one attack. `_select_attack_data` reads `_data["attacks"]`, absent from all content, so it always returns `_data` | `castle_enemy_base.gd:676-685`; no `"attacks"` key in `content/enemies/*.json` |
| ENE-02 | P0 | `TelegraphMesh` is declared and hidden in four places, never shown. The only readable windup cue is a 2D-ish billboard bar over the head | `castle_enemy_base.gd:25`, `:85`, `:244`, `:303`, `:366`; `castle_grunt.tscn:77` |
| ENE-03 | P0 | Floor/tier damage scaling is a no-op: `dungeon_builder.gd` calls `set_damage_multiplier` on enemies; no enemy script defines it | `dungeon_builder.gd:929`, `:938`; `rg "func set_damage_multiplier" scripts/enemies` returns nothing |
| ENE-04 | P0 | 19 archetypes have zero differentiated behaviour — hound, brute, shield, swarm, knight, raider all patrol/chase/single-swing identically | `castle_hound.gd:3`, `frost_knight.gd:3`, `swamp_brute.gd:3`, `swamp_swarm.gd:3`, `castle_shield.gd:4` |
| ENE-05 | P0 | Four fully authored enemies can never spawn: no biome `enemyPool` lists them | `crystal_shade`, `swamp_hag`, `swamp_toad`, `swamp_witch` absent from all `content/biomes/*.json` |
| ENE-06 | P0 | `swamp_hydra` (620 HP, two-phase boss script) is in the `venom_mire` trash `enemyPool`; `_is_reserved_boss_enemy` misses it because it lacks a `boss_` prefix | `content/biomes/venom_mire.json:38`; `procgen_placements.gd:271` |
| ENE-07 | P1 | Shield archetype has stats but no behaviour: no guard-raise state, no guard-break, no directional block reaction | `castle_shield.json:20-21`; `castle_shield.gd` has 4 lines |
| ENE-08 | P1 | `_apply_mesh_tint` writes an override onto `$MeshInstance3D`, which `_setup_diorama_visual` hides | `castle_enemy_base.gd:211`, `:112` |
| ENE-09 | P1 | `enemy_type: "boss"`, `"caster"`, `"beast"` resolve to the `melee` silhouette; `PROFILES` has no such keys | `diorama_character_skin.gd:32-86`, `:167`; `castle_enemy_base.gd:130` |
| ENE-10 | P1 | All hurtboxes are `1.0 x 1.8 x 1.0` regardless of `scale`; a `1.35x` golem and a `0.7x` bat have the same authored hit volume | `castle_grunt.tscn` `BoxShape3D_hurt`, replicated in all 36 scenes |
| ENE-11 | P1 | No pathfinding. Movement is `direction * speed` + `move_and_slide()`; enemies stick on pillars and door frames | `castle_enemy_base.gd:523-535`; no `NavigationAgent3D` in `scenes/enemies/*.tscn` |
| ENE-12 | P1 | Aggro is per-instance. Nothing propagates an alert, so a pack of `swamp_swarm` engages one at a time as the player walks in | `castle_enemy_base.gd:537-568` |
| ENE-13 | P1 | Patrol is a uniform random point in a square; enemies drift into walls and idle-jitter | `castle_enemy_base.gd:732-739` |
| ENE-14 | P1 | `STAGGER` returns before gravity and `move_and_slide()`, so a staggered airborne enemy freezes mid-air | `castle_enemy_base.gd:383-390` |
| ENE-15 | P1 | `attack_telegraph_started` / `attack_active` have no consumers; audio, VFX, and camera cannot react to enemy attacks | `castle_enemy_base.gd:9-10`, `:632`, `:651`; zero `connect()` sites |
| ENE-16 | P1 | Schema is `additionalProperties: false` yet omits eight keys the code reads; any validator run rejects the shipped content | `enemy-definition.v1.json:7`; missing `retreat_threshold`, `windup_variance`, `attack_token_group`, `weapon_kit`, `attacks`, `combo_followups`, `coinReward`, `goldReward` |
| ENE-17 | P2 | `training_grunt.gd` duplicates the state machine with its own enum and drifts (no retreat, no LOS, no attack tokens) | `training_grunt.gd:3-235` |
| ENE-18 | P2 | `EnemyPool` is dead code; spawning allocates and frees every instance | `enemy_pool.gd:9-38`; no call site |
| ENE-19 | P2 | Windup audio is a synthesized 72 Hz tone shared by all 29 enemies | `audio_director.gd:41` |
| ENE-20 | P2 | `_force_dead_silent()` has no call site | `castle_enemy_base.gd:354` |

## Target design

### Data-driven movesets (ENE-01)

Enemy behaviour becomes an `attacks` array in JSON; the base machine stops assuming one swing.
Chosen over per-variant GDScript overrides because 29 archetypes x N attacks in code is unmaintainable
and untestable, and because the base already has the read sites.

```json
"attacks": [
  {
    "id": "overhead",
    "weight": 3.0,
    "min_range": 0.0,
    "max_range": 2.4,
    "windup_duration": 0.75,
    "windup_variance": 0.1,
    "active_duration": 0.18,
    "recovery_duration": 0.6,
    "attack_damage": 14.0,
    "attack_poise_damage": 22.0,
    "damage_type": "physical",
    "hitbox_shape": { "size": [1.2, 0.9, 1.6], "offset": [0.0, 1.0, 0.9] },
    "telegraph": { "color": [0.95, 0.35, 0.15], "shape": "cone", "arc_deg": 90.0, "range": 2.4 },
    "advance_speed_scale": 0.35,
    "anim": "attack_overhead",
    "sfx_windup": "enemy_windup_heavy",
    "combo_followups": [{ "id": "sweep", "chance": 0.45 }]
  }
]
```

`_select_attack_data` filters by `min_range <= distance <= max_range`, then picks by `weight`.
When `attacks` is absent it keeps building a single synthetic entry from the flat keys, so migration is
incremental. `_start_attack` resizes the `Hitbox` `BoxShape3D` from `hitbox_shape` before enabling it.

### Telegraph (ENE-02, ENE-15)

`TelegraphMesh` becomes a decal-style flat mesh on the floor, driven from the selected attack's
`telegraph` block, and is the primary read:

- `_start_windup` sets `visible = true`, builds the shape (`cone` / `line` / `circle`) sized to
  `range` and `arc_deg`, and tweens `shader_parameter/fill` from 0 to 1 over the windup duration.
- Final 0.15 s of windup: fill color lerps to `Color(1.0, 0.9, 0.4)` — the parry window cue.
- `_start_attack` sets fill to 1 and `visible = false` after 0.08 s.
- `_end_attack` / `apply_stagger` / `_finalize_death` force `visible = false`.

`attack_telegraph_started(attack_id: String, duration: float)` and
`attack_active(attack_id: String)` get real consumers: `AudioDirector` (per-attack `sfx_windup`),
`VfxService` (windup dust), and the lock-on camera (subtle 0.1 shake on `attack_active`).

### Archetype differentiation (ENE-04, ENE-07)

Behaviour selected by a new `ai_profile` key, implemented as one `EnemyAiProfile` resource-free
dictionary in `castle_enemy_base.gd` plus small strategy scripts under
`scripts/enemies/ai/` so no variant needs code. `ai_profile` values and their contract:

| `ai_profile` | Archetypes | Behaviour delta from base |
|--------------|-----------|---------------------------|
| `bruiser` | `castle_grunt`, `swamp_slasher`, `frost_raider`, `cathedral_acolyte` | Base machine. Windup 0.7-0.9 s, one telegraph, `advance_speed_scale 0.35` |
| `heavy` | `swamp_brute`, `crystal_golem`, `frost_knight`, `cathedral_warden` | Windup 1.1-1.4 s, poise x2.0, immune to stagger below 40 poise damage, `advance_speed_scale 0.0`, 2 attacks with a 0.45 combo chance |
| `skirmisher` | `castle_hound`, `frost_hound`, `swamp_leech`, `crystal_crawler` | `CIRCLE` state: orbits at `attack_range * 1.3` for 1.0-2.0 s before committing; windup 0.4-0.55 s; retreats 1.2 s after every `RECOVERY` |
| `ranged` | `castle_archer`, `frost_archer`, `crystal_spitter`, `swamp_spitter`, `crystal_bat`, `crystal_wisp` | Existing kite logic promoted from `castle_archer.gd` into the base as `REPOSITION`; adds `_lock_shot_trajectory` at windup |
| `caster` | `crystal_shade`, `swamp_witch`, `cathedral_shade` | Ranged plus a 6.0 s-cooldown ground AoE (`telegraph.shape = "circle"`, 1.6 s windup) and a 0.35 s blink on taking a hit while in `WINDUP` |
| `shield` | `castle_shield` | New `GUARD` state: enters when player is within `aggro_range` and facing the enemy; `block_mitigation 0.75` inside `block_angle_deg 100`. Guard breaks after 60 accumulated blocked poise damage, forcing a 2.0 s `STAGGER` with `TelegraphMesh` flashing white |
| `swarm` | `swamp_swarm`, `swamp_bogling` | Shares aggro within 12.0 m (ENE-12); windup 0.35 s; 45 HP; never retreats |
| `beast` | `swamp_toad`, `swamp_hydra` when not a boss | Lunge attack: `active_duration` moves the body forward `3.5 m` over 0.22 s |

State additions to the machine: `CIRCLE`, `REPOSITION`, `GUARD`. Exit conditions:

- `CIRCLE` → `WINDUP` when `_circle_timer <= 0.0` and `_can_attack()`; → `CHASE` when distance > `attack_range * 2.0`.
- `REPOSITION` → `WINDUP` when `preferred_range - 0.5 <= distance <= preferred_range + 0.5` and cooldown clear; → `RETREAT` when distance < `retreat_range`.
- `GUARD` → `WINDUP` when player attacks within 1.5 m (guard-punish) or after 2.5 s of guarding; → `CHASE` when distance > 3.0 m.

### Reach and scale correctness (ENE-03, ENE-10)

Add to `castle_enemy_base.gd`:

```gdscript
func set_damage_multiplier(mult: float) -> void:
    _damage_multiplier = maxf(0.1, mult)
```

applied in `_start_attack` when writing `Hitbox.damage`. Add `body_scale` and
`hurtbox_size: [x, y, z]` to enemy JSON; `_ready` resizes `CollisionShape3D`, `Hurtbox` shape, and
`get_hp_bar_height()` from those instead of per-script `scale` assignments, deleting the 5 rescale shims.

### Navigation and perception (ENE-11, ENE-12, ENE-13)

- Add `NavigationAgent3D` (`path_desired_distance 0.4`, `target_desired_distance 0.6`,
  `avoidance_enabled true`, `radius 0.5`) to every enemy scene; `_move_towards` queries
  `get_next_path_position()` and falls back to the straight-line vector when the map is not baked.
  `DungeonBuilder` must bake a `NavigationRegion3D` per floor.
- Authored patrol: `patrol_points: [[x, z], ...]` in the room template consumed by
  `procgen_placements`, passed to the enemy through `set_patrol_route(PackedVector3Array)`. Falls back
  to the current random square when the route is empty.
- `EnemyAlertService` autoload: `report_engagement(enemy, position, radius)` on aggro acquisition;
  enemies with `alert_radius > 0.0` in JSON force-latch aggro and enter `INVESTIGATE`.

### Content reachability (ENE-05, ENE-06)

Add the four orphans to pools (`crystal_shade` → `crystal_caverns`, `prism_depths`; `swamp_toad`,
`swamp_witch` → `venom_mire`; `swamp_hag` → `venom_mire` `bossPool` as `miniboss_swamp_hag`), remove
`swamp_hydra` from the `venom_mire` `enemyPool`, and make `_is_reserved_boss_enemy` authoritative by
reading `enemy_type == "boss"` from the definition rather than matching the id prefix.

### Stagger physics (ENE-14)

`_physics_process` must apply gravity and call `move_and_slide()` during `STAGGER`; only `_update_ai`
and the facing turn are skipped. Horizontal velocity decays with
`velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)`.

## Work plan

1. **Schema truth** — extend `content/schemas/enemy-definition.v1.json` with every key the code reads plus the new ones. Fixes ENE-16 alone; nothing else changes.
2. **Damage multiplier + hurtbox sizing** — add `set_damage_multiplier`, `body_scale`, `hurtbox_size` to `castle_enemy_base.gd`; move the 5 rescale shims into JSON. Fixes ENE-03, ENE-10.
3. **Content reachability** — edit `content/biomes/*.json` pools; rewrite `_is_reserved_boss_enemy` in `procgen_placements.gd` to use `enemy_type`. Fixes ENE-05, ENE-06.
4. **Stagger and mesh-tint cleanup** — fix `_physics_process` early-return; delete `_apply_mesh_tint` and the calls in the 8 shims, replacing with a `tint` key consumed by `_setup_diorama_visual`. Fixes ENE-14, ENE-08.
5. **Moveset data path** — implement range-filtered weighted `_select_attack_data`, per-attack hitbox resize, `combo_followups`; author `attacks` for `castle_grunt`, `swamp_brute`, `castle_archer` first. Fixes ENE-01.
6. **Telegraph** — floor decal shader + `TelegraphMesh` driver; wire `attack_telegraph_started` / `attack_active` to `AudioDirector` and `VfxService`. Fixes ENE-02, ENE-15, ENE-19.
7. **AI profiles** — add `CIRCLE`, `REPOSITION`, `GUARD`; move `castle_archer` kiting into the base as the `ranged` profile; set `ai_profile` on all 29 definitions; delete the 19 shim scripts and point the scenes at `castle_enemy_base.gd`. Fixes ENE-04, ENE-07.
8. **Navigation and alerts** — `NavigationAgent3D` in scenes, `NavigationRegion3D` bake in `DungeonBuilder`, `set_patrol_route`, `EnemyAlertService`. Fixes ENE-11, ENE-12, ENE-13.
9. **Cleanup** — `training_grunt.gd` re-parented to `CastleEnemyBase` with a `dummy` `ai_profile`; wire `EnemyPool` into `DungeonBuilder._place_enemy` and `waves_run._spawn_enemy`; delete `_force_dead_silent()`. Fixes ENE-17, ENE-18, ENE-20.

## Data and schema changes

`content/schemas/enemy-definition.v1.json`:

- Add existing-but-unschemad: `retreat_threshold` (number 0-1), `windup_variance` (number >= 0),
  `attack_token_group` (string), `weapon_kit` (string), `coinReward` (integer), `goldReward` (integer),
  `phase2_threshold` (number 0-1).
- Add new: `ai_profile` (enum `bruiser`, `heavy`, `skirmisher`, `ranged`, `caster`, `shield`, `swarm`, `beast`, `dummy`),
  `body_scale` (array of 3 numbers or number), `hurtbox_size` (array of 3 numbers), `tint` (array of 3-4 numbers),
  `alert_radius` (number, default 0.0), `guard_break_poise` (number), `attacks` (array of the attack object above),
  `patrol_style` (enum `random`, `route`, `static`).
- Keep `additionalProperties: false` only after every shipped file validates.

New `content/schemas/enemy-attack.v1.json` holding the attack object, referenced by `$ref` from
`enemy-definition.v1.json` and reused by `content/schemas/` boss definitions.

`content/biomes/*.json` pool edits require no schema change (`biome-definition.v1.json` already
allows arbitrary `enemyId` strings).

No save-format change: `capture_state()` still emits `{"alive", "health"}`, so no
`save_migrator.gd` version bump.

## Acceptance criteria

- [ ] Every file in `content/enemies/` and `content/bosses/` validates against `enemy-definition.v1.json` with `additionalProperties: false`.
- [ ] `castle_grunt` performs at least two distinct attacks with different windup durations and telegraph shapes across 20 consecutive engagements.
- [ ] A floor-10 endless enemy deals strictly more damage than the same enemy on floor 1 with identical player defense.
- [ ] `TelegraphMesh.visible` is `true` for the whole `WINDUP` state and `false` in every other state, asserted in a suite.
- [ ] A `castle_shield` blocks 75 percent of frontal damage, and 60 accumulated blocked poise damage forces a 2.0 s stagger.
- [ ] `swamp_hydra` never appears in a non-boss room; `crystal_shade`, `swamp_toad`, `swamp_witch` each appear in at least one seeded floor of their biome.
- [ ] No enemy remains suspended in mid-air after a stagger.
- [ ] Every enemy scene contains a `NavigationAgent3D`, and an enemy chasing the player around a pillar reaches the player within 6.0 s.
- [ ] `scripts/enemies/` contains no script whose only body is `get_enemy_id()`.

## Validation

Extend `apps/game/client/scripts/validation/suites/combat_suite.gd`:

- `assert_enemy_definitions_schema_valid()` — every `content/enemies/*.json` and `content/bosses/*.json` key is in the schema; every required key present.
- `assert_every_enemy_has_scene_and_script()` — `EnemyCatalog.get_scene(id)` resolves and its root script is `CastleEnemyBase` or a subclass.
- `assert_enemy_ai_profile_known()` — `ai_profile` is one of the enum values for all 29 definitions.
- `assert_damage_multiplier_supported()` — `CastleEnemyBase.has_method("set_damage_multiplier")` and applying `2.0` doubles the `Hitbox.damage` written in `_start_attack`.
- `assert_telegraph_visible_during_windup()` — drive an instance to `WINDUP`, assert `TelegraphMesh.visible == true`; step to `RECOVERY`, assert `false`.
- `assert_telegraph_signal_consumers()` — `attack_telegraph_started.get_connections().size() > 0` after `_ready`.
- `assert_stagger_applies_gravity()` — stagger an airborne instance, step 0.5 s, assert `global_position.y` decreased.
- `assert_attack_selection_respects_range()` — with two `attacks` entries at disjoint ranges, only the in-range one is selected across 50 rolls.
- `assert_shield_guard_break()` — 60 blocked poise damage transitions `castle_shield` to `STAGGER`.

Extend `apps/game/client/scripts/validation/suites/procgen_suite.gd`:

- `assert_no_boss_in_enemy_pool()` — no `enemyPool` entry of any biome has `enemy_type == "boss"`.
- `assert_all_enemies_reachable()` — every id in `content/enemies/` appears in at least one biome `enemyPool` or `bossPool`, except `training_grunt`.
- `assert_navigation_region_baked()` — a generated floor has a `NavigationRegion3D` with a non-empty `navigation_mesh`.

Manual only: judging whether the telegraph decal reads at the default camera pitch on a 1080p display.

## Related

- Existing behaviour: [`../existing_codebase/enemies.md`](../existing_codebase/enemies.md)
- [`bosses.md`](bosses.md) — boss phases build on the same moveset data shape
- [`combat-core.md`](combat-core.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`statuses-and-buffs.md`](statuses-and-buffs.md)
- [`dungeon-builder.md`](dungeon-builder.md) — navigation bake and floor scaling
- [`procgen-placements.md`](procgen-placements.md) — pool selection and patrol routes
- [`diorama-character-skin.md`](diorama-character-skin.md) — profile keys for `caster`, `beast`, `boss`
- [`validation-suites.md`](validation-suites.md)
- [`00-QUALITY-BAR.md`](00-QUALITY-BAR.md)

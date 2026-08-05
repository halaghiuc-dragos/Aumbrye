# Statuses and buffs — improvement plan

Current state: [`../existing_codebase/statuses-and-buffs.md`](../existing_codebase/statuses-and-buffs.md)

## Problem

The status system works and nothing uses it. `StatusController` exists on exactly one node in the project (`player.tscn:89`), so every status the player inflicts is silently dropped at `hurtbox.gd:165`. Of five authored statuses, two (`burn`, `stun`) have no gameplay applier at all. Of eleven relics, five grant stats no system reads. Statuses have no VFX, no audio, no on-body tint and no build-up, so even the ones that land are invisible until the player looks at a HUD corner.

The fix is in four parts: make statuses land on enemies, make them readable, add build-up so they are a resource the player spends hits on rather than a coin flip, and make relics do something other than add a number.

## Gaps

| ID | Priority | Gap | Evidence |
|----|----------|-----|----------|
| STA-1 | P0 | No enemy has a `StatusController`, so every player-inflicted status is dropped | `hurtbox.gd:165`; `StatusController` appears only in `player.tscn:89` |
| STA-2 | P0 | `bleed` is authored on all five dagger attacks and can never apply | `content/weapons/dagger.json:6,18,28,38,50` vs STA-1 |
| STA-3 | P0 | Statuses have no VFX, audio or body tint; the only signal is a HUD icon | `status_controller.gd` makes no `VfxService` or `AudioDirector` call |
| STA-4 | P1 | `stun` has no applier anywhere in the repo | No `apply_status("stun"` and no `"status_on_hit": "stun"` in `content/` |
| STA-5 | P1 | `burn` is applied only by the F8 debug key and `m5_suite` | `combat_hud.gd:357`, `m5_suite.gd:286` |
| STA-6 | P1 | `stunDuration` is read as a boolean; the stun lasts the status `duration` instead | `status_controller.gd:123-124` |
| STA-7 | P1 | Five relics grant stats no gameplay system reads | `relic_frost_shard`/`relic_poison_vial` -> `bonusDamage`, dead at `equipment.gd:150-151`; `relic_sun_medallion` `healthRegen`, `relic_wind_charm` `attackSpeed`, `relic_bloodstone` `lifesteal` have zero readers outside `equipment.gd:12-16` |
| STA-8 | P1 | No status build-up; one hit applies full stacks with no resistance | `status_controller.gd:41-60`; no `buildup`/`threshold` key in `content/schemas/status-definition.v1.json` |
| STA-9 | P2 | Status ticks bypass defense, guard, i-frames and `HitFeedback` | `status_controller.gd:100` calls `_health.take_damage()` directly |
| STA-10 | P2 | `_recalc_modifiers()` runs and emits `statuses_changed` every physics frame while any status is active | `status_controller.gd:38,125` |
| STA-11 | P2 | Relics can only add flat stats; no triggers, no conditions | `content/schemas/relic-definition.v1.json:6-17`; `run_buffs.gd` exposes only `get_stat_totals()` |
| STA-12 | P2 | The HUD shows player statuses only; enemy statuses are invisible | `combat_hud.gd:85` |
| STA-13 | P3 | `StatusCatalog._definitions` is a static cache with no invalidation | `status_catalog.gd:4,21-22` |

## Target design

### 1. Every damageable body owns a StatusController (STA-1, STA-2)

Do not lazily create the node from `Hurtbox` — that hides an authoring error and produces a controller with no `health_path`. Instead make the controller mandatory and assert it.

Add to every enemy scene under `apps/game/client/scenes/enemies/` and `scenes/bosses/`, as a direct child of the `CharacterBody3D`:

```
[node name="StatusController" type="Node" parent="."]
script = ExtResource("status_controller")
health_path = NodePath("../Health")
team = "enemy"
```

Then in `hurtbox.gd`, replace the silent `get_node_or_null` with a resolved-and-warned lookup:

```gdscript
func _resolve_status_controller() -> StatusController:
    var body := _find_character_body()
    if body == null:
        return null
    var ctrl := body.get_node_or_null("StatusController") as StatusController
    if ctrl == null:
        push_warning("Hurtbox: %s has no StatusController; status '%s' dropped" % [body.name, info.status_id])
    return ctrl
```

Cache the result in `_ready()` rather than resolving per hit.

`StatusController` should also gain `func set_health(h: Health) -> void` so a runtime-spawned body can bind without a `NodePath`.

### 2. Build-up instead of instant application (STA-8)

A status that lands on hit one is either irrelevant or oppressive. Move to a build-up meter, the standard for this genre.

Schema change — `content/schemas/status-definition.v1.json`, add to `properties`:

```json
"buildupThreshold": { "type": "number", "minimum": 1 },
"buildupDecayPerSecond": { "type": "number", "minimum": 0 },
"buildupDecayDelay": { "type": "number", "minimum": 0 },
"resistGainPerApplication": { "type": "number", "minimum": 0, "maximum": 1 }
```

Authored values:

| id | `buildupThreshold` | `buildupDecayPerSecond` | `buildupDecayDelay` | `resistGainPerApplication` |
|----|--------------------|--------------------------|---------------------|-----------------------------|
| `bleed` | 60 | 12 | 3.0 | 0.20 |
| `burn` | 50 | 15 | 2.5 | 0.20 |
| `poison` | 70 | 8 | 4.0 | 0.15 |
| `freeze` | 80 | 20 | 2.0 | 0.30 |
| `stun` | 100 | 30 | 1.5 | 0.35 |

Weapons and enemies then author build-up per hit rather than stacks. Rename the weapon key path in `content/schemas/weapon-definition.v1.json` from `status_stacks` to `status_buildup` (integer, 1-100) and give the dagger `"status_buildup": 22` per light hit, so three hits proc `bleed`. Frost enemies get `"status_buildup_on_hit": 30`, so three connected hits freeze.

`StatusController` gains:

```gdscript
func add_buildup(status_id: String, amount: float) -> bool   # returns true if it procced
func get_buildup(status_id: String) -> float                 # 0.0 - 1.0 normalised, for the HUD
func get_resistance(status_id: String) -> float              # 0.0 - 1.0
```

`add_buildup` raises the meter by `amount * (1.0 - get_resistance(status_id))`, and when it crosses `buildupThreshold` calls the existing `apply_status(status_id, maxStacks)`, zeroes the meter, and raises resistance by `resistGainPerApplication` (capped at 0.75). Resistance decays 0.05 per second once the status expires. Meters decay at `buildupDecayPerSecond` after `buildupDecayDelay` seconds without a contribution.

Keep `apply_status()` as the direct path for hazards, bosses and debug.

### 3. Statuses you can see and hear (STA-3, STA-12)

Add to the schema:

```json
"bodyTint": { "type": "string" },
"onApplyVfx": { "type": "string" },
"tickVfx": { "type": "string" },
"onApplySfx": { "type": "string" },
"buildupColor": { "type": "string" }
```

`StatusController` emits `status_applied(status_id)`, `status_removed(status_id)` and `status_ticked(status_id, damage)`. A new sibling `StatusVisuals` node listens and drives:

- On apply: `VfxService.spawn_burst(global_position, Color.from_string(def.onApplyVfx, WHITE), 18)` and `AudioDirector.play_sfx(def.onApplySfx)`.
- While active: a persistent tint through the existing `MaterialFlash` shader parameter, blended at 0.35 strength in the status's `bodyTint`. Priority when several are active: `stun` > `freeze` > `burn` > `poison` > `bleed`.
- On tick: a 6-particle micro-burst at the body's chest marker plus the damage number already spawned by the tick, so damage over time reads as damage and not as a health bar drifting down for no reason.

Enemy-side readability: extend `enemy_health_bar` with up to three 8x8 status pips under the bar, driven by `status_applied`/`status_removed`. Player build-up meters go in the HUD as thin arcs around the status icon slot, filled to `get_buildup()` in `buildupColor`, so a player can see a freeze coming.

Target numbers: an applied status must be identifiable within 150 ms of application from a normal camera distance, and the tint must remain visible during a `MaterialFlash` hit flash (flash writes to a separate shader parameter, so blend rather than overwrite).

### 4. Fix stun and give burn a home (STA-4, STA-5, STA-6)

`_recalc_modifiers()` must use the authored duration:

```gdscript
func _recalc_modifiers() -> void:
    var prev_slow := _slow_multiplier
    var prev_stun := _stunned
    _slow_multiplier = 1.0
    _stunned = false
    for status_id in _active:
        var def := StatusCatalog.get_definition(status_id)
        _slow_multiplier = minf(_slow_multiplier, float(def.get("slowMultiplier", 1.0)))
        var stun_dur := float(def.get("stunDuration", 0.0))
        if stun_dur > 0.0 and float(_active[status_id].get("elapsed", 0.0)) < stun_dur:
            _stunned = true
    if not is_equal_approx(prev_slow, _slow_multiplier) or prev_stun != _stunned:
        statuses_changed.emit()
```

This also resolves STA-10: track `elapsed` per entry and emit only on an actual change.

Appliers to author:

- `stun` — the castle brute's slam (`content/enemies/castle_brute.json`), `"status_on_hit": "stun"`, `"status_buildup_on_hit": 55`, so two slams stun. Also the player's greatsword heavy at `"status_buildup": 40`.
- `burn` — the fire-themed content that already exists: `relic_flame_core` should convert a fraction of the player's damage to fire and contribute burn build-up (see below), and any brazier hazard should apply it via `apply_status("burn", 1, 3.0)`.

### 5. Relics that do something (STA-7, STA-11)

Two changes. First, wire the five dead stats:

| Stat | Where to read it |
|------|------------------|
| `healthRegen` | `Health` gains `regen_per_second`, configured from `inventory_service.apply_equipment_to_player_node()` next to the existing `configure()` call; ticks out of combat only (3 s since last damage taken) |
| `attackSpeed` | `weapon_controller.gd` divides `startup`, `active` and `recovery` by `1.0 + attackSpeed`, clamped to a 1.5x ceiling so animations do not desync |
| `lifesteal` | `hitbox.gd` after a confirmed hit: heal the attacker `final_damage * lifesteal`, floor 1 |
| `frostDamage` / `poisonDamage` | Contribute build-up rather than damage: `status_buildup` for `freeze`/`poison` on every player hit, `+4` each per point |

Second, extend relics past flat stats. Add to `content/schemas/relic-definition.v1.json`:

```json
"trigger": {
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "event": { "enum": ["on_hit", "on_kill", "on_damaged", "on_dodge", "on_parry", "on_room_clear"] },
    "chance": { "type": "number", "minimum": 0, "maximum": 1 },
    "cooldown": { "type": "number", "minimum": 0 },
    "effect": { "enum": ["apply_status", "heal", "grant_stamina", "spawn_burst", "grant_iframes"] },
    "statusId": { "type": "string" },
    "amount": { "type": "number" }
  },
  "required": ["event", "effect"]
}
```

`RunBuffs` gains `func fire_trigger(event: String, ctx: Dictionary) -> void`, called from `hitbox.gd` (`on_hit`), `health.gd` (`on_damaged`, `on_kill`), `dodge.gd` (`on_dodge`) and `guard.gd` (`on_parry`). It walks `_active`, matches `trigger.event`, rolls `chance` (scaled by stacks), respects a per-relic cooldown, and dispatches. Reference authoring:

```json
{
  "id": "relic_bloodstone",
  "name": "Bloodstone",
  "description": "Heal on kill.",
  "maxStacks": 3,
  "stats": { "lifesteal": 0.03 },
  "trigger": { "event": "on_kill", "chance": 1.0, "cooldown": 0.0, "effect": "heal", "amount": 6 }
}
```

### 6. Status ticks respect mitigation (STA-9)

Route `_apply_tick` through the victim's `Hurtbox` with a flag that skips i-frames and guard (damage over time should not be dodgeable) but honours defense and produces a damage number and `HitFeedback` call:

```gdscript
var info := DamageInfo.new()
info.amount = tick_dmg
info.damage_type = dmg_type
info.source_team = "status"
info.ignore_iframes = true
info.ignore_guard = true
_hurtbox.receive_hit(info)
```

Requires two new `DamageInfo` booleans and the corresponding early-out changes in `hurtbox.receive_hit`.

### 7. Cache invalidation (STA-13)

`StatusCatalog` gains `static func reset_cache() -> void`, called from the same content-reload path as the other catalogs.

## Validation

Add to `apps/game/client/scripts/validation/suites/combat_suite.gd`:

- `test_enemy_has_status_controller` — instantiate every scene in `apps/game/client/scenes/enemies/`, assert `get_node_or_null("StatusController") != null` and that its `health_path` resolves.
- `test_status_lands_on_enemy` — spawn a grunt, call `hurtbox.receive_hit` with `status_id = "bleed"`, assert `get_active_statuses()` has one entry with id `bleed`.
- `test_buildup_threshold` — apply `add_buildup("bleed", 22.0)` three times, assert not applied after two and applied after three.
- `test_buildup_decay` — one `add_buildup` of 30, wait `buildupDecayDelay + 2.0` s, assert `get_buildup()` dropped by `2.0 * buildupDecayPerSecond / buildupThreshold` within 0.02.
- `test_resistance_growth` — proc `bleed` twice, assert `get_resistance("bleed")` is 0.40 within 0.001 and the third proc needs more build-up.
- `test_stun_uses_stun_duration` — apply `stun` (`duration` 1.2, `stunDuration` 1.2), then a variant with `stunDuration` 0.4, assert `is_stunned()` is false at 0.5 s in the second case.
- `test_every_status_has_an_applier` — for each id in `StatusCatalog.all_ids()`, grep `content/enemies/`, `content/bosses/`, `content/weapons/` and `content/hazards/` for `status_on_hit`/`status` equal to that id, or the script call `apply_status("<id>"` outside `combat_hud.gd` and the validation suites; fail with the list of orphans.
- `test_every_relic_stat_is_read` — union of every key in every `content/relics/*.json` `stats` object must be a subset of a hand-maintained `READ_STATS` constant in the suite; fail naming the unread keys.
- `test_relic_trigger_fires` — grant a relic with `{"event": "on_kill", "effect": "heal", "amount": 6}`, kill an enemy, assert player health rose by exactly 6.
- `test_status_tick_respects_defense` — apply `poison` to a body with `combat_defense` 5, assert the tick damage matches `DamageInfo.apply_defense(2.5, 5)` rather than 2.5.
- `test_statuses_changed_not_spammed` — apply `bleed`, count `statuses_changed` emissions over 60 physics frames, assert fewer than 4.

Content validation in `m5_suite.gd`: assert every `content/statuses/*.json` validates against `status-definition.v1.json` including the new keys, and that `buildupThreshold` is present on every status once the build-up system ships.

## Sequencing

1. STA-1 and STA-2 — add `StatusController` to every enemy scene, warn on a dropped status. Unblocks everything else.
2. STA-3 — VFX, audio, tint, enemy pips. Statuses become visible.
3. STA-8 with STA-6 — build-up, resistance, correct stun duration.
4. STA-4 and STA-5 — author appliers for `stun` and `burn`.
5. STA-7 — wire the five dead relic stats.
6. STA-9, STA-10, STA-11, STA-12, STA-13.

## Related

- [`hit-hurtboxes.md`](hit-hurtboxes.md) — the `Hurtbox` lookup that must stop failing silently
- [`combat-core.md`](combat-core.md) — `DamageInfo` flags, resistances, defense
- [`weapons.md`](weapons.md) — `status_buildup` authoring on weapon attacks
- [`hit-feedback.md`](hit-feedback.md) — shared `MaterialFlash` and `VfxService` budget
- [`combat-validation.md`](combat-validation.md) — where the assertions above live
- [`loot-and-equipment.md`](loot-and-equipment.md), [`inventory-service.md`](inventory-service.md)

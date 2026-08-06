# Stamina and mana

Two near-identical resource nodes mounted on `player.tscn`. `Stamina` is on the live play path and gates every attack, dodge, jump, sprint, heal and block. `Mana` is instantiated, ticks a regen loop, and drives a HUD bar; nothing in the game spends it.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/combat/stamina.gd` | `Stamina` node: pool, exhaustion, regen |
| `apps/game/client/scripts/combat/mana.gd` | `Mana` node: pool, regen |
| `apps/game/client/scenes/player/player.tscn` | Mounts both (`:68-72`) |
| `apps/game/client/scripts/ui/combat_hud.gd` | Binds both bars (`:362-374`) |

## How it works

### Stamina

`stamina.gd`. Constants: `MAX_STAMINA := 100.0`, `REGEN_DELAY := 0.7` seconds, `REGEN_RATE := 25.0` per second, `EXHAUSTION_RECOVERY := 15.0`.

`_process(delta)` (`:54`) clears `_exhausted` once `current >= EXHAUSTION_RECOVERY`, decrements `_regen_timer` and returns while it is positive, then regenerates at a rate chosen by state: `0` while `RegenState.SUPPRESSED` (attacks, dodges), `REGEN_RATE_BLOCKING := 6.0` while blocking, `REGEN_RATE_EXHAUSTED := 12.0` while exhausted, else `REGEN_RATE * _regen_multiplier`. `set_regen_state()` is called from `weapon_controller.gd`, `dodge.gd`, and `guard.gd`.

Three spend paths, which behave differently:

| Method | Refuses while `_exhausted` | Refuses when `current < amount` | Emits `insufficient` | Sets `_regen_timer` |
|--------|---------------------------|--------------------------------|---------------------|---------------------|
| `consume(amount)` (`:44`) | yes | yes | yes | yes |
| `drain(amount)` (`:60`) | no | yes | no | yes |
| `has(amount)` (`:72`) | returns false | returns false | no | n/a |

Both `consume` and `drain` refuse while `_exhausted`, emit `insufficient` on failure, set `_exhausted = true` and emit `depleted` when `current` reaches 0. `get_speed_multiplier()` returns `0.75` while exhausted (read by `locomotion.gd`).

`configure(max_value, regen_multiplier, preserve_ratio)` (`:29`) sets `max_stamina` (floor 1.0) and `_regen_multiplier` (floor 0.1). With `preserve_ratio := true`, `current` scales proportionally when max rises; otherwise it clamps down. Clears exhaustion. Called from `inventory_service.gd` with `Stamina.MAX_STAMINA + max_stamina_bonus(...)` and `stamina_regen_multiplier(...)`. `Mana.configure` uses the same API with `max_mana_bonus` / `mana_regen_multiplier`.

`reset_stamina()` refills and clears exhaustion; called from `run_flow.gd:455`, `combat_arena.gd:80`, `debug_overlay.gd:213`.

Live spenders:

| Cost | Caller |
|------|--------|
| Attack `stamina_cost` from weapon JSON, times `stamina_cost_multiplier(talent_stats)` | `weapon_controller.gd:273-277` |
| Weapon-art `stamina_cost` (default 24.0) | `weapon_controller.gd:288-292` (unreachable — see [`weapons.md`](weapons.md)) |
| Bow heavy `stamina_cost` (default 18.0), **not** talent-scaled | `weapon_controller.gd:402-407` |
| `DODGE_STAMINA_COST := 32.0` | `dodge.gd:110` |
| `JUMP_STAMINA_COST := 18.0` | `dodge.gd:94` |
| `SPRINT_STAMINA_DRAIN := 18.0` per second, via `drain()` | `locomotion.gd:109` |
| `BLOCK_STAMINA_DRAIN_PER_HIT := 18.0` per blocked hit | `guard.gd:106` |
| `HEAL_STAMINA_COST` | `player_heal.gd:62` |

Authored attack costs range from 8 (`bow` light) to 38 (`greatsword` heavy). At `REGEN_RATE := 25.0`, a full 100-point bar refills in 4.0 s of standing still plus the 0.7 s delay.

### Mana

`mana.gd`. Constants: `MAX_MANA := 100.0`, `REGEN_DELAY := 0.7`, `REGEN_RATE := 20.0`. The API mirrors `Stamina` minus exhaustion: `configure`, `consume`, `drain`, `has`, `reset_mana`, plus `mana_changed`, `depleted` and `insufficient` signals.

`inventory_service.gd` configures max and regen via `max_mana_bonus` / `mana_regen_multiplier`. `combat_hud.gd` connects `mana_changed`, `insufficient`, and `depleted`. Staff heavy attacks and weapon arts can spend mana via `weapon_controller.gd`; `player_heal.gd` spends mana for heals. Consumables with `manaRestore` restore mana through the inventory consumption path.

`waves_run_service.gd:28-29,34` lists a `mana_potion` item id in its reward tables, but no consumable code path calls `Mana.heal`-equivalent restoration.

## Contracts

- **Node names:** children of the player `CharacterBody3D` named exactly `Stamina` and `Mana`. `WeaponController` (`:79`), `Guard` (`:42`), `Dodge` (`:39`) and `Locomotion` (`:29`) each resolve `Stamina` by that name.
- **Class names:** `Stamina` and `Mana` are `class_name` types; `combat_hud.gd` casts to both.
- **Signals:** `stamina_changed(current, max_value)` / `mana_changed(current, max_value)` — consumed by `combat_hud.gd`. `depleted` and `insufficient` connect to `combat_hud.gd` bar flash and `AudioDirector` denial cues.
- **Stat keys read (indirectly, via `CombatStatModifiers`):** `staminaMax`, `staminaRegen`, `staminaCostReduction`.
- **Constants read by other files:** `Stamina.MAX_STAMINA` and `Mana.MAX_MANA` in `combat_hud.gd:371,374`; `Stamina.MAX_STAMINA` in `inventory_service.gd:193`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Stamina pool, regen, exhaustion | IMPLEMENTED | `stamina.gd:54-119` |
| `RegenState` suppression during attack/block/dodge | IMPLEMENTED | `stamina.gd:8,44-67`; callers in `weapon_controller.gd`, `guard.gd`, `dodge.gd` |
| Stamina gating on attacks, dodge, jump, sprint, block, heal | IMPLEMENTED | `weapon_controller.gd`, `dodge.gd`, `locomotion.gd`, `guard.gd`, `player_heal.gd` |
| Equipment/talent scaling of max stamina and regen | IMPLEMENTED | `inventory_service.gd` |
| Exhaustion speed penalty + poise vulnerability | IMPLEMENTED | `get_speed_multiplier()` `stamina.gd:48-51`; `EXHAUSTED_POISE_MULT` in `hurtbox.gd:124` |
| `insufficient` / `depleted` HUD and audio feedback | IMPLEMENTED | `combat_hud.gd:433-434,550-557` |
| `drain()` aligned with `consume()` exhaustion gate | IMPLEMENTED | `stamina.gd:88-101` |
| Mana equipment scaling and spenders | IMPLEMENTED | `inventory_service.gd:283-285`, `weapon_controller.gd`, `player_heal.gd` |
| Class `resources` block tuning | PARTIAL | Schema exists; not all classes authored with overrides |
| `mana_potion` consumable restore | PARTIAL | Item listed in waves rewards; restore path depends on `manaRestore` key on item defs |

## Related

- Improvement plan: [`../actual_improvements/stamina-mana.md`](../actual_improvements/stamina-mana.md) — **FINISHED**
- [`weapons.md`](weapons.md) — attack costs
- [`dodge.md`](dodge.md) — dodge and jump costs
- [`guard.md`](guard.md) — per-hit block drain
- [`combat-core.md`](combat-core.md) — `CombatStatModifiers` stamina helpers
- [`ui/combat_hud.md`](ui/combat_hud.md) — the bars
- [`player-heal.md`](player-heal.md), [`locomotion.md`](locomotion.md)

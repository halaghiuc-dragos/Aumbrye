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

`_process(delta)` (`:33`) clears `_exhausted` once `current >= EXHAUSTION_RECOVERY`, decrements `_regen_timer` and returns while it is positive, then regenerates `REGEN_RATE * _regen_multiplier * delta`. Regen is not gated on combat state — it runs during attacks, blocks and dodges alike; the only brake is the 0.7 s window after each spend.

Three spend paths, which behave differently:

| Method | Refuses while `_exhausted` | Refuses when `current < amount` | Emits `insufficient` | Sets `_regen_timer` |
|--------|---------------------------|--------------------------------|---------------------|---------------------|
| `consume(amount)` (`:44`) | yes | yes | yes | yes |
| `drain(amount)` (`:60`) | no | yes | no | yes |
| `has(amount)` (`:72`) | returns false | returns false | no | n/a |

Both `consume` and `drain` set `_exhausted = true` and emit `depleted` when `current` reaches 0.

`configure(max_value, regen_multiplier)` (`:24`) sets `max_stamina` (floor 1.0) and `_regen_multiplier` (floor 0.1), clamps `current` down to the new max — it does **not** refill — and clears exhaustion. Called from `inventory_service.gd:193-194` with `Stamina.MAX_STAMINA + max_stamina_bonus(equip_stats, talent_stats)` and `stamina_regen_multiplier(talent_stats)`.

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

Every one of `configure`, `consume`, `drain`, `has` and `reset_mana` is defined and has no caller anywhere under `apps/game/client/scripts/`. The only code that touches the node is `combat_hud.gd:365-374`, which connects `mana_changed` and seeds the bar with `Mana.MAX_MANA`. Because nothing spends it and it starts full, the bar renders at 100% for the entire game.

`waves_run_service.gd:28-29,34` lists a `mana_potion` item id in its reward tables, but no consumable code path calls `Mana.heal`-equivalent restoration.

## Contracts

- **Node names:** children of the player `CharacterBody3D` named exactly `Stamina` and `Mana`. `WeaponController` (`:79`), `Guard` (`:42`), `Dodge` (`:39`) and `Locomotion` (`:29`) each resolve `Stamina` by that name.
- **Class names:** `Stamina` and `Mana` are `class_name` types; `combat_hud.gd` casts to both.
- **Signals:** `stamina_changed(current, max_value)` / `mana_changed(current, max_value)` — consumed by `combat_hud.gd`. `depleted` and `insufficient` are declared on both nodes and have no `connect` call anywhere under `apps/`.
- **Stat keys read (indirectly, via `CombatStatModifiers`):** `staminaMax`, `staminaRegen`, `staminaCostReduction`.
- **Constants read by other files:** `Stamina.MAX_STAMINA` and `Mana.MAX_MANA` in `combat_hud.gd:371,374`; `Stamina.MAX_STAMINA` in `inventory_service.gd:193`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Stamina pool, regen, exhaustion | IMPLEMENTED | `stamina.gd:33-79` |
| Stamina gating on attacks, dodge, jump, sprint, block, heal | IMPLEMENTED | `weapon_controller.gd:274`, `dodge.gd:94,110`, `locomotion.gd:109`, `guard.gd:106`, `player_heal.gd:62` |
| Equipment/talent scaling of max stamina and regen | IMPLEMENTED | `inventory_service.gd:193-194` |
| `Stamina.drain()` ignoring exhaustion | PARTIAL | `stamina.gd:60-69` has no `_exhausted` check and never emits `insufficient`, so sprint can drain from below `EXHAUSTION_RECOVERY := 15.0` down to 0 while `consume()` would refuse |
| Regen suppression during combat actions | ABSENT | `stamina.gd:33-41` — the only brake is the flat 0.7 s post-spend delay |
| Exhaustion consequence beyond refusal | ABSENT | `_exhausted` is read only by `consume()` and `has()`; `depleted` has no listener |
| `insufficient` feedback | ABSENT | Signal declared at `stamina.gd:6` and `mana.gd:6`; no `connect` anywhere under `apps/` |
| Bow shot cost bypassing talent reduction | PARTIAL | `weapon_controller.gd:402` reads `stamina_cost` raw, unlike `:273` |
| `Mana.consume` / `drain` / `has` / `configure` / `reset_mana` | STUB | Defined in `mana.gd:22,39,51,62,66`; no call site under `apps/game/client/scripts/` |
| Mana HUD bar | FAKE | `combat_hud.gd:140-154,473-477` renders a bar that is permanently 100/100 because nothing spends mana |
| Mana scaling from equipment/talents | ABSENT | `inventory_service.gd:187-198` configures `Health`, `Stamina` and `Poise`; `Mana` is not touched |
| `mana_potion` item | PARTIAL | Listed in `waves_run_service.gd:28-29,34`; no consumption code path restores mana |

## Related

- Improvement plan: [`../actual_improvements/stamina-mana.md`](../actual_improvements/stamina-mana.md)
- [`weapons.md`](weapons.md) — attack costs
- [`dodge.md`](dodge.md) — dodge and jump costs
- [`guard.md`](guard.md) — per-hit block drain
- [`combat-core.md`](combat-core.md) — `CombatStatModifiers` stamina helpers
- [`ui/combat_hud.md`](ui/combat_hud.md) — the bars
- [`player-heal.md`](player-heal.md), [`locomotion.md`](locomotion.md)

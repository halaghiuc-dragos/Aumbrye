# Player heal — improvement plan

## Current state

`PlayerHeal` (`apps/game/client/scripts/player/player_heal.gd`) gives the player three charges, a `1.35` s drink, and a `45` percent heal, refilled at a bonfire by `RunFlow.rest_at_bonfire`. The state machine works. See [`../existing_codebase/player-heal.md`](../existing_codebase/player-heal.md).

Everything a player would use to make the decision is missing. There is no charge counter on screen — `charges_changed` has no listener anywhere in the repo. The drink plays the `stagger` hurt animation because `play_heal` is an alias for `play_stagger`. There is no sound. The movement lock is written correctly but never applied, because its only caller sits behind an unconditional `return`. Nothing interrupts a drink when the player is hit, and charges do not persist across a scene load.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| HEA-01 | P0 | No charge HUD. `charges_changed(current, max_value)` is emitted three times and has no listener anywhere; `combat_hud.gd` has no flask widget | `player_heal.gd:30`, `:45`, `:74`; grep of `charges_changed` finds only `player_heal.gd` |
| HEA-02 | P0 | Drinking plays the hurt animation. `PlayerAnimDirector.play_heal(duration)` is a one-line alias for `play_stagger(duration)`, and `DioramaAnimLibrary.CLIPS` has no heal clip. The `stagger` clip is time-warped to `speed_scale = 0.85 / 1.35 = 0.63` | `apps/game/client/scripts/player/player_anim_director.gd:128-129`, `apps/game/client/scripts/art/characters/diorama_anim_library.gd:230`, `apps/game/client/scripts/art/characters/diorama_anim_controller.gd:217-220` |
| HEA-03 | P0 | Drinking does not lock movement. `locks_movement()` is correct, but its only caller is unreachable behind `player_combat_reactions.gd:59-60`, so the player sprints at `7.0` m/s while drinking | `player_heal.gd:48-49`, `apps/game/client/scripts/player/player_combat_reactions.gd:59-66` |
| HEA-04 | P0 | A drink cannot be interrupted. Nothing clears `is_drinking` on damage, poise break, or stagger, so a hit mid-drink costs nothing and the heal still lands | `player_heal.gd:33-40`; no `Health` or `Poise` signal connection in `_ready` (`:25-30`) |
| HEA-05 | P1 | No drink SFX. `player_heal.gd` never calls `AudioDirector`, and `SFX_PROFILES` has no `heal` entry — `play_sfx` silently substitutes the `hit` profile for unknown keys | `apps/game/client/scripts/audio/audio_director.gd:34-43`, `:221-226` |
| HEA-06 | P1 | No drink VFX. No `VfxService` call anywhere in the file | absence in `player_heal.gd` |
| HEA-07 | P1 | Charges do not persist. `current_charges` is a plain field initializer with no `LocalSave` key, so it resets to `3` on every scene load, including a floor transition mid-run | `player_heal.gd:15`; no `PlayerHeal` reference in `apps/game/client/scripts/save/local_save.gd` |
| HEA-08 | P1 | `max_charges` and `HEAL_AMOUNT` cannot be upgraded. `max_charges` is writable and nothing writes it; `HEAL_AMOUNT` is `const`. No `content/` key feeds either, so flask upgrades are impossible | `player_heal.gd:5-6`, `:14` |
| HEA-09 | P2 | `HEAL_STAMINA_COST = 0.0` makes both stamina checks unreachable dead code | `player_heal.gd:8`, `:59-62` |
| HEA-10 | P2 | The heal is a single instantaneous application at the end of the window, so the player gets no readable feedback about how much is coming and interruption is all-or-nothing even once implemented | `player_heal.gd:71-77` |

## Target design

**Interruptible, marker-driven drink.** The drink becomes a three-phase action anchored on animation markers rather than a single timer:

| Phase | Window | Behaviour |
|-------|--------|-----------|
| raise | `0.00`–`0.30` s | committed: movement locked, `dodge` cancels for free and refunds the charge |
| gulp | `0.30`–`0.95` s | committed: `dodge` cancels but the charge is spent; two `anim_heal_gulp` markers fire SFX |
| commit | `0.95` s | `anim_heal_commit` fires; health is applied here, not at the end |
| recover | `0.95`–`1.35` s | movement lock released at `1.15` s so the tail is cancellable by any action |

| Named constant | Default | Meaning |
|----------------|---------|---------|
| `DRINK_DURATION` | `1.35` s | unchanged, matches the new `heal` clip length |
| `DRINK_FREE_CANCEL_END` | `0.30` s | cancel window that refunds the charge |
| `DRINK_COMMIT_TIME` | `0.95` s | when health is applied |
| `DRINK_LOCK_END` | `1.15` s | when movement unlocks |
| `INTERRUPT_POISE_THRESHOLD` | `8.0` | poise damage that breaks a drink |
| `HEAL_AMOUNT` | `0.45` | base fraction, now data-driven |
| `HEAL_TICK_COUNT` | `3` | health arrives in three steps over `0.24` s so the bar reads as a heal, not a snap |

Interruption: `CombatReactions.stagger_started`, or any `Hurtbox` hit whose `poise_damage >= INTERRUPT_POISE_THRESHOLD`, cancels the drink. Before `DRINK_COMMIT_TIME` the charge is lost and no health is gained — the trade the flask exists to create. After it, the heal has already landed.

Rejected alternative: making the heal apply gradually across the whole window. It would let a player pre-drink into a boss combo and keep partial value with no decision, which removes the tension the bound-charge design is built on.

**Charge HUD.** Add a flask row to `combat_hud.gd` under the existing bars, sized `BAR_WIDTH` wide and `18.0` px tall: one pip per charge, `PIP_SIZE = 14` px with `PIP_GAP = 4` px, filled pips in `Color(0.42, 0.82, 0.45)` and spent pips at 25 percent alpha. It listens to `charges_changed`, flashes the consumed pip white for `0.12` s, and dims the whole row while `is_drinking` so the commit point is visible. When `max_charges` exceeds 8 the row switches to a numeric `count / max` label so an upgraded flask does not overflow the width.

**Sound and VFX.** New `AudioDirector.SFX_PROFILES` entries: `heal_raise` `{freq 180.0, duration 0.10, bus SFX}`, `heal_gulp` `{freq 300.0, duration 0.12, bus SFX}`, `heal_commit` `{freq 520.0, duration 0.22, bus SFX}`. `VfxService.play_heal_burst(world_pos, color)` emits an upward `Color(0.42, 0.86, 0.5)` sparkle burst at the commit frame, plus a short emissive pulse on the rig via `MaterialFlash.flash(visual, Color(0.42, 0.86, 0.5), 0.18)`.

**Persistence.** Charges belong to run state, not to the meta save. Add `healCharges: int` to the character run blob written by `LocalSave`, saved whenever `charges_changed` fires and read in `PlayerHeal._ready`. Bonfire rest and a new run both reset to `max_charges`.

**Data-driven flask.** New content file `content/progression/flask.json`:

```json
{
  "base_charges": 3,
  "base_heal_fraction": 0.45,
  "charge_upgrades": [
    {"id": "flask_capacity_1", "charges": 4, "cost": {"shards": 250}},
    {"id": "flask_capacity_2", "charges": 5, "cost": {"shards": 700}}
  ],
  "potency_upgrades": [
    {"id": "flask_potency_1", "heal_fraction": 0.55, "cost": {"shards": 400}},
    {"id": "flask_potency_2", "heal_fraction": 0.65, "cost": {"shards": 1100}}
  ]
}
```

`PlayerHeal._ready` reads it through `ContentLoader.load_json` and applies the highest owned upgrade from `ProgressionService`. `HEAL_AMOUNT` becomes the fallback default when the file is missing.

**Stamina cost.** Set `HEAL_STAMINA_COST = 12.0` so the two existing checks become live and drinking competes with dodging, or delete the constant and both branches. Chosen: keep it at `12.0`. A free heal with no resource contention makes the stamina economy irrelevant during recovery windows.

## Work plan

1. **Author the `heal` clip and markers** in `diorama_anim_library.gd`, rewrite `PlayerAnimDirector.play_heal` to use it at `Priority.ATTACK`, and add the `heal_commit_frame` signal. Closes HEA-02. Detailed in [`player-anim-director.md`](player-anim-director.md).
2. **Fix the movement-lock aggregator** in `player_combat_reactions.gd` so `PlayerHeal.locks_movement()` is reachable. Closes HEA-03. Detailed in [`player-combat-reactions.md`](player-combat-reactions.md).
3. **Rework the drink into phases**: the five new timing constants, `DRINK_LOCK_END` in `locks_movement()`, `cancel_drink(refund: bool)`, and the health application moved onto `heal_commit_frame` split into `HEAL_TICK_COUNT` steps. Closes HEA-10.
4. **Add interruption.** Connect `CombatReactions.stagger_started` and the new `Hurtbox.damaged` poise argument; call `cancel_drink(false)` past the free window and `cancel_drink(true)` inside it. Closes HEA-04.
5. **Add SFX and VFX.** Three `SFX_PROFILES` entries, `VfxService.play_heal_burst`, the rig flash, and marker wiring. Closes HEA-05, HEA-06.
6. **Add the flask HUD row** to `combat_hud.gd` listening to `charges_changed`. Closes HEA-01.
7. **Persist charges** through `LocalSave` as `healCharges`. Closes HEA-07.
8. **Add `content/progression/flask.json`** plus its schema, read it in `_ready`, and expose the upgrades in the hub vendor UI. Closes HEA-08.
9. **Set `HEAL_STAMINA_COST = 12.0`** and confirm both checks run. Closes HEA-09.

## Data and schema changes

- New content file `content/progression/flask.json` as above. New schema `content/schemas/flask.schema.json` requiring `base_charges` (integer, 1-12), `base_heal_fraction` (number, 0-1), and two optional upgrade arrays whose entries require `id` and either `charges` or `heal_fraction` plus a `cost` object.
- `LocalSave` character blob gains `healCharges: int`. This is a run-state key inside an existing untyped dictionary, so it needs a **`save_migrator.gd` version bump** that defaults `healCharges` to `base_charges` for saves written before the bump; without it a mid-run load would report zero charges.
- `AudioDirector.SFX_PROFILES` gains `heal_raise`, `heal_gulp`, `heal_commit`.
- `diorama_anim_library.gd` gains the `heal` clip and two marker constants; the six `.res` files under `apps/game/client/assets/animations/diorama/` are regenerated.

## Acceptance criteria

- [ ] The HUD shows three filled pips at full charges, dims one on each drink, and the row dims while drinking. (HEA-01)
- [ ] Drinking plays the `heal` clip, not `stagger`. (HEA-02)
- [ ] Held movement keys produce zero velocity from `0.00` s to `1.15` s of a drink and full velocity after. (HEA-03)
- [ ] A 10-poise hit at `0.20` s cancels the drink and refunds the charge; the same hit at `0.60` s cancels it and consumes the charge with no health gained; at `1.00` s the health has already been applied. (HEA-04)
- [ ] Two distinct gulp sounds play during a drink and a commit sound plays at `0.95` s. (HEA-05)
- [ ] A green sparkle burst and a rig flash fire at the commit frame. (HEA-06)
- [ ] Drinking twice, taking a floor transition, and reloading shows one charge remaining. (HEA-07)
- [ ] With `flask_capacity_1` owned, a bonfire rest yields four charges; with `flask_potency_1`, each drink restores 55 percent. (HEA-08)
- [ ] A drink is refused below 12 stamina. (HEA-09)
- [ ] The health bar visibly climbs in three steps over `0.24` s rather than snapping. (HEA-10)

## Validation

Extend `apps/game/client/scripts/validation/suites/player_suite.gd`:

- `player.heal_charges_signal` — connect to `charges_changed`, drink once, assert one emission carrying `(2, 3)`.
- `player.heal_uses_heal_clip` — assert `AnimationPlayer.current_animation == "heal"` during a drink.
- `player.heal_locks_movement` — assert `CombatReactions.is_movement_locked()` is `true` at `0.5` s of a drink and `false` at `1.25` s.
- `player.heal_interrupt_refund_window` — drive the three interruption times and assert charge count and health for each.
- `player.heal_commit_timing` — assert health is unchanged at `0.90` s and changed by the expected fraction at `1.00` s.
- `player.heal_stamina_gate` — set stamina to `11.0` and assert the drink is refused; set `12.0` and assert it starts.
- `player.heal_charges_persist` — back up the save, drink, reload the run blob, assert `healCharges == 2`, restore.
- `player.flask_upgrades_apply` — stub `ProgressionService` ownership of `flask_capacity_1` and `flask_potency_1` and assert `max_charges == 4` and the heal fraction is `0.55`.

Extend `apps/game/client/scripts/validation/suites/content_suite.gd`:

- `content.flask_schema` — validate `content/progression/flask.json` against `content/schemas/flask.schema.json` and assert every upgrade `id` is unique.

Extend `apps/game/client/scripts/validation/suites/save_suite.gd`:

- `save.heal_charges_migration` — load a pre-bump save fixture and assert `healCharges` defaults to `base_charges` rather than `0`.

## Related
- Existing state: [`../existing_codebase/player-heal.md`](../existing_codebase/player-heal.md)
- [`player-anim-director.md`](player-anim-director.md), [`player-combat-reactions.md`](player-combat-reactions.md), [`player-controls.md`](player-controls.md)
- [`stamina-mana.md`](stamina-mana.md), [`ui/combat_hud.md`](ui/combat_hud.md), [`audio-director.md`](audio-director.md), [`vfx-service.md`](vfx-service.md), [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md), [`progression-service.md`](progression-service.md), [`content-data.md`](content-data.md)

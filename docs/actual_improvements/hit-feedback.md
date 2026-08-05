# Hit feedback — improvement plan

## Current state

`HitFeedback` already ships hitstop, a noise-driven camera punch with an FOV kick, gamepad vibration, a damage vignette, material flashing and pooled VFX (see [`../existing_codebase/hit-feedback.md`](../existing_codebase/hit-feedback.md)). The problem is honesty and coordination. The damage number the player reads on a landed hit is `damage_amount` — the value written into the hitbox before crit, backstab, defense, resistances and blocking — so the number is routinely wrong. A single blocked hit fires the feedback path twice from two points inside `receive_hit` and can produce three floating labels with two different figures. Hitstop slows only the attacker's own animation, never the target's, so impacts do not connect visually. A successful i-frame dodge produces nothing at all, and every hit in the game plays the same `"hit"` sound.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| HFB-01 | P0 | The damage number on a landed hit shows the pre-mitigation, pre-crit configured value, not the damage dealt | `hitbox.gd:134-136,153`, `hurtbox.gd:52-56` |
| HFB-02 | P0 | Feedback is emitted from two points inside `receive_hit`, so one blocked hit spawns up to three labels with two different numbers | `hurtbox.gd:51,60`, `hit_feedback.gd:72-77,60-69` |
| HFB-03 | P0 | A successful i-frame dodge produces no feedback of any kind | `hurtbox.gd:37-39` |
| HFB-04 | P1 | Hitstop is applied only to the attacker's `AnimDirector`; the target keeps animating at full speed, so hits do not read as impacts | `hit_feedback.gd:100-112` |
| HFB-05 | P1 | `_restore_animation_speed()` writes `set_speed_scale(1.0)` on every idle frame, clobbering any other speed-scale writer | `hit_feedback.gd:44-45,110-112` |
| HFB-06 | P1 | One `"hit"` audio cue for every hit — no weapon, damage, material, crit or block variation | `hit_feedback.gd:171-173` |
| HFB-07 | P1 | Damage numbers ignore damage type; `AccessibilitySettings.get_damage_color()` exists and is called only by a validation suite | `damage_number.gd:35`, `accessibility_settings.gd:37`, `m6_suite.gd:281` |
| HFB-08 | P1 | Poise break has no dedicated feedback — only a 0.12 s mesh scale pulse | `player_combat_reactions.gd:94-95,124-129` |
| HFB-09 | P2 | `MaterialFlash` duplicates a `ShaderMaterial` and creates a `Tween` per mesh per hit | `material_flash.gd:42-48` |
| HFB-10 | P2 | `feedback_intensity` is an `@export` with no writer and no accessibility binding | `hit_feedback.gd:13`, `accessibility_settings.gd:8-12` |
| HFB-11 | P2 | `_apply_camera_shake` writes `h_offset`/`v_offset` unconditionally every frame even with no shake active, fighting any other camera-offset writer | `hit_feedback.gd:132-137` |

## Target design

### 1. One event, one feedback pass

Every feedback decision moves behind the `hit_resolved(DamageResolution)` signal introduced in [`combat-core.md`](combat-core.md). `Hurtbox.receive_hit` stops calling `_emit_block_feedback` mid-pipeline and stops calling `_emit_victim_feedback` at the end; it builds the resolution and emits once. `Hitbox._try_hit` likewise stops calling `HitFeedback.on_hit` directly — the attacker's feedback is driven by the same resolution, forwarded through `res.attacker`.

```gdscript
# hit_feedback.gd — replaces on_hit / on_hit_received / on_hit_blocked
func on_hit_resolved(res: DamageResolution) -> void
```

One resolution produces exactly one damage-number spawn, exactly one hitstop application and exactly one audio cue. This closes HFB-01 and HFB-02 together, because `res.outgoing` is by construction the number `Health` actually lost.

The three old methods are kept as thin adapters for one release so nothing breaks mid-migration, then deleted.

### 2. Hitstop that both parties feel

Hitstop is the primary impact cue and it currently reaches one animator. Target model — a global, short, weight-scaled freeze:

```gdscript
const HITSTOP_BASE := 0.055          # seconds at weight 1.0
const HITSTOP_MAX := 0.16
const HITSTOP_TIME_SCALE := 0.08     # Engine.time_scale during the freeze
const HITSTOP_CRIT_MULT := 1.6
const HITSTOP_PARRY := 0.18          # a parry gets the longest freeze in the game
```

Duration is `clampf(HITSTOP_BASE * (res.outgoing / 20.0), HITSTOP_BASE * 0.7, HITSTOP_MAX)`, multiplied by `HITSTOP_CRIT_MULT` on a crit. A `sword_basic` light (12 damage) freezes for 0.039 s clamped up to 0.0385 s, a `greatsword` heavy (48) for 0.132 s, a parry for 0.18 s. The heavy weapons feel heavy because the number that drives it is the damage that landed.

Implementation: a new `HitstopService` autoload owns `Engine.time_scale` so two simultaneous hits cannot stack or fight. It exposes `request(duration: float, scale: float = HITSTOP_TIME_SCALE)` which takes the max of the current and requested remaining time. The camera, the HUD and any UI tween run on `PROCESS_MODE_ALWAYS`-equivalent unscaled delta so the interface does not stutter.

`AnimDirector.set_speed_scale` writes are removed from `HitFeedback` entirely, closing HFB-05.

Rejected alternative: per-node animation freezing (slow only the two combatants). It is more surgical but needs a pause hook on every animated system including VFX and projectiles, and half-frozen scenes read worse than a true global freeze at these durations.

### 3. The dodge confirms

On `res.dodged`, `HitFeedback` plays the cue set defined in [`dodge.md`](dodge.md):

| Cue | Value |
|-----|-------|
| Hitstop | 0.09 s at `time_scale` 0.55 (a soft-focus slow, not a hard freeze) |
| VFX | `VfxService.play_dodge_trail(from, to, direction)` — new pooled ribbon |
| Material | `MaterialFlash.flash(body, 0.4, Color(0.6, 0.85, 1.0))` |
| Audio | `AudioDirector.play_combat_sfx("dodge_perfect")` |
| Label | none for a normal dodge; `PERFECT` in `Color(0.6, 0.95, 1.0)` for a perfect dodge |

### 4. Audio that varies

`_play_sfx_hook()` is replaced by a resolution-driven selector:

```gdscript
func _resolve_hit_cue(res: DamageResolution) -> String
```

Cue key is `"hit_<archetype>_<material>"` with fallbacks `"hit_<archetype>"` then `"hit"`. `archetype` comes from `WeaponController.get_archetype()`, `material` from a new `hit_material` string on the victim's `Hurtbox` (`"flesh"`, `"armor"`, `"stone"`, `"crystal"`, `"wood"`), defaulting to `"flesh"`. Special cases take priority: `res.parried` → `"parry"`, `res.blocked` → `"block_<material>"`, `res.crit` → `"crit"`, `res.absorbed_by_poise` → `"stagger"`.

`content/audio_profiles/` gains the cue names; `AudioDirector`'s existing fallback path covers any cue without a file, so the change is safe before the audio exists.

### 5. Damage numbers that read

Presentation is specified in [`combat-core.md`](combat-core.md) section 6 (`spawn_resolution`). The feedback-side requirements are:

- Exactly one label per resolution.
- Color from `AccessibilitySettings.get_damage_color(res.damage_type)`, so the colorblind modes already implemented at `accessibility_settings.gd:37-44` finally do something.
- Crit and backstab get scale and lifetime bumps rather than a second label.
- Numbers stack vertically when multiple land on the same target within 0.2 s, offsetting each new label by 0.35 m upward, so a multi-hit greatsword sweep is legible.

### 6. Poise break as a distinct event

`Poise.poise_broken` routes into `HitFeedback` (currently it reaches only `player_combat_reactions.gd:94`):

| Cue | Value |
|-----|-------|
| Hitstop | 0.14 s |
| Label | `STAGGER` in `Color(1.0, 0.85, 0.35)` |
| VFX | `VfxService.play_stagger_burst(anchor)` — a new ring burst distinct from `play_hit_spark` |
| Audio | `AudioDirector.play_combat_sfx("stagger")` |
| Material | `MaterialFlash.flash(body, 1.0, Color(1.0, 0.9, 0.5))` held for 0.4 s |

This is the moment the player earned with poise damage; it currently looks identical to any other hit.

### 7. Accessibility and cost

- `AccessibilitySettings` gains `feedback_intensity: float = 1.0` (0.0-1.5) and `reduce_hitstop: bool = false`, both persisted through the existing `SAVE_KEY := "accessibility"` dictionary. `HitFeedback._ready()` reads them; `HitstopService` returns immediately when `reduce_hitstop`.
- `MaterialFlash` caches one duplicated `ShaderMaterial` per mesh in a meta and reuses it across hits instead of duplicating each time, and reuses a single `Tween` per mesh by restarting it.
- `_apply_camera_shake` returns early without writing offsets when `_shake_timer <= 0.0` and the offsets are already zero, so it stops competing with `orbit_camera.gd` and `pixel_camera_snap.gd` on idle frames.

## Work plan

1. **`on_hit_resolved`** — add the single entry point on `HitFeedback`, wire `Hurtbox` and `Hitbox` to emit `hit_resolved` only, keep the three old methods as adapters. This alone fixes the wrong numbers and the triple labels. (HFB-01, HFB-02)
2. **`HitstopService`** — new autoload owning `Engine.time_scale`; `HitFeedback` requests through it; delete the `AnimDirector.set_speed_scale` writes. (HFB-04, HFB-05)
3. **Dodge confirmation** — `res.dodged` branch, `VfxService.play_dodge_trail`, `MaterialFlash.flash` tint argument, `dodge_perfect` cue. Depends on [`dodge.md`](dodge.md) step 5. (HFB-03)
4. **Damage-number rework** — `spawn_resolution`, accessibility coloring, stacking offsets, removal of the old adapters. (HFB-07)
5. **Audio selector** — `_resolve_hit_cue`, `hit_material` export on `Hurtbox`, cue names into `content/audio_profiles/`. (HFB-06)
6. **Poise-break feedback** — `poise_broken` route, `play_stagger_burst`, `stagger` cue, held flash. (HFB-08)
7. **Accessibility and cost** — `feedback_intensity` and `reduce_hitstop` in `AccessibilitySettings` and the settings UI; `MaterialFlash` material and tween reuse; idle-frame early return in `_apply_camera_shake`. (HFB-09, HFB-10, HFB-11)

Step 1 is the gate: everything else consumes `DamageResolution`. Steps 2-6 are independent of each other.

## Data and schema changes

| Change | File |
|--------|------|
| Combat cue names: `hit_<archetype>`, `hit_<archetype>_<material>`, `crit`, `block_<material>`, `parry`, `stagger`, `dodge_perfect` | `content/schemas/audio-profile.v1.json`, `content/audio_profiles/*.json` |
| `hit_material` (string, enum `flesh` / `armor` / `stone` / `crystal` / `wood`) on enemy definitions, used to configure the `Hurtbox` export at spawn | `content/schemas/enemy-definition.v1.json` |

Save format: `AccessibilitySettings` persists into the existing `accessibility` meta dictionary (`accessibility_settings.gd:24-34`), which is a free-form object — adding `feedback_intensity` and `reduce_hitstop` needs no migration and no `save_migrator.gd` version bump. `CURRENT_VERSION` stays at 4.

## Acceptance criteria

- [ ] The number shown on a landed hit equals the HP the target lost, for normal, crit, backstab, resisted and blocked hits. (HFB-01)
- [ ] A blocked hit produces exactly one floating label. (HFB-02)
- [ ] A hit produces exactly one damage-number node. (HFB-02)
- [ ] Dodging through an attack produces a visible trail, a distinct audio cue and a brief slowdown. (HFB-03)
- [ ] During hitstop, both the attacker's and the target's animations are frozen. (HFB-04)
- [ ] A `greatsword` heavy (48 damage) produces a measurably longer hitstop than a `sword_basic` light (12 damage). (HFB-04)
- [ ] `hit_feedback.gd` contains no `set_speed_scale` call. (HFB-05)
- [ ] Hitting a `castle_shield`'s shield and a `castle_grunt`'s body play different audio cues. (HFB-06)
- [ ] A fire hit's damage number is colored by `AccessibilitySettings.get_damage_color("fire")` and changes with `colorblind_mode`. (HFB-07)
- [ ] Breaking an enemy's poise produces a `STAGGER` label, a distinct burst and a distinct cue. (HFB-08)
- [ ] Landing 100 hits on a training dummy allocates no more `ShaderMaterial` duplicates than there are meshes on it. (HFB-09)
- [ ] Setting `feedback_intensity` to 0.0 in settings removes camera punch, shake and hitstop. (HFB-10)
- [ ] With no shake active, `HitFeedback` performs no write to `Camera3D.h_offset`. (HFB-11)

## Validation

Extend `apps/game/client/scripts/validation/suites/combat_suite.gd`; `combat_suite.gd` currently contains no feedback assertion at all.

| Assertion id | Checks | Gap |
|--------------|--------|-----|
| `feedback.number_matches_damage` | Land a hit with `combat_defense` meta 20 → the spawned label text equals `int(round(hit_resolved.outgoing))` | HFB-01 |
| `feedback.one_label_per_hit` | Count `damage_number.tscn` instances before/after one blocked hit → delta 1 | HFB-02 |
| `feedback.dodge_cue_fires` | Force i-frames, land a hit, assert `HitFeedback` received a resolution with `dodged` and that `VfxService.play_dodge_trail` was reached | HFB-03 |
| `feedback.hitstop_is_global` | Land a hit, assert `Engine.time_scale < 1.0` within one frame and returns to 1.0 within `HITSTOP_MAX + 0.05` s | HFB-04 |
| `feedback.hitstop_scales_with_damage` | Compare durations for a 12-damage and a 48-damage hit → strictly increasing | HFB-04 |
| `feedback.no_anim_speed_writes` | `ctx.file_contains("res://scripts/combat/hit_feedback.gd", "set_speed_scale")` is false | HFB-05 |
| `feedback.cue_varies_by_material` | `_resolve_hit_cue` for `hit_material` `"armor"` vs `"flesh"` → different strings | HFB-06 |
| `feedback.number_color_from_accessibility` | Spawn a fire-type number, compare `Label3D.modulate` to `AccessibilitySettings.get_damage_color("fire")` | HFB-07 |
| `feedback.poise_break_cue` | Break a `training_grunt`'s poise → a `STAGGER` label exists | HFB-08 |
| `feedback.flash_reuses_material` | Flash the same mesh 10 times, assert at most one `ShaderMaterial` duplicate was created | HFB-09 |
| `feedback.intensity_zero_disables` | `feedback_intensity = 0.0` → no camera offset write and no `Engine.time_scale` change on hit | HFB-10 |

Extend `m6_suite.gd` (which already exercises `AccessibilitySettings.get_damage_color` at `:281`) with `a11y.reduce_hitstop_respected`: with `reduce_hitstop = true`, landing a hit leaves `Engine.time_scale` at 1.0.

## Related

- Current behavior: [`../existing_codebase/hit-feedback.md`](../existing_codebase/hit-feedback.md)
- [`combat-core.md`](combat-core.md) — `DamageResolution` and `spawn_resolution`
- [`hit-hurtboxes.md`](hit-hurtboxes.md) — where feedback is triggered from
- [`dodge.md`](dodge.md) — the dodge cue set
- [`guard.md`](guard.md) — block and parry outcomes
- [`material-flash.md`](material-flash.md), [`vfx-service.md`](vfx-service.md), [`audio-director.md`](audio-director.md)
- [`accessibility.md`](accessibility.md), [`ui/settings.md`](ui/settings.md)

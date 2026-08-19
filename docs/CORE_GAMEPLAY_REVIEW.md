# Core gameplay review — `combat`, `player`, `enemies`, `bosses`, `camera`, `input`

60 files, ~11,700 lines.

## Coverage, honestly

| Read in full | Traced by targeted read + grep | Not yet opened |
|---|---|---|
| all 14 small enemy shells, `dodge`, `stamina`, `poise`, `health`, `mana`, `damage_info`, `damage_resolution`, `combat_facing`, `attack_token_service`, `class_perks`, `combat_stat_modifiers`, `hitbox`, `guard`, `hit_feedback`, **`lock_on`, `orbit_camera`, `lock_on_movement`, `player_heal`, `player_combat_reactions`, `boss_phase_controller`, `castle_knight`, `crystal_sovereign`, `arena_hazard`** | `hurtbox` (200/534), `weapon_controller` (~450/1129), `castle_enemy_base` (attack selection + state machine) | `player_anim_director` (915), `locomotion` (448), `status_controller` (316), `training_grunt` (296), `combat_events` (293), `run_buffs` (283), `enemy_blackboard` (228), `final_boss_forgotten_castle` (184), `castle_archer` (118), `swamp_hydra` (112), `combat_collision_debug`, `swamp_cleanse_zone`, `crystal_pillar_hazard`, `damage_number` body |

So: roughly 8,000 of 11,700 lines actually read (see the addendum in §7 for the second pass). The findings below are all from code I read. I have not audited the
animation director, locomotion, or status/buff systems, and I am not going to imply otherwise.

---

## 1. Confirmed bugs

### C-01 — Coyote time never expires while airborne → a free mid-air jump on every fall
**`player/dodge.gd`, `_update_timers()`** — high severity, easy fix.

```gdscript
if _body and _body.is_on_floor():
    _coyote_timer = COYOTE_TIME
elif _was_on_floor:
    _coyote_timer = maxf(0.0, _coyote_timer - delta)
_was_on_floor = _body.is_on_floor() if _body else false
```

`_was_on_floor` is assigned the *current* floor state at the end of the function, so the `elif`
branch is only reachable on the single frame after leaving the ground. Trace it:

- frame N — on floor: `_coyote_timer = 0.12`, `_was_on_floor = true`
- frame N+1 — airborne, `_was_on_floor` still true: timer decrements once → 0.1133, then `_was_on_floor = false`
- frame N+2 onward — airborne, `_was_on_floor` false: **neither branch runs. The timer freezes at 0.1133.**

`_handle_jump_buffer()` gates on `_coyote_timer > 0.0`, so the 0.12 s forgiveness window lasts the
entire fall. Walk off any ledge and you keep a jump in your pocket for as long as you are in the air.
It resets on landing and is zeroed by jumping, so it is one free air-jump per fall rather than
infinite — still a platforming and arena-boundary exploit.

**Fix** — decrement whenever airborne: `elif _coyote_timer > 0.0: _coyote_timer -= delta`. The
`_was_on_floor` variable then has no remaining purpose.

### C-02 — Locked-on forward and backward rolls are treated as backsteps
**`player/dodge.gd`, `_start_dash()`** — high severity for feel.

```gdscript
if LockOnMovement.is_active(lock_on):
    _dodge_direction = LockOnMovement.get_locked_dodge_direction(_body, lock_on, input_dir)
    if input_dir.length_squared() > 0.01 and absf(input_dir.x) >= 0.01:
        _dodge_speed = DODGE_SPEED
    else:
        _dodge_speed = DODGE_BACK_SPEED
```

Only the **x** component is tested. Locked on and holding pure forward or pure backward gives
`input_dir.x == 0`, so the roll is classified as a backstep. `_is_backstep` then applies
`BACKSTEP_SPEED_MULT` (0.667) and `BACKSTEP_DURATION_MULT` (0.8).

The knock-on effect is worse than the shorter distance. For the light profile,
`_active_duration = 0.48 × 0.8 = 0.384 s`, but `_iframe_end` is an absolute time of `0.42 s`. The
roll **ends before the i-frame window closes**, so invulnerability runs 0.06 → 0.384 instead of
0.06 → 0.42 — an 8% shorter defensive window, silently, on the two most common inputs in a
locked-on boss fight.

Rolling *through* an attack while locked on is the single most important move in the genre, and it
is currently the nerfed version.

**Fix** — classify on the whole vector, not just x: `input_dir.length_squared() > 0.01` alone.
Separately, i-frame windows should be expressed as fractions of `_active_duration` so shortening a
roll cannot silently clip them.

### C-03 — You cannot re-raise your guard for 0.4 s after releasing it
**`combat/guard.gd`** — high severity for feel.

`_enter_guard()` sets `_parry_cooldown_timer = PARRY_COOLDOWN` (0.4 s), and the `IDLE` branch of
`_physics_process` refuses to enter guard while that timer is running. The cooldown is named and
intended for the *parry read*, but it gates the entire guard.

So: tap block, release, see an attack coming, press block again — nothing happens for 0.4 s, with no
UI indication. In a game where blocking is a moment-to-moment defensive option, that is an invisible
punish for using it.

**Fix** — let the guard raise unconditionally and give it `_parry_timer = 0.0` while the parry
cooldown is live. `_enter_guard()` already has exactly this shape for the "cannot afford the parry"
case, so the pattern is there.

### C-04 — Raising the guard always charges the parry cost
**`combat/guard.gd`, `_enter_guard()`** — medium.

Every guard raise consumes `PARRY_STAMINA_COST` (10) if affordable, whether the player wanted a
parry or just wanted to block. Combined with C-03 this makes blocking both rate-limited and
expensive, and it means "block" and "parry" cannot be played as separate decisions — which is the
whole tactical point of having both.

**Fix** — charge the 10 stamina when the parry window actually *catches* something, or split the
inputs. Note the fixed cost also makes the parry strictly better than blocking at low stamina, since
a failed parry costs the same as a successful one.

### C-05 — `GuardState.GUARD_BROKEN` is dead
**`combat/guard.gd`, `_trigger_guard_break()`** — low, but it hides intent.

```gdscript
_state = GuardState.GUARD_BROKEN
_reset_guard_state()      # ← sets _state = GuardState.IDLE
_stagger_timer = GUARD_BREAK_STAGGER
```

`_reset_guard_state()` overwrites the state on the next line, so the `GuardState.GUARD_BROKEN`
branch in `_physics_process` is unreachable. Guard break still works — `guard_broken_state` and
`_stagger_timer` carry it — but the enum has a state the machine can never be in.

Also worth noting: guard break sets `_stagger_timer = 0.8` *and* fully breaks poise, whose
`break_duration` defaults to 1.2 s and carries a 1.35× damage multiplier. So a guard break leaves
you takeable-for-extra-damage for 0.4 s longer than you are staggered. Probably not intended.

### C-06 — The hit spark plays twice, and plays on blocked hits
**`combat/hitbox.gd` `_try_hit()` + `combat/hit_feedback.gd` `_flash_diorama_body()`** — medium.

Both call into `VfxService`: `Hitbox` fires `play_hit_spark()` unconditionally at the end of
`_try_hit`, and `HitFeedback` then fires `play_hit_spark()` or `play_crit_spark()` from the victim
side. Every landed hit spawns two sparks.

Worse, `Hitbox` plays its spark *before* `area.call("receive_hit", info)` resolves — so a hit that
gets blocked or parried still emits a flesh-hit spark, on top of the block/parry VFX. The player
cannot tell a blocked hit from a landed one by looking at it, which undermines the entire
read-and-block loop.

**Fix** — delete the `Hitbox` spark and let `HitFeedback` own impact VFX; it already has the
resolution and the crit flag.

### C-07 — The swing sound fires when the hitbox opens, not when the swing starts
**`combat/weapon_controller.gd`, `_enable_hitbox_for_attack()`** — medium, high felt impact.

`VfxService.play_attack_swing()` and `AudioDirector.play_sfx("swing")` both live inside
`_enable_hitbox_for_attack()`, which runs at the transition into `ACTIVE`. The whoosh therefore
plays at the moment of contact rather than during the wind-up, so audio trails the animation by the
whole startup window — 0.15 s for a light, 0.35 s for a heavy — and the sound loses its telegraph
value entirely.

It is also inconsistent: when `_sync_hitbox_from_anim` is true the same function is driven by an
animation frame signal instead of the phase timer, so the swing audio timing changes depending on
whether the AnimDirector bound successfully.

**Fix** — play the swing VFX/SFX in `_start_attack()`, keep hitbox activation where it is.

### C-08 — `crit_multiplier()` reads talents only
**`combat/combat_stat_modifiers.gd`** — low now, latent.

Every other helper in this file deliberately reads *both* `equipment_stats` and `talent_stats`, and
the file's own docstring explains why: reading talents alone "quietly discarded the same stat when it
came from a class or from a gear affix". `crit_multiplier()` is the one function still doing it:

```gdscript
static func crit_multiplier(talent_stats: Dictionary) -> float:
    return 1.5 + float(talent_stats.get("critDamage", 0.0))
```

There is no `critDamage` affix in `content/affixes/` today, so nothing is lost yet — but the moment
one is added (and crit damage is an obvious affix for a looter) it will silently do nothing. This is
the last instance of the bug the file was written to eliminate.

### C-09 — Phase-timer overshoot is discarded
**`combat/weapon_controller.gd`, `_process_attack_phase()`** — low.

Each transition assigns the next phase duration fresh, throwing away the negative remainder of the
previous one. Across startup → active → recovery that is up to three frames (~50 ms at 60 fps) added
to every swing, so the authored 0.52 s light attack actually runs closer to 0.57 s. Carry the
remainder: `_phase_timer = next_duration + _phase_timer`.

---

## 2. The structural finding: enemies are a tint and a scale

Every enemy variant in `enemies/` is a shell of this exact shape:

```gdscript
extends CastleEnemyBase

func _resolve_enemy_id() -> String:
    return "crystal_slime"

func _ready() -> void:
    super._ready()
    _apply_mesh_tint(Color(0.55, 0.85, 1.0, 1.0))
    scale = Vector3(0.85, 0.85, 0.85)
```

Thirteen lines. `swamp_bogling`, `crystal_shade`, `swamp_witch`, `crystal_bat`, `crystal_golem`,
`swamp_toad`, `swamp_leech`, `crystal_slime` — all of them. The ranged ones extend `castle_archer`
instead of `CastleEnemyBase`; that is the entire behavioural taxonomy. Bosses add four more lines to
re-emit `boss_phase_entered` as `phase_changed`.

So there is **no per-enemy behaviour hook in code at all**. Differentiation is a colour multiply and
a scale vector, plus whichever of the 23 shared attack ids the JSON references. This is why the
bestiary reads as eight fights in fifty-four costumes — it is not a content gap, it is an
architecture with nowhere to put the difference.

To be fair to what is there: `castle_enemy_base.gd` is genuinely capable. Attack selection picks by
**range band** then rolls on weight, wind-up carries randomised variance
(`_enemy_rng.randf_range(-windup_variance, windup_variance)`), there is a seeded per-enemy RNG, a
patrol/circle/approach state machine, LOD-strided line-of-sight, and `AttackTokenService` caps how
many enemies may commit at once. The engine for interesting fights exists. Nothing uses it
distinctly.

**What I would build.** Add one optional virtual per enemy — `_on_attack_windup(attack_id)`,
`_on_attack_land(attack_id)`, `_on_staggered()` — and give roughly fifteen enemies one line of real
behaviour each. A leech that latches and drains until you roll. A golem that gains poise while its
crystal is intact. A bogling that calls two friends when it drops below half. That is a day of work
against an existing base class, and it converts fifty-four skins into fifteen actual fights.

---

## 3. What is genuinely good, and should be the template

**`class_perks.gd` is the answer to the loot problem.** Five perks, each wired into the one system
it touches, with a docstring that says exactly the right thing: *"none of them are expressible as a
flat number merged at equip time."* `bloodrage` scales damage by missing health inside
`_enable_hitbox_for_attack`. `shadowstep` extends the i-frame window inside `_process_dash`.
`arcane_focus` restores mana inside `_try_hit`.

That is precisely the shape behavioural item affixes need, and it already exists, with call sites in
the right places. The item-behaviour work I recommended in `GAME_FEEL_REVIEW.md` §3.1 is not a new
system — it is `ClassPerks` with a data-driven trigger table.

**The dodge weight-class model** is excellent: three profiles driven from `content/combat/dodge.json`,
resolved from `combat_defense` meta, with peak/end speed, recovery speed ramp and per-class stamina
multipliers. Light armour rolls 0.48 s with 75% invulnerability; heavy rolls 0.62 s with 48%. That is
a real build decision expressed in movement.

**`combat_stat_modifiers.gd` and `hurtbox.gd` carry their history in comments** — the arc-gated
parry, the hyperarmor poise reduction that was reported but never applied, the defence/armor key
split. Whoever wrote those comments was doing the job properly.

**`attack_token_service.gd`** is 31 lines and solves the "nine enemies attack simultaneously"
problem that ruins most indie soulslikes.

---

## 4. Making it memorable, addictive, fun

### Combat — the arc that is missing
The moment-to-moment is good. What has no shape is the *fight*. Every exchange is: approach, they
swing, roll, punish, repeat. Add escalation:

- **Poise break should be a spectacle, not a multiplier.** Right now breaking poise sets
  `_broken = true` and multiplies incoming damage by 1.35. Make it a staggered stumble with a
  distinct sound, a slow-motion beat, and an execution prompt. `EXECUTION_STARTUP/ACTIVE/RECOVERY`
  and `set_execution()` already exist in `Hitbox` and `WeaponController` — the plumbing for a
  finisher is built and under-sold.
- **Riposte already has a 1.4 s window and a 2× multiplier** (`RIPOSTE_WINDOW`,
  `RIPOSTE_DAMAGE_MULT`). A player will never notice a 2× number. Make the riposte a different
  *animation* with its own camera angle. This is the clip people share.
- **Give the parry a real payoff.** With C-03 and C-04 fixed, parry becomes a genuine skill
  expression. Then: full world hitstop, a bright rim-flash on the parried enemy, a metallic ring
  that ducks the music for 200 ms.

### Enemies — telegraph in the world, not just the data
160 attacks carry telegraph data and `_select_attack_data` respects range bands, but the player reads
none of it. Colour-code the wind-up: white flash for blockable, **red for unblockable** (the
`_guard_break_poise` path already exists and is invisible), yellow for parryable. That one change
turns "I got hit" into "I misread that", which is the difference between frustrating and addictive.

### Visuals and shaders
- The two highest-value fixes are already documented as `B-01` (world hitstop only on CRITICAL) and
  `B-02` (FXAA inside the low-res pixel viewport) in `GAME_FEEL_REVIEW.md` §8. Do those first.
- **Rim light on every combatant.** The single biggest legibility problem in the screenshots is that
  characters sink into the floor. A cheap fresnel rim in the character shader fixes it everywhere at
  once.
- **Contact shadows.** Nothing in the captures feels planted on the ground.
- **Weapon trails** on the swing arc, coloured by damage type. `_damage_type` is already threaded
  from the weapon through `set_attack_values` — the data is there.
- **Enemy attack wind-up lighting.** A brief coloured light on the enemy during startup reads at any
  distance, unlike an animation pose.

### Audio
- Fix C-07 so the swoosh leads the swing.
- **Layer impact by material.** `_play_hit_sfx` already picks `hit_armor` by checking whether the
  enemy id contains "shield" or "knight" — a string match standing in for a material tag. Put a
  `hitMaterial` field on the enemy JSON and give flesh, armour, stone and crystal distinct impacts.
- **Duck the music on parry and poise-break.** `AudioDirector` already runs layered explore/combat
  stems; a 200 ms sidechain on those two events would make them land.
- The 11 placeholder SFX (`AudioDirector` warns about them every boot) include `footstep_*` — the
  sound the player hears most often in the game is a synthesised tone.

### Bosses
`boss_phase_controller.gd` is 130 lines and the boss scripts are 4-line signal relays. Phases exist
mechanically but there is no *moment*: no health-bar break, no arena change, no roar, no camera
pull-back. A phase transition is the most memorable thing in a boss fight and currently it emits a
signal.

---

## 5. Priority order

1. **C-01, C-02, C-03** — three small, high-severity feel bugs in the two most-used actions.
2. **`B-01`, `B-02`** from `GAME_FEEL_REVIEW.md` §8 — world hitstop and the pixel-viewport FXAA.
3. **C-06, C-07** — spark duplication/mis-signalling and swing audio timing. Cheap, immediately felt.
4. **Rim light + contact shadows + weapon trails** — fixes legibility across every screen at once.
5. **Enemy behaviour hooks** — the `_on_attack_windup` / `_on_attack_land` virtuals, then fifteen
   enemies with one real behaviour each.
6. **Telegraph colour-coding**, then poise-break and riposte as spectacles.
7. **C-04, C-05, C-08, C-09** — correctness cleanups with lower felt impact.

## 6. Still to audit
`orbit_camera`, `lock_on`, `lock_on_movement`, `locomotion`, `player_anim_director`,
`player_combat_reactions`, `player_heal`, `status_controller`, `run_buffs`, `combat_events`,
`enemy_blackboard`, `training_grunt`, `castle_archer`, `boss_phase_controller`, the boss hazard
files. Camera and lock-on in particular are where a third-person soulslike usually hides its worst
feel bugs, and I have not looked at either.

---

# 7. Addendum — second pass (camera, lock-on, reactions, heal, bosses)

## 7.1 Corrections — three things §2 and §4 got wrong

**I claimed there were no boss files and no phases. There are 16, and they are fully authored.**
I looked in `content/enemies/` and never checked `content/bosses/`. Every one of the 16 files has
2–3 phases with escalating attack pools (3 → 5 → 5) and a complete `onEnter` block:
`tellDuration`, `invulnerableFor`, `telegraphRadius`, `telegraphShape`, `telegraphTint`, `sfx`,
`shake`, plus `hazards` or `spawnAdds` per phase.

**I claimed a phase transition "currently emits a signal".** `BossPhaseController._play_entry()`
implements the whole spectacle: it calls `begin_phase_transition(tell, invuln)`, draws a shaped
telegraph ring in the phase's authored tint, plays VFX and SFX, requests screen shake scaled to the
tell, and spawns adds and hazard rings. The mechanism is built and the content uses it.

**I claimed the boss scripts are "4-line signal relays".** That is true of `enemies/boss_*.gd`, but
`bosses/castle_knight.gd` and `bosses/crystal_sovereign.gd` are real: arena containment clamping per
physics frame, a `get_lock_aim_point()` override, `AudioDirector.play_boss_music()`, and an
`apply_state()` that restarts the fight from phase one rather than resuming a worn-down boss. I
conflated two directories.

One genuine gap survives: there is no `music` key in `onEnter`, and `play_boss_music()` is called
once in `_ready`. So the phase-two escalation has a telegraph, a roar and adds, but the music does
not change. That is the cheapest remaining win on bosses.

Also note the "23 distinct attack ids across 54 enemies" figure in `GAME_FEEL_REVIEW.md` §3.2
counted `content/enemies/` only and excluded these 16 boss files. Bestiary variety is better than
that number implied — the trash-mob sameness finding stands, the boss part of it does not.

## 7.2 New bugs

### C-10 — You cannot roll toward a locked-on target. Ever.
**`player/lock_on_movement.gd`, `get_locked_dodge_direction()`** — highest severity in this document.
This supersedes C-02, which described a symptom rather than the cause.

```gdscript
var stick_x := _apply_axis_deadzone(input_dir.x)
if absf(stick_x) < 0.001:
    return radial          # radial = (player - target).normalized() — AWAY from the target
return tangent * signf(stick_x)
```

The **y axis is never read**. `radial` points from the target to the player, so with any pure
forward or backward input the roll goes *directly away from the enemy*. Locked on, the complete set
of available dodges is: strafe left, strafe right, and retreat. Holding forward and pressing dodge
rolls you backwards.

`ORBIT_INPUT_DEADZONE` is 0.15, so on keyboard W or S gives `x = 0` and lands in the `radial`
branch every time.

That this is an oversight rather than a design choice is settled by `get_move_direction()` twenty
lines above, which handles the same input correctly: `direction = tangent * stick_x + radial_forward * stick_y`
with `radial_forward = -radial`. So *walking* toward a locked target works and *dodging* toward it
does not, in the same file.

Rolling through an attack — and rolling behind a boss — is the central defensive and offensive move
of the genre, and it is currently unavailable whenever lock-on is on.

**Fix** — mirror `get_move_direction`: `var dir := tangent * stick_x + (-radial) * stick_y`, and
fall back to `radial` only when both axes are inside the deadzone. Then fix the backstep
classification in `dodge.gd` (C-02) so it tests the whole vector.

### C-11 — Death framing never activates: wrong argument count
**`player/player_combat_reactions.gd`, `_run_death_sequence()`**

```gdscript
_orbit_camera.call("enter_death_framing", _body)
```

`OrbitCamera.enter_death_framing()` takes no parameters. `Object.call()` with the wrong arity raises
an error and does nothing, so `_death_framing` is never set and the death camera never engages —
the one shot in the game that is guaranteed to be seen by every player who dies.

### C-12 — Guard break has no camera feedback: method does not exist
**`player/player_combat_reactions.gd`, `_flash_guard_break_feedback()`**

```gdscript
if _orbit_camera and _orbit_camera.has_method("apply_camera_dip"):
    _orbit_camera.call("apply_camera_dip", 0.35, 0.35)
```

`OrbitCamera` has no `apply_camera_dip`. It has `apply_landing_dip(strength)`. The `has_method`
guard means this fails silently, so the harshest defensive failure in the game produces a material
flash and nothing else. Two dead camera hooks in the same file, both of the same shape as the
`_on_fullscreen_confirm_timeout()` arity bug fixed earlier in this session.

### C-13 — Getting staggered breaks your lock-on
**`player/player_combat_reactions.gd`, `_apply_stagger()`** — calls `_break_player_lock()`.

Every stagger drops the lock. In the genre's reference implementations, being staggered does not.
Combined with C-10 this is brutal: you get hit, lose lock, re-lock, and the only dodge that would
have saved you rolls the wrong way.

### C-14 — Locked-on vertical camera adjustment does nothing on mouse
**`camera/orbit_camera.gd`** — `_lock_pitch_bias` has two writers with different limits.

`_apply_lock_pitch_look()` (mouse, from `_unhandled_input`) clamps to `±LOCK_PITCH_MOUSE_MAX` (28°).
`update_lock_on_frame()` (physics, every frame) re-clamps the same variable to
`±LOCK_PITCH_BIAS_MAX` (12°) — and then:

```gdscript
if absf(stick.y) < 0.15:
    _lock_pitch_bias = lerpf(_lock_pitch_bias, 0.0, clampf(4.0 * delta, 0.0, 1.0))
```

For a mouse-and-keyboard player `stick.y` is always 0, so the bias decays to zero every frame. Mouse
pitch while locked on is clamped to less than half its intended range and then actively erased.
`LOCK_PITCH_MOUSE_MAX` is effectively dead.

### C-15 — `apply_shake(strength, duration)` half-ignores its duration
**`camera/orbit_camera.gd`, `_update_camera_effects()`**

```gdscript
var t := 1.0 - clampf(_shake_timer / 0.11, 0.0, 1.0)
```

The envelope is normalised against a hardcoded 0.11 s regardless of the duration passed in.
`HitFeedback` passes `shake_time` values from 0.11 up to 0.2, so a critical hit's 0.2 s shake runs at
full amplitude for 0.09 s and only then begins to decay — a flat-topped envelope instead of a
falloff. Divide by the stored duration instead.

### C-16 — Camera pitch is not re-clamped on mode change
**`camera/orbit_camera.gd`** — `_pitch` is only clamped inside `_apply_look()`, using limits that
lerp with `_fp_blend` (FP allows ±80°, TP −45°/+60°). Look straight down in first person, toggle to
third, and `rotation.x` keeps the out-of-range value until the player next moves the camera.
`apply_state()` restoring a saved pitch has the same hole.

### C-17 — Lock-on aims at a fixed offset for any enemy with a default-named mesh
**`camera/lock_on.gd`, `_should_skip_lock_aim_mesh()`**

```gdscript
match mesh.name:
    "TelegraphMesh", "MeshInstance3D":
        return true
```

`"MeshInstance3D"` is Godot's *default* node name, and the project does use it (`final_boss_crystal.gd`
looks up `get_node_or_null("MeshInstance3D")`). Any enemy whose mesh kept the default name is
excluded from the aim-point AABB, so `get_target_aim_point()` falls through to
`global_position + Vector3(0, 1.2, 0)`. For the small enemies — `swamp_leech` at scale 0.6,
`crystal_slime` at 0.85 — the reticle and camera aim well above the actual body.

### C-18 — `request_lock(target)` skips all validation
**`camera/lock_on.gd`** — the explicit-target path calls `_set_lock(target)` with no range, vertical
limit or line-of-sight check, and `_set_lock()` does not reset `_break_grace_timer`. A scripted lock
(boss intro, camera state restore) onto a target outside `break_range()` therefore breaks on the
first `_update_lock` tick with zero grace, because the timer is still 0 from the previous break.

### C-19 — Lock-on line-of-sight rebuilds its exclude list every physics frame
**`camera/lock_on.gd`, `_has_line_of_sight_to()`** — walks the entire `lockable` group to build an
`Array[RID]` of defeated enemies on every call, and `_update_lock()` calls it once per physics frame
while locked. `_find_best_target()` calls it per candidate, making acquisition O(n²). Cache the
exclude array and rebuild it on lock change or death.

### C-20 — Drinking a flask plays the damage spark
**`player/player_heal.gd`, `_on_heal_commit()`** — `VfxService.play_hit_spark(...)`. The heal — the
tensest voluntary act in the game — is visually indistinguishable from being hit. It needs its own
VFX, and this is a one-line change once one exists.

### C-21 — `_connect_heal_anim_signals()` and `_bind_anim_signals()` are byte-identical
**`player/player_heal.gd`** — same body, one called from `_ready()` and one from `_try_drink()`.
Also `HEAL_STAMINA_COST := 0.0` makes four stamina branches in `_try_drink()` unreachable.

### C-22 — Two dead branches in the camera
**`camera/orbit_camera.gd`** — `SNAP_DISABLE_WHILE_LOCKED` is a `const … := false`, so
`if SNAP_DISABLE_WHILE_LOCKED and _lock_on_active: return` can never fire. And
`_apply_camera_effects_transform()` computes `offset.z += 0.12` under `_death_framing` but only ever
applies `offset.x` and `offset.y` to `h_offset`/`v_offset`, so the death-framing dolly does nothing.

### C-23 — Suspected: the pixel snap may ratchet
**`camera/orbit_camera.gd`, `_apply_gameplay_pixel_snap()`** — reads `_camera.global_transform`,
snaps it, and writes it back, every `_process`. Because the write lands on the camera's local
transform relative to the spring arm, the next frame's read already contains the previous frame's
snap delta and gets snapped again. Re-snapping is idempotent only while the grid is unchanged, and
the grid depends on FOV and arm length, both of which move continuously (sprint FOV, punch kick, arm
smoothing). Worth verifying against a cached unsnapped transform — this is a plausible contributor
to the soft, unstable look in the captures.

## 7.3 Revised priority

The order in §5 changes, because C-10 outranks everything previously listed:

1. **C-10** — locked-on dodge direction. One line, and it restores the core defensive move.
2. **C-01, C-02, C-03** — coyote time, backstep classification, guard re-raise lockout.
3. **C-11, C-12** — two dead camera hooks; death framing and guard-break feedback are free once fixed.
4. **`B-01`, `B-02`** from `GAME_FEEL_REVIEW.md` §8 — world hitstop and pixel-viewport FXAA.
5. **C-13, C-14, C-17** — stagger dropping lock, locked mouse pitch, lock-on aim point.
6. **C-06, C-07, C-20** — spark duplication, swing audio timing, heal using the hit spark.
7. **Boss phase music** — the one authored-content gap in an otherwise complete phase system.
8. Everything else in §5, then the remaining correctness cleanups.

## 7.4 Still unread
`player_anim_director` (915), `locomotion` (448), `status_controller` (316), `training_grunt` (296),
`combat_events` (293), `run_buffs` (283), `enemy_blackboard` (228), `final_boss_forgotten_castle`
(184), `castle_archer` (118), `swamp_hydra` (112), `combat_collision_debug` (69),
`swamp_cleanse_zone` (48), `crystal_pillar_hazard` (48), plus the unread remainder of `hurtbox`
(334), `weapon_controller` (~680) and `castle_enemy_base` (~1400).

---

# 8. Addendum — third pass

Read this pass: `locomotion`, `status_controller`, `combat_events`, `run_buffs`, `enemy_blackboard`,
`castle_archer`, `swamp_hydra`, `crystal_pillar_hazard`, `swamp_cleanse_zone`, `damage_number`,
`combat_collision_debug`. Plus an automated arity scan over all 60 files (§8.4).

**Still unread:** `player_anim_director` (915), `training_grunt` (296),
`final_boss_forgotten_castle` (184), and the remainders of `hurtbox` (~330), `weapon_controller`
(~680) and `castle_enemy_base` (~1400, though its attack selection, AI state machine, noise model,
token release paths and blackboard integration have all been read via targeted reads).

## 8.1 The correction that matters most: behavioural loot already exists

**`GAME_FEEL_REVIEW.md` §3.1 is wrong, and this review repeated it.** I reported "184 equipment
items, 0 of them do anything" and recommended building a trigger/effect system. Both were mistakes.

I probed for keys named `onHit`, `onKill`, `proc`, `effect`, `ability`, `uniqueEffect`, `behaviour`,
`behavior` and `grants`. The actual key is **`rules`**. Measured properly:

| rarity | items | with `rules` |
|---|---|---|
| common | 39 | 0 |
| magic | 37 | 0 |
| rare | 54 | 8 |
| epic | 28 | 20 |
| legendary | 17 | 14 |
| aumbral | 9 | 5 |
| **total** | **184** | **47** |

All 35 relics carry rules, and so does `content/talents/tree.json`.

And `combat/combat_events.gd` is a complete run-scoped rule engine whose own docstring says it is
"shared by unique items, relics, class perks and talent keystones". It implements 14 events —
`onHit`, `onKill`, `onParry`, `onBlock`, `onDodge`, `onCrit`, `onBackstab`, `onRiposte`,
`onHitTaken`, `onLowHealth`, `onRoomClear`, `onFloorEnter`, `onStatusApplied`, `onRunStart` — and 10
effects including `lifesteal`, `spread_status`, `refund_flask` and `add_stack`, with `cooldown`,
`chance`, `ifTargetHasStatus`, `ifDamageType`, `maxStacks`, `resetOn` and a `radius` for spreads.
`InventoryService`, `RunBuffs`, `ProgressionService` and `CharacterService` all register into it.

The event list I "recommended adding" is very nearly the list already implemented.

**The revised finding**, which is smaller but real:

1. **The rarity curve is correct.** Behaviour concentrated in epic and above, commons and magics as
   pure stat filler, is exactly the right shape. Nothing to change.
2. **Three legendaries and four aumbrals still have no `rules`** — seven top-rarity items that are
   stat sticks at the summit of the chase ladder. That is the gap worth closing.
3. **The authored rules are thin, and that is the actual problem.** Two real examples:
   - *Ledger of Debts* — `{"event": "onKill", "effect": "bonus_gold", "amount": 12}`
   - *The Unsaid Prayer* — `{"event": "onKill", "effect": "restore_mana", "amount": 15}`

   Those are stats wearing a trigger. Compare a relic: *"Twenty health surrendered. Every parry
   restores a flask charge."* The engine supports the second kind — `refund_flask` on `onParry` with
   a cooldown is one line of JSON. The item names are already excellent (*The Unsaid Prayer*,
   *Hearthless Cuirass*, *Reliquary of Ash*, *Debtor's Pendant*). The ceiling here is authoring
   ambition, not engineering.

So: no schema work, no new system. Write ~40 better rule blocks against an engine that already runs
them, and fill the seven empty top-rarity items.

## 8.2 A second thing already built: the results-screen data

`RunBuffs.get_run_highlights()` returns `relics` (with per-relic proc counts), `topRelic`,
`topRelicProcs`, `offersTaken` and `trapCatches`, under a comment reading *"Per-run figures the
results screen can turn into something worth repeating: which relic actually did the work, how
often…"*.

The results screen shows Time, Kills, Loot, XP. "Ashen Wake procced 41 times" is sitting in memory,
already tracked, unused. That makes §3.3 of `GAME_FEEL_REVIEW.md` cheaper than I estimated.

## 8.3 New bugs

### C-25 — Landing while dodging, staggered, or in landing-lock skips fall damage entirely
**`player/locomotion.gd`, `_physics_process()`** — high severity, exploitable.

`_update_floor_state()` both returns the computed fall height *and* resets `_was_on_floor`. Three
early-return branches call it and discard the return value:

```gdscript
if _combat_reactions and _combat_reactions.is_movement_locked():
    ... move_and_slide(); _update_floor_state(); ...; return      # fall height dropped
if _landing_lock_timer > 0.0:
    ... move_and_slide(); _update_floor_state(); ...; return      # dropped
if _dodge: _dodge.process_dash_physics(delta)
    if _dodge.is_dodging: _update_floor_state(); ...; return      # dropped
```

Only the main path calls `_on_landed(fall_height)`. So touching down in any of those three states
means no fall damage, no landing camera dip, and no landing footstep — the touchdown is consumed and
forgotten. **Press dodge as you land and a lethal fall costs nothing.** Getting staggered mid-air has
the same effect.

**Fix** — capture the return in all four branches and call `_on_landed()` when it is positive.

### C-26 — Status damage-over-time has resistances applied twice
**`combat/statuses/status_controller.gd` `_deal_damage()` → `combat/hurtbox.gd`**

```gdscript
var resolved := DamageInfo.apply_resistance(amount, dmg_type, _get_resistances())
... hurtbox.receive_periodic_damage(resolved, dmg_type)
```

`receive_periodic_damage()` builds a `DamageInfo` and calls `receive_hit()`, which runs
`_apply_resistances()` again. Every poison, burn and bleed tick is reduced by the target's resistance
twice — so a 50% frost-resistant enemy takes 25% frost tick damage, not 50%. All DoT balance is
silently off, and it compounds with the `tickGrowth` ramp.

**Fix** — pass the raw amount and let the hurtbox own resistance, which is where every other damage
path resolves it.

### C-27 — A stat-only buff expiring leaves stale totals with no notification
**`combat/statuses/status_controller.gd`, `_recalc_modifiers()`** — the trailing emit is conditional:

```gdscript
if (not is_equal_approx(prev_slow, _slow_multiplier)
        or prev_stun != _stunned
        or not is_equal_approx(prev_taken, _damage_taken_multiplier)):
    statuses_changed.emit()
```

`_stat_totals` is rebuilt above but is not part of the comparison. `apply_status()` emits
unconditionally so gaining a buff is fine; **expiry** goes through `_physics_process` →
`_recalc_modifiers()`, so a buff whose only effect is `stats` falls off without telling anyone.
Anything caching `get_stat_totals()` keeps the bonus.

### C-28 — Un-engaged enemies report the most aggressive AI role
**`enemies/enemy_blackboard.gd`, `role_for()` / `_assign_roles()`**

`_assign_roles()` only writes entries for members in the `engaged` list. `role_for()` defaults a
missing entry to `Role.ENGAGER`:

```gdscript
return int(roles.get(member.get_instance_id(), Role.ENGAGER))
```

So every enemy that has *not* engaged reports ENGAGER — the pressing role — instead of WAITER. The
default is backwards, which undercuts the whole point of the role system (the file's own docstring:
"the board decides who is *allowed* to ask for a token"). Default to `Role.WAITER`.

### C-29 — Room spatial culling uses a stale centre
**`enemies/enemy_blackboard.gd`, `_room_bounds()`** — the cache is keyed on member *count*:

```gdscript
if cached is Dictionary and int(cached.get("count", -1)) == members_list.size():
    return cached
```

The comment says it is "refreshed when the membership changes", but enemies move every frame while
the count stays constant. `nearby()` culls whole rooms by comparing that stale centre against the
query radius, so ally-alert propagation can miss enemies that have walked toward the player or
include ones that walked away. Add a time or frame-based invalidation.

### C-30 — The swamp cleanse window strips every player buff
**`bosses/swamp_cleanse_zone.gd`, `_clear_poison_on_player()`**

```gdscript
for entry in status_ctrl.get_active_statuses():
    if entry.get("id", "") == "poison":
        status_ctrl.clear_all()
        return
```

`clear_all()` wipes the entire status table — relic buffs, consumable buffs, weapon buffs, everything.
So the mechanic that exists to make the poison phase survivable also deletes the player's build the
moment they use it. `StatusController` has no public single-status removal (`_remove_status` is
private), so the fix needs one added.

### C-31 — `crystal_pillar_hazard` ignores its own damage value and its telegraph is invisible-by-parity
**`bosses/crystal_pillar_hazard.gd`** — three omissions against its sibling `arena_hazard.gd`:

- never assigns `_damage_area.damage = damage`, so the `@export var damage := 10.0` is dead and the
  hazard deals whatever the scene default is;
- never applies `AccessibilitySettings.emphasise_telegraph_tint()`, which `arena_hazard` does — so
  the accessibility telegraph-emphasis setting works on fire zones and not on pillars;
- never sets `_active_zone.material_override`, which `arena_hazard` does — so the live damaging zone
  and the harmless telegraph may render identically.

### C-32 — Stacking a rules-bearing relic gives no extra rule effect
**`combat/run_buffs.gd`, `_sync_relic_rules()`** — `if not CombatEvents.is_registered(source_id): register(...)`.
`add_relic()` increments `stacks` and then calls this, which sees the source already registered and
does nothing. Stacks scale `stats` only; a 2-stack relic's rule still fires once. Given `maxStacks`
is authored per relic, that is very likely unintended.

### C-33 — Two smaller ones
- **`bosses/swamp_cleanse_zone.gd`** duplicates the zone material every physics frame
  (`mat = mat.duplicate()` inside `_physics_process`) to animate one alpha value. Duplicate once in
  `_ready`.
- **`combat/damage_number.gd`** calls `load("res://scenes/combat/damage_number.tscn")` on every
  spawn in both static factories, rather than a `preload` const. ResourceLoader caches, so this is a
  lookup rather than a disk read, but it happens on every hit.

## 8.4 Automated cross-check, and two non-bugs

I scanned all 60 files for `.call("name", …)` sites whose argument count no target definition
accepts. Six hits; four were false positives from my own comma-splitting inside nested calls
(`apply_shake`, `launch`). The two real ones were **C-11** and **C-12**, already found by reading —
which is a useful signal that the manual pass caught what a scan would.

Two apparent hits verified as correct by design, and **not** bugs:

- `hurtbox.gd:269` calls `body.is_hyperarmor_active()`, which nothing defines — but it is the second
  branch of `_is_hyperarmor_active()`, and the first branch resolves
  `WeaponController.has_hyperarmor()`, which does exist (`weapon_controller.gd:349`). Player
  hyperarmor works; the body branch is an unused extension point for enemies.
- `castle_enemy_base.gd:1223` calls `_player.get_noise_level()`, undefined — but
  `_player_noise_level()` guards it with `has_method` and falls back to reading the player's velocity
  directly, with a comment explaining exactly that ("so nothing has to be pushed in from the
  locomotion side"). Working optional hook.

## 8.5 What this pass changes about the plan

Two of my three headline recommendations across both documents were built already:

| Recommendation | Reality |
|---|---|
| "Add a behaviour block to the item schema" (`GAME_FEEL_REVIEW` §3.1) | `CombatEvents` + `rules` exist; 47/184 items use them. Real work: better rule *writing*, and 7 empty top-rarity items |
| "Rebuild the results screen" (§3.3) | Still right, and cheaper — `RunBuffs.get_run_highlights()` already tracks the interesting data |
| "Enemy behaviour hooks" (§2) | Still right. Per-enemy scripts remain tint + scale, though `EnemyBlackboard`'s role system and `CastleEnemyBase`'s range-band selection are genuinely good |

Revised top of the queue:

1. **C-10** — locked-on dodge direction.
2. **C-25** — the fall-damage hole (four lines, closes an exploit).
3. **C-01, C-02, C-03** — coyote time, backstep classification, guard re-raise lockout.
4. **C-26** — double resistance on every DoT tick; all status balance depends on it.
5. **C-11, C-12** — the two dead camera hooks.
6. **`B-01`, `B-02`** — world hitstop, pixel-viewport FXAA.
7. **C-30** — the cleanse window deleting the player's build.
8. **Rule-writing pass** on the 47 rules-bearing items plus the 7 empty ones.
9. Everything else above, then the correctness cleanups.

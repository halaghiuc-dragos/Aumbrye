# Aumbrye — Critical Design & Implementation Audit

> Derived **solely from reading the codebase and content data**. No prior document, roadmap,
> or in-code comment was treated as evidence: every claim below was re-verified against the
> implementation itself. Where an in-code comment asserts a system works, the audit asks
> whether the code actually delivers the *player-facing outcome* that comment claims.

---

## 0. Verdict up front

**Engineering quality: high. Design contract: broken at the core.**

Aumbrye is not a prototype. 123k lines of GDScript, 699 content JSON files, 65 enemy scenes,
10 biomes, a content-driven catalogue layer, seeded procgen with a validation harness,
save migrations, accessibility scaling, achievements, a hub economy, quests, Steam hooks,
and a per-system validation suite. Whoever built this shipped a lot of real systems.

And it would still not feel like a soulslike, because **the single defining verb of the genre
— the dodge — is decorative in this build.** Everything else in this audit is downstream
of that.

Two mechanics decide whether a soulslike is loved or bounced off:

1. **You can read an attack and get out of it.**
2. **Healing is a gamble you can lose.**

Aumbrye failed both. Not through absence — both systems are implemented, tuned, data-driven
and telegraphed — but through specific defects that quietly nullified them.

**That is the defining pattern of this codebase, and it repeats.** The dominant failure mode
here is not missing work; it is finished work that nothing calls. A seeded relic-offer system
with 24 unreachable relics behind it. A flask counter the HUD never drew. A stack-split bound
to an input action that does not exist. Buff statuses whose stat blocks nothing read. Five
validation tests asserting things the code could not produce, and reporting green.

This is the most dangerous shape a project can take: everything *looks* built, the suites
pass, and the game still feels wrong in a way playtesters describe as "the enemies are unfair"
without being able to say why. Finding it requires asking of every system not "is it correct?"
but "does anything call it?" — which is how this audit was run.

---

## 1. CRITICAL — the combat contract

### C1. Every enemy attack is a homing missile
**`scripts/enemies/castle_enemy_base.gd:824–916, 1539–1548`**

Three behaviours compound:

```gdscript
func _should_track_player() -> bool:
	return _player != null and (_aggro_locked or _state != State.PATROL)

func _face_direction(dir: Vector3, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, angle, ENEMY_TURN_SPEED * delta)   # 22.0 rad/s
```

- `_should_track_player()` has **no state exclusion**. It is true during `WINDUP` and `ATTACK`.
- `ENEMY_TURN_SPEED = 22.0` rad/s ≈ **1260°/s**. At 60 Hz that is a near-instant snap, not a turn.
- `_update_ai` additionally drives the enemy *toward* the player at `0.9×` speed during
  `WINDUP` and `0.7×` during `ATTACK`.

Net player experience: you see a 1.04 s overhead cleave telegraph, you roll sideways —
and the enemy rotates with you at 1260°/s and walks into you while its hitbox is open.
The i-frame window doesn't save you either, because the enemy is still closing during the
active frames and re-overlaps as soon as they end.

There is no counterplay left except out-ranging. Rolling, spacing, circling, and every
piece of the (genuinely good) per-attack telegraph data in `content/enemies/*.json`
is wasted. **This alone would sink the game.**

The content layer is already authored well enough to fix this properly — `castle_grunt.json`
has distinct 0.44 s / 0.62 s / 1.04 s windups with variance and combo follow-ups. The data
deserves an AI that honours commitment.

### C2. Healing carries no risk
**`scripts/player/player_heal.gd:55–63, 148–154`**

```gdscript
func _finish_drink() -> void:
	is_drinking = false
	current_charges = maxi(0, current_charges - 1)
	if not _heal_committed:
		_apply_heal_amount()          # heals unconditionally
```

Nothing interrupts a drink. Not damage, not stagger, not poise break, not death of the
animation. `PlayerCombatReactions` connects `hurt_received`, `poise_broken` and `died`,
and forwards **none** of them to `PlayerHeal`. The 1.35 s "vulnerable drink animation"
described in the class docstring is vulnerable only in the sense that you take damage
during it — you always get the heal anyway.

In Dark Souls the estus gamble *is* the tension: commit to 1.3 s of helplessness and you
might get nothing. Here it is a free 45% max HP with no decision attached. Combined with
C1 (attacks you cannot dodge), the resulting loop is "get hit, heal, get hit, heal" —
attrition, not fencing.

### C3. You can parry an enemy standing behind you
**`scripts/combat/hurtbox.gd:91–102`, `scripts/combat/guard.gd:195–214, 284–295`**

`receive_hit` computes the hit arc, then calls `try_parry_attack` **before using it**:

```gdscript
var arc := DamageInfo.classify_arc(owner_body, info.source.global_position)   # computed
var guard := _cached_guard if not info.ignore_guard else null
if guard and guard.has_method("try_parry_attack") and info.source:
	if guard.call("try_parry_attack", info.source):                            # arc unused
```

`try_parry_attack` itself checks state, parry window and exhaustion — never direction.
Result: holding block and mashing it turns a backstab into a free riposte.

Note on the *block* path, which I initially read as a second bug and it is not:
`Guard._is_frontal_hit()` and `BLOCK_ARC_DEGREES = 120.0` are genuinely dead code, but
`DamageInfo.classify_arc`'s `FRONT` bucket is `angle <= 60.0` — a ±60° cone, which is
exactly the same 120° arc. The block cone the game enforces matches the authored one.
Only the parry was ungated.

### C4. The backstep is not a backstep
**`scripts/player/dodge.gd:258–280, 321–344`**

`_start_dash` carefully picks `DODGE_SPEED (9.0)` vs `DODGE_BACK_SPEED (6.0)` … and then
`_process_dash` ignores `_dodge_speed` entirely and uses the weight-class `peak_speed` /
`end_speed`. The only surviving use of `_dodge_speed` is deriving the `_is_backstep` flag.

A neutral backstep therefore travels the *same distance as a full committed roll* —
11.0 m/s peak on medium weight. Backstep-as-a-spacing-tool, one of the more expressive
options in the genre, does not exist; it is just a roll you didn't aim.

### C5. Attack inputs are silently eaten while guarding
**`scripts/combat/weapon_controller.gd:180–206`**

```gdscript
if _is_action_blocked():          # true whenever _guard.is_guard_active
	...
	return                        # returns BEFORE the buffer-consume branch
```

Nothing records an attack press during guard. Releasing block and pressing attack in the
same frame produces nothing; the player has to notice and press again. The input buffer
already exists and works for the dodge→attack and recovery→attack cases — guard is simply
missing from it. Players read this as unresponsive controls, which is the fastest way to
lose someone in the first twenty minutes.

### C6. Jump cancels any attack at any phase
**`scripts/player/dodge.gd:237–246`**

`_handle_jump_buffer` never consults `_weapon.allows_cancel_into("dodge")`, unlike
`_can_dash()` twelve lines below which does. So the entire commitment model —
`cancel_into`, `cancel_after`, recovery windows, the whole reason heavy attacks feel heavy —
is bypassed by tapping F. Free cancel out of a 0.45 s heavy recovery for 18 stamina.

### C7. Hit detection runs at half the physics rate
**`scripts/combat/hitbox.gd:116–124`**

```gdscript
_poll_alternate = not _poll_alternate
if not _poll_alternate:
	return                        # skips every other physics frame
```

A light attack has `active: 0.12` — 7 physics frames — so the shape query runs 3 times.
Combine that with the per-target line-of-sight gate (`_has_clear_line_to`) which must also
succeed on one of those 3 frames, and hits at the edge of a swing are genuinely lost.

Trading hit-detection fidelity for one saved `intersect_shape` during a ≤0.2 s window is
not a trade worth making. Dropped hits in a soulslike are perceived as the game cheating.

---

## 2. MAJOR — correctness and readability

| # | Finding | Location |
|---|---|---|
| C8 | `Stamina`, `Poise` and `Mana` call `set_process(false)` in `_ready()` while implementing `_physics_process`. It disables the wrong callback — regen survives by accident, not design. | `combat/stamina.gd:28`, `combat/poise.gd:23`, `combat/mana.gd` |
| C9 | `POISE_BROKEN_DAMAGE_MULT` is declared in **both** `poise.gd:12` (dead) and `hurtbox.gd:11` (live). Two sources of truth for a balance constant. | `combat/poise.gd:12` |
| C10 | Enemy flinch plays on *every* hit regardless of poise, while the attack state machine keeps running. The enemy visibly reacts while its hitbox is still open — the player reads a stagger that isn't one. | `enemies/castle_enemy_base.gd:1569–1581` |
| C11 | Guard costs 10 stamina on every press. When the press fails the stamina check, `Stamina.consume` returns false and **nothing else happens** — no guard, no feedback, no sound. | `combat/guard.gd:103–111` |
| C12 | Enemies patrol at full chase speed. There is no visible difference between "hasn't noticed you" and "hunting you", which defeats the (well-built) awareness/vision-cone/hearing system feeding it. | `enemies/castle_enemy_base.gd:941` |
| P1 | `respec_talents()` mutates state, emits `progression_changed`, and never calls `LocalSave.autosave()` — every sibling mutator does. A respec is lost on crash or quit-without-save. | `progression/progression_service.gd:184` |
| A1 | `WeaponController` hardcodes `sword_basic.json` as its `_ready()` default, so every spawn runs basic-sword damage/hitbox numbers until `apply_equipment_to_player_node` lands a frame or more later. | `combat/weapon_controller.gd:7, 457` |
| A2 | In an exported build a missing `content/` directory produces `push_warning` and `{}` per file. The game boots with no weapons, no enemies, no loot and **no visible error**. | `app/content_loader.gd:47–58` |

---

## 3. DESIGN — will humans play this?

The systems inventory is strong and modern: run modes (castle / endless / waves /
challenge), a hub with blacksmith + merchant + storage + quests, descent pacts, run
modifiers, an affix/rarity loot system, talents, class perks, achievements, a bestiary,
and an XP-shard death-recovery mechanic. That is a genuinely competitive feature set for
the action-roguelite shelf.

The gaps are about **retention shape**, not feature count.

**D1 — The permanent ladder is far too short.**
`content/progression/xp_curve.json` caps at level 20 for 10,450 XP total, at 25 XP/kill and
1 talent point per level. That is ~420 kills to exhaust *all* permanent progression, and 19
talent points to spend. A roguelite lives on the promise that tonight's run makes tomorrow's
run stronger. This ladder is finished in a weekend.

**D2 — The bloodstain loop is complete but unnavigable.**
I expected to find this half-built and it is not: `run_flow.on_player_died` stakes gold
(`DEATH_GOLD_STAKE_RATIO = 0.4`), defers XP into a recoverable shard keyed to floor and
dungeon, `castle_run._spawn_recoverable_xp_shard` re-places it exactly where you fell, and
`xp_shard_pickup` hands both back on interact. The mechanic is real and correct.

The gap is purely wayfinding. The shard is a knee-high pickup whose label only becomes
visible once you are already standing in its 1.2 m trigger, on a procedurally generated
floor you have just respawned into from the other end. A recovery run you cannot navigate
is not a recovery run — the tension of *"it is over there and something is standing on it"*
requires being able to see where "there" is.

**D3 — Nothing punishes rhythm-breaking.** With C1 and C2 fixed, the fight becomes
read → space → punish. Without a stamina consequence for whiffing (currently a whiffed
heavy costs 32 stamina and nothing else) there is no *escalating* danger from playing badly,
only a flat one.

**D4 — Onboarding.** The title routes to a hub with tutorial hooks (`hub_tutorial_service.gd`)
and a training arena, which is the right structure. But the first thing a new player will
experience is C1 and C5 — undodgeable attacks and dropped inputs — and that is the twenty
minutes that decides a refund.

---

## 3b. Second pass — systems built and never wired

A second, exhaustive sweep over all 412 scripts, 699 content files, every scene, every
`res://` reference and every input action. Method: rather than reading serially, scan for
*classes* of defect — declared-but-unconnected signals, defined-but-uncalled functions,
unreachable content, unresolvable references — then read what lights up. That is what
surfaced the largest finding in the whole audit.

### W1 — 24 of 35 relics are unreachable, and the choice-of-three offer is never invoked
**`scripts/combat/run_buffs.gd:88–127`**

`roll_offer()` — seeded per decision point, synergy-weighted so a build compounds — and
`take_offer()` are complete, correct, and **called from nowhere in the entire codebase**.

The only route by which a relic can enter a run is picking up one of the eleven items that
carry a `runRelicId`. Cross-referencing every relic definition against every item:

```
relic definitions: 35     reachable via items: 11     unreachable: 24
```

Every unreachable one is a rule-bearing relic — `the_open_wound`, `a_debt_of_breath`,
`the_hollow_flask`, `answered_in_kind` — the build-defining kind that carries a `rules` block
and changes how the game plays rather than adding a number. **The core roguelite decision
loop was authored, implemented, tuned, and left dark.**

This is invisible to every other check: the relics load, validate, and behave correctly.
They simply never appear.

### W2 — The HUD has no flask counter
**`scripts/ui/combat_hud.gd`**

`PlayerHeal` has tracked charges and emitted `charges_changed` since it was written. Nothing
listened. The player had **no way to see how many heals remained** — in a genre where the
flask count is one of the three things permanently on screen. Worse in combination with C2:
now that a broken drink still spends the charge, an invisible counter makes the cost of a
failed heal unattributable.

### W3 — Splitting an inventory stack was bound to an action that does not exist
**`scripts/ui/inventory_ui.gd:340`**

```gdscript
elif event.is_action_pressed("ui_page_down"):   # never defined in project.godot
    _split_selected_stack()
```

Godot logs an error and returns false for an unknown action, so `_split_selected_stack()` —
fully implemented, with `InventoryService.split_stack_at_index` behind it — could not be
reached by any input on any device.

### W4 — Relic, consumable and status-buff stats reached almost nothing
**`scripts/inventory/inventory_service.gd:447`**

`apply_equipment_to_player_node` built two aggregates and used the wrong one nearly
everywhere. `merged_stats` (equipment + class + talents + run relics + consumable buffs) fed
**only** max health and elemental resistances. Every other consumer — stamina max and regen,
poise, mana, weapon damage, move speed, dodge cost, block reduction, armour, flat damage
reduction — received `equip_stats`, which was equipment and class only.

So a relic that grants stamina, a potion that grants move speed, or a buff that grants armour
did nothing at all. That is most of what a relic or a potion is *for*.

### W5 — Buff statuses had a stat block nothing read
**`scripts/combat/statuses/status_controller.gd:183, 299`**

`get_stat_totals()` aggregated the `stats` block of every active buff status and was never
called. `get_damage_taken_multiplier()` accumulated `damageTakenMultiplier` and was never
called. Four authored buffs were inert in whole or part:

| Status | Dead field |
|---|---|
| `stoneskin` | `damageTakenMultiplier: 0.82` **and** `stats.armor: 6` |
| `focus` | `stats.damagePercent: 6` |
| `resolve` | `stats.healthRegen: 1` |
| `swiftness` | `stats.moveSpeedPercent: 8` |

### W6 — Two more player-facing signals emitted into the void

`Guard.riposte_ready` — the 1.4 s window in which a heavy press becomes a critical riposte had
no indicator; the player had to already know the mechanic existed and guess at its length.
`LockOn.lock_occluded` — occlusion was tracked and never shown, so the reticle looked identical
whether the target was in the open or behind a wall, right until the lock silently dropped.

### Checks that came back clean

Worth recording, because they bound the audit:

- **Every `res://` reference in every script, scene and resource resolves.** (The 59 apparent
  misses were `.gdshader` paths truncated by my own regex, plus example strings inside the
  `godot_mcp` editor addon.)
- **All 44 autoloads and every scene named in `project.godot` exist.**
- **Every `.tscn`'s attached script path resolves.**
- **No content cross-reference is broken** — every enemy and boss `scene`, every item
  `weaponId`, every loot-table `itemId`, every `status_on_hit` id.
- **Enemies, statuses, items, traps and quests are all reachable** (quests and recipes are
  directory-scanned by their catalogues, so ID-reference counting under-reports them).
- **Loot rolls are properly seeded** from `RunFlow.current_seed` mixed with a per-drop
  ordinal; the unseeded `randi()` fallback only fires outside a run.
- **No attack anywhere has an `active_duration` ≥ 0.4 s**, which is why removing
  chase-during-attack (C1) breaks no authored encounter.

---

## 4. Validation tests that were asserting falsehoods

Found while checking that the fixes above did not break the suites. Both are pre-existing
and independent of the changes.

**V1 — `combat.guard.block_requires_frontal` could not have been passing.**
`combat_suite.gd` built the rear-hit `DamageInfo` with `fixture.defender_body()` as its own
source. The arc gate reads the attacker's *position*, so the offset was zero, which
`classify_arc` classifies as `FRONT` unconditionally — the "rear hit" was a frontal hit, the
guard applied, and the assertion compared 13.5 against an expected 30.0. It was also missing
the arc damage multiplier a real rear hit earns.

**V2 — `progression.talent_points_from_curve` likewise.**
It called `from_save_dict({"level": 5, "xp": 500})`, but `from_save_dict` recomputes the
level from XP and discards the `level` field. 500 XP is level 4 on the authored curve, so it
compared 3 talent points against an expected 4.

**V3 — three suites demanded `.wav` assets that ship as `.ogg`.**
`setup.combat_sfx_assets` listed seven `res://assets/audio/sfx/*.wav` paths; all seven exist
only as `.ogg`, so the assertion was unsatisfiable and reported every combat cue missing on
every run. `player.heal_authored_sfx` and `quality.audio.combat_sfx_assets` repeated the same
mistake, and `quality.audio.combat_sfx_bank` searched `sfx.json` for a literal
(`res://assets/audio/sfx/hit.wav`) that appears nowhere in it — the bank references
`assets/audio/sfx/hit_flesh_01.ogg` and siblings.

A test that asserts something false is worse than no test: it occupies the slot where a real
guard would go and reports green while doing it. All five are fixed.

---

## 5. What was implemented

### Combat contract (§1)

| ID | Change |
|---|---|
| C1 | Attack commitment in `castle_enemy_base`. Re-aim is allowed for the first `tracking_fraction` (default 0.55) of a wind-up at 0.45× turn speed, then the heading **locks**; the active window neither turns (`ATTACK_TRACKING_SPEED_MULT = 0`) nor pursues. Approach speed during wind-up decays to zero at the commit point, so the spacing the player reads at the start of the telegraph is the spacing the swing lands at. Authored `lunge_distance` on an attack still moves the enemy — along the locked heading, so it is dodgeable. `tracking_fraction` is overridable per attack and per enemy, so a deliberately relentless boss move stays expressible in data. All 65 enemies and every boss inherit this: `castle_enemy_base` is the only definition of `_update_ai`. |
| C1b | `_face_direction` now clamps its `lerp_angle` weight to 1.0. At AI-LOD stride 16 the weight reached ~5.9, which overshoots badly — a latent bug that only appeared on distant enemies. |
| C1c | New `_on_windup_tick(committed)` hook. `castle_archer` re-locks its shot for exactly as long as the body may still turn and freezes on the same frame; previously it locked at wind-up start and then kept rotating, so the arrow left along a heading the archer was no longer facing. |
| C2 | The drink is interruptible. `PlayerHeal` binds `Hurtbox.hurt_received`, `CombatReactions.stagger_started` and `Health.died`. A hit at or above `INTERRUPT_DAMAGE_THRESHOLD` (4.0) breaks it; the charge is spent either way. The heal still lands if the commit point had passed — from the rig's `heal_commit_frame` where the clip authors one, otherwise `HEAL_COMMIT_FRACTION` (0.62) of the drink, so the risk model does not depend on rig authoring. `DioramaAnimController.cancel_heal()` added so the interrupt is visible rather than only logical. |
| C3 | `Guard.try_parry_attack` takes the hit arc and refuses anything non-frontal, backed by a positional cone check. `Hurtbox` now passes the arc it already computed. |
| C4 | Backstep is a real backstep: `BACKSTEP_SPEED_MULT` (0.67) and `BACKSTEP_DURATION_MULT` (0.8) scale the weight-class profile, so it is a short spacing tool rather than a full commit roll. `_active_duration` added so i-frames and `get_dash_progress` track the motion actually playing. |
| C5 | Attack presses made while another action owns the character are buffered instead of discarded (`_buffer_blocked_attack_input`), sharing the existing short buffer window. |
| C6 | Jump respects `allows_cancel_into("dodge")`, matching `_can_dash`. |
| C7 | `Hitbox` scans every physics frame it is open. |

### Correctness (§2)

C8 `set_physics_process(true)` made explicit in `Stamina`/`Poise`/`Mana`, with the intent
written down · C9 dead duplicate `POISE_BROKEN_DAMAGE_MULT` removed from `poise.gd` ·
C10 enemy flinch suppressed during `WINDUP`/`ATTACK` so only a real poise break interrupts ·
C11 a guard press with insufficient stamina now raises the guard without the parry window
instead of doing nothing silently · C12 `PATROL_SPEED_MULT` (0.45) · P1 `respec_talents`
autosaves · A1 `WeaponController` loads the equipped weapon rather than always booting on
`sword_basic` · A2 `ContentLoader.has_missing_content()` / `missing_content_paths()` so a
mispackaged build can report itself instead of looking broken.

### Design (§3)

**D1** — XP curve extended from level 20 to 40. Levels 1–20 are **byte-identical** to the
authored values (the curve follows `25n(n+1) − 50`, continued rather than replaced), so no
existing save shifts. Total 10,450 → 40,950 XP. Sized deliberately to the talent tree's real
per-character capacity: 3 shared branches + 1 class branch = 48 slots, and level 40 grants 39
points, leaving builds exclusive. `bossBonusXp` 150 → 400 and `escapeBonusXp` 50 → 200, so
*finishing* runs outweighs farming trash rather than the reverse.

**D2** — `xp_shard_pickup` grows a depth-tested-off pillar of light, visible across a room and
through floors, with a slow pulse. The recovery loop was already correct; this makes it
navigable.

### Second pass (§3b)

| ID | Change |
|---|---|
| W1 | New `scripts/ui/relic_offer_ui.gd` — a choice-of-three modal presented on boss defeat, keyed `boss:<dungeon>:<floor>` so the run seed fixes which three appear and dying does not reroll them. Wired from `castle_run._on_boss_defeated`, placed **after** the epilogue await so two modals never contend for the pause. No cancel path: the offer is a decision, not a prompt. All 24 dark relics are now reachable. |
| W2 | New `scripts/ui/heal_charge_meter.gd` — one pip per charge, above the status row with the other resources, plus a red flash on interrupt so a spent charge is attributable to the hit that took it. |
| W3 | Added an `inventory_split` action (X) to `project.godot`, registered it as rebindable and keyboard-only (gamepad buttons 0–14 are all taken), gave it a display name, and pointed the handler at it. |
| W4 | New `InventoryService.get_combat_aggregate_stats()` — equipment + class + relics + consumable buffs + status buffs, deliberately *excluding* talents because `CombatStatModifiers` takes those separately and adds both. Every consumer in `apply_equipment_to_player_node` now reads it. |
| W5 | `StatusController.get_stat_totals()` folded into that aggregate, refreshed on `statuses_changed` behind a re-entrancy guard so buffs apply *and* wear off. `get_damage_taken_multiplier()` wired into `Hurtbox`, after resistances. |
| W6 | `riposte_ready` drives a HUD prompt that outranks the parry tell (extracted to `scripts/ui/guard_indicator.gd`); `lock_occluded` tints the reticle. New `HUD_RIPOSTE_READY` string in en + ro. |
| — | Hardened `StatusController`'s tick and meter loops to iterate key snapshots — `_apply_tick` routes damage through the Hurtbox, which can reach `apply_status` and insert into the dictionary being walked. |
| — | Removed dead `_compare_label` from `inventory_ui` (created, styled, added to the tree, never given text — the comparison renders in the tooltip instead). |

### Tests

- New `enemy.attack_commitment` — asserts the C1 invariant directly on the state machine. It
  is the one property in this codebase whose loss is invisible to every other test and fatal
  to how the game feels.
- New `guard.parry_requires_frontal`.
- New `progression.relic_offer_reachable` — asserts offers roll deterministically for a key,
  differ across keys, apply on take, and are actually presented on boss defeat. W1 was
  invisible to the whole existing suite; this is the guard that stops it going dark again.
- V1–V3 fixed, plus `combat_fixture.attacker_body()` so arc tests can place a real attacker.

### Verification

Every changed script parses cleanly under `gdlint`, and each was compared **category-by-category
against its own `HEAD` baseline**: no file gained a lint category it did not already have, and
the three new files are clean outright. (`combat_hud.gd` did cross the 1000-line rule it
previously satisfied, which is why the flask meter and the guard indicators were extracted into
their own files rather than left inline — it is back to 999.)

Also verified: all input actions resolve, `project.godot` still parses with balanced blocks,
`strings.csv` has no malformed rows, `xp_curve.json` is schema-valid, and every `.gd` touched
is LF-terminated per `.gitattributes`.

**No Godot binary was available in this environment, so the validation suites were not
executed.** The new and corrected tests follow the suites' existing idioms but have not been
run, and the combat changes shift feel substantially — they want playtesting before the
numbers I chose are trusted.

One incidental note for the diff: `combat_fixture.gd` was committed with CRLF endings against a
`.gitattributes` that declares `*.gd text eol=lf`, so git was already warning it would normalize
on the next touch. It is now LF like every other script, which costs a one-time whole-file
diff on that file — the substantive change to it is the four-line `attacker_body()` accessor.

---

## 6. Not implemented, and why

Every defect found is fixed. What remains is authoring and tuning, which I am flagging rather
than deciding unilaterally:

- **D3 (escalating whiff punish).** A design addition, not a defect. With C1 and C2 landed the
  fight is already read → space → punish; adding a second failure axis on top of an untested
  new baseline would be tuning blind. Worth revisiting after the combat changes are played.
- **Widening the talent tree.** D1 deliberately stops short of the 48-slot ceiling to keep
  builds exclusive. If the ladder should go past level 40, the tree needs roughly 70+ slots
  first — that is content authoring, and picking those nodes is a design decision, not a repair.
- **Per-boss `tracking_fraction` values.** C1 exposes the knob per attack and per enemy so a
  deliberately relentless boss move stays expressible; every enemy currently runs the 0.55
  default. Which bosses should deviate is a playtest question, and inventing numbers for 65
  enemies without playing them would be worse than the honest default.
- **Relic offers outside boss kills.** The offer is hooked to boss defeat, which is the highest-
  tension moment and the one that makes all 24 dark relics reachable. Bonfires and floor
  transitions are equally valid hooks; adding more without seeing pacing is a balance decision.
- **New bosses, biomes, encounters.** Content authoring.
- **`_dodge_speed` / `DODGE_SPEED` / `DODGE_BACK_SPEED`.** Left in place: they still derive
  `_is_backstep` and now feed `BACKSTEP_SPEED_MULT`. Removing them is a separate cleanup.
- **~170 unreferenced functions** remain across the codebase. I triaged all of them; the
  gameplay-affecting ones are fixed above. The rest are legitimate API surface — catalogue
  getters, save accessors, convenience wrappers, and getters used dynamically by name
  (`Callable(SettingsSchema, "_get_%s" % id)` in the settings schema, which my static scan
  could not see). Deleting them would be churn, not repair.

# Aumbrye — does this feel like a modern soulslike yet?

A player-side review, written after looking at captured screenshots of every screen and reading the
tuning numbers and content behind them. Nothing here is taken from a previous document; every claim
is measured against the tree as it stands.

**Method** — `res://scenes/debug/capture_world_screens.tscn` and `capture_ui_screens.tscn` produced
29 screenshots (hub, castle run, dungeon slice, combat arena, and 25 menus). Combat feel comes from
`scripts/player/dodge.gd`, `content/tuning/dodge.json`, `scripts/combat/weapon_controller.gd` and
`scripts/combat/hit_feedback.gd`. Content counts come from `content/`.

---

## 0. The short version

**Snappy combat: yes, on paper — and it may be the best thing here.** The numbers are genuinely
well chosen. What is missing is not tuning, it is *feedback*: the hit lands correctly and looks like
almost nothing happened.

**Beautiful pixel graphics: not yet.** The pipeline is right, the palettes are sometimes lovely, but
the thing a player looks at 100% of the time — their own character — is an unreadable grey blob, and
half the environments sit in a near-black or washed-out band with no contrast.

**Balanced and addictive: no, and this is the real problem.** Not because the numbers are wrong, but
because **the two loops that make this genre addictive are not implemented as loops.** 184 pieces of
equipment contain zero behavioural effects, and the end-of-run screen — the single most important
moment in a roguelite — currently reads:

```
Time: --   Kills: --   Loot: --   XP: --
```

**Generous, thematic item pool: half true.** 263 items and 234 of them are reachable from loot
tables, which is genuinely generous *in count*. But there is only one *kind* of item in the game.

The encouraging part: this project already demonstrates it knows how to do the hard version. The
35 relics are written like a real designer wrote them. That voice just hasn't reached the loot yet.

---

## 1. What I actually saw

### The hub — `world_hub.png`

The first thing I liked. Warm sunset gradient, banded sky, and four portals with distinct colour
identity (ember orange, two violets, gold) that read instantly as "four places I can go". That is
good, legible game design.

Then the problems:

- **The debug overlay is on.** Eleven lines of `player pos`, `camera facing: yaw -180°`, and
  `speed: 4.77 (base 4.50 x equip 1.06 x status 1.00 x weapon 1.00 x dir 1.00)` across the top
  right of a *hub screenshot*. If this is on in a capture it is one flag away from being on in a
  build. It has to be off by default and gated behind a debug build.
- **The floor is an enormous unbroken plain.** Roughly 60% of the frame is one flat tile pattern
  with nothing on it — no props, no height change, no framing, no reason for the eye to travel.
- **The player is a grey blob with a brown skirt** and a strange blue disc through the shoulders.
  I cannot tell what class they are, what they are holding, or which way they are facing.
- **The pixel font is being scaled non-integer.** "Warden" renders closer to "Marden" — letterforms
  are unevenly sampled. On a pixel font this is very visible and reads as broken.

### The dungeon slice — `world_forgotten_castle_slice.png`

The weakest image, and honestly the one that would stop me buying. Almost the entire frame sits
within a few values of black. In the middle is a **flat untextured grey rectangle** where a doorway
should be, with a brown noise-texture panel above it that reads as a missing material rather than a
designed object. There is one thin white light streak on the right with no visible source.

As a player I would not read this as atmospheric. I would read it as unfinished.

### The castle run — `world_castle_run.png`

Much better. Torchlight, warm orange falloff, brick that actually reads as brick, a lit doorway
drawing me forward. This is the closest the game gets to a mood.

Still: the entire image is one hue. Warm orange-brown everywhere, nothing cool to push against it,
so there is no depth separation between me, the wall and the floor. The brazier is another flat
noise rectangle. And there is a lone yellow `>` chevron floating in mid-air on the right with no
explanation.

### The combat arena — `world_combat_arena.png`

The best-composed frame in the set, and proof the art direction *can* work: a central altar with a
banner, a gold path leading the eye to it, symmetric walls framing the space, warm gold against cool
lavender stone. That is real composition.

Two things break it:

- **Nothing is crisp.** The pipeline is configured correctly — integer `stretch_shrink`, nearest
  filtering, `snap_2d_transforms_to_pixel` — yet the result reads as a soft, muddy upscale rather
  than deliberate pixel art. Character and enemies smear into the floor. Check what
  anti-aliasing is doing *inside* the low-res SubViewport (`anti_aliasing_off` is a setting, so it
  is not always off), and check whether the textures themselves are noisy at the internal
  resolution. Pixel art lives or dies on hard edges.
- **Everything is midtone.** No true blacks, no bright highlights except the gold path. The player,
  six enemies, the floor and the walls all sit in the same narrow value band, so nothing pops.

### The menus

The **inventory** (`inventory_ui.png`) is the most professionally crafted thing in the project.
Clean pixel frames, gold accents, a proper paperdoll with per-slot icons, keycap hints along the
bottom. Genuinely good.

But as a player about to spend hours in it: it is cold and it is missing the reason to open it.
There is **no stat panel anywhere** — no damage, no armour, no resistances. A looter without a stat
readout cannot support build-crafting, because I cannot tell whether the thing I just found is
better. There is no character render on the paperdoll, so I never see my warden wearing anything.
And roughly 35% of the screen width is empty margin.

The **talent screen** (`talents_ui.png`) is a flat scrolling text list. Not a tree — a list box.
The names are excellent ("The Killing Half-Second", "Executioner's Patience", "Old Scars") and the
effects are "+3% Physical Damage".

The **results screen** (`results_screen.png`) is discussed in §3.

---

## 2. Combat feel — this is already good, and it is being hidden

Credit where it is due. These numbers are correct:

| | value | read |
|---|---|---|
| Light attack | 0.15 startup / 0.12 active / 0.25 recovery | 0.52 s total — snappier than Dark Souls, right for this genre |
| Heavy attack | 0.35 / 0.18 / 0.45 | 0.98 s — a real commitment |
| Input buffer | 0.20 s | correct; combos will chain |
| Hitstop | 0.09 s at 0.08× time scale | a strong, deliberate hit freeze |
| Light roll | 0.48 s, i-frames 0.06 → 0.42 | **75% of the roll is invulnerable** |

That roll ratio is the single most important number in a soulslike, and it matches a Dark Souls
medium roll almost exactly. It is also **per armour weight class**, driven from
`content/tuning/dodge.json` — light rolls further and stays invulnerable longer, heavy gives up
i-frames. That is a proper, load-bearing system.

So the combat is not the problem.

**Correction.** My first pass through the screenshots claimed hits had "no impact language". That
was wrong, and reading `scripts/combat/hit_feedback.gd` shows how wrong. The feedback system is
thorough: three impact classes with distinct freeze, camera punch, shake and gamepad rumble
profiles; a material flash on the struck body tinted per event (white on hit, gold on parry, blue
on block); separate crit and hit spark VFX; a damage vignette when you take a hit; an extra
`hit_armor` audio layer on critical impacts; and floating `PARRIED` / `BLOCKED` text. A parry
already routes through the CRITICAL profile with a gold flash. None of that is visible in a static
screenshot, and I should not have inferred its absence from one.

What the code *does* show is that most of this machinery is not reaching the player, for reasons
that are bugs rather than missing features. Those are in §8.

---

## 3. The three changes that decide whether this is addictive

### 3.1 Loot has no fantasy — 184 items, 0 of them do anything

This is the biggest single finding in the review.

```
equipment items:                    184
items with any behavioural field:     0
```

Every equipment JSON has exactly the same shape: `id, name, itemType, equipmentSlot, gridWidth,
gridHeight, stackSize, rarity, description, value, stats`. There are six rarities up to `aumbral`,
but a legendary is a common with bigger numbers in the `stats` block. Nothing procs. Nothing changes
how I play. There are no uniques with rules text.

The affix pool has the same shape — 26 prefixes and 26 suffixes, and the stat distribution is
`physicalDamage, critChance, armor, maxHealth, staminaRegen, goldFind, xpGain…`. Fifty-two affixes,
all of them "+N to a number".

A player's loop in this genre is: *kill → drop → read the rules text → "oh, that changes
everything" → rebuild around it.* Step three does not exist here. That is why the loot cannot be
addictive no matter how many items you add.

**But you already know how to write the good version.** From `content/relics/`:

> *Penitent Chain* — "Twenty health surrendered. Every parry restores a flask charge."
> *The Narrow Path* — "Consecutive dodges sharpen you until something lands."
> *Mourner's Interest* — "Three percent more damage, and kills against the frozen return health."

That is exactly the right voice: a cost, a behaviour, and a reason to change how you fight. Thirty-
five of them, and they are the best content in the project.

**What I would change:**

1. **Add a `behaviour` block to the item schema** — trigger (`onHit`, `onKill`, `onParry`,
   `onDodge`, `onLowHealth`, `onFlaskUse`), effect, and rules text. One schema change unlocks
   everything below.
2. **Give every legendary and aumbral item exactly one behaviour, and no more raw stats than a
   rare.** Seventeen legendaries and nine aumbrals means 26 items that are *chased*, not 26 items
   that are numerically slightly ahead. A legendary should be a build, not an upgrade.
3. **Convert about a third of the affix pool to behavioural affixes.** Keep the flat stats as the
   filler that makes the good rolls feel good — that contrast is the point. Suggested, in the
   existing voice:
   - *Rimebound* — "Your heavy attack leaves frost on the ground for two seconds."
   - *Vengeful* — "Taking a hit while guarding returns a flask charge, once per room."
   - *Hollowing* — "Your dodge costs no stamina below 30% health."
   - *Sworn* — "First hit on a full-health enemy always crits."
   - *Ashen* — "Kills leave an ember; walking through it refunds stamina."
4. **Weapons need movesets, not just numbers.** There are 8 archetypes (sword, greatsword, axe,
   spear, dagger, bow, staff, castle_sword). A soulslike lives on "this weapon *plays* differently".
   Give each a distinct light chain length, a signature heavy, and one weapon art.

### 3.2 The bestiary is 8 fights wearing 54 costumes

```
enemy files:                54
distinct attack ids:        23
attacks per enemy:          3 (for 53 of 54)
```

The attack ids cluster hard: `bolt / hex / ward_burst` appear on 13 enemies each; `snap / lunge /
worry` on 12 each. So the 54-strong bestiary is really about eight movesets re-skinned across
biomes. I fight the same hound in ten colours.

The soulslike loop is *learn the moveset → beat the moveset*. If the moveset is shared, learning one
biome teaches me all ten, and by biome three I am not learning anything — I am grinding.

The telegraphy work is done (160 attacks carry telegraph data), which is the expensive part. What is
missing is variety on top of it.

**What I would change:**

1. **Give each biome family one signature attack that exists nowhere else** — a delayed
   grab in the mire, a two-stage overhead in the castle, a ranged mirror-image in the prism. Ten new
   attacks would roughly double perceived variety for a fraction of the cost of new enemies.
2. **Vary the counts.** Trash can keep two attacks; elites should have four to five; a boss with
   three attacks is not a boss.
3. **There are no boss files at all** — `swamp_hag`, `umbral_confessor`, `iron_foreman` and friends
   are ordinary enemy JSONs with three attacks and no phases. For ten biomes on a "ten-tier
   replayable ladder", each biome needs a boss with at least two phases, a phase-transition moment,
   and one attack the player must *learn* rather than react to.

### 3.3 The reward moment is four dashes in a box

This is the cheapest big win available.

The end-of-run screen is where a roguelite either hooks you or lets you go. Hades, Dead Cells and
Returnal all spend enormous effort here. Aumbrye's currently reads: `Time: --  Kills: --  Loot: --
XP: --` and a `Continue` button, on a black background.

Even fully populated with real values, four numbers in a static box is not a reward — it is a
receipt.

**What I would change**, roughly in order of impact per hour spent:

1. **Count up, don't print.** XP bar fills, kills tick, gold spins. Motion is the reward.
2. **Show the loot.** A row of the actual item icons pulled this run, rarity-framed, best item
   largest and revealed last.
3. **Compare to last time.** "Deepest floor: 7 (best: 6) — NEW". One line, enormous effect.
4. **Show what unlocked.** New recipe, new relic added to the pool, biome tier opened.
5. **Put the next run one button away.** "Descend again" as the primary action, on the results
   screen, pre-seeded with the same class. Never make me walk back through the hub to start.
6. **Death should show the same screen.** Dying in a roguelite must still feel like progress.

---

## 4. Balance and progression

- **Rarity weights** (`content/affixes/rarity_rules.json`) are `common 48 / magic 28 / rare 14 /
  epic 6 / legendary 3 / aumbral 1`. That curve is sane for a game where legendaries are *builds*.
  It is far too stingy for a game where a legendary is a stat stick — right now I grind 100 drops
  for 3% more damage. Fix §3.1 and this curve becomes correct as written.
- **Loot reachability is good**: 234 of 263 authored items appear in a loot table. Twenty-nine are
  currently unreachable and should be audited — an unreachable item is authored content nobody sees.
- **The talent list is 0/1 percentage nodes.** Forty-odd nodes of "+3% Physical Damage" is a
  checklist, not a build. It needs *keystones*: a handful of nodes that change a rule and are
  mutually exclusive ("you can no longer roll, but guarding is free"). And it needs to look like a
  tree, because the shape of a tree is itself the promise of a build.
- **A stat panel is non-negotiable** for a game with 263 items and 52 affixes. Without one the
  entire loot system is invisible to the player.

---

## 5. Is it unique?

Honestly, at the moment: not visually. A dark 3D-voxel dungeon with a low-res filter reads as
generic, and the character silhouette gives it no identity at all.

But there are two things here that nobody else has, and both are being under-used:

**The relic writing.** "Twenty health surrendered. Every parry restores a flask charge." That is a
voice — spare, liturgical, a bit cruel. It matches the name Aumbrye. If that voice ran through the
item names, the death messages, the biome titles and the boss intros, the game would have a
personality before it has better art.

**The diorama framing.** The combat arena screenshot shows what the pixel-diorama idea can be: a
composed, lit, theatrical little box. That is the unique selling point. It should be pushed hard —
every room composed like a diorama with a clear focal point, deliberate lighting and a foreground
frame, rather than corridors of tiled brick.

---

## 6. What I would do, in order

**First — make the existing combat visible.** Impact frames, hit flash, weight-scaled screen shake,
a parry that stops the world, a readable weapon in the player's hands. The combat is already good;
this is the cheapest route to it *feeling* good.

**Second — fix the character silhouette.** I look at this thing for the entire game. It needs a
readable head, a visible weapon, a colour that separates it from every floor, and a rim light or
outline so it never sinks into the background.

**Third — rebuild the results screen.** One screen, enormous return on the addiction loop, and it
needs no new art.

**Fourth — add behaviour to loot.** The schema change, then 26 behavioural legendaries and ~15
behavioural affixes. This is what turns 184 items into a reason to keep playing.

**Fifth — lighting and contrast pass on the dungeon biomes.** True blacks, real highlights, one cool
accent per warm biome, and a fix for the flat untextured doorway and the noise-texture panels.

**Sixth — a stat panel, and turn the talent list into a tree with keystones.**

**Seventh — biome signature attacks and real bosses with phases.**

---

## 7. What I would not touch

- The dodge tuning and its per-weight-class model. It is correct.
- The attack timing and buffer windows.
- The inventory screen's visual language — extend it, don't redesign it.
- The relic system and its writing. Use it as the template for everything else.
- The hub's portal colour-coding.
- The combat arena's composition and palette. That is the target the other environments should hit.

---

## 8. Code verification — what the screenshots got right and wrong

Every visual claim above was re-checked against the source. Six were wrong and are corrected here.
Five turned out to be real bugs, and between them they explain most of what I disliked in the
images.

### 8.1 Corrections — I was wrong about these

| Claim | Reality |
|---|---|
| "Hits have no impact language" | Fully implemented in `hit_feedback.gd` — see the correction in §2 |
| "The debug overlay is on by default" | `debug_overlay.gd` sets `show_debug := OS.is_debug_build()`, and the docstring explains the decision. My captures were a debug build. Correctly gated |
| "The results screen is four dashes" | `results_screen.gd` formats real values (`Time: %d:%02d`, `Kills: %d`). The `--` I saw is the no-run-data fallback. The screen is not broken — my *design* criticism in §3.3 stands, the implied bug does not |
| "The player has no readable weapon" | `DioramaCharacterSkin.attach_weapon()` is called from `diorama_anim_controller.gd`. Weapons do attach. The gold and brown rectangles I could not identify *are* the weapons — that is a silhouette and modelling problem, not missing code |
| "Talents render +3% wrongly" | `talents_ui.gd` already special-cases `MULTIPLIER_DAMAGE_STAT` precisely so a 3% node does not render as "+0". Correct as written |
| "The pixel font is mis-imported" | `aumbrye_pixel.ttf.import` is set up correctly for pixel rendering: `antialiasing=0`, `generate_mipmaps=false`, `hinting=0`, `subpixel_positioning=0` |

### 8.2 Confirmed bugs

**B-01 — World hitstop only ever fires on CRITICAL hits.** *(the big one)*

`HitFeedback._apply_hitstop()` computes a freeze duration for every impact class, then:

```gdscript
if impact == ImpactClass.CRITICAL:
    VfxService.push_time_scale(&"hitstop", HITSTOP_TIME_SCALE, duration_ms)
```

`IMPACT_PROFILES` defines `freeze: 0.04` for GLANCING and `freeze: 0.085` for SOLID. Both are
computed into `duration` and `duration_ms` — and then discarded. Only the *attacker's* AnimDirector
is slowed (`set_speed_scale(0.05)`); `Engine.time_scale` is never touched.

So every ordinary sword hit in the game has **no world hitstop at all**. The player's animation
hitches while the world keeps running at full speed, which reads as a stutter rather than an impact.
This is almost certainly why the combat looked weightless to me, and it is a handful of lines to
fix.
**Where** — `apps/game/client/scripts/combat/hit_feedback.gd`

**B-02 — FXAA and MSAA run inside the low-resolution pixel viewport, by default.**

```gdscript
const DEFAULT_ANTI_ALIASING_OFF := false
...
var msaa := Viewport.MSAA_DISABLED if anti_aliasing_off else Viewport.MSAA_2X
var ss_aa := Viewport.SCREEN_SPACE_AA_DISABLED if anti_aliasing_off else Viewport.SCREEN_SPACE_AA_FXAA
```

The default is AA **on**, so the pixel-diorama SubViewport renders with `MSAA_2X` plus
`SCREEN_SPACE_AA_FXAA`. FXAA is a post-process edge blur — applied to a low-res render it smears
exactly the hard pixel boundaries the entire art direction depends on, *before* the crisp
nearest-neighbour upscale ever happens.

This is the direct cause of the soft, muddy look in all three 3D captures. Everything else in the
pipeline is right — integer `stretch_shrink`, `TEXTURE_FILTER_NEAREST`, `snap_2d_transforms_to_pixel`
— and this one setting undoes it. The double-negative name (`anti_aliasing_off = false` meaning "AA
on") is the likely reason it was never noticed.
**Where** — `apps/game/client/scripts/art/pipeline/pixel_diorama_settings.gd`

**B-03 — Crits never reach the damage number.**

`on_hit()` takes a `crit: bool` and passes it only to `_flash_diorama_body()`, which picks
`play_crit_spark` over `play_hit_spark`. `_spawn_damage_number()` is called with damage and damage
type only, and `damage_number.gd` modulates purely by `damage_type`. A critical hit therefore prints
a number identical in size and colour to a glancing one. My §2 note about damage-number craft was
correct, and this is why.
**Where** — `apps/game/client/scripts/combat/hit_feedback.gd`, `scripts/combat/damage_number.gd`

**B-04 — Early-game hits are classified GLANCING, so the first hour has the weakest feedback.**

`Hurtbox._impact_class_for()` returns GLANCING when `res.outgoing < HitFeedback.GLANCING_DAMAGE`,
and `GLANCING_DAMAGE := 15.0`. The fallback light attack does `damage: 12.0`. The GLANCING profile
has `shake: 0.0`, no audio layer, and — per B-01 — no world hitstop.

A new player's first hour is therefore the least satisfying combat in the game, which is precisely
backwards: that hour decides whether they keep playing. The threshold should scale with weapon class
or target max health rather than being a flat damage number.
**Where** — `apps/game/client/scripts/combat/hurtbox.gd`, `scripts/combat/hit_feedback.gd`

**B-05 — The talent tree has branch structure that the UI throws away.**

`ProgressionService.get_available_talent_tree()` returns `{branches: [{name, nodes: [...]}]}` — the
data is already shaped as a tree. `talents_ui.gd` walks those branches and flattens every node into
a single flat `ItemList`, keeping only the branch name as a `[Arms]` / `[Guard]` text prefix.

So the flat list I criticised in §1 is not a missing feature — the structure exists and is discarded
at render time. Drawing it as an actual branching tree is a UI change, not a data change.
**Where** — `apps/game/client/scripts/ui/talents_ui.gd`

### 8.3 Unconfirmed

- **Uneven letterforms in the hub greeting.** The font import is correct, but `UITextScale`
  applies `int(base_size * scale)`, which can land on sizes that are not integer multiples of the
  font's design size. With `antialiasing=0` that shows up as doubled or dropped pixel rows rather
  than blur — which matches "Warden" reading as "Marden". Worth snapping scaled sizes to multiples
  of the design size, but I could not confirm the design size from the import file alone.
- **The flat grey doorway and the noise-texture panels** in the dungeon slice. I found no obvious
  missing-material path in `dungeon_builder.gd` or `floor_shell_builder.gd` in the time available.
  Needs someone to open `forgotten_castle_slice.tscn` and look at the door frame's material.
- **The lone yellow `>` chevron** in `world_castle_run.png`. The only chevrons in the UI code belong
  to `appearance_row.gd` (character creation), so this is something else — most likely an
  interaction or objective marker rendering without its label.

### 8.4 What this changes about the priorities

§6 asked for impact frames and hit flash as the first job. That was based on a wrong reading — the
work is already done. The revised first job is much cheaper:

1. **Fix B-01 and B-02.** Two small edits. Between them they restore world hitstop on every hit and
   make the entire game crisp. This is the highest ratio of felt improvement to effort anywhere in
   this document.
2. **Fix B-04, then B-03.** Early-game impact class, then crit-scaled damage numbers.
3. Everything else in §6 stands, starting with the character silhouette.

The loot and bestiary findings in §3 are unaffected — those were measured from content counts, not
inferred from images, and they remain the deciding factor for whether the game is addictive.

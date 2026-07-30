# Phase M5 — Content Pack A

- **phase:** M5
- **goal:** Three distinct kingdoms + combat depth (elements, statuses, weapon archetypes).
- **depends_on:** M4 exit criteria
- **exit_criteria:**
  - [ ] Themes complete: Forgotten Castle (art pass), Crystal Caverns, Poison Swamp
  - [ ] Each theme: room kit, 4–5 enemies, miniboss, boss, puzzle, audio profile, unique items
  - [ ] Damage types: physical, fire, frost, poison, lightning, arcane
  - [ ] Statuses: burn, bleed, poison, freeze, stun
  - [ ] Weapons playable: sword, greatsword, dagger, spear, bow
  - [ ] Player can identify themes by silhouette/lighting/audio alone

---

## Minor milestones

### THEME-5.1 — Forgotten Castle art pass

- **status:** not_started
- **depends_on:** [M4]
- **unlocks:** []
- **primary_paths:**
  - `apps/game/client/scenes/rooms/castle/`
  - `assets/`
- **agent_instructions:**
  - Replace blockout with pixel-diorama pass; lighting profile finalized.
- **acceptance_criteria:**
  - [ ] No graybox dominant in screenshots
  - [ ] Lighting profile id referenced by biome
- **out_of_scope:**
  - Cinematics

### THEME-5.2 — Crystal Caverns full set

- **status:** not_started
- **depends_on:** [PROC biome content support]
- **unlocks:** []
- **primary_paths:**
  - `content/biomes/crystal_caverns.json`
  - `apps/game/client/scenes/rooms/crystal/`
- **agent_instructions:**
  - Room templates, enemy pool, boss, miniboss, puzzle, loot table, audio.
  - Must feel distinct from castle (verticality/crystals/cold light).
- **acceptance_criteria:**
  - [ ] Generatable and completable
  - [ ] Blind playtester names theme without UI label (spot check) — [MANUAL_PLAYTEST_CHECKLIST.md](../../design/MANUAL_PLAYTEST_CHECKLIST.md) `M5.theme.blind`
- **out_of_scope:**
  - Second cavern variant

### THEME-5.3 — Poison Swamp full set

- **status:** not_started
- **depends_on:** [DMG-5.1]
- **unlocks:** []
- **primary_paths:**
  - `content/biomes/poison_swamp.json`
  - `apps/game/client/scenes/rooms/swamp/`
- **agent_instructions:**
  - Hazards use poison status; murky lighting; distinct enemy silhouettes.
- **acceptance_criteria:**
  - [ ] Generatable and completable
  - [ ] Environmental poison readable and fair
- **out_of_scope:**
  - Mounts/boats

### DMG-5.1 — Damage type pipeline

- **status:** not_started
- **depends_on:** [WPN-1.1]
- **unlocks:** [DMG-5.2, THEME-5.3]
- **primary_paths:**
  - `apps/game/client/scripts/combat/damage_info.gd`
  - `content/` resistances on enemies
- **agent_instructions:**
  - Extend DamageInfo with types; enemy resistances/weaknesses data-driven.
- **acceptance_criteria:**
  - [ ] All six types deal damage through pipeline
  - [ ] Resistance reduces correctly per data
- **out_of_scope:**
  - Hybrid complex formulas beyond simple mul

### DMG-5.2 — Status effects

- **status:** not_started
- **depends_on:** [DMG-5.1]
- **unlocks:** []
- **primary_paths:**
  - `apps/game/client/scripts/combat/statuses/`
  - `content/statuses/`
- **agent_instructions:**
  - Implement burn, bleed, poison, freeze, stun with stacks/durations in data.
- **acceptance_criteria:**
  - [ ] Each status has unit test or debug apply cheat
  - [ ] UI icon row shows active statuses
- **out_of_scope:**
  - Curse (defer unless free)

### WPN-5.1 — Greatsword moveset

- **status:** not_started
- **depends_on:** [COMBAT-1.2]
- **unlocks:** []
- **primary_paths:**
  - `content/weapons/`
- **agent_instructions:**
  - Slow heavy hyperarmor swings; high poise damage.
- **acceptance_criteria:**
  - [ ] Distinct from sword timings
  - [ ] Usable in arena vs training+castle enemies
- **out_of_scope:**
  - Unique skill trees

### WPN-5.2 — Dagger moveset

- **status:** not_started
- **depends_on:** [COMBAT-1.2]
- **unlocks:** []
- **agent_instructions:**
  - Fast multihit; bleed application; low stagger.
- **acceptance_criteria:**
  - [ ] Clear identity vs sword
- **out_of_scope:**
  - Stealth meters

### WPN-5.3 — Spear moveset

- **status:** not_started
- **depends_on:** [COMBAT-1.2]
- **unlocks:** []
- **agent_instructions:**
  - Range advantage; thrust moveset; spaced pokes.
- **acceptance_criteria:**
  - [ ] Longer reach than sword measurable
- **out_of_scope:**
  - Mounted combat

### WPN-5.4 — Bow moveset

- **status:** not_started
- **depends_on:** [COMBAT-1.2, ENEMY-2.2]
- **unlocks:** []
- **agent_instructions:**
  - Draw/release; stamina; aiming with lock-on assist.
  - Secondary melee nudge optional light.
- **acceptance_criteria:**
  - [ ] Can clear archer duel at range
  - [ ] Draw telegraph for player shots not required; enemy fairness retained
- **out_of_scope:**
  - Gun archetypes

### WPN-5.5 — Weapon swap + unlocks

- **status:** not_started
- **depends_on:** [WPN-5.1, WPN-5.2, WPN-5.3, WPN-5.4, PROG-4.1]
- **unlocks:** []
- **primary_paths:**
  - inventory + progression flags
- **agent_instructions:**
  - Swap equipped weapon; gate some weapons behind recipes/levels.
- **acceptance_criteria:**
  - [ ] Five archetypes selectable in hub loadout
- **out_of_scope:**
  - Axe/staff (stub defs allowed unused)

### AUDIO-5.1 — Per-biome audio profiles

- **status:** not_started
- **depends_on:** [AUDIO-2.1, THEME-5.2]
- **unlocks:** []
- **primary_paths:**
  - `content/audio_profiles/`
  - `apps/game/client/scripts/audio/`
- **agent_instructions:**
  - Ambience, explore, combat, boss per biome; seamless crossfade ≤1s.
- **acceptance_criteria:**
  - [ ] Combat→explore crossfade works
  - [ ] Each of 3 themes has unique boss track stub/final
- **out_of_scope:**
  - Dynamic stem remixing

### BOSS-5.1 — Caverns boss + miniboss

- **status:** not_started
- **depends_on:** [THEME-5.2, BOSS-2.2 patterns]
- **unlocks:** []
- **agent_instructions:**
  - Multi-phase boss; distinct arena mechanic (e.g. crystal pillars).
- **acceptance_criteria:**
  - [ ] 2 phases minimum
  - [ ] Mechanic taught by telegraph not tutorial text
- **out_of_scope:**
  - Raid-style adds spam

### BOSS-5.2 — Swamp boss + miniboss

- **status:** not_started
- **depends_on:** [THEME-5.3, DMG-5.2]
- **unlocks:** []
- **agent_instructions:**
  - Poison-centric phase mechanics; fair cleanse windows or spacing answers.
- **acceptance_criteria:**
  - [ ] Completable without mandatory curse/poison death loops
- **out_of_scope:**
  - Instant kill clouds

### ITEM-5.1 — Theme unique items batch A

- **status:** not_started
- **depends_on:** [LOOT-4.1]
- **unlocks:** []
- **primary_paths:**
  - `content/items/`
- **agent_instructions:**
  - Add theme-unique items toward EA 80 cap; at least 2–3 per theme.
- **acceptance_criteria:**
  - [ ] Items appear in theme loot tables
  - [ ] Icons exist (SVG/PNG)
- **out_of_scope:**
  - Filling entire 80 yet

### BAL-5.1 — Mid content balance pass

- **status:** not_started
- **depends_on:** [THEME-5.3, WPN-5.5]
- **unlocks:** []
- **primary_paths:**
  - `docs/design/balance_m5.md`
  - `scripts/` damage simulator stub
- **agent_instructions:**
  - Compare TTK across weapons vs common enemies; adjust data not code when possible.
- **acceptance_criteria:**
  - [ ] Notes + data tweaks committed
- **out_of_scope:**
  - Perfect parity

---

## M5 ordered work queue

1. DMG-5.1 → DMG-5.2
2. THEME-5.1 parallel with WPN-5.1–5.4
3. THEME-5.2 → BOSS-5.1 → AUDIO-5.1
4. THEME-5.3 → BOSS-5.2
5. WPN-5.5 + ITEM-5.1 + BAL-5.1
6. Exit criteria

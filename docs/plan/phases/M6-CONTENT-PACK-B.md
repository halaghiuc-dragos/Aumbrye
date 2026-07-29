# Phase M6 — Content Pack B + Meta

- **phase:** M6
- **goal:** Five themes total; EA content volume; website; accessibility; meta features.
- **depends_on:** M5 exit criteria
- **exit_criteria:**
  - [ ] Themes: +Frozen Fortress, +Dark Cathedral (5 total)
  - [ ] ~20 enemies, ~8 bosses, ~80 items
  - [ ] Achievements framework + ~25 achievements
  - [ ] Optional leaderboards (clear time)
  - [ ] Website: landing, account, patch notes, wiki stubs, leaderboards
  - [ ] Accessibility baseline
  - [ ] ~8–12 hours distinct content estimate documented

---

## Minor milestones

### THEME-6.1 — Frozen Fortress full set

- **status:** not_started
- **depends_on:** [M5]
- **unlocks:** []
- **primary_paths:**
  - `content/biomes/frozen_fortress.json`
  - `apps/game/client/scenes/rooms/frozen/`
- **agent_instructions:**
  - Frost hazards; distinct architecture; boss + miniboss + puzzle + audio + enemies.
- **acceptance_criteria:**
  - [ ] Completable generated runs
  - [ ] Freeze status used fairly
- **out_of_scope:**
  - Ice skating vehicle

### THEME-6.2 — Dark Cathedral full set

- **status:** not_started
- **depends_on:** [M5]
- **unlocks:** []
- **primary_paths:**
  - `content/biomes/dark_cathedral.json`
  - `apps/game/client/scenes/rooms/cathedral/`
- **agent_instructions:**
  - Vertical nave spaces; shadow/holy-arcane fantasy; memorable boss.
- **acceptance_criteria:**
  - [ ] Completable generated runs
  - [ ] Distinct audio/lighting identity
- **out_of_scope:**
  - Religious real-world assets

### ENEMY-6.1 — Fill roster to ≤20

- **status:** not_started
- **depends_on:** [THEME-6.1, THEME-6.2]
- **unlocks:** []
- **primary_paths:**
  - `content/enemies/`
  - [content/02-ENEMIES.md](../content/02-ENEMIES.md)
- **agent_instructions:**
  - Implement remaining enemies on roster until count ≤20 and themes covered.
- **acceptance_criteria:**
  - [ ] Roster checklist complete
  - [ ] Each enemy has telegraph profile
- **out_of_scope:**
  - Exceeding 20

### BOSS-6.1 — Fill boss roster to ≤8

- **status:** not_started
- **depends_on:** [THEME-6.1, THEME-6.2]
- **unlocks:** []
- **primary_paths:**
  - `content/bosses/`
  - [content/03-BOSSES.md](../content/03-BOSSES.md)
- **agent_instructions:**
  - Ensure 5 theme bosses + additional miniboss promotions / variants to 8.
- **acceptance_criteria:**
  - [ ] 8 bosses listed and playable
- **out_of_scope:**
  - >8 bosses

### ITEM-6.1 — Fill items to ≤80

- **status:** not_started
- **depends_on:** [LOOT-4.1]
- **unlocks:** []
- **primary_paths:**
  - `content/items/`
  - [content/04-ITEMS.md](../content/04-ITEMS.md)
- **agent_instructions:**
  - Complete item defs across slots/rarities; validate loot tables reference only existing ids.
- **acceptance_criteria:**
  - [ ] ≤80 defs; tables valid
  - [ ] Each slot has multiple options
- **out_of_scope:**
  - Cosmetics-only items flooding cap

### META-6.1 — Achievements framework

- **status:** not_started
- **depends_on:** [SAVE-4.1]
- **unlocks:** [META-6.2, STEAM-7.2]
- **primary_paths:**
  - `content/achievements/`
  - backend + Godot achievement service
- **agent_instructions:**
  - Unlock flags server-side; client displays toasts.
- **acceptance_criteria:**
  - [ ] Unlock persists
  - [ ] ~25 achievements defined
- **out_of_scope:**
  - Steam sync (M7)

### META-6.2 — Leaderboards

- **status:** not_started
- **depends_on:** [API Redis]
- **unlocks:** [WEB-6.4]
- **primary_paths:**
  - `services/backend/` Leaderboards
- **agent_instructions:**
  - Opt-in daily/tier clear-time leaderboard in Redis sorted sets.
- **acceptance_criteria:**
  - [ ] Submit on escape with boss defeated
  - [ ] Top N query works
- **out_of_scope:**
  - Global season ladder UI complexity

### WEB-6.1 — Landing page

- **status:** not_started
- **depends_on:** [SETUP-0.5, M4]
- **unlocks:** []
- **primary_paths:**
  - `apps/web/`
- **agent_instructions:**
  - Brand-first landing per frontend design rules; trailer/screenshot slots; CTA to Steam wishlist placeholder.
- **acceptance_criteria:**
  - [ ] Desktop + mobile readable
  - [ ] Brand dominates first viewport
- **out_of_scope:**
  - Full blog CMS

### WEB-6.2 — Account pages

- **status:** not_started
- **depends_on:** [AUTH-3.1, WEB-6.1]
- **unlocks:** []
- **agent_instructions:**
  - Login/register/refresh against API; show linked character summary.
- **acceptance_criteria:**
  - [ ] Auth flow works against deployed/local API
- **out_of_scope:**
  - OAuth buttons required (optional)

### WEB-6.3 — Patch notes + wiki stubs

- **status:** not_started
- **depends_on:** [WEB-6.1]
- **unlocks:** []
- **agent_instructions:**
  - MD/JSON-driven patch notes; stub wiki pages for controls, biomes, FAQ.
- **acceptance_criteria:**
  - [ ] Can publish a patch note entry without code change (content file)
- **out_of_scope:**
  - Full community wiki edit

### WEB-6.4 — Leaderboards page

- **status:** not_started
- **depends_on:** [META-6.2, WEB-6.2]
- **unlocks:** []
- **agent_instructions:**
  - Display top clears; filters by biome/tier.
- **acceptance_criteria:**
  - [ ] Matches API data
- **out_of_scope:**
  - Replays

### A11Y-6.1 — Accessibility baseline

- **status:** not_started
- **depends_on:** [UI systems]
- **unlocks:** []
- **primary_paths:**
  - settings UI + [systems/21-ACCESSIBILITY.md](../systems/21-ACCESSIBILITY.md)
- **agent_instructions:**
  - Remap inputs; UI scale; reduce camera shake; colorblind-friendly damage colors; subtitle-sized fonts.
- **acceptance_criteria:**
  - [ ] Checklist in accessibility doc complete
- **out_of_scope:**
  - Full screen reader support for 3D world

### AUTH-6.1 — OAuth Google/Discord (optional polish)

- **status:** not_started
- **depends_on:** [AUTH-3.1, WEB-6.2]
- **unlocks:** []
- **agent_instructions:**
  - Add OAuth if schedule allows; not EA blocker.
- **acceptance_criteria:**
  - [ ] Either implemented with tests OR explicitly deferred in known issues
- **out_of_scope:**
  - Steam auth (M7/post)

### BAL-6.1 — Tools + wide balance pass

- **status:** not_started
- **depends_on:** [ITEM-6.1, ENEMY-6.1]
- **unlocks:** []
- **primary_paths:**
  - `scripts/` balance CLI
- **agent_instructions:**
  - Export content tables; simulate DPS bands; tune outliers.
- **acceptance_criteria:**
  - [ ] Tool runs in CI or documented local
  - [ ] Balance notes for M6 filed
- **out_of_scope:**
  - Automated ML balancer

### PERF-6.1 — Content performance pass

- **status:** not_started
- **depends_on:** [THEME-6.2]
- **unlocks:** [PERF-7.x]
- **agent_instructions:**
  - Room streaming, enemy pooling, light budgets per biome.
- **acceptance_criteria:**
  - [ ] 1080p 60 FPS in 5-theme combat rooms on mid-range target machine profile documented
- **out_of_scope:**
  - 4K unlocks

---

## M6 ordered work queue

1. THEME-6.1 + THEME-6.2
2. ENEMY-6.1 + BOSS-6.1 + ITEM-6.1
3. META-6.1 + META-6.2
4. WEB-6.1 → 6.2 → 6.3 → 6.4
5. A11Y-6.1 + BAL-6.1 + PERF-6.1
6. AUTH-6.1 optional
7. Exit criteria

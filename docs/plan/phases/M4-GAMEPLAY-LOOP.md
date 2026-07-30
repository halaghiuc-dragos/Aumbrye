# Phase M4 — Full Gameplay Loop

- **phase:** M4
- **goal:** Town → choose dungeon → run → loot → upgrade → repeat with cloud saves.
- **depends_on:** M3 exit criteria
- **exit_criteria:**
  - [ ] Handcrafted hub with blacksmith, merchant, storage, training arena, quest board, portals
  - [ ] Affixed loot Common–Rare at minimum (Epic+ tables exist)
  - [ ] Permanent XP/level + small talent tree
  - [ ] Run relics/buffs
  - [ ] Inventory sort/filter/compare
  - [ ] Cloud save + local cache
  - [ ] 10 consecutive runs without softlock
  - [ ] 3 hub NPCs with dialogue

---

## Minor milestones

### HUB-4.1 — Hub layout handcrafted

- **status:** not_started
- **depends_on:** [HUB-2.1]
- **unlocks:** [HUB-4.2]
- **primary_paths:**
  - `apps/game/client/scenes/hub/hub.tscn`
- **agent_instructions:**
  - Expand stub into branded hub with clear landmarks for each service.
- **acceptance_criteria:**
  - [ ] Player can walk to each service without UI map dependency
  - [ ] Portal room supports biome/tier select UI
- **out_of_scope:**
  - Multi-hub

### HUB-4.2 — Blacksmith

- **status:** not_started
- **depends_on:** [HUB-4.1, INV-4.1]
- **unlocks:** []
- **primary_paths:**
  - `apps/game/client/scripts/hub/blacksmith.gd`
  - `content/recipes/`
- **agent_instructions:**
  - Upgrade weapon/armor costs gold; repair durability.
- **acceptance_criteria:**
  - [ ] Upgrade changes item power
  - [ ] Cannot upgrade without currency
- **out_of_scope:**
  - Infusion crafting trees

### HUB-4.3 — Merchant

- **status:** not_started
- **depends_on:** [HUB-4.1, LOOT-4.1]
- **unlocks:** []
- **primary_paths:**
  - `apps/game/client/scripts/hub/merchant.gd`
- **agent_instructions:**
  - Buy consumables; sell junk; stock from data.
- **acceptance_criteria:**
  - [ ] Buy/sell updates inventory and gold
- **out_of_scope:**
  - Dynamic economy simulation

### HUB-4.4 — Storage + training + portals

- **status:** not_started
- **depends_on:** [HUB-4.1, INV-4.1]
- **unlocks:** []
- **primary_paths:**
  - `apps/game/client/scripts/hub/`
- **agent_instructions:**
  - Storage grid separate from inventory; arena door; portal tier select.
- **acceptance_criteria:**
  - [ ] Move items inventory↔storage
  - [ ] Start tier-1 castle run from portal
- **out_of_scope:**
  - Shared guild stash

### NPC-4.1 — NPC framework

- **status:** not_started
- **depends_on:** [HUB-4.1]
- **unlocks:** [DLG-4.1]
- **primary_paths:**
  - `apps/game/client/scripts/npc/`
  - `content/npcs/`
- **agent_instructions:**
  - Data-driven NPC spawn + interact prompt.
- **acceptance_criteria:**
  - [ ] Interact opens dialogue or shop by NPC type
- **out_of_scope:**
  - Schedules/day-night

### DLG-4.1 — Dialogue runner

- **status:** not_started
- **depends_on:** [NPC-4.1]
- **unlocks:** [QUEST-4.1]
- **primary_paths:**
  - `apps/game/client/scripts/dialogue/`
  - `content/dialogue/`
- **agent_instructions:**
  - JSON branching dialogue; conditions on flags/level; localized string keys.
- **acceptance_criteria:**
  - [ ] Branch choices work on gamepad
  - [ ] Condition gates lines
- **out_of_scope:**
  - Voice acting

### QUEST-4.1 — Optional quest board

- **status:** not_started
- **depends_on:** [DLG-4.1]
- **unlocks:** []
- **primary_paths:**
  - `content/quests/`
  - `apps/game/client/scripts/quests/`
- **agent_instructions:**
  - Simple fetch/kill/escape quests; never block portals.
- **acceptance_criteria:**
  - [ ] Can ignore quests and still progress
  - [ ] Completing quest grants reward via server or local+sync path
- **out_of_scope:**
  - Multi-act campaign

### LOOT-4.1 — Rarity + affix roller (server)

- **status:** not_started
- **depends_on:** [API-3.3, SCHEMA-4.2]
- **unlocks:** [LOOT-4.2]
- **primary_paths:**
  - `services/backend/` + `content/affixes/`
- **agent_instructions:**
  - Roll rarity + affixes on chest open / enemy drop allowances defined in dungeon definition.
  - Persist ItemInstances on complete.
- **acceptance_criteria:**
  - [ ] Identical rollSeed → identical affixes
  - [ ] Affix count by rarity respected
- **out_of_scope:**
  - Mythic unique legends set (can stub)

### SCHEMA-4.2 — Affix schema

- **status:** not_started
- **depends_on:** [SCHEMA-2.1]
- **unlocks:** [LOOT-4.1]
- **primary_paths:**
  - `content/schemas/affix.schema.json`
  - `content/affixes/`
- **agent_instructions:**
  - Define affix defs and rarity rules.
- **acceptance_criteria:**
  - [ ] Validator covers affix pack
- **out_of_scope:**
  - Set bonuses

### LOOT-4.2 — Equipment slots full set

- **status:** not_started
- **depends_on:** [LOOT-4.1, INV-4.1]
- **unlocks:** []
- **primary_paths:**
  - `apps/game/client/scripts/items/equipment.gd`
- **agent_instructions:**
  - Support all EA slots; apply stats to player.
- **acceptance_criteria:**
  - [ ] Equipping rare item changes damage/defense visibly
  - [ ] Two-weapon slots behave (weapon/secondary)
- **out_of_scope:**
  - Cosmetics

### INV-4.1 — Inventory UX complete

- **status:** not_started
- **depends_on:** [INV-2.1]
- **unlocks:** [HUB-4.2, LOOT-4.2]
- **primary_paths:**
  - `apps/game/client/scripts/ui/inventory_ui.gd`
- **agent_instructions:**
  - Drag-drop, sort, filter, compare tooltips; controller-first.
- **acceptance_criteria:**
  - [ ] Compare shows stat deltas
  - [ ] Filter by rarity/type
  - [ ] Fully usable without mouse
- **out_of_scope:**
  - Trading

### PROG-4.1 — XP / level

- **status:** not_started
- **depends_on:** [API-3.3]
- **unlocks:** [PROG-4.2]
- **primary_paths:**
  - `services/backend/` + Godot HUD
- **agent_instructions:**
  - Grant XP on run complete; level curve in content; death grants reduced XP.
- **acceptance_criteria:**
  - [ ] Level up persists in save
  - [ ] Curve documented
- **out_of_scope:**
  - Prestige

### PROG-4.2 — Talent tree

- **status:** not_started
- **depends_on:** [PROG-4.1, SCHEMA-4.1]
- **unlocks:** []
- **primary_paths:**
  - `content/talents/`
  - `apps/game/client/scripts/ui/talents_ui.gd`
- **agent_instructions:**
  - 3 branches × ~6 nodes; spend points on level; server validates.
- **acceptance_criteria:**
  - [ ] Illegal unlock rejected by API
  - [ ] Talents affect combat stats/rules as defined
- **out_of_scope:**
  - Respec shop (optional later)

### SCHEMA-4.1 — CharacterState schema

- **status:** not_started
- **depends_on:** [SCHEMA-2.1]
- **unlocks:** [PROG-4.2, SAVE-4.1]
- **primary_paths:**
  - `content/schemas/character_state.schema.json`
- **agent_instructions:**
  - Freeze CharacterState v1 fields used by API/Godot.
- **acceptance_criteria:**
  - [ ] Schema validates sample save
- **out_of_scope:**
  - Cosmetics inventory

### PROG-4.3 — Run relics / buffs

- **status:** not_started
- **depends_on:** [LOOT-4.1]
- **unlocks:** []
- **primary_paths:**
  - `content/relics/`
  - `apps/game/client/scripts/combat/run_buffs.gd`
- **agent_instructions:**
  - In-run relics expire on escape/death per rules; stack limits data-driven.
- **acceptance_criteria:**
  - [ ] Relic modifies run combat
  - [ ] Cleared from state after run end
- **out_of_scope:**
  - Roguelike meta between seasons

### SAVE-4.1 — Cloud save + local cache

- **status:** not_started
- **depends_on:** [SCHEMA-4.1, API-3.1]
- **unlocks:** [SAVE-4.2]
- **primary_paths:**
  - `services/backend/` Saves feature + Godot save service
- **agent_instructions:**
  - `GET/PUT /api/v1/saves/current`; local cache; conflict policy = server wins with backup of local.
- **acceptance_criteria:**
  - [ ] Second device/session loads cloud state
  - [ ] Offline changes sync when online or warn
- **out_of_scope:**
  - Steam Cloud (M7)

### SAVE-4.2 — Automatic backups

- **status:** not_started
- **depends_on:** [SAVE-4.1]
- **unlocks:** []
- **primary_paths:**
  - `apps/game/client/scripts/save/`
- **agent_instructions:**
  - Rotate N local backups; expose restore in settings.
- **acceptance_criteria:**
  - [ ] Can restore previous backup
- **out_of_scope:**
  - Point-in-time server backups UI

### FLOW-4.1 — Death / escape economy

- **status:** not_started
- **depends_on:** [PROG-4.1, LOOT-4.1, PROG-4.3]
- **unlocks:** []
- **primary_paths:**
  - `docs/design/run_economy.md`
  - backend complete-run logic
- **agent_instructions:**
  - Document and implement: escape keeps loot; death keeps XP fraction, loses run relics; tune defaults.
- **acceptance_criteria:**
  - [ ] Rules documented and enforced server-side
  - [ ] Client UI explains outcome
- **out_of_scope:**
  - Hardcore delete character

### TEST-4.1 — Ten-run softlock soak

- **status:** not_started
- **depends_on:** [FLOW-4.1, HUB-4.4]
- **unlocks:** []
- **primary_paths:**
  - `docs/design/m4_soak_notes.md`
- **agent_instructions:**
  - Manually or semi-auto complete 10 runs; log issues in `docs/design/m4_soak_notes.md`.
  - Track progress in [MANUAL_PLAYTEST_CHECKLIST.md](../../design/MANUAL_PLAYTEST_CHECKLIST.md) § M4+.
- **acceptance_criteria:**
  - [ ] 10/10 no softlock
  - [ ] Notes filed
- **out_of_scope:**
  - Balance perfection

---

## M4 ordered work queue

1. SCHEMA-4.1 + SCHEMA-4.2
2. HUB-4.1 → NPC/DLG → HUB services
3. INV-4.1 → LOOT-4.1 → LOOT-4.2
4. PROG-4.1 → 4.2 → 4.3
5. SAVE-4.1 → 4.2 + FLOW-4.1
6. QUEST-4.1 + TEST-4.1
7. Exit criteria

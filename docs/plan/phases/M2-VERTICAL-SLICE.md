# Phase M2 — Vertical Slice

- **phase:** M2
- **goal:** Playable handcrafted Forgotten Castle run with boss and local save — no server gen yet.
- **depends_on:** M1 complete — [M1_IMPLEMENTATION_LOG.md](../../design/M1_IMPLEMENTATION_LOG.md)
- **exit_criteria:**
  - [x] Hub stub portal → castle dungeon → boss → escape → results
  - [x] 6–8 rooms including 1 secret
  - [x] 3 enemy types + traps
  - [x] 2-phase boss
  - [x] Temporary grid inventory with pickups
  - [x] Local JSON save with schemaVersion
  - [ ] External friend can complete a run (optional — KB/M signed off 2026-07-30)

---

## Minor milestones

### ART-2.1 — Castle room kit blockout

- **status:** done
- **depends_on:** [M1]
- **unlocks:** [DUNGEON-2.1]
- **primary_paths:**
  - `apps/game/client/scenes/rooms/castle/`
  - `assets/models/castle/`
- **agent_instructions:**
  - Create modular room templates: hall, stairs, courtyard, treasure, secret, arena, boss.
  - Placeholder pixel textures OK.
- **acceptance_criteria:**
  - [x] ≥6 distinct room scenes with navigation bounds
  - [x] Consistent doorway socket convention documented
- **out_of_scope:**
  - Final art pass

### DUNGEON-2.1 — Hand-authored castle layout

- **status:** done
- **depends_on:** [ART-2.1]
- **unlocks:** [DUNGEON-2.2, BOSS-2.1]
- **primary_paths:**
  - `apps/game/client/scenes/dungeon/forgotten_castle_slice.tscn`
- **agent_instructions:**
  - Wire 6–8 rooms; include shortcut and 1 secret room.
  - Entrance + exit portal after boss flag.
- **acceptance_criteria:**
  - [x] Player can traverse entrance to boss door
  - [x] Secret is findable without guide (subtle cue)
  - [x] Shortcut reconnects early/late areas
- **out_of_scope:**
  - Procedural assembly

### DUNGEON-2.2 — Fixture definition mirror

- **status:** done
- **depends_on:** [DUNGEON-2.1, SCHEMA-0.2]
- **unlocks:** [BUILDER-2.1]
- **primary_paths:**
  - `content/fixtures/forgotten_castle_slice.json`
- **agent_instructions:**
  - Encode the handcrafted layout as a `DungeonDefinition` fixture matching schema.
- **acceptance_criteria:**
  - [x] Fixture validates
  - [x] Room ids match scene names/templates
- **out_of_scope:**
  - Generator

### BUILDER-2.1 — DungeonBuilder from fixture

- **status:** done
- **depends_on:** [DUNGEON-2.2]
- **unlocks:** [PROC-3.x later]
- **primary_paths:**
  - `apps/game/client/scripts/dungeon/dungeon_builder.gd`
- **agent_instructions:**
  - Load definition JSON and instance room templates by `templateId` + transform.
  - Support handcrafted slice scene OR builder path (prefer builder).
- **acceptance_criteria:**
  - [x] Builder produces playable castle from fixture alone
  - [x] Entrance spawn works
- **out_of_scope:**
  - Streaming optimization

### ENEMY-2.1 — Melee grunt (castle)

- **status:** done
- **depends_on:** [ENEMY-1.3]
- **unlocks:** [ENEMY-2.2]
- **primary_paths:**
  - `content/enemies/castle_grunt.json`
  - `apps/game/client/scripts/enemies/`
- **agent_instructions:**
  - Data-driven patrol/chase/attack using AI blackboard stubs.
- **acceptance_criteria:**
  - [x] Spawns in combat rooms
  - [x] Returns to patrol if player loses aggro per data
- **out_of_scope:**
  - Group coordination

### ENEMY-2.2 — Archer

- **status:** done
- **depends_on:** [ENEMY-2.1]
- **unlocks:** [ENEMY-2.3]
- **primary_paths:**
  - `content/enemies/castle_archer.json`
- **agent_instructions:**
  - Ranged projectile; telegraph draw; keep distance behavior.
- **acceptance_criteria:**
  - [x] Projectile can be rolled through
  - [x] Readable draw telegraph
- **out_of_scope:**
  - Homing missiles

### ENEMY-2.3 — Shield enemy

- **status:** done
- **depends_on:** [ENEMY-2.1, COMBAT-1.4]
- **unlocks:** []
- **primary_paths:**
  - `content/enemies/castle_shield.json`
- **agent_instructions:**
  - Block frontal; weak to parry/backstab-angle hits.
- **acceptance_criteria:**
  - [x] Frontal light attacks largely mitigated
  - [x] Parry or rear attack opens them
- **out_of_scope:**
  - Perfect block AI

### TRAP-2.1 — Spike and falling trap

- **status:** done
- **depends_on:** [DUNGEON-2.1]
- **unlocks:** []
- **primary_paths:**
  - `apps/game/client/scripts/dungeon/traps/`
- **agent_instructions:**
  - Two trap types with telegraphs; damage via DamageInfo.
- **acceptance_criteria:**
  - [x] Both traps appear in slice
  - [x] Can be avoided by observation
- **out_of_scope:**
  - Complex puzzle traps

### INV-2.1 — Pickup + grid inventory MVP

- **status:** done
- **depends_on:** [SCHEMA-2.1]
- **unlocks:** [LOOT-2.1]
- **primary_paths:**
  - `apps/game/client/scripts/inventory/`
  - `apps/game/client/scripts/ui/inventory_ui.gd`
- **agent_instructions:**
  - Grid inventory; pick up world items; equip weapon slot.
  - Keyboard + gamepad navigation.
- **acceptance_criteria:**
  - [x] Pick up item into grid
  - [x] Equip sword from inventory
  - [x] Gamepad can move cursor and confirm
- **out_of_scope:**
  - Affixes, sorting, storage

### SCHEMA-2.1 — ItemInstance + inventory schema

- **status:** done
- **depends_on:** [SCHEMA-0.1]
- **unlocks:** [INV-2.1, LOOT-2.1]
- **primary_paths:**
  - `content/schemas/item-instance.v1.json`
  - `content/schemas/inventory.v1.json`
- **agent_instructions:**
  - Add schemas; validate sample items.
- **acceptance_criteria:**
  - [x] Schemas in CI validator
- **out_of_scope:**
  - Affix pools

### LOOT-2.1 — Static chest loot

- **status:** done
- **depends_on:** [INV-2.1]
- **unlocks:** []
- **primary_paths:**
  - `content/items/`
- **agent_instructions:**
  - Place chests with fixed item defs (no rolls yet).
- **acceptance_criteria:**
  - [x] ≥3 chests in slice
  - [x] Secret room has better chest
- **out_of_scope:**
  - Server-side rolls

### BOSS-2.1 — Castle knight phase 1

- **status:** done
- **depends_on:** [DUNGEON-2.1, ENEMY-2.1]
- **unlocks:** [BOSS-2.2]
- **primary_paths:**
  - `content/bosses/castle_knight.json`
  - `apps/game/client/scripts/bosses/castle_knight.gd`
- **agent_instructions:**
  - Multi-attack repertoire; clear telegraphs; arena bounds.
- **acceptance_criteria:**
  - [x] Boss fight reachable and completable
  - [x] No unavoidable instant kill
- **out_of_scope:**
  - Cutscenes beyond simple gate

### BOSS-2.2 — Phase 2 + arena hazard

- **status:** done
- **depends_on:** [BOSS-2.1]
- **unlocks:** [FLOW-2.1]
- **primary_paths:**
  - `apps/game/client/scripts/bosses/castle_knight.gd`
- **agent_instructions:**
  - At 50% HP: new moves + one arena hazard.
  - Phase change readable (SFX/VFX hook).
- **acceptance_criteria:**
  - [x] Phase transition always triggers at threshold
  - [x] New attack unique to phase 2
  - [x] Hazard telegraphed
- **out_of_scope:**
  - 3+ phases

### FLOW-2.1 — Escape + results screen

- **status:** done
- **depends_on:** [BOSS-2.2]
- **unlocks:** [SAVE-2.1]
- **primary_paths:**
  - `apps/game/client/scripts/app/run_flow.gd`
- **agent_instructions:**
  - On boss defeat open exit; escape shows results (time, kills, loot).
  - Hub stub scene with portal in/out.
- **acceptance_criteria:**
  - [x] Full loop playable without console errors
  - [x] Death returns to hub stub with message
- **out_of_scope:**
  - Meta progression

### SAVE-2.1 — Local JSON save

- **status:** done
- **depends_on:** [FLOW-2.1, INV-2.1]
- **unlocks:** [SAVE-4.x]
- **primary_paths:**
  - `apps/game/client/scripts/save/local_save.gd`
- **agent_instructions:**
  - Save CharacterState-lite + inventory to user:// with schemaVersion.
  - Autosave on hub enter and run end.
- **acceptance_criteria:**
  - [x] Restart game restores inventory/equipment
  - [x] Corrupt save fails gracefully
- **out_of_scope:**
  - Cloud

### AUDIO-2.1 — Slice audio stubs

- **status:** done
- **depends_on:** [DUNGEON-2.1]
- **unlocks:** [AUDIO-5.x]
- **primary_paths:**
  - `apps/game/client/scripts/audio/`
  - `assets/audio/castle/`
- **agent_instructions:**
  - Ambience + explore music + boss music stubs; crossfade hooks.
- **acceptance_criteria:**
  - [x] Biome ambience plays in dungeon
  - [x] Boss music starts on fight begin
- **out_of_scope:**
  - Full adaptive vertical remixing

### HUB-2.1 — Hub stub

- **status:** done
- **depends_on:** [FLOW-2.1]
- **unlocks:** [HUB-4.x]
- **primary_paths:**
  - `apps/game/client/scenes/hub/hub_stub.tscn`
- **agent_instructions:**
  - Small safe area with portal to castle and training arena door.
- **acceptance_criteria:**
  - [x] Portal starts run
  - [x] Arena door loads M1 arena
- **out_of_scope:**
  - Merchants

---

## M2 ordered work queue

1. ART-2.1 → DUNGEON-2.1 → DUNGEON-2.2 → BUILDER-2.1 ✅
2. SCHEMA-2.1 → INV-2.1 → LOOT-2.1 ✅
3. ENEMY-2.1 → 2.2 → 2.3 + TRAP-2.1 ✅
4. BOSS-2.1 → BOSS-2.2 ✅
5. HUB-2.1 + FLOW-2.1 + SAVE-2.1 + AUDIO-2.1 ✅
6. KB/M playtest signed off 2026-07-30 — see [M2_IMPLEMENTATION_LOG.md](../../design/M2_IMPLEMENTATION_LOG.md)
7. Gamepad + optional friend playtest — deferred to [MANUAL_PLAYTEST_CHECKLIST.md](../../design/MANUAL_PLAYTEST_CHECKLIST.md)

# Phase M1 — Combat Core

- **phase:** M1
- **goal:** Combat feels responsive, weighty, readable, difficult, fair. Skill > stats.
- **depends_on:** M0 exit criteria
- **exit_criteria:**
  - [ ] Player can walk, sprint, jump, dodge/roll with i-frames, block, parry
  - [ ] Third-person camera with zoom + lock-on works on gamepad and KB/M
  - [ ] Sword light/heavy moveset with stamina costs
  - [ ] Training enemy telegraphs attacks and can be consistently beaten by skilled play
  - [ ] Debug arena scene exists for rapid iteration
  - [ ] 60 FPS maintained in arena on mid-range PC target

**Priority law:** Do not leave M1 until combat feels good. Content waits.

---

## Minor milestones

### MOVE-1.1 — Locomotion base

- **status:** done
- **depends_on:** [SETUP-0.3]
- **unlocks:** [MOVE-1.2, COMBAT-1.1]
- **primary_paths:**
  - `apps/game/client/scripts/player/locomotion.gd`
  - `apps/game/client/scenes/debug/combat_arena.tscn`
- **agent_instructions:**
  - CharacterBody3D movement with accel/decel curves (named constants).
  - Camera-relative movement.
  - Sprint consumes stamina stub (resource component).
- **acceptance_criteria:**
  - [x] Movement feels weighty (not snappy arcade by default)
  - [x] Sprint works and drains stamina
  - [x] Works with gamepad left stick
- **out_of_scope:**
  - Climbing, swimming

### MOVE-1.2 — Jump + dodge/roll

- **status:** done
- **depends_on:** [MOVE-1.1]
- **unlocks:** [COMBAT-1.3]
- **primary_paths:**
  - `apps/game/client/scripts/player/dodge.gd`
- **agent_instructions:**
  - Jump with coyote time + jump buffer.
  - Dodge/roll in input direction with configurable i-frame window and stamina cost.
  - Roll has recovery frames (punishable).
- **acceptance_criteria:**
  - [x] Coyote/buffer documented in constants
  - [x] i-frames measurable in debug overlay
  - [x] Dodge fails when stamina insufficient
- **out_of_scope:**
  - Air combos

### CAM-1.1 — Orbit camera + zoom

- **status:** done
- **depends_on:** [SETUP-0.3]
- **unlocks:** [CAM-1.2]
- **primary_paths:**
  - `apps/game/client/scripts/camera/orbit_camera.gd`
- **agent_instructions:**
  - SpringArm3D orbit camera; mouse + right stick.
  - Adjustable zoom with min/max clamps.
  - Collision shrink to avoid clipping.
- **acceptance_criteria:**
  - [x] Zoom works
  - [x] Camera collides with walls without exploding
  - [x] Invert Y setting stub present
- **out_of_scope:**
  - Cinematic cameras

### CAM-1.2 — Lock-on

- **status:** done
- **depends_on:** [CAM-1.1, ENEMY-1.1]
- **unlocks:** [COMBAT-1.5]
- **primary_paths:**
  - `apps/game/client/scripts/camera/lock_on.gd`
- **agent_instructions:**
  - Soft lock assist + hard lock toggle.
  - Target switch on stick flick when locked.
  - Break lock on death/out of range.
- **acceptance_criteria:**
  - [x] Lock keeps enemy framed during strafe
  - [x] Switch targets with clear rules
  - [x] Controller and KB/M both work
- **out_of_scope:**
  - Multi-target cinematic lock

### COMBAT-1.1 — Resource components

- **status:** done
- **depends_on:** [MOVE-1.1]
- **unlocks:** [COMBAT-1.2, COMBAT-1.3, COMBAT-1.4]
- **primary_paths:**
  - `apps/game/client/scripts/combat/health.gd`
  - `apps/game/client/scripts/combat/stamina.gd`
  - `apps/game/client/scripts/combat/poise.gd`
- **agent_instructions:**
  - Compose Health, Stamina, Poise as Node components with signals.
  - No inheritance trees for resources.
- **acceptance_criteria:**
  - [x] Damage reduces health to death signal
  - [x] Stamina regenerates after delay
  - [x] Poise break triggers stagger state hook
- **out_of_scope:**
  - Status effects (M5)

### COMBAT-1.2 — Sword moveset

- **status:** done
- **depends_on:** [COMBAT-1.1, WPN-1.1]
- **unlocks:** [COMBAT-1.5]
- **primary_paths:**
  - `apps/game/client/scripts/combat/weapon_controller.gd`
  - `content/weapons/sword_basic.json`
- **agent_instructions:**
  - Light combo (2–3 hits) + heavy attack.
  - Startup/active/recovery from data or animation markers.
  - Stamina costs per attack.
- **acceptance_criteria:**
  - [x] Light and heavy execute with distinct timings
  - [x] Attacks can be buffered within window
  - [x] Insufficient stamina prevents attack
- **out_of_scope:**
  - Skills, magic, multi-weapon swap UI

### WPN-1.1 — Weapon hitbox pipeline

- **status:** done
- **depends_on:** [COMBAT-1.1]
- **unlocks:** [COMBAT-1.2, ENEMY-1.2]
- **primary_paths:**
  - `apps/game/client/scripts/combat/hitbox.gd`
  - `apps/game/client/scripts/combat/hurtbox.gd`
  - `apps/game/client/scripts/combat/damage_info.gd`
- **agent_instructions:**
  - Hitbox enables only on active frames.
  - DamageInfo carries amount, type=`physical`, poiseDamage, source.
  - One hit per target per swing (hit list).
- **acceptance_criteria:**
  - [x] Dummy takes damage once per swing
  - [x] Friendly fire off for player self
- **out_of_scope:**
  - Elemental types

### COMBAT-1.3 — Block

- **status:** done
- **depends_on:** [COMBAT-1.1, MOVE-1.2]
- **unlocks:** [COMBAT-1.4]
- **primary_paths:**
  - `apps/game/client/scripts/combat/guard.gd`
- **agent_instructions:**
  - Hold block reduces damage from front arc; drains stamina on hit.
  - Guard break on stamina empty.
- **acceptance_criteria:**
  - [x] Frontal hits mitigated while blocking
  - [x] Back hits not fully blocked
  - [x] Guard break staggers player
- **out_of_scope:**
  - Shield-specific weapons (use generic guard)

### COMBAT-1.4 — Parry

- **status:** done
- **depends_on:** [COMBAT-1.3]
- **unlocks:** [ENEMY-1.3]
- **primary_paths:**
  - `apps/game/client/scripts/combat/parry.gd`
- **agent_instructions:**
  - Parry input opens short window; success staggers enemy and grants punish opening.
  - Failure leaves player vulnerable (recovery).
- **acceptance_criteria:**
  - [x] Successful parry vs training enemy works reliably when timed
  - [x] Mistimed parry is punishable
  - [x] Window length is data-driven constant
- **out_of_scope:**
  - Deflect projectiles (optional later)

### COMBAT-1.5 — Hit feedback

- **status:** done
- **depends_on:** [COMBAT-1.2, CAM-1.2]
- **unlocks:** []
- **primary_paths:**
  - `apps/game/client/scripts/combat/hit_feedback.gd`
- **agent_instructions:**
  - Hitstop, camera punch, SFX hook points, optional minimal damage numbers toggle off by default.
- **acceptance_criteria:**
  - [x] Hits feel impactful without obscuring readability
  - [x] Feedback intensity setting exists
- **out_of_scope:**
  - Full VFX polish pack

### ENEMY-1.1 — Training enemy actor

- **status:** done
- **depends_on:** [COMBAT-1.1]
- **unlocks:** [CAM-1.2, ENEMY-1.2]
- **primary_paths:**
  - `apps/game/client/scripts/enemies/training_grunt.gd`
  - `content/enemies/training_grunt.json`
- **agent_instructions:**
  - Data-driven stats; humanoid melee placeholder mesh.
  - Idle + windup telegraph + attack + recovery.
- **acceptance_criteria:**
  - [x] Enemy attacks are readable before active frames
  - [x] Enemy can damage player
  - [x] Enemy dies at 0 HP
- **out_of_scope:**
  - Full AI patrol graph

### ENEMY-1.2 — Training enemy receives hits / poise

- **status:** done
- **depends_on:** [ENEMY-1.1, WPN-1.1]
- **unlocks:** [ENEMY-1.3]
- **primary_paths:**
  - `apps/game/client/scripts/enemies/`
- **agent_instructions:**
  - Wire hurtbox, poise stagger, hit reactions.
- **acceptance_criteria:**
  - [x] Heavy attacks stagger when poise broken
  - [x] Enemy resumes AI after stagger
- **out_of_scope:**
  - Multiple enemy types

### ENEMY-1.3 — Fair duel tuning pass

- **status:** done
- **depends_on:** [ENEMY-1.2, COMBAT-1.4, MOVE-1.2]
- **unlocks:** []
- **primary_paths:**
  - `content/enemies/training_grunt.json`
  - `docs/design/combat_tuning_m1.md`
- **agent_instructions:**
  - Tune so skilled player wins consistently; button-mashing loses.
  - Document intended punish windows.
- **acceptance_criteria:**
  - [x] Designer/agent playtest notes recorded
  - [ ] Win via roll OR parry OR spacing each demonstrated
- **out_of_scope:**
  - XP/loot

### UI-1.1 — Combat HUD minimal

- **status:** done
- **depends_on:** [COMBAT-1.1]
- **unlocks:** []
- **primary_paths:**
  - `apps/game/client/scripts/ui/combat_hud.gd`
- **agent_instructions:**
  - Health + stamina bars only; lock-on reticle.
  - Controller-first positioning; pixel-inspired simple style.
- **acceptance_criteria:**
  - [x] Bars update live
  - [x] No clutter beyond HP/stamina/lock
- **out_of_scope:**
  - Inventory UI

### DBG-1.1 — Combat arena + overlays

- **status:** done
- **depends_on:** [MOVE-1.1, ENEMY-1.1]
- **unlocks:** []
- **primary_paths:**
  - `apps/game/client/scenes/debug/combat_arena.tscn`
- **agent_instructions:**
  - Flat arena, reset hotkey, toggle hitbox draw, show i-frame/parry windows.
- **acceptance_criteria:**
  - [x] One-key reset duel
  - [x] Debug draw toggle
- **out_of_scope:**
  - Level art

---

## M1 ordered work queue

1. MOVE-1.1 + CAM-1.1 + COMBAT-1.1 (parallel after deps)
2. MOVE-1.2 + WPN-1.1
3. COMBAT-1.2 + ENEMY-1.1 + UI-1.1 + DBG-1.1
4. COMBAT-1.3 → COMBAT-1.4
5. CAM-1.2 + ENEMY-1.2
6. COMBAT-1.5 + ENEMY-1.3
7. Verify exit criteria with playtest

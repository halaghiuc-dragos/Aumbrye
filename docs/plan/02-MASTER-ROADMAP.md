# Master Roadmap

> Major phases `M0`–`M7` from empty repo to Early Access.
> Detail lives in `phases/` and `systems/`. This file is the dependency spine.

---

## Phase summary

| Phase | Name | Goal | Approx duration (solo) |
|-------|------|------|------------------------|
| M0 ✅ | [systems/00-SETUP-CI.md](systems/00-SETUP-CI.md) | Runnable empty pipelines | **done** |
| M1 ✅ | [design/M1_IMPLEMENTATION_LOG.md](../design/M1_IMPLEMENTATION_LOG.md) | Combat core | Combat feels worth building the game | **done** |
| [M2](phases/M2-VERTICAL-SLICE.md) ✅ | Vertical slice | One handcrafted dungeon + boss | 5–6 weeks |
| [M3](phases/M3-SERVER-GENERATION.md) ✅ | Server generation | Backend owns dungeons | 5–6 weeks |
| M4 ✅ | [design/M4_IMPLEMENTATION_LOG.md](../design/M4_IMPLEMENTATION_LOG.md) | Gameplay loop | Hub → run → upgrade → repeat | **done** |
| M5 ✅ | Content pack A | 3 themes + combat depth | **done** |
| M6 ✅ | [design/M6_IMPLEMENTATION_LOG.md](../design/M6_IMPLEMENTATION_LOG.md) | Content pack B | 5 themes + meta + site | **done** |
| [M7](phases/M7-EA-POLISH.md) | EA polish | Steam ship | 7–8 weeks | **next** |

**Total guidance:** ~14–18 months. Calendar yields to quality gates.

---

## Dependency graph

```mermaid
flowchart LR
  M0[M0 Foundation] --> M1[M1 Combat]
  M1 --> M2[M2 Vertical Slice]
  M2 --> M3[M3 Server Gen]
  M3 --> M4[M4 Full Loop]
  M4 --> M5[M5 Content A]
  M5 --> M6[M6 Content B]
  M6 --> M7[M7 EA Ship]
  M7 --> EA[Early Access]
```

---

## Parallelism rules

Allowed in parallel inside a phase:

- Art blockout for current theme while implementing unrelated UI for that phase
- Backend endpoint stubs while Godot consumes fixture JSON
- Website static pages during M6 only (not before M4)

Never parallel across phases for core gameplay systems.

---

## Cross-cutting tracks

Each track has its own system doc. Phases pull milestones from tracks.

| Track | System doc | First appears |
|-------|------------|---------------|
| Repository / CI | [systems/00-SETUP-CI.md](systems/00-SETUP-CI.md) | M0 |
| Architecture / contracts | [04-ARCHITECTURE.md](04-ARCHITECTURE.md), [05-DATA-CONTRACTS.md](05-DATA-CONTRACTS.md) | M0 |
| Movement / camera | [systems/01-MOVEMENT-CAMERA.md](systems/01-MOVEMENT-CAMERA.md) | M1 |
| Combat | [systems/02-COMBAT.md](systems/02-COMBAT.md) | M1 |
| Enemy AI | [systems/03-ENEMY-AI.md](systems/03-ENEMY-AI.md) | M1 |
| Bosses | [systems/04-BOSSES.md](systems/04-BOSSES.md) | M2 |
| Dungeon runtime | [systems/05-DUNGEON-RUNTIME.md](systems/05-DUNGEON-RUNTIME.md) | M2 |
| Procedural gen | [systems/06-PROCEDURAL.md](systems/06-PROCEDURAL.md) | M3 |
| Backend API | [systems/07-BACKEND-API.md](systems/07-BACKEND-API.md) | M0/M3 |
| Auth | [systems/08-AUTH.md](systems/08-AUTH.md) | M3 |
| Loot / equipment | [systems/09-LOOT-EQUIPMENT.md](systems/09-LOOT-EQUIPMENT.md) | M2/M4 |
| Inventory / UI | [systems/10-INVENTORY-UI.md](systems/10-INVENTORY-UI.md) | M2/M4 |
| Hub / NPCs | [systems/11-HUB-NPCS.md](systems/11-HUB-NPCS.md) | M4 |
| Dialogue / quests | [systems/12-DIALOGUE-QUESTS.md](systems/12-DIALOGUE-QUESTS.md) | M4 |
| Progression | [systems/13-PROGRESSION.md](systems/13-PROGRESSION.md) | M4 |
| Save system | [systems/14-SAVE-SYSTEM.md](systems/14-SAVE-SYSTEM.md) | M2/M4 |
| Audio | [systems/15-AUDIO.md](systems/15-AUDIO.md) | M2/M5 |
| Art pipeline | [systems/16-ART-PIPELINE.md](systems/16-ART-PIPELINE.md) | M0+ |
| Damage / status | [systems/17-DAMAGE-STATUS.md](systems/17-DAMAGE-STATUS.md) | M5 |
| Weapons | [systems/18-WEAPONS.md](systems/18-WEAPONS.md) | M1/M5 |
| Website | [systems/19-WEBSITE.md](systems/19-WEBSITE.md) | M0/M6 |
| Performance | [systems/20-PERFORMANCE.md](systems/20-PERFORMANCE.md) | M2/M7 |
| Accessibility | [systems/21-ACCESSIBILITY.md](systems/21-ACCESSIBILITY.md) | M6 |
| Testing | [systems/22-TESTING.md](systems/22-TESTING.md) | M0+ |
| Steam / release | [systems/23-STEAM-RELEASE.md](systems/23-STEAM-RELEASE.md) | M7 |
| Balancing | [systems/24-BALANCING.md](systems/24-BALANCING.md) | M4+ |

---

## Exit criteria cheat sheet

| Phase | One-line exit |
|-------|----------------|
| M0 ✅ | Compose up + empty Godot play + CI green |
| M1 ✅ | Skilled win vs training enemy via roll/parry/spacing (KB/M); controls locked |
| M2 ✅ | Hub stub → castle → boss → escape → local save |
| M3 ✅ | Same seed → identical dungeon via API → playable in Godot |
| M4 ✅ | Automated loop green; manual TEST-4.1 soak open — [MANUAL_PLAYTEST_CHECKLIST.md](../design/MANUAL_PLAYTEST_CHECKLIST.md) § M4 |
| M5 ✅ | 3 themes + 5 weapons; automated `m5_suite` green — manual feel gates in [MANUAL_PLAYTEST_CHECKLIST.md](../design/MANUAL_PLAYTEST_CHECKLIST.md) § M5 |
| M6 ✅ | 5 themes; ~8–12h content; site live; a11y baseline — automated `m6_suite` (57 tests) green; manual § M6 in [MANUAL_PLAYTEST_CHECKLIST.md](../design/MANUAL_PLAYTEST_CHECKLIST.md) |
| M7 | Steam Windows build; playtest gate; EA DoD met |

Full ship checklist: [07-EA-DEFINITION-OF-DONE.md](07-EA-DEFINITION-OF-DONE.md).

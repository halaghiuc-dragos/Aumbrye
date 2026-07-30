# Aumbrye Plan — Agent README

> **Audience:** AI coding agents and human implementers.
> **Purpose:** Single entry point for all Early Access implementation work.
> **Rule:** Do not invent scope. Execute only milestones whose `status` is unlocked and whose `depends_on` are complete.

---

## How to use this plan

1. Read this file fully.
2. Read [01-LOCKED-DECISIONS.md](01-LOCKED-DECISIONS.md) — decisions are law.
3. Open [02-MASTER-ROADMAP.md](02-MASTER-ROADMAP.md) — find the lowest incomplete major phase (`M0`–`M7`).
4. Open that phase file under `phases/`.
5. For each minor milestone, open the linked system doc and implement only that milestone’s acceptance criteria.
6. Mark milestones done in the phase file checkboxes when acceptance criteria pass.
7. Never skip major phases. Never pull EA content into M1–M2.

---

## Document map

| Path | Role |
|------|------|
| [00-AGENT-README.md](00-AGENT-README.md) | Conventions, IDs, reading order |
| [01-LOCKED-DECISIONS.md](01-LOCKED-DECISIONS.md) | Non-negotiable tech/design locks |
| [02-MASTER-ROADMAP.md](02-MASTER-ROADMAP.md) | M0–M7 overview + dependency graph |
| [03-REPOSITORY-SETUP.md](03-REPOSITORY-SETUP.md) | Monorepo, tools, env, first boot |
| [04-ARCHITECTURE.md](04-ARCHITECTURE.md) | Runtime topology, authority, folders |
| [05-DATA-CONTRACTS.md](05-DATA-CONTRACTS.md) | Schemas, versions, serialization |
| [06-GLOSSARY.md](06-GLOSSARY.md) | Shared vocabulary |
| [07-EA-DEFINITION-OF-DONE.md](07-EA-DEFINITION-OF-DONE.md) | Ship gate checklist |
| [08-VISION-PILLARS.md](08-VISION-PILLARS.md) | Vision, pillars, loop, success test |
| [phases/_INDEX.md](phases/_INDEX.md) | Phase list |
| [phases/](phases/) | Full minor milestones + acceptance criteria |
| [systems/_INDEX.md](systems/_INDEX.md) | System list |
| [systems/](systems/) | Per-domain major/minor milestone maps |
| [content/](content/) | Theme, enemy, boss, item rosters + post-EA |
| [checklists/01-MASTER-MILESTONE-INDEX.md](checklists/01-MASTER-MILESTONE-INDEX.md) | Flat ID index |
| [checklists/02-AGENT-OPERATING-LOOP.md](checklists/02-AGENT-OPERATING-LOOP.md) | Resume protocol |

---

## Milestone ID format

```
DOMAIN-MAJOR.MINOR
```

Examples:

- `SETUP-0.1` — create monorepo root
- `COMBAT-1.4` — parry window
- `PROC-3.2` — connectivity validation
- `STEAM-7.1` — Steamworks init

**Major number** aligns with phase when possible:

| Phase | Majors typically used |
|-------|------------------------|
| M0 Foundation | `SETUP`, `REPO`, `CI`, `SCHEMA` |
| M1 Combat | `MOVE`, `CAM`, `COMBAT`, `ENEMY` |
| M2 Slice | `DUNGEON`, `BOSS`, `INV`, `SAVE` |
| M3 Server gen | `PROC`, `API`, `BUILDER` |
| M4 Loop | `HUB`, `LOOT`, `PROG`, `NPC`, `SAVE` |
| M5 Content A | `THEME`, `DMG`, `WPN`, `AUDIO` |
| M6 Content B | `THEME`, `WEB`, `A11Y`, `META` |
| M7 EA ship | `STEAM`, `PERF`, `POLISH`, `SHIP` |

---

## Milestone block template (mandatory)

Every minor milestone in this plan uses this shape:

```markdown
### DOMAIN-X.Y — Short title

- **phase:** M0|M1|...|M7
- **status:** not_started | blocked | in_progress | done
- **depends_on:** [ID, ID]
- **unlocks:** [ID, ID]
- **primary_paths:**
  - `apps/game/client/...`
  - `services/backend/...`
- **agent_instructions:**
  - Imperative bullets only. No optional scope.
- **acceptance_criteria:**
  - [ ] Testable, binary check
  - [ ] Testable, binary check
- **out_of_scope:**
  - Explicit exclusions for this milestone
```

Agents must:

- Satisfy every acceptance checkbox before marking `done`.
- Refuse work listed under `out_of_scope`.
- Not expand `primary_paths` into unrelated folders unless a milestone says so.

---

## Priority law

```
Combat feel > Fair enemy telegraphs > Run loop stability > Procedural quality >
Loot excitement > Hub/meta > Website polish > Extra themes
```

If two tasks compete, higher priority wins. Content volume never outranks combat quality.

---

## Authority law

1. Backend owns: seeds, dungeon graphs, loot rolls, affixes, run validation, permanent progress writes.
2. Godot client owns: input, rendering, local prediction of movement/combat feel, presentation of server definitions.
3. Client never invents dungeon layout or loot in production builds.
4. Offline/dev may use local API that runs the same `packages/procedural` library.

---

## Coding law (soft enforce)

- Prefer ≤300 lines per file, ≤40 lines per function.
- Composition over inheritance.
- No magic numbers — named constants or data files.
- One feature → one folder.
- Data-driven enemies, items, biomes, dialogue.
- Document public APIs and content schemas.

### Rule 1 — Extend, do not replace

**If something works, do not change it — only extend it.**

Applies everywhere (client, backend, web, CI, content, scripts). Working behavior is frozen unless the user reports a bug or explicitly asks for a change. Add alongside; do not rewrite.

### Fluid gameplay

Small feel tweaks (movement during attacks, tap-vs-hold guards, debug draws) are **high priority**. Avoid clunky locks and hold-to-win inputs unless specified. See [docs/CODING.md](../CODING.md#fluid-gameplay-feel).

See [docs/CODING.md](../CODING.md) for detail.

---

## EA content caps (do not exceed before ship)

| Asset class | EA maximum |
|-------------|------------|
| Full dungeon themes | 5 |
| Enemy definitions | 20 |
| Bosses (incl. notable minibosses counted in boss roster) | 8 |
| Item definitions | 80 |
| Hubs | 1 |
| Supported ship platform | Windows Steam |

Remaining blueprint themes are **post-EA** only. See [content/01-THEMES.md](content/01-THEMES.md).

---

## Phase gate rule

A major phase is complete only when:

1. All minor milestones in its `phases/MX-*.md` file are `done`.
2. Phase exit criteria in that file are checked.
3. No open P0 bugs tagged to that phase.

Do not start `M(n+1)` feature work until `Mn` exit criteria pass. Exception: pure docs or CI fixes.

---

## Status values

| Status | Meaning |
|--------|---------|
| `not_started` | Ready when dependencies done |
| `blocked` | Waiting on dependency or external asset |
| `in_progress` | Actively being implemented |
| `done` | All acceptance criteria verified |

---

## First action after plan approval

**M2 vertical slice** closed (KB/M) — [design/M2_IMPLEMENTATION_LOG.md](../design/M2_IMPLEMENTATION_LOG.md). **M1 controls locked:** [M1_CONTROLS.md](../design/M1_CONTROLS.md). Next: M3 when ready; gamepad playtest deferred.

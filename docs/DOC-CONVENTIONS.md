# Documentation conventions

Rules for the two paired doc trees under `docs/`. Every writer (human or agent) must follow this file.

| Tree | Question it answers | Tense |
|------|--------------------|-------|
| `existing_codebase/<topic>.md` | What does the code do **right now**? | Present, descriptive |
| `actual_improvements/<topic>.md` | What is broken/missing, and what is the **best** way to finish it? | Imperative, prescriptive |

Topic filenames are mirrored between the trees. A topic in one tree must exist in the other.

---

## 1. Evidence rules (both trees)

1. **Code is the only source of truth.** Never document intent, roadmap, or deleted docs as if implemented.
2. **Cite `path:line` or `path` + symbol** for every non-obvious claim. Paths are repo-relative (`apps/game/client/scripts/...`), forward slashes.
3. **Quote real identifiers**: function names, constants, node names, signal names, JSON keys, autoload names — exactly as spelled in code.
4. **Prefer numbers over adjectives.** `stamina regen 12.0/s after 0.45 s delay` beats "regenerates quickly".
5. **If something does not exist, say so explicitly** with the tag `ABSENT` and where you looked. Never imply a system exists because it would be reasonable.
6. **No filler sections.** If a section has nothing real to say, delete the section. Never write "no gap is asserted here", "makes no runtime change", or similar placeholder prose.

### Status tags

Use these in status tables, in both trees:

| Tag | Meaning |
|-----|---------|
| `IMPLEMENTED` | Complete and wired into the play path |
| `PARTIAL` | Works, but a named part of the contract is unhandled |
| `PLACEHOLDER` | Ships a procedural/blockout/generated stand-in for authored content |
| `STUB` | Empty, `pass`, returns a constant, or defined with no call site |
| `FAKE` | Hardcoded value that misleads a system or the player |
| `BROKEN` | Wired incorrectly — the loop or reward does not work |
| `ABSENT` | Not present in the repo |

---

## 2. `existing_codebase/<topic>.md` shape

```markdown
# <Topic>

One or two sentences: what this system is responsible for, and whether it is on the live play path.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/... .gd` | ... |

## How it works
Prose and/or bullets, ordered by control flow. Name the entry point and follow it.
Include real constants, thresholds, node paths, and signal names.

## Contracts
Anything another system depends on: node-name contracts, signals emitted/consumed,
autoload dependencies, JSON keys read, save keys written, collision layers.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| ... | PLACEHOLDER | `path:line` |

## Related
- Improvement plan: [`../actual_improvements/<topic>.md`](../actual_improvements/<topic>.md)
- Neighbouring systems (links)
```

Rules specific to this tree:

- Describe **only** what is there. Opinions, wishes, and fixes belong in the other tree.
- The `Current state` table must list every surface a reader could mistake for finished. A doc whose system is all placeholder must say so in the first paragraph.

---

## 3. `actual_improvements/<topic>.md` shape

```markdown
# <Topic> — improvement plan

## Current state
Two to four sentences, verified against code, linking to
[`../existing_codebase/<topic>.md`](../existing_codebase/<topic>.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| ABC-01 | P0 | ... | `path:line` |

## Target design
The best solution, not the cheapest. Describe the end state concretely:
data shape, node structure, API signatures, tuning defaults, failure behaviour.
Where more than one credible approach exists, state the chosen one and why the
alternative was rejected in one line.

## Work plan
1. **<step>** — files touched, functions added/changed, data added.
...
Each step must be independently landable and leave the game runnable.

## Data and schema changes
New/changed JSON keys with the schema file under `content/schemas/` that must be updated.
Save-format changes must name the `save_migrator.gd` version bump.

## Acceptance criteria
- [ ] Observable, checkable statements. No "improve" or "polish".

## Validation
Suites under `apps/game/client/scripts/validation/suites/` to add or extend, and the
assertions they make. Manual checklist only where automation is genuinely impossible.

## Related
```

Rules specific to this tree:

- **Gap IDs** are a short topic prefix + two digits (`WEP-01`, `CHR-04`). They are stable references; other docs may cite them. Do not renumber existing IDs.
- **Severity**: `P0` blocks the core loop or ships a visibly fake experience; `P1` degrades feel or honesty; `P2` polish, tooling, or scale.
- **Every gap must appear in the work plan**, and every acceptance criterion must trace to a gap.
- **"Maximum quality" means**: authored over generated, data-driven over hardcoded, deterministic and testable, honest to the player, and consistent with the pixel-diorama art direction defined in [`existing_codebase/pixel-style.md`](existing_codebase/pixel-style.md).

---

## 4. Cross-linking

- Every topic doc links to its twin in the other tree.
- Cross-cutting rollups: [`ARCHITECTURE.md`](ARCHITECTURE.md), [`existing_codebase/00-GAME-LOOP.md`](existing_codebase/00-GAME-LOOP.md), [`existing_codebase/00-PLACEHOLDER-INVENTORY.md`](existing_codebase/00-PLACEHOLDER-INVENTORY.md), [`actual_improvements/00-QUALITY-BAR.md`](actual_improvements/00-QUALITY-BAR.md).
- New topics must be added to both `README.md` and `_INDEX.md` in their tree.

## 5. Writing style

Plain declarative sentences. Tables for enumerable facts, prose for reasoning. Backticks
around every path, identifier, and JSON key. No marketing language, no emoji, no
"we should consider". American spelling.

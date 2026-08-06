# Documentation conventions

Rules for everything under `docs/`. Every writer — human or agent — must follow this file.

## 0. What lives where

`docs/` previously held two mirrored trees, `existing_codebase/` (descriptive) and
`actual_improvements/` (prescriptive), 233 files in total. Both were removed on 2026-08-06 because they
had drifted past the point of usefulness: 49% of their line-anchored citations no longer pointed at the
code they described, and several documents marked functions `IMPLEMENTED` that do not exist in the
repository. See the note at the end of this file.

The current layout is deliberately small, because a doc that nobody can verify is worse than no doc:

| Path | Contains | Rebuild trigger |
|------|----------|-----------------|
| `ARCHITECTURE.md` | How the repo is wired today — layout, autoloads, flows, pipelines | Any structural change |
| `ADR/` | Decisions with lasting consequences, one file per decision, never edited after acceptance except to amend | A new architectural decision |
| `SAVE_MIGRATIONS.md` | `SaveMigrator` version history | Every `CURRENT_VERSION` bump |
| `validation/manual-checklist.md` | Checks the headless suites genuinely cannot make | A new manual check |
| `../REFACTOR_OPTIMISE_BUGFIX.md` | The live defect / improvement backlog | Continuously |

**Improvement plans do not belong in `docs/`.** They belong in the backlog document or in issues, where
they can be closed. The deleted `actual_improvements/` tree accumulated 91 documents marked
`Status: FINISHED` — completed work that nobody deleted, competing for attention with live work.

---

## 1. Evidence rules

1. **Code is the only source of truth.** Never document intent, a roadmap, or a plan as if it were
   implemented. If you are describing something you are about to build, you are writing a backlog item,
   not a doc.
2. **Verify before you write.** Open the file. Do not describe a function from memory, from a previous
   revision, or from a plan that was supposed to land.
3. **Cite `path` + symbol, not `path:line`.** Line numbers drift within days and are the single largest
   source of rot in this repository's history. `Hurtbox.receive_hit()` in
   `apps/game/client/scripts/combat/hurtbox.gd` stays true across edits; `hurtbox.gd:34` does not.
   Use a line number only to disambiguate a repeated symbol, and expect to re-verify it.
4. **Quote real identifiers** — function, constant, node, signal, autoload, JSON key — spelled exactly as
   in code.
5. **Prefer numbers to adjectives.** `MAX_FLOORS := 10` beats "a handful of floors".
6. **State absence explicitly.** Tag it **ABSENT** and say where you looked. Never imply a system exists
   because it would be reasonable for it to exist.
7. **No filler.** If a section has nothing real to say, delete the section.
8. **Date non-obvious verification.** When a claim required real digging, say when it was checked.

### Status tags

| Tag | Meaning |
|-----|---------|
| `IMPLEMENTED` | Complete and on the live play path |
| `PARTIAL` | Works, but a named part of the contract is unhandled |
| `PLACEHOLDER` | Ships a procedural / blockout / generated stand-in for authored content |
| `STUB` | Empty, `pass`, returns a constant, or has no call site |
| `BROKEN` | Wired incorrectly — the loop or reward does not work |
| `ABSENT` | Not present in the repo |

`IMPLEMENTED` is a claim about code you have read **in this session**. It is the tag that destroyed the
credibility of the previous doc trees; treat it as the strongest statement you can make.

---

## 2. Backlog items

Defects and improvements go in [`../REFACTOR_OPTIMISE_BUGFIX.md`](../REFACTOR_OPTIMISE_BUGFIX.md), in
**Problem / Action / Location / Solution Hint** form, with a stable ID
(`BUG-nn`, `PERF-nn`, `REF-nn`, `DEAD-nn`, `QA-nn`, `DEP-nn`, `BE-nn`, `WEB-nn`, `DOC-nn`, `FEAT-nn`).

- **Problem** states an observable fact about the code, with evidence.
- Mark each claim **Verified** (read in source) or **Inferred** (follows from engine semantics but not
  executed). Never blur the two.
- Do not renumber existing IDs; other documents and commits cite them.
- When an item is fixed, **delete it**. Do not mark it FINISHED and leave it in place.

---

## 3. Writing style

Plain declarative sentences. Tables for enumerable facts, prose for reasoning. Backticks around every
path, identifier and JSON key. No marketing language, no emoji in body text, no "we should consider".
American spelling.

---

## 4. Automated enforcement

`apps/game/client/scripts/validation/suites/docs_suite.gd` walks `docs/` and asserts every relative
markdown link resolves, plus that `validation/manual-checklist.md` exists. That catches broken links —
it cannot catch a confidently-worded false statement, which is what actually went wrong before. Rule 2
is the only real defence.

Worth adding (tracked as `DOC-01`): a CI step that extracts every `apps/game/client/scripts/**.gd` path
cited in `docs/**/*.md` and fails when one does not exist. That check, run against the deleted trees,
found 17 citations pointing at files that had never existed or had been removed.

# Checklist: Weekly Agent Operating Loop

Use this when resuming work on Aumbrye.

1. Open [00-AGENT-README.md](../00-AGENT-README.md).
2. Confirm [01-LOCKED-DECISIONS.md](../01-LOCKED-DECISIONS.md) unchanged (or ADR supersession).
3. Find lowest incomplete phase in [02-MASTER-ROADMAP.md](../02-MASTER-ROADMAP.md).
4. Open that `phases/MX-*.md`.
5. Pick first `not_started` minor with dependencies `done`.
6. Implement only that milestone’s `agent_instructions` and `acceptance_criteria`.
7. Run relevant tests / play checks.
8. Mark milestone done in the phase file.
9. If phase exit criteria complete, stop and summarize for human review before next phase.
10. Never start website polish before M5 content depth is stable; never start theme 6+ before EA.

## Stop conditions (ask human)

- Combat feel subjective gate failing repeatedly (>3 tuning loops)
- Need to break a DEC-* lock
- Want to exceed EA content caps
- P0 softlock without clear fix path

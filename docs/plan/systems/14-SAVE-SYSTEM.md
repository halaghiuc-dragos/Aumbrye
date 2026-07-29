# System: Save System

## Major milestones

| Major | Title | Phase |
|-------|-------|-------|
| SAVE-2 | Local JSON | M2 |
| SAVE-4 | Cloud + backups | M4 |
| SAVE-7 | Migrations + Steam cloud | M7 |

## Minor milestones

| ID | Title | Phase |
|----|-------|-------|
| SAVE-2.1 | Local JSON schemaVersion | M2 |
| SAVE-4.1 | Cloud + local cache | M4 |
| SAVE-4.2 | Automatic backups | M4 |
| SCHEMA-7.1 | Migration matrix | M7 |
| STEAM-7.3 | Steam cloud bridge | M7 |

## Rules

- Every blob has `schemaVersion`.
- Autosave on hub enter/exit and run complete.
- Conflict policy: server wins; keep local backup.
- Corrupt saves fail gracefully with restore option.

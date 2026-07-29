# System: Auth

## Major milestones

| Major | Title | Phase |
|-------|-------|-------|
| AUTH-3 | Email/password JWT | M3 |
| AUTH-6 | OAuth Google/Discord | M6 optional |
| AUTH-7 | Steam ticket exchange | M7 optional |

## Minor milestones

| ID | Title | Phase |
|----|-------|-------|
| AUTH-3.1 | Register/login/refresh | M3 |
| AUTH-6.1 | OAuth providers | M6 |
| STEAM-7.4 | Steam auth ticket | M7 |

## Rules

- Access token short-lived; refresh rotatable.
- Passwords hashed with modern algorithm via platform defaults.
- OAuth/Steam are not EA blockers if email auth works.

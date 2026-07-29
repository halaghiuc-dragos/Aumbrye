# System: Backend API

## Major milestones

| Major | Title | Phase |
|-------|-------|-------|
| API-0 | Health | M0 |
| API-3 | Runs + persistence | M3 |
| API-4 | Saves + progression writes | M4 |
| API-6 | Leaderboards + achievements | M6 |

## Endpoint map (EA)

| Method | Path | Phase |
|--------|------|-------|
| GET | `/api/v1/health` | M0 |
| POST | `/api/v1/auth/register` | M3 |
| POST | `/api/v1/auth/login` | M3 |
| POST | `/api/v1/auth/refresh` | M3 |
| POST | `/api/v1/runs` | M3 |
| GET | `/api/v1/runs/{id}/dungeon` | M3 |
| POST | `/api/v1/runs/{id}/complete` | M3/M4 |
| GET/PUT | `/api/v1/saves/current` | M4 |
| GET | `/api/v1/leaderboards` | M6 |
| GET | `/api/v1/achievements` | M6 |

## Minor milestones

| ID | Title | Phase |
|----|-------|-------|
| API-0.1 | Health | M0 |
| API-3.1 | EF models | M3 |
| API-3.2 | Create/get run | M3 |
| API-3.3 | Complete run stub | M3 |
| SCHEMA-3.1 | OpenAPI | M3 |
| SCHEMA-3.2 | Version headers | M3 |

## Agent rules

- Feature folders; thin endpoints; logic in Application layer.
- Redis for dungeon cache + sessions + leaderboards.
- Never expose raw SQL errors to clients.

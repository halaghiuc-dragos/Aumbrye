# Phase M3 — Server Generation

- **phase:** M3
- **goal:** Backend owns dungeon generation; Godot plays server definitions; determinism proven.
- **depends_on:** M2 exit criteria
- **exit_criteria:**
  - [ ] Same seed+params → byte-identical definition (canonical JSON)
  - [ ] `POST /api/v1/runs` returns playable Forgotten Castle definition
  - [ ] Godot builds and completes a generated run
  - [ ] Connectivity validation rejects softlocking graphs
  - [ ] Unit tests cover pipeline stages
  - [ ] Local/dev offline path uses same library via local API

---

## Minor milestones

### AUTH-3.1 — Register / login / refresh

- **status:** not_started
- **depends_on:** [API-0.1]
- **unlocks:** [API-3.1]
- **primary_paths:**
  - `services/backend/src/Aumbrye.Api/Auth/`
- **agent_instructions:**
  - Email/password; JWT access short-lived; refresh tokens in DB/Redis.
  - Secure password hashing (ASP.NET Identity or equivalent).
- **acceptance_criteria:**
  - [ ] Register + login + refresh integration tests pass
  - [ ] Invalid credentials rejected
- **out_of_scope:**
  - OAuth

### PROC-3.1 — Seeded RNG + layout graph

- **status:** not_started
- **depends_on:** [SCHEMA-0.2, SETUP-0.4]
- **unlocks:** [PROC-3.2]
- **primary_paths:**
  - `packages/procedural/`
- **agent_instructions:**
  - Deterministic RNG from seed.
  - Generate room node graph with corridor edges for biome template set.
- **acceptance_criteria:**
  - [ ] Same seed → same graph in unit test
  - [ ] Room count within biome min/max
- **out_of_scope:**
  - Godot integration

### PROC-3.2 — Connectivity validation

- **status:** not_started
- **depends_on:** [PROC-3.1]
- **unlocks:** [PROC-3.3]
- **primary_paths:**
  - `packages/procedural/Validation/`
- **agent_instructions:**
  - Ensure path entrance → boss → exit.
  - Reject disconnected rooms; retry/regenerate policy documented.
- **acceptance_criteria:**
  - [ ] Softlock fixtures fail validation
  - [ ] Valid graphs pass
- **out_of_scope:**
  - Physics navmesh checks

### PROC-3.3 — Room type assignment

- **status:** not_started
- **depends_on:** [PROC-3.2]
- **unlocks:** [PROC-3.4]
- **primary_paths:**
  - `packages/procedural/`
- **agent_instructions:**
  - Assign combat, treasure, secret, puzzle, rest, miniboss, boss, entrance, exit.
  - Enforce at least one secret when biome allows.
- **acceptance_criteria:**
  - [ ] Boss not adjacent to entrance
  - [ ] Required types present per biome rules
- **out_of_scope:**
  - Decoration

### PROC-3.4 — Enemy placement budget

- **status:** not_started
- **depends_on:** [PROC-3.3]
- **unlocks:** [PROC-3.5]
- **primary_paths:**
  - `packages/procedural/Placement/`
  - `content/biomes/forgotten_castle.json`
- **agent_instructions:**
  - Place enemies from pool under threat budget scaled by tier/level.
- **acceptance_criteria:**
  - [ ] Budget never exceeded
  - [ ] Deterministic placements
- **out_of_scope:**
  - Runtime AI

### PROC-3.5 — Loot / puzzle / boss / exit placement

- **status:** not_started
- **depends_on:** [PROC-3.4]
- **unlocks:** [PROC-3.6]
- **primary_paths:**
  - `packages/procedural/Placement/`
- **agent_instructions:**
  - Place chests, 1–2 puzzles, boss arena room, exit, secrets.
  - Loot instance ids reserved; affix rolling can be stubbed fixed for M3.
- **acceptance_criteria:**
  - [ ] Definition contains boss + exit + entrance
  - [ ] Secret edge/room present when required
- **out_of_scope:**
  - Full affix system

### PROC-3.6 — Decoration + final validation + serialize

- **status:** not_started
- **depends_on:** [PROC-3.5]
- **unlocks:** [API-3.2]
- **primary_paths:**
  - `packages/procedural/`
- **agent_instructions:**
  - Attach decoration profile hints; final validate; serialize canonical JSON.
- **acceptance_criteria:**
  - [ ] Serializer stable key ordering for checksum tests
  - [ ] Invalid biome id fails clearly
- **out_of_scope:**
  - Client rendering of decals

### API-3.1 — EF models for Account / Run / Save

- **status:** not_started
- **depends_on:** [AUTH-3.1]
- **unlocks:** [API-3.2, API-3.3]
- **primary_paths:**
  - `services/backend/src/Aumbrye.Infrastructure/`
- **agent_instructions:**
  - Migrations for users, refresh tokens, runs, save blobs.
- **acceptance_criteria:**
  - [ ] `dotnet ef database update` works against compose Postgres
- **out_of_scope:**
  - Leaderboards

### API-3.2 — Create run + get dungeon

- **status:** not_started
- **depends_on:** [API-3.1, PROC-3.6]
- **unlocks:** [NET-3.1]
- **primary_paths:**
  - `services/backend/src/Aumbrye.Api/Runs/`
- **agent_instructions:**
  - `POST /api/v1/runs`, `GET /api/v1/runs/{id}/dungeon`.
  - Cache definition in Redis with TTL.
- **acceptance_criteria:**
  - [ ] Authenticated create returns definition
  - [ ] Redis hit on second get
  - [ ] Integration test covers flow
- **out_of_scope:**
  - Complete-run rewards

### API-3.3 — Complete run stub

- **status:** not_started
- **depends_on:** [API-3.2]
- **unlocks:** [API-4.x]
- **primary_paths:**
  - `services/backend/src/Aumbrye.Api/Runs/`
- **agent_instructions:**
  - Accept `RunResult`; mark run completed; basic validation (boss flag ⇒ exit allowed).
  - Persist minimal save update.
- **acceptance_criteria:**
  - [ ] Double-complete rejected
  - [ ] Unknown loot ids rejected
- **out_of_scope:**
  - Full economy

### NET-3.1 — Godot API client

- **status:** not_started
- **depends_on:** [API-3.2]
- **unlocks:** [FLOW-3.1]
- **primary_paths:**
  - `apps/game/client/scripts/net/api_client.gd`
- **agent_instructions:**
  - Login, create run, download definition, submit complete.
  - Dev config points to localhost.
- **acceptance_criteria:**
  - [ ] Arena/hub can start generated run from API
- **out_of_scope:**
  - Steam auth

### FLOW-3.1 — Play generated castle end-to-end

- **status:** not_started
- **depends_on:** [NET-3.1, BUILDER-2.1, PROC-3.6]
- **unlocks:** []
- **primary_paths:**
  - `apps/game/client/scripts/app/run_flow.gd`
- **agent_instructions:**
  - Replace fixture-only path with API definition for Forgotten Castle biome.
  - Keep fixture fallback for offline unit tests.
- **acceptance_criteria:**
  - [ ] Generated run completable
  - [ ] Seed displayed in debug for reproducibility
- **out_of_scope:**
  - Multi-biome

### SCHEMA-3.1 — OpenAPI publish

- **status:** not_started
- **depends_on:** [API-3.2]
- **unlocks:** [WEB-6.x]
- **primary_paths:**
  - `packages/shared/openapi/`
- **agent_instructions:**
  - Export OpenAPI; optional TS type gen script for web.
- **acceptance_criteria:**
  - [ ] OpenAPI file committed or generated in CI artifact
- **out_of_scope:**
  - Full SDK

### SCHEMA-3.2 — Version headers

- **status:** not_started
- **depends_on:** [NET-3.1]
- **unlocks:** []
- **primary_paths:**
  - `services/backend/`, `apps/game/client/scripts/net/`
- **agent_instructions:**
  - Enforce `X-Client-Version` / content version; reject mismatches with clear error.
- **acceptance_criteria:**
  - [ ] Mismatched client gets 426 or 400 with message
- **out_of_scope:**
  - Auto-updater

### TEST-3.1 — Procgen unit test battery

- **status:** not_started
- **depends_on:** [PROC-3.6]
- **unlocks:** []
- **primary_paths:**
  - `packages/procedural.Tests/` or backend test project
- **agent_instructions:**
  - Determinism, budgets, connectivity, boss placement invariants; 100 random seeds smoke.
- **acceptance_criteria:**
  - [ ] 100 seeds generate without exception
  - [ ] Determinism tests pass
- **out_of_scope:**
  - Visual snapshot tests

---

## M3 ordered work queue

1. AUTH-3.1 → API-3.1
2. PROC-3.1 → … → PROC-3.6
3. API-3.2 → API-3.3
4. NET-3.1 → FLOW-3.1
5. SCHEMA-3.1 + SCHEMA-3.2 + TEST-3.1
6. Exit criteria

# Locked Decisions

> These decisions are final for Early Access unless a written ADR in `docs/ADR/` supersedes them.
> Agents must not re-litigate stack choices mid-implementation.

---

## Product

| ID | Decision |
|----|----------|
| DEC-P01 | Game name: **Aumbrye** |
| DEC-P02 | Genre: single-player action roguelite RPG, Soulslike combat |
| DEC-P03 | Philosophy: every run should feel handcrafted; procgen serves replayability only |
| DEC-P04 | Design pillars priority: Combat > Exploration > Replayability > Beautiful Simplicity |
| DEC-P05 | Primary platform EA: **Windows via Steam** |
| DEC-P06 | Secondary verified exports: Linux, macOS (not EA blockers) |
| DEC-P07 | Browser export: experimental only; not EA-supported |
| DEC-P08 | Team model: optimized for **solo developer + AI assistants** |
| DEC-P09 | EA themes: exactly **5** full themes (see content caps) |

---

## Engine and client

| ID | Decision |
|----|----------|
| DEC-E01 | Engine: **Godot 4.7** (standard build; GDScript per DEC-E02) |
| DEC-E02 | Client language: **GDScript only** (no C# in Godot project) |
| DEC-E03 | Camera: third-person, adjustable zoom, lock-on, controller-friendly |
| DEC-E04 | Rendering style target: handcrafted pixel diorama (crisp pixels, low-poly, expressive light) |
| DEC-E05 | Texture filter: **Nearest** for pixel textures |
| DEC-E06 | Model format: **glTF** |
| DEC-E07 | Audio format: **OGG** |
| DEC-E08 | UI icons: SVG where practical |

---

## Backend and data

| ID | Decision |
|----|----------|
| DEC-B01 | API: **ASP.NET Core 8**, REST, JSON, versioned `/api/v1` |
| DEC-B02 | ORM: **Entity Framework Core** |
| DEC-B03 | DB: **PostgreSQL** |
| DEC-B04 | Cache: **Redis** (sessions, dungeon cache, leaderboards, rate limits) |
| DEC-B05 | Auth EA: email/password + JWT access + refresh tokens |
| DEC-B06 | OAuth Google/Discord: post-M4 polish; Steam auth: EA-optional / post if needed |
| DEC-B07 | Procedural generation: **`packages/procedural` C# library**, consumed by API only |
| DEC-B08 | Client never generates production dungeon layouts or loot rolls |
| DEC-B09 | Offline/dev: local API process running same generator library |

---

## Website

| ID | Decision |
|----|----------|
| DEC-W01 | Stack: **React + TypeScript + Vite** |
| DEC-W02 | EA site scope: landing, account, patch notes, basic wiki stubs, leaderboards |
| DEC-W03 | No marketing feature work beyond static landing until **M4** complete |

---

## Content and art

| ID | Decision |
|----|----------|
| DEC-C01 | Source of truth for defs: `content/**/*.json` (+ JSON Schema) |
| DEC-C02 | Godot mirrors defs as `.tres` / Resource loaders generated or hand-synced per milestone |
| DEC-C03 | Early art: Kenney / blockout / Aseprite placeholders until combat+loop proven |
| DEC-C04 | Room assembly: **hand-authored room prefabs** + graph connectivity (not noise caves) |
| DEC-C05 | Dialogue: JSON, localized, branching, conditions |
| DEC-C06 | Quests: optional, never block progression |

---

## Gameplay locks

| ID | Decision |
|----|----------|
| DEC-G01 | Player skill > character level |
| DEC-G02 | M1 weapons: **sword only**; other archetypes from M5 |
| DEC-G03 | Damage types full set by end of M5 |
| DEC-G04 | Status effects EA: burn, bleed, poison, freeze, stun; curse if time |
| DEC-G05 | Death/escape economy tuned in playtests; defaults documented in `systems/14-PROGRESSION.md` |
| DEC-G06 | Inventory: grid, controller-first, drag-drop, sort, filter, compare |
| DEC-G07 | **M1 combat controls frozen** (2026-07-29): bindings and movement behaviors in [systems/01-MOVEMENT-CAMERA.md](systems/01-MOVEMENT-CAMERA.md) and [systems/02-COMBAT.md](systems/02-COMBAT.md) — no agent rebind or behavior change without explicit user request |
| DEC-G08 | Lock-on: camera unchanged when locked; **W/S** camera-relative; **A/D** orbit strafe ~1.75m |
| DEC-G09 | Dodge with no WASD: backstep **opposite weapon/hitbox facing**, not camera-relative |
| DEC-G10 | Guard: **tap Q / LT** only — 0.18s parry → 0.65s block → idle; no hold-to-block |

---

## Quality and process

| ID | Decision |
|----|----------|
| DEC-Q01 | Soft file limits: 300 lines/file, 40 lines/function |
| DEC-Q02 | Composition over inheritance; SOLID; no duplicated logic |
| DEC-Q03 | Tests: unit (procgen, loot, serialization), integration (API runs/saves), manual combat |
| DEC-Q04 | CI: GitHub Actions — format, lint, tests, builds |
| DEC-Q05 | Deploy: Docker for API/DB; website on Cloudflare |
| DEC-Q06 | Perf targets: Desktop 1080p min 60 / aspire 144; Web 60 experimental |
| DEC-Q07 | VCS: Git + GitHub |

---

## Explicit non-goals before EA

- Cooperative multiplayer
- Steam Workshop
- Seasonal events / battle pass
- Hardcore mode / daily runs as required features (leaderboards OK)
- All 20 blueprint themes
- Photoreal or AI-generated final art direction
- Client-side authoritative loot

Any request for these before EA must be deferred to `docs/plan/content/99-POST-EA.md`.

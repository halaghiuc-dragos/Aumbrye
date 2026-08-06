# Aumbrye — Architecture

> **Source of truth: the code on disk.** Every claim below was verified against the repository on
> 2026-08-06. Where a system is genuinely missing, it is tagged **ABSENT** with where it was looked for.
> Known defects are catalogued separately in [`../REFACTOR_OPTIMISE_BUGFIX.md`](../REFACTOR_OPTIMISE_BUGFIX.md)
> and referenced here by ID (e.g. `BUG-01`).

**Stack:** Godot 4.7 client (`.godot-version` pins `4.7.0`); ASP.NET Core 8 API; C# procgen
(`packages/procedural`); React 19 + Vite SPA (`apps/web`); JSON `content/` with schemas under
`content/schemas/`. The play loop is offline-first — online procgen is compiled off.

---

## 1. Repository layout

```
Aumbrye/
├── apps/game/client/     # Godot 4.7 project (primary gameplay)
├── apps/web/             # React 19 + TypeScript + Vite marketing/account site
├── services/backend/     # ASP.NET Core 8 (Api / Application / Domain / Infrastructure)
├── packages/procedural/  # C# dungeon generator (server-authoritative + parity tests)
├── packages/shared/      # C# DTOs + OpenAPI yaml
├── content/              # 323 JSON definitions + content/schemas/*.v1.json + fixtures
├── tools/procgen-cli/    # CLI over packages/procedural
├── tools/voxel-import/   # Voxel art import tooling
├── art-source/           # 262 authored .vox character sources
├── scripts/              # validate-content, balance, openapi-drift, audio generators
├── docker-compose.yml    # postgres + redis + api
└── .github/workflows/    # ci.yml, release.yml, codeql.yml
```

Main scene: `apps/game/client/scenes/ui/title_screen.tscn` (`project.godot` → `run/main_scene`).

The API **does** have a container image: `services/backend/Dockerfile` exists, `docker-compose.yml`
defines an `api` service (`container_name: aumbrye-api`), CI builds it in the `api-image` job, and
`release.yml` pushes it to `ghcr.io`.

---

## 2. Client autoloads

27 autoloads are registered in `apps/game/client/project.godot` under `[autoload]`. All paths below are
`res://`-relative.

| Autoload | Script | Role |
|----------|--------|------|
| `RunFlow` | `scripts/app/run_flow.gd` | Hub ↔ dungeon ↔ results; floor cache; `USE_ONLINE_PROCgen := false` |
| `ApiConfig` | `scripts/net/api_config.gd` | Base URL, token storage, HTTP request pool |
| `LocalSave` | `scripts/save/local_save.gd` | JSON save, roster, active-run snapshots |
| `CharacterService` | `scripts/save/character_service.gd` | Gold/coins, flags, class, appearance |
| `ProgressionService` | `scripts/progression/progression_service.gd` | XP, level, talents |
| `RunBuffs` | `scripts/combat/run_buffs.gd` | Run-scoped buffs and relics |
| `InventoryService` | `scripts/inventory/inventory_service.gd` | Grid inventory + equipment |
| `StorageService` | `scripts/hub/storage_service.gd` | Hub stash |
| `QuestService` | `scripts/quests/quest_service.gd` | Quest state |
| `AudioDirector` | `scripts/audio/audio_director.gd` | Buses, layers, SFX bank, reverb |
| `AchievementService` | `scripts/meta/achievement_service.gd` | Local achievements + Steam sync hooks |
| `SteamService` | `scripts/platform/steam_service.gd` | GodotSteam or dev stub (`DEV_APP_ID := 480`) |
| `CrashLogger` | `scripts/platform/crash_logger.gd` | Breadcrumbs under `user://crash_reports/` |
| `WavesRunService` | `scripts/dungeon/waves_run_service.gd` | Waves-mode state |
| `DungeonTierService` | `scripts/dungeon/dungeon_tier_service.gd` | Per-dungeon tier unlocks |
| `VfxService` | `scripts/art/vfx/vfx_service.gd` | Pooled bursts, decals, hitstop, shake |
| `DisplayService` | `scripts/app/display_service.gd` | Window mode, vsync, FPS cap, UI scale |
| `PlayerControls` | `scripts/app/player_controls.gd` | Meta UI gating — **not** locomotion |
| `MenuStack` | `scripts/ui/menu_stack.gd` | Menu push/pop |
| `WorldState` | `scripts/app/world_state.gd` | Run-scoped key/value flags |
| `PixelDioramaViewport` | `scripts/art/pipeline/pixel_diorama_viewport.gd` | Low-res SubViewport camera mirror |
| `AttackTokenService` | `scripts/combat/attack_token_service.gd` | Per-room attacker concurrency |
| `GameFacade` | `scripts/app/game_facade.gd` | Grouping accessors |
| `InputRebindService` | `scripts/app/input_rebind_service.gd` | Runtime input remapping |
| `DebugConsole` | `scripts/debug/debug_console.gd` | `F12` console (`content_reload` clears catalog caches) |
| `InputGlyphWatcher` | `scripts/ui/input_glyph_watcher.gd` | Device-change → glyph refresh |
| `UISymbolBus` | `scripts/ui/ui_symbol_bus.gd` | Shared UI symbol lookup |

Non-autoload statics carry a large share of state: catalogs under `scripts/content/`, plus
`BiomeRegistry`, `DungeonCatalog`, `ContentLoader`, `EnemyPool`, `VoxelMeshBuilder`.

> The size of this list is itself a finding — see `REF-01`.

---

## 3. Scene and run flow

```mermaid
flowchart LR
  Title[title_screen.tscn] --> Menu[main_menu / character_create]
  Menu --> Loading[loading_screen.tscn]
  Loading --> Hub[hub.tscn]
  Hub -->|castle / endless| Castle[castle_run.tscn]
  Hub -->|waves| Waves[waves_run.tscn]
  Hub -->|arena| Arena[combat_arena.tscn]
  Castle --> Results[results_screen.tscn]
  Waves --> Results
  Results --> Hub
```

Floor counts come from `scripts/dungeon/run_floor_config.gd`:

| Mode | Floors | Biome | Scene |
|------|--------|-------|-------|
| `castle` | `MAX_FLOORS := 10`; floor 10 is final | Selected dungeon biome | `scenes/dungeon/castle_run.tscn` |
| `endless` | `ENDLESS_MAX_FLOORS := 999999`; `is_final_floor()` always false | Forced `umbral_chapel` | same |
| `waves` | Wave counter | Waves service | `scenes/dungeon/waves_run.tscn` |

Ten biomes, each with a matching dungeon definition and room kit:
`forgotten_castle`, `crystal_caverns`, `poison_swamp`, `frozen_fortress`, `dark_cathedral`,
`iron_vault`, `prism_depths`, `venom_mire`, `glacial_hollow`, `umbral_chapel`.

Room kits live at `scenes/rooms/{castle,crystal,swamp,frozen,cathedral,vault,prism,mire,hollow,umbral}/`
and are resolved by **string interpolation**, not by static reference:
`BiomeRegistry.room_scene_path()` builds `"res://scenes/rooms/%s/%s_%s.tscn"`. A typo in a content
`scene` field therefore fails at spawn time, not at import time.

Player scene: `scenes/player/player.tscn`.

---

## 4. Dungeon assembly

```mermaid
sequenceDiagram
  participant Hub
  participant RunFlow
  participant LocalProcgen
  participant CastleRun
  participant DungeonBuilder
  participant LocalSave

  Hub->>RunFlow: start_new_run / endless / waves
  RunFlow->>LocalProcgen: generate(biome, seed, floor)
  LocalProcgen-->>RunFlow: DungeonDefinition
  RunFlow->>CastleRun: change_scene_to_file
  CastleRun->>DungeonBuilder: build_from_definition
  CastleRun->>RunFlow: ascend / death / escape
  RunFlow->>LocalSave: results + autosave
  RunFlow->>Hub: return
```

- **Live offline path:** `scripts/dungeon/local_procgen.gd` → `scripts/dungeon/procgen/dungeon_procgen.gd`
  (GDScript).
- **Online path:** `RunFlow.USE_ONLINE_PROCgen` is `false` (`run_flow.gd:29`), so
  `ApiClient.create_run` is not on the live play path. The check is at `run_flow.gd:225`.
- **Server / parity path:** `packages/procedural` (C#), exercised by `tools/procgen-cli` and
  `cross_stack_parity_suite.gd`.

The duplication between the GDScript and C# generators is tracked as `REF-02`.

Room geometry is `MeshInstance3D` boxes plus `StaticBody3D` from `castle_blockout.gd` — not CSG.
`DungeonBuilder.build_from_source()` is fully synchronous (zero `await`), which is the main cause of
floor-transition stalls (`PERF-03`).

Builder hooks worth knowing:

| Hook | State |
|------|-------|
| `_build_height_transitions()` | Implemented — reads `maxHeightLevel`, walks rooms and edges (`dungeon_builder.gd:332`) |
| `_build_shortcut_corridors()` | **ABSENT** — no such function; shortcut edges are handled by `_wire_shortcut_edges()` (`:236`) |

---

## 5. Combat

Client-authoritative. Happy path:

`WeaponController` → `Hitbox` → `Hurtbox.receive_hit()` → i-frames / immunity / parry / block / arc
multipliers / defense / resistances → `Health` + `Poise` + `StatusController` → `HitFeedback` +
`VfxService`.

`Hurtbox.receive_hit()` (`scripts/combat/hurtbox.gd:44`) builds a `DamageResolution`
(`scripts/combat/damage_resolution.gd`) and emits `hit_resolved` at every exit, including dodged and
parried hits. The legacy `damaged(info)` signal is still emitted for existing listeners.

**Node names are the API.** `Hurtbox` locates `Guard`, `Dodge`, `StatusController` and `HitFeedback` by
literal node name; renaming any of them silently disables that stage.

Collision layers (`project.godot` → `[layer_names]`):

| Layer | Name |
|-------|------|
| 1 | `world` |
| 2 | `player_body` |
| 3 | `hitbox` |
| 4 | `hurtbox` |
| 5 | `interactable` |
| 6 | `trap` |
| 7 | `projectile` |
| 8 | `camera_blocker` |

Hit detection currently polls: `Hitbox` connects `area_entered` **and** runs a shape query every physics
frame while active, with a per-candidate raycast and a group lookup (`PERF-01`). Enemy AI raycasts for
line-of-sight two to three times per physics frame with no distance LOD (`PERF-02`).

---

## 6. Character art pipeline

Characters are **not** runtime box primitives only — there are three parallel representations on disk:

| Representation | Count | Location | Used at runtime |
|---|---|---|---|
| `.vox` authored source | 262 | `art-source/characters/` | No (source) |
| `.mesh` exported ArrayMesh | 262 | `apps/game/client/assets/characters/` | Yes — 40 referenced; **222 orphaned** |
| `.voxels.json` runtime JSON | 115 | `apps/game/client/assets/characters/` | Yes — 133 manifest references |

Rig manifests under `content/characters/*.json` map part names (`LegL`, `Torso`, `Head`, `ArmL`, …) to a
mesh path and a joint offset. `DioramaCharacterSkin` walks the manifest and builds a pivot hierarchy,
loading meshes through `VoxelMeshBuilder.load_mesh()`. Profiles for bodies without a manifest fall back to
`PROFILES` box primitives in `scripts/art/characters/diorama_character_skin.gd`.

Two defects sit in this pipeline: `VoxelMeshBuilder` reads through `ProjectSettings.globalize_path()`,
which cannot read from an exported `.pck` (`BUG-02`), and its "greedy-merged" docstring is false — it
emits two unindexed triangles per exposed voxel face (`PERF-14`). Consolidation is tracked as `REF-05`.

**Rendering:** `PixelDioramaViewport` mirrors the gameplay camera into a low-res `SubViewport`
(`render_target_update_mode = UPDATE_ALWAYS`) and sets `root.disable_3d = true`. The scene graph is never
reparented; only the camera is mirrored.

---

## 7. Audio

`AudioDirector` owns four layers (`ambience`, `music`, `explore`, `combat`), a stinger player, an
eight-player SFX pool, four `AudioStreamPlayer3D` slots, five buses, per-biome reverb and a duck.

Authored OGG stems are the live path. All ten biomes have all four stems under
`apps/game/client/assets/audio/<biome_id>/`, plus `shared/sting_boss.ogg`, `shared/sting_clear.ogg` and
24 SFX files. `AudioStreamGenerator` synthesis is a genuine fallback: `_process()` only fills a layer
whose `stream is AudioStreamGenerator`, and loaded stems replace the generator, so synthesis does not run
in normal play. `audio_suite.gd` asserts this behaviourally (`audio.no_process_synthesis_with_stems`).

`apps/game/client/assets/audio/castle/` is a **legacy unreferenced folder** (`BIOME_CASTLE` resolves to
`forgotten_castle`), and 24 `.wav` files sit alongside their `.ogg` counterparts — both are dead weight
(`DEAD-06`).

---

## 8. Content pipeline

- Source: `content/**/*.json` validated against `content/schemas/*.v1.json`.
- Client load: `ContentLoader.content_root()` resolves `globalize_path("res://")/../../..`, i.e. the
  **repo root** — outside `res://`. This works in the editor and breaks in an exported build (`BUG-01`).
  `aumbrye/content_root` in `project.godot` is `""`.
- Directory catalogs (`ItemCatalog`, `EnemyCatalog`, `ClassCatalog`, `RelicCatalog`, `QuestCatalog`,
  `DialogueCatalog`) share `ContentDirLoader.load_id_map()`.
- `content/items/catalog.json` is the tooling index. Set `aumbrye/strict_item_catalog=true` to intersect
  disk ids against it; default is `false`.
- Run relics live under `content/relics/` via `RelicCatalog`, not in `items/catalog.json`.
- Dev reload: `DebugConsole` → `content_reload` calls `ContentLoader.clear_all_caches()`.
- `ContentLoader.load_json()` has **no cache** and re-parses on every call (`PERF-07`).

Save format: `SaveMigrator.CURRENT_VERSION` is **10**. See [`SAVE_MIGRATIONS.md`](SAVE_MIGRATIONS.md).

---

## 9. Backend, packages, web

```mermaid
flowchart LR
  Client[ApiClient GDScript] -.->|optional, off by default| API[Aumbrye.Api]
  API --> App[Application]
  App --> Proc[packages/procedural]
  App --> PG[(Postgres)]
  App --> Redis[(Redis)]
  Web[apps/web] --> API
  CLI[procgen-cli] --> Proc
  Content[content/] --> Proc
  Content --> Client
```

**API** (`services/backend/src/Aumbrye.Api/Endpoints/`), grouped:

| Group | Routes |
|-------|--------|
| Health | `GET /api/v1/health`, `GET /api/v1/health/ready` |
| Auth | `POST /api/v1/auth/register`, `/login`, `/refresh`, `/logout`, `/steam` |
| Account | `GET /api/v1/account`, `POST /api/v1/account/link-steam` |
| Runs | `POST /api/v1/runs`, `GET /api/v1/runs/{id}/dungeon`, `POST /api/v1/runs/{id}/complete` |
| Saves | `GET/PUT /api/v1/saves/current` |
| Leaderboards | `GET /api/v1/leaderboards`, `POST /api/v1/leaderboards/submit` |
| Telemetry | `POST /api/v1/telemetry/crash` |

A Steam auth ticket exchange endpoint **does** exist (`/api/v1/auth/steam`, backed by
`Infrastructure/Security/SteamAuthService.cs`). What is missing is the client half: GodotSteam binaries
are absent, so `SteamService` runs in stub mode and cannot produce a ticket (`DEP-04`).

CORS **is** configured — `Program.cs:87-89` reads `Cors:AllowedOrigins` and `Program.cs:215` calls
`app.UseCors("web")`; `CorsTests.cs` covers it.

**Web** (`apps/web/src/`, 27 files): React 19 SPA using React Router 7 with real URL routes
(`App.tsx` declares `/`, `/account`, `/patch-notes`, `/wiki`, `/leaderboards`). API access via
`src/api/client.ts` + `VITE_API_URL`. `vite.config.ts` prerenders five routes with Puppeteer at build
time (`WEB-01`).

> **Defect:** `main.tsx` wraps `<App/>` in a `<BrowserRouter>` imported from `react-router` while
> `App.tsx` renders a second `<BrowserRouter>` from `react-router-dom` — nested routers, from two package
> specifiers (`WEB-03`).

**Multiplayer / co-op / dedicated game server:** **ABSENT** — no networking code for it under
`apps/game/client/scripts/`.

---

## 10. Build and CI

`.github/workflows/ci.yml` jobs: `backend`, `api-image`, `web`, `contract`, `e2e`, `python-lint`,
`voxel-import`, `gdlint`, `godot`, `openapi-drift`, `docs-link-check`.

The `godot` job runs, in order: animation-library drift verification, a 500-seed procgen health sweep, the
balance export, and the full headless validation suite
(`godot --headless --script res://scripts/validation/validation_main.gd`).

Two gaps worth knowing before trusting CI:

- No job runs an **exported** build, so `BUG-01` and `BUG-02` — both of which only manifest outside the
  editor — cannot be caught (`QA-05`).
- The frame-budget gate skips when `user://perf_baseline.json` is absent, which is always true on a fresh
  runner (`QA-02`).

`release.yml` builds the API image, the web bundle, and a Windows Godot export.

---

## 11. Related

- [`../REFACTOR_OPTIMISE_BUGFIX.md`](../REFACTOR_OPTIMISE_BUGFIX.md) — the live defect and improvement backlog
- [`ADR/0001-client-server-authority.md`](ADR/0001-client-server-authority.md) — authority boundaries
- [`SAVE_MIGRATIONS.md`](SAVE_MIGRATIONS.md) — save schema history
- [`DOC-CONVENTIONS.md`](DOC-CONVENTIONS.md) — how to write docs in this repo
- [`validation/manual-checklist.md`](validation/manual-checklist.md) — manual QA items

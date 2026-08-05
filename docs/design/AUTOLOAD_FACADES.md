# Autoload facades

Godot registers 18 singletons in `project.godot`. New code should depend on the smallest surface possible.

## GameFacade

`GameFacade` (`scripts/app/game_facade.gd`) groups autoloads by concern:

| Accessor | Autoloads |
|----------|-----------|
| `persistence()` | LocalSave, CharacterService |
| `progression()` | ProgressionService, QuestService, AchievementService |
| `inventory()` | InventoryService, StorageService |
| `run()` | RunFlow, WavesRunService, DungeonTierService |
| `presentation()` | AudioDirector, VfxService, PixelDioramaViewport |
| `platform()` | SteamService, CrashLogger, ApiConfig |

Combat helpers (`RunBuffs`, `AttackTokenService`, `PlayerControls`, `WorldState`) stay direct autoloads — they are scene-local systems, not cross-cutting services.

## RunFlow split

- `run_lifecycle.gd` — escape/death result dictionaries
- `run_scene_router.gd` — scene paths and `change_scene_to_file` deferral
- `run_flow.gd` — run state, procgen, persistence (still the run orchestrator)

## Future

Inject services into new scenes via `@export` or constructor args where practical; reserve autoload access for leaf UI and legacy paths.

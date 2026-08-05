extends Node

## Thin facade grouping autoloads by concern. Prefer injecting dependencies in new code;
## use these accessors when crossing subsystem boundaries from UI or debug tooling.
##
## Groups (see docs/design/AUTOLOAD_FACADES.md):
##   persistence — LocalSave, CharacterService
##   progression — ProgressionService, QuestService, AchievementService
##   inventory   — InventoryService, StorageService
##   run         — RunFlow, WavesRunService, DungeonTierService
##   presentation — AudioDirector, VfxService, PixelDioramaViewport
##   platform    — SteamService, CrashLogger, ApiConfig


func persistence() -> Dictionary:
	return {"save": LocalSave, "character": CharacterService}


func progression() -> Dictionary:
	return {
		"progression": ProgressionService,
		"quests": QuestService,
		"achievements": AchievementService,
	}


func inventory() -> Dictionary:
	return {"inventory": InventoryService, "storage": StorageService}


func run() -> Dictionary:
	return {
		"flow": RunFlow,
		"waves": WavesRunService,
		"dungeon_tiers": DungeonTierService,
	}


func presentation() -> Dictionary:
	return {
		"audio": AudioDirector,
		"vfx": VfxService,
		"pixel_viewport": PixelDioramaViewport,
	}


func platform() -> Dictionary:
	return {"steam": SteamService, "crash": CrashLogger, "api": ApiConfig}

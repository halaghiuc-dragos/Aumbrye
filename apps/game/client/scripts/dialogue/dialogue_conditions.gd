extends RefCounted
class_name DialogueConditions

## Evaluates dialogue/quest condition blocks against CharacterService state (DLG-4.1).

const KNOWN_KEYS := [
	"all",
	"any",
	"not",
	"flag",
	"minLevel",
	"maxLevel",
	"quest",
	"gold",
	"minRuns",
	"minDeaths",
	"hasItem",
	"dungeonCleared",
	"biome",
	"minTier",
	"relationship",
	"storyBeat",
	"questCompletions",
	"lastRunOutcome",
	"lastRunBiome",
	"minLastRunFloor",
	"lastRunBoss",
	"bestiaryKills",
	"bountyTokens",
]

const LAST_RUN_FLAG := "last_run"

const RELATIONSHIP_FLAG_PREFIX := "rel_"
const STORY_BEAT_FLAG := "story_beat"


static func evaluate(condition: Variant) -> bool:
	if condition == null:
		return true
	if not condition is Dictionary:
		return true
	if condition.is_empty():
		return true

	if condition.has("all"):
		for entry in condition.get("all", []):
			if not evaluate(entry):
				return false
		return true

	if condition.has("any"):
		for entry in condition.get("any", []):
			if evaluate(entry):
				return true
		return false

	if condition.has("not"):
		return not evaluate(condition.get("not"))

	if condition.has("flag"):
		var flag_id: String = str(condition.get("flag", ""))
		if condition.has("atLeast"):
			return _flag_number(flag_id) >= int(condition.get("atLeast", 0))
		var expected: Variant = condition.get("value", true)
		return CharacterService.get_flag(flag_id) == expected

	if condition.has("minLevel"):
		return CharacterService.get_level() >= int(condition.get("minLevel", 1))

	if condition.has("maxLevel"):
		return CharacterService.get_level() <= int(condition.get("maxLevel", 999))

	if condition.has("quest"):
		var quest_id: String = str(condition.get("quest", ""))
		var expected_state: String = str(condition.get("state", "active"))
		return CharacterService.get_quest_state(quest_id) == expected_state

	if condition.has("gold"):
		return CharacterService.gold >= int(condition.get("gold", 0))

	if condition.has("minRuns"):
		return int(CharacterService.get_flag("runs_started", 0)) >= int(condition.get("minRuns", 0))

	if condition.has("minDeaths"):
		return int(CharacterService.get_flag("deaths", 0)) >= int(condition.get("minDeaths", 0))

	if condition.has("hasItem"):
		var item_id: String = str(condition.get("hasItem", ""))
		if item_id == "" or InventoryService == null:
			return false
		return InventoryService.count_item(item_id) >= int(condition.get("count", 1))

	if condition.has("dungeonCleared"):
		var dungeon_id: String = str(condition.get("dungeonCleared", ""))
		var clear_flag := DungeonCatalog.get_clear_flag(dungeon_id)
		if clear_flag == "":
			return false
		return CharacterService.is_flag_truthy(clear_flag)

	if condition.has("biome"):
		if RunFlow == null:
			return false
		return str(RunFlow.current_biome_id) == str(condition.get("biome", ""))

	if condition.has("minTier"):
		if DungeonTierService == null:
			return false
		return DungeonTierService.get_max_unlocked_tier() >= int(condition.get("minTier", 1))

	if condition.has("relationship"):
		var npc_key: String = str(condition.get("relationship", ""))
		if npc_key == "":
			return false
		return (
			_flag_number("%s%s" % [RELATIONSHIP_FLAG_PREFIX, npc_key])
			>= int(condition.get("atLeast", 1))
		)

	if condition.has("storyBeat"):
		return _flag_number(STORY_BEAT_FLAG) >= int(condition.get("storyBeat", 0))

	if condition.has("questCompletions"):
		var completed_id: String = str(condition.get("questCompletions", ""))
		if completed_id == "" or QuestService == null:
			return false
		return QuestService.get_completions(completed_id) >= int(condition.get("atLeast", 1))

	if condition.has("lastRunOutcome"):
		return str(_last_run().get("outcome", "")) == str(condition.get("lastRunOutcome", ""))

	if condition.has("lastRunBiome"):
		return str(_last_run().get("biome", "")) == str(condition.get("lastRunBiome", ""))

	if condition.has("minLastRunFloor"):
		return int(_last_run().get("floor", 0)) >= int(condition.get("minLastRunFloor", 1))

	if condition.has("lastRunBoss"):
		return bool(_last_run().get("boss", false)) == bool(condition.get("lastRunBoss", true))

	if condition.has("bestiaryKills"):
		var enemy_id: String = str(condition.get("bestiaryKills", ""))
		if enemy_id == "":
			return false
		return BestiaryService.get_kills(enemy_id) >= int(condition.get("atLeast", 1))

	if condition.has("bountyTokens"):
		return (
			int(CharacterService.get_flag("bounty_tokens", 0))
			>= int(condition.get("bountyTokens", 0))
		)

	# NOTE: this used to `assert(false)` here. In a debug build that halts the process, so any
	# content typo in a dialogue condition crashed the game outright — and it aborted the whole
	# validation run, because hub_m4_suite deliberately feeds `{"minLvl": 1}` to exercise this
	# path. That abort is why the suite could never reach the end and why CI was never wired.
	#
	# OPEN QUESTION for the team: the comment below says unknown keys fail *open* (return true),
	# while hub_m4_suite.gd:187 asserts they fail *closed* (expects false). With the assert gone
	# the suite now reports that disagreement instead of hiding it behind a crash. Current
	# behaviour is preserved until the intended semantics are chosen.
	push_warning("DialogueConditions: unrecognized condition keys: %s" % str(condition.keys()))
	# Release builds fail open: an unknown key must never silently hide content.
	return true


static func _last_run() -> Dictionary:
	var raw: Variant = CharacterService.get_flag(LAST_RUN_FLAG, {})
	return raw if raw is Dictionary else {}


static func _flag_number(flag_id: String) -> int:
	var raw: Variant = CharacterService.get_flag(flag_id, 0)
	if raw is bool:
		return 1 if raw else 0
	if raw is int or raw is float:
		return int(raw)
	if raw is String and str(raw).is_valid_int():
		return int(str(raw))
	return 0

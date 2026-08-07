extends RefCounted
class_name DialogueConditions

## Evaluates dialogue/quest condition blocks against CharacterService state (DLG-4.1).

const KNOWN_KEYS := [
	"all", "any", "not", "flag", "minLevel", "maxLevel", "quest", "gold", "minRuns", "minDeaths"
]


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

	push_warning("DialogueConditions: unrecognized condition keys: %s" % str(condition.keys()))
	assert(false, "DialogueConditions: unrecognized condition keys: %s" % str(condition.keys()))
	# Release builds fail open: an unknown key must never silently hide content.
	return true

extends Node

## Gates the three core run modes behind the depth ladder.
##
## The rules live in `content/modes/unlocks.json` so a designer can retune the ladder without
## touching code. Nothing here writes save state except `consume_announcements()`, which marks a
## newly-opened portal as "the player has been told", so the hub only celebrates it once.

signal mode_unlocked(mode_id: String)

const UNLOCKS_PATH := "content/modes/unlocks.json"
const FLAG_ANNOUNCED := "modes_announced"

const MODE_CASTLE := "castle"
const MODE_WAVES := "waves"
const MODE_ENDLESS := "endless"

var _modes: Dictionary = {}
var _order: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()


func _load() -> void:
	_modes.clear()
	_order.clear()
	var data: Dictionary = ContentLoader.load_json(UNLOCKS_PATH)
	if data.is_empty():
		push_error("ModeUnlockService: failed to load %s" % UNLOCKS_PATH)
		return
	for entry in data.get("modes", []):
		if not entry is Dictionary:
			continue
		var mode: Dictionary = entry
		var mode_id := str(mode.get("id", ""))
		if mode_id == "":
			continue
		_modes[mode_id] = mode
		_order.append(mode_id)


func reload() -> void:
	_load()


func all_mode_ids() -> Array[String]:
	return _order.duplicate()


func has_mode(mode_id: String) -> bool:
	return _modes.has(mode_id)


func get_mode(mode_id: String) -> Dictionary:
	var entry: Variant = _modes.get(mode_id, {})
	return entry if entry is Dictionary else {}


func portal_node_name(mode_id: String) -> String:
	return str(get_mode(mode_id).get("portalNode", ""))


func display_name(mode_id: String) -> String:
	return str(get_mode(mode_id).get("displayName", mode_id.capitalize()))


func locked_label(mode_id: String) -> String:
	var label := str(get_mode(mode_id).get("lockedLabel", ""))
	return label if label != "" else "%s — sealed" % display_name(mode_id)


func is_unlocked(mode_id: String) -> bool:
	var mode := get_mode(mode_id)
	if mode.is_empty():
		return true
	for requirement in mode.get("requirements", []):
		if not requirement is Dictionary:
			continue
		if not _requirement_met(requirement):
			return false
	return true


## Human-readable progress, one line per unmet requirement: "Reach Depth 3 of the Descent (2/3)".
func requirement_lines(mode_id: String) -> Array[String]:
	var lines: Array[String] = []
	for requirement in get_mode(mode_id).get("requirements", []):
		if not requirement is Dictionary:
			continue
		var req: Dictionary = requirement
		var needed := int(req.get("value", 1))
		var have := mini(_counter(str(req.get("type", ""))), needed)
		lines.append("%s (%d/%d)" % [str(req.get("text", "")), have, needed])
	return lines


## One-line summary for the hub message when a player walks into a sealed portal.
func lock_message(mode_id: String) -> String:
	var lines := requirement_lines(mode_id)
	if lines.is_empty():
		return locked_label(mode_id)
	return "%s\n%s" % [locked_label(mode_id), "\n".join(lines)]


## Modes that are unlocked but whose opening has not been shown to the player yet. Calling this
## marks them announced, so it returns each mode exactly once across the character's lifetime.
func consume_announcements() -> Array[Dictionary]:
	var announced: Dictionary = _announced_flag()
	var fresh: Array[Dictionary] = []
	var dirty := false
	for mode_id in _order:
		if mode_id == MODE_CASTLE:
			continue
		if not is_unlocked(mode_id):
			continue
		if bool(announced.get(mode_id, false)):
			continue
		announced[mode_id] = true
		dirty = true
		fresh.append(
			{
				"id": mode_id,
				"name": display_name(mode_id),
				"announce": str(get_mode(mode_id).get("announce", "")),
			}
		)
		mode_unlocked.emit(mode_id)
	if dirty:
		CharacterService.set_flag(FLAG_ANNOUNCED, announced)
	return fresh


func _announced_flag() -> Dictionary:
	var stored: Variant = CharacterService.get_flag(FLAG_ANNOUNCED, {})
	return (stored as Dictionary).duplicate() if stored is Dictionary else {}


func _requirement_met(requirement: Dictionary) -> bool:
	return _counter(str(requirement.get("type", ""))) >= int(requirement.get("value", 1))


func _counter(requirement_type: String) -> int:
	match requirement_type:
		"dungeonDepth":
			return DungeonTierService.get_max_unlocked_tier()
		"dungeonDepthCleared":
			return DungeonTierService.get_deepest_cleared()
		"wavesCompletions":
			return int(CharacterService.get_flag("waves_completions"))
	push_warning("ModeUnlockService: unknown requirement type '%s'" % requirement_type)
	return 0

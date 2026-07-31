extends RefCounted
class_name HubTutorialService

## POLISH-7.2 — skippable first-run hub tips.

const SAVE_KEY := "hub_tutorial"

static var tips_enabled := true
static var tips_completed := false
static var current_tip_index := 0

static var TIPS: Array[String] = [
	"Roll with Space to dodge attacks. Practice in the combat arena.",
	"Block with right-click; a well-timed parry staggers enemies.",
	"Defeat the floor boss, then use the stair lever to ascend.",
	"Secret rooms hide extra loot — listen for hidden passages.",
	"Press Esc to open inventory and equip better gear.",
]


static func load_from_save() -> void:
	var data: Dictionary = LocalSave.get_meta_data().get(SAVE_KEY, {})
	tips_enabled = bool(data.get("enabled", true))
	tips_completed = bool(data.get("completed", false))
	current_tip_index = int(data.get("index", 0))


static func save() -> void:
	var meta := LocalSave.get_meta_data()
	meta[SAVE_KEY] = {
		"enabled": tips_enabled,
		"completed": tips_completed,
		"index": current_tip_index,
	}
	LocalSave.set_meta_data(meta)
	LocalSave.autosave()


static func should_show_tips() -> bool:
	return tips_enabled and not tips_completed


static func get_current_tip() -> String:
	if current_tip_index < 0 or current_tip_index >= TIPS.size():
		return ""
	return TIPS[current_tip_index]


static func advance_tip() -> String:
	current_tip_index += 1
	if current_tip_index >= TIPS.size():
		tips_completed = true
	save()
	return get_current_tip()


static func skip_all() -> void:
	tips_completed = true
	tips_enabled = false
	save()

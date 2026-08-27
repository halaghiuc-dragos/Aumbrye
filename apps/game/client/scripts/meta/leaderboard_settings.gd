extends RefCounted
class_name LeaderboardSettings


const SAVE_KEY := "leaderboard"

static var opt_in: bool = false


static func load_from_save() -> void:
	var data: Dictionary = LocalSave.get_meta_data().get(SAVE_KEY, {})
	opt_in = bool(data.get("opt_in", false))


static func save() -> void:
	var meta := LocalSave.get_meta_data()
	meta[SAVE_KEY] = {"opt_in": opt_in}
	LocalSave.set_meta_data(meta)
	LocalSave.autosave()

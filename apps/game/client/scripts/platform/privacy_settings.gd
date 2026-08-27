extends RefCounted
class_name PrivacySettings


const SAVE_KEY := "privacy"

static var send_crash_reports: bool = false


static func load_from_save() -> void:
	var data: Dictionary = LocalSave.get_meta_data().get(SAVE_KEY, {})
	send_crash_reports = bool(data.get("send_crash_reports", false))


static func save() -> void:
	var meta := LocalSave.get_meta_data()
	meta[SAVE_KEY] = {"send_crash_reports": send_crash_reports}
	LocalSave.set_meta_data(meta)
	LocalSave.autosave()

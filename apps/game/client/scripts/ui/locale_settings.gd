extends RefCounted
class_name LocaleSettings


const SAVE_KEY := "locale"
const SUPPORTED_LOCALES := ["en", "ro"]

static var locale: String = "en"

static var _changed_listeners: Array[Callable] = []


static func connect_changed(callback: Callable) -> void:
	if not _changed_listeners.has(callback):
		_changed_listeners.append(callback)


static func disconnect_changed(callback: Callable) -> void:
	_changed_listeners.erase(callback)


static func _notify_changed() -> void:
	for callback in _changed_listeners.duplicate():
		if callback.is_valid():
			callback.call()
		else:
			_changed_listeners.erase(callback)


static func load_from_save() -> void:
	var data: Dictionary = LocalSave.get_meta_data().get(SAVE_KEY, {})
	locale = str(data.get("code", "en"))
	if locale not in SUPPORTED_LOCALES:
		locale = "en"
	apply()


static func save() -> void:
	var meta := LocalSave.get_meta_data()
	meta[SAVE_KEY] = {"code": locale}
	LocalSave.set_meta_data(meta)
	LocalSave.autosave()


static func apply() -> void:
	TranslationServer.set_locale(locale)


static func set_locale_code(code: String) -> void:
	if code not in SUPPORTED_LOCALES:
		return
	if locale == code:
		return
	locale = code
	apply()
	save()
	_notify_changed()

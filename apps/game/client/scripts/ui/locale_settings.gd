extends RefCounted
class_name LocaleSettings

## Locale preference stored in save meta (CFG-10).

const SAVE_KEY := "locale"
const SUPPORTED_LOCALES := ["en", "ro"]

static var locale: String = "en"


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
	locale = code
	apply()
	save()

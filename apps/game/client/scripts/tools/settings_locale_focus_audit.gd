extends Node


const SettingsUIScript := preload("res://scripts/ui/settings_ui.gd")

var _failures := 0


func _ready() -> void:
	var settings: Control = SettingsUIScript.new()
	add_child(settings)
	await get_tree().process_frame
	settings.call("open_settings")
	await get_tree().process_frame
	var rows_by_page: Dictionary = settings.get("_rows_by_page")
	var language_row: SettingsRow = _find_language_row(rows_by_page.get("gameplay", []))
	_check(language_row != null, "gameplay page builds the language settings row")
	if language_row == null:
		_finish(settings)
		return
	var language_widget := language_row.get_widget()
	_check(language_widget != null, "language row exposes a focusable selector")
	if language_widget == null:
		_finish(settings)
		return
	language_widget.grab_focus()
	await get_tree().process_frame
	_check(
		get_viewport().gui_get_focus_owner() == language_widget,
		"language selector can receive focus before locale refresh"
	)
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("ro" if previous_locale != "ro" else "en")
	settings.call("_on_locale_changed")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(int(settings.get("_active_page_idx")) == 0, "locale refresh preserves the active settings page")
	var refreshed_rows: Dictionary = settings.get("_rows_by_page")
	var refreshed_language_row: SettingsRow = _find_language_row(refreshed_rows.get("gameplay", []))
	_check(refreshed_language_row != null, "locale refresh rebuilds the language row")
	if refreshed_language_row:
		_check(
			get_viewport().gui_get_focus_owner() == refreshed_language_row.get_widget(),
			"locale refresh restores focus to the same setting control"
		)
	TranslationServer.set_locale(previous_locale)
	_finish(settings)


func _find_language_row(rows: Array) -> SettingsRow:
	for row in rows:
		if row is SettingsRow and row.get_setting_id() == "language":
			return row as SettingsRow
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _finish(settings: Control) -> void:
	settings.set("_open", false)
	var stack: Node = settings.call("_menu_stack")
	if stack and stack.has_method("pop"):
		stack.call("pop", settings)
	settings.queue_free()
	print("SETTINGS LOCALE FOCUS RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

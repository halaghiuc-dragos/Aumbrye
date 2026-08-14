extends Control

## Achievement browser — locked/unlocked list from catalog (META-6.1).

signal closed

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")

var _open := false
var _list: ItemList


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_open() -> bool:
	return _open


func open() -> void:
	_build_ui_if_needed()
	_refresh()
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _list:
		_list.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _build_ui_if_needed() -> void:
	if _list != null and is_instance_valid(_list):
		return
	for child in get_children():
		child.queue_free()
	GameUISkinScript.ensure_full_rect(self)
	var shell: Dictionary = MenuShellScript.build_modal(
		self, "Achievements", GameUISkinScript.SETTINGS_HALF_W, GameUISkinScript.SETTINGS_HALF_H
	)
	var content_vbox: VBoxContainer = shell["content_vbox"]
	_list = ItemList.new()
	_list.name = "AchievementList"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 320)
	content_vbox.add_child(_list)
	var close_btn := MenuShellScript.make_menu_button(tr("UI_CLOSE"), close)
	content_vbox.add_child(close_btn)
	MenuShellScript.add_hint(content_vbox, "Esc to close")


func _refresh() -> void:
	if _list == null:
		return
	_list.clear()
	if not AchievementService:
		_list.add_item(tr("ACHIEVEMENTS_UNAVAILABLE"))
		return
	var entries: Array = []
	for def in AchievementService.get_all_definitions():
		if not def is Dictionary:
			continue
		if bool(def.get("hidden", false)) and not AchievementService.is_unlocked(str(def.get("id", ""))):
			continue
		entries.append(def)
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_unlocked := AchievementService.is_unlocked(str(a.get("id", "")))
			var b_unlocked := AchievementService.is_unlocked(str(b.get("id", "")))
			if a_unlocked != b_unlocked:
				return a_unlocked
			return str(a.get("name", "")) < str(b.get("name", ""))
	)
	for def in entries:
		var id: String = str(def.get("id", ""))
		var unlocked := AchievementService.is_unlocked(id)
		var prefix := "[Unlocked] " if unlocked else "[Locked] "
		var line := "%s%s — %s" % [prefix, def.get("name", id), def.get("description", "")]
		_list.add_item(line)


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

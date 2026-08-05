extends Control

## Character / save slot picker — current save plus rotating backups.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")

signal slot_selected(backup_index: int)
signal slot_deleted(backup_index: int)
signal cancelled

var _slot_list: ItemList
var _detail_label: Label
var _play_button: Button
var _delete_button: Button
var _slots: Array[Dictionary] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	var shell: Dictionary = MenuShellScript.build_modal(self, "Continue", 400.0, 340.0)
	var vbox: VBoxContainer = shell["content_vbox"]
	MenuShellScript.add_subtitle(vbox, "Select a warden echo to resume.")
	_slot_list = ItemList.new()
	_slot_list.custom_minimum_size = Vector2(0, 200)
	_slot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_list.item_selected.connect(_on_slot_selected)
	vbox.add_child(_slot_list)
	_detail_label = Label.new()
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(_detail_label)
	vbox.add_child(_detail_label)
	var back := MenuShellScript.make_menu_button("Back", _on_back_pressed)
	_play_button = MenuShellScript.make_menu_button("Continue", _on_play_pressed)
	_delete_button = MenuShellScript.make_menu_button("Delete Save", _on_delete_pressed)
	MenuShellScript.add_button_row(vbox, [back, _play_button])
	MenuShellScript.add_button_row(vbox, [_delete_button])


func open_menu() -> void:
	GameUISkinScript.ensure_full_rect(self)
	_reload_slots()
	visible = true
	move_to_front()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _slot_list.item_count > 0:
		_slot_list.select(0)
		_on_slot_selected(0)


func close_menu() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _reload_slots() -> void:
	_slots = LocalSave.list_character_slots()
	_slot_list.clear()
	_detail_label.text = ""
	var has_slots := not _slots.is_empty()
	_play_button.disabled = not has_slots
	_delete_button.disabled = not has_slots
	if not has_slots:
		_slot_list.add_item("No saved wardens yet — start a New Game.")
		return
	for entry in _slots:
		var label := str(entry.get("label", "Unknown"))
		_slot_list.add_item(label)


func _selected_entry() -> Dictionary:
	var selected := _slot_list.get_selected_items()
	if selected.is_empty() or _slots.is_empty():
		return {}
	var index: int = selected[0]
	if index < 0 or index >= _slots.size():
		return {}
	return _slots[index]


func _on_slot_selected(index: int) -> void:
	if index < 0 or index >= _slots.size():
		_detail_label.text = ""
		_delete_button.disabled = true
		return
	var entry := _slots[index]
	_detail_label.text = str(entry.get("detail", ""))
	_delete_button.disabled = false


func _on_play_pressed() -> void:
	var entry := _selected_entry()
	if entry.is_empty():
		return
	var backup_index: int = int(entry.get("backupIndex", -1))
	close_menu()
	slot_selected.emit(backup_index)


func _on_delete_pressed() -> void:
	var entry := _selected_entry()
	if entry.is_empty():
		return
	var backup_index: int = int(entry.get("backupIndex", -1))
	var slot_name := str(entry.get("label", "this save"))
	MenuShellScript.show_confirmation(
		self,
		"Delete Save",
		"Permanently delete %s?\nThis cannot be undone." % slot_name,
		func() -> void:
			if LocalSave.delete_character_slot(backup_index):
				slot_deleted.emit(backup_index)
				_reload_slots()
				if _slots.is_empty():
					_on_back_pressed()
	)


func _on_back_pressed() -> void:
	close_menu()
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()

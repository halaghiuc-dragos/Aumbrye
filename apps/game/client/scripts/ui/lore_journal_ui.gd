extends Control


signal closed

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")

var _open := false
var _entries: ItemList
var _detail: Label
var _records: Array[Dictionary] = []


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
	move_to_front()
	if MenuStack:
		MenuStack.push(self)
	if _entries and _entries.item_count > 0:
		_entries.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if MenuStack:
		MenuStack.pop(self)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _build_ui_if_needed() -> void:
	if _entries != null and is_instance_valid(_entries):
		return
	GameUISkinScript.ensure_full_rect(self)
	var shell: Dictionary = MenuShellScript.build_modal(
		self, "Lore Journal", GameUISkinScript.PANEL_HALF_W, GameUISkinScript.PANEL_HALF_H
	)
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", GameUISkinScript.SECTION_SEPARATION)
	(shell["content_vbox"] as VBoxContainer).add_child(split)
	_entries = ItemList.new()
	_entries.custom_minimum_size = Vector2(280.0, 360.0)
	_entries.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_entries.item_selected.connect(_on_entry_selected)
	split.add_child(_entries)
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	GameUISkinScript.style_body_label(_detail)
	split.add_child(_detail)
	var close_button := MenuShellScript.make_menu_button("Close", close)
	(shell["content_vbox"] as VBoxContainer).add_child(close_button)


func _refresh() -> void:
	_records.clear()
	_entries.clear()
	var discovered: Dictionary = CharacterService.get_flag("lore_discoveries", {}) as Dictionary
	for lore_id in discovered:
		if bool(discovered[lore_id]):
			_records.append(_record_for(str(lore_id)))
	_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	for record in _records:
		_entries.add_item(str(record["title"]))
	if _records.is_empty():
		_detail.text = tr("LORE_JOURNAL_EMPTY")
	else:
		_entries.select(0)
		_show_record(0)


func _record_for(lore_id: String) -> Dictionary:
	var parts := lore_id.split(":", false)
	var biome := str(parts[0]) if not parts.is_empty() else "forgotten_castle"
	var number := posmod(lore_id.hash(), 12) + 1
	var node_id := "start" if number == 1 else "%s_%d" % [biome, number]
	var dialogue := DialogueCatalog.get_dialogue("dungeon_lore_default")
	var nodes: Dictionary = dialogue.get("nodes", {}) as Dictionary
	var node: Dictionary = nodes.get(node_id, {}) as Dictionary
	return {"id": lore_id, "title": str(node.get("speaker", lore_id)), "text": str(node.get("text", lore_id))}


func _on_entry_selected(index: int) -> void:
	_show_record(index)


func _show_record(index: int) -> void:
	if index < 0 or index >= _records.size():
		return
	var record := _records[index]
	_detail.text = "%s\n\n%s" % [str(record["title"]), str(record["text"])]

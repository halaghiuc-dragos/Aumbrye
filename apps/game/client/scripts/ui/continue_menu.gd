extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")

signal slot_selected(character_id: String)
signal slot_deleted(character_id: String)
signal cancelled

const SLOT_HEIGHT := 56
const SLOT_TEXT_INSET := 18.0
const SLOT_SEPARATION := 8
const ROSTER_MIN_HEIGHT := (
	SLOT_HEIGHT * 5 + SLOT_SEPARATION * 4 + ROSTER_PADDING * 2
)
const ROSTER_PADDING := 12

var _roster: VBoxContainer
var _empty_label: Label
var _footer_label: Label
var _slot_buttons: Array[Button] = []
var _slot_group: ButtonGroup
var _selected_index := -1
var _detail_label: Label
var _play_button: Button
var _delete_button: Button
var _slots: Array[Dictionary] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	var shell: Dictionary = MenuShellScript.build_modal(self, "Continue", 420.0, 360.0)
	var vbox: VBoxContainer = shell["content_vbox"]
	MenuShellScript.add_subtitle(vbox, "Choose a warden to enter Aumbrye Tower.")

	var casket := PanelContainer.new()
	casket.name = "Roster"
	GameUISkinScript.style_panel(casket)
	casket.custom_minimum_size = Vector2(0, ROSTER_MIN_HEIGHT)
	casket.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(casket)

	var inner := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		inner.add_theme_constant_override("margin_%s" % side, ROSTER_PADDING)
	casket.add_child(inner)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(scroll)

	_roster = VBoxContainer.new()
	_roster.name = "Slots"
	_roster.add_theme_constant_override("separation", SLOT_SEPARATION)
	_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_roster)

	_slot_group = ButtonGroup.new()

	_empty_label = Label.new()
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_body_label(_empty_label)
	_empty_label.visible = false
	_roster.add_child(_empty_label)

	_footer_label = Label.new()
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_hint_label(_footer_label)
	vbox.add_child(_footer_label)

	_detail_label = Label.new()
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_body_label(_detail_label)
	vbox.add_child(_detail_label)
	var back := MenuShellScript.make_menu_button(tr("CONTINUE_BACK"), _on_back_pressed)
	_play_button = MenuShellScript.make_menu_button(tr("CONTINUE_PLAY"), _on_play_pressed)
	_delete_button = MenuShellScript.make_menu_button(tr("CONTINUE_DELETE"), _on_delete_pressed)
	MenuShellScript.add_button_row(vbox, [back, _play_button])
	MenuShellScript.add_button_row(vbox, [_delete_button])


func open_menu() -> void:
	GameUISkinScript.ensure_full_rect(self)
	_reload_slots()
	visible = true
	move_to_front()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not _slot_buttons.is_empty():
		_slot_buttons[0].button_pressed = true
		_slot_buttons[0].grab_focus()
		_on_slot_selected(0)


func close_menu() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _reload_slots() -> void:
	_slots = LocalSave.list_character_slots()
	for button in _slot_buttons:
		if is_instance_valid(button):
			button.queue_free()
	_slot_buttons.clear()
	_selected_index = -1
	_detail_label.text = ""
	var has_slots := not _slots.is_empty()
	_play_button.disabled = not has_slots
	_delete_button.disabled = not has_slots
	_empty_label.visible = not has_slots
	if not has_slots:
		_empty_label.text = tr("CONTINUE_NO_WARDENS")
		_footer_label.text = ""
		return
	for i in _slots.size():
		_slot_buttons.append(_make_slot_button(i, str(_slots[i].get("label", "Unknown"))))
	_footer_label.text = (
		"— %d of %d warden slots used —"
		% [LocalSave.used_character_slots(), LocalSave.character_slot_limit()]
	)


func _make_slot_button(index: int, label: String) -> Button:
	var button := GameUISkinScript.make_button(label)
	button.name = "Slot%d" % index
	button.toggle_mode = true
	button.button_group = _slot_group
	button.custom_minimum_size = Vector2(0, SLOT_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("h_separation", 12)
	for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		var style := GameUISkinScript.make_button_style(state)
		style.content_margin_left = SLOT_TEXT_INSET
		style.content_margin_right = SLOT_TEXT_INSET
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(func() -> void: _on_slot_selected(index))
	_roster.add_child(button)
	return button


func _selected_entry() -> Dictionary:
	if _selected_index < 0 or _selected_index >= _slots.size():
		return {}
	return _slots[_selected_index]


func _on_slot_selected(index: int) -> void:
	if index < 0 or index >= _slots.size():
		_selected_index = -1
		_detail_label.text = ""
		_delete_button.disabled = true
		return
	_selected_index = index
	var entry := _slots[index]
	_detail_label.text = str(entry.get("detail", ""))
	_delete_button.disabled = false


func _on_play_pressed() -> void:
	var entry := _selected_entry()
	if entry.is_empty():
		return
	var character_id := str(entry.get("characterId", ""))
	if character_id == "":
		return
	close_menu()
	slot_selected.emit(character_id)


func _on_delete_pressed() -> void:
	var entry := _selected_entry()
	if entry.is_empty():
		return
	var character_id := str(entry.get("characterId", ""))
	if character_id == "":
		return
	var slot_name := str(entry.get("label", "this warden"))
	MenuShellScript.show_confirmation(
		self,
		"Delete Warden",
		(
			"Permanently delete %s?\nAll progress, inventory, and hub state for this warden will be erased."
			% slot_name
		),
		func() -> void:
			if LocalSave.delete_character(character_id):
				slot_deleted.emit(character_id)
				_reload_slots()
				if _slots.is_empty():
					_on_back_pressed(),
		Callable(),
		"Delete Forever",
		"Keep Warden"
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

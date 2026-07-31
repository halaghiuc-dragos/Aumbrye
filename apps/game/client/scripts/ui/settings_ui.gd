extends Control

## Settings overlay with save backup restore (SAVE-4.2).

signal closed

var _backup_list: ItemList
var _status_label: Label
var _hint_label: Label

var _open := false


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui_if_needed()
	_refresh_backups()
	AccessibilitySettings.load_from_save()
	LeaderboardSettings.load_from_save()


func _build_ui_if_needed() -> void:
	if _backup_list != null:
		return
	if has_node("Panel/Margin/VBox/BackupList"):
		_backup_list = $Panel/Margin/VBox/BackupList
		_status_label = $Panel/Margin/VBox/StatusLabel
		_hint_label = $Panel/Margin/VBox/HintLabel
		return
	for child in get_children():
		child.queue_free()
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280
	panel.offset_top = -200
	panel.offset_right = 280
	panel.offset_bottom = 200
	add_child(panel)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_backup_list = ItemList.new()
	_backup_list.name = "BackupList"
	_backup_list.custom_minimum_size = Vector2(480, 180)
	vbox.add_child(_backup_list)
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	vbox.add_child(_status_label)
	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.text = "Enter: restore | Esc: close"
	vbox.add_child(_hint_label)
	_build_accessibility_section(vbox)


func _build_accessibility_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var title := Label.new()
	title.text = "Accessibility"
	parent.add_child(title)
	var ui_scale := HSlider.new()
	ui_scale.name = "UiScaleSlider"
	ui_scale.min_value = 0.8
	ui_scale.max_value = 1.5
	ui_scale.step = 0.05
	ui_scale.value = AccessibilitySettings.ui_scale
	ui_scale.value_changed.connect(func(v: float) -> void:
		AccessibilitySettings.ui_scale = v
		AccessibilitySettings.save()
	)
	parent.add_child(ui_scale)
	var shake := CheckBox.new()
	shake.text = "Reduce camera shake"
	shake.button_pressed = AccessibilitySettings.reduce_camera_shake
	shake.toggled.connect(func(on: bool) -> void:
		AccessibilitySettings.reduce_camera_shake = on
		AccessibilitySettings.save()
	)
	parent.add_child(shake)
	var cb := OptionButton.new()
	cb.add_item("Default", 0)
	cb.add_item("Protanopia", 1)
	cb.add_item("Deuteranopia", 2)
	cb.add_item("Tritanopia", 3)
	match AccessibilitySettings.colorblind_mode:
		"protanopia": cb.selected = 1
		"deuteranopia": cb.selected = 2
		"tritanopia": cb.selected = 3
		_: cb.selected = 0
	cb.item_selected.connect(func(idx: int) -> void:
		var modes := ["default", "protanopia", "deuteranopia", "tritanopia"]
		AccessibilitySettings.colorblind_mode = modes[idx]
		AccessibilitySettings.save()
	)
	parent.add_child(cb)
	var lb := CheckBox.new()
	lb.text = "Submit clear times to leaderboards (opt-in)"
	lb.button_pressed = LeaderboardSettings.opt_in
	lb.toggled.connect(func(on: bool) -> void:
		LeaderboardSettings.opt_in = on
		LeaderboardSettings.save()
	)
	parent.add_child(lb)


func is_open() -> bool:
	return _open


func open_settings() -> void:
	_open = true
	visible = true
	_refresh_backups()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_settings() -> void:
	_open = false
	visible = false
	closed.emit()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close_settings()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_restore_selected()
		get_viewport().set_input_as_handled()


func _refresh_backups() -> void:
	if _backup_list == null:
		return
	_backup_list.clear()
	var backups := LocalSave.list_backups()
	if backups.is_empty():
		_backup_list.add_item("No backups yet (autosave creates them)")
		if _status_label:
			_status_label.text = ""
		return
	for entry in backups:
		_backup_list.add_item(
			"Backup %d — Lv%d — %s" % [
				entry.get("index", 0),
				entry.get("level", 1),
				entry.get("savedAt", "?"),
			]
		)
	if _status_label:
		_status_label.text = "%d backup(s) available" % backups.size()


func _restore_selected() -> void:
	if _backup_list == null:
		return
	var selected := _backup_list.get_selected_items()
	if selected.is_empty():
		return
	var backups := LocalSave.list_backups()
	var row: int = selected[0]
	if row < 0 or row >= backups.size():
		return
	var index: int = int(backups[row].get("index", 0))
	if LocalSave.restore_backup(index):
		if _status_label:
			_status_label.text = "Restored backup %d" % index
		_refresh_backups()
	elif _status_label:
		_status_label.text = "Restore failed"

extends Control


signal closed

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")

var _open := false
var _list: ItemList
var _summary_label: Label
var _detail_label: Label
var _ids: Array[String] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_open() -> bool:
	return _open


func open() -> void:
	move_to_front()
	_build_ui_if_needed()
	_refresh()
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if MenuStack:
		MenuStack.push(self)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _list:
		_list.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if MenuStack:
		MenuStack.pop(self)
	else:
		PlayerControls.capture_mouse_if_allowed()
	closed.emit()


func _build_ui_if_needed() -> void:
	if _list != null and is_instance_valid(_list):
		return
	for child in get_children():
		child.queue_free()
	GameUISkinScript.ensure_full_rect(self)
	var shell: Dictionary = MenuShellScript.build_modal(
		self, "Bestiary", GameUISkinScript.PANEL_HALF_W, GameUISkinScript.PANEL_HALF_H
	)
	var content_vbox: VBoxContainer = shell["content_vbox"]

	_summary_label = Label.new()
	_summary_label.name = "BestiarySummary"
	GameUISkinScript.style_hint_label(_summary_label)
	content_vbox.add_child(_summary_label)

	var split := HBoxContainer.new()
	split.name = "BestiarySplit"
	split.add_theme_constant_override("separation", GameUISkinScript.SECTION_SEPARATION)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(split)

	var list_frame := GameUISkinScript.make_pixel_frame("Records")
	list_frame.name = "BestiaryListFrame"
	list_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(list_frame)
	_list = ItemList.new()
	_list.name = "BestiaryList"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(300, 360)
	_list.item_selected.connect(_on_entry_selected)
	GameUISkinScript.pixel_frame_content(list_frame).add_child(_list)

	var detail_frame := GameUISkinScript.make_pixel_frame("Field Notes")
	detail_frame.name = "BestiaryDetailFrame"
	detail_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(detail_frame)
	_detail_label = Label.new()
	_detail_label.name = "BestiaryDetail"
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_label.custom_minimum_size = Vector2(300, 360)
	GameUISkinScript.style_body_label(_detail_label)
	GameUISkinScript.pixel_frame_content(detail_frame).add_child(_detail_label)

	var close_btn := MenuShellScript.make_menu_button(tr("UI_CLOSE"), close)
	content_vbox.add_child(close_btn)
	MenuShellScript.add_hint(content_vbox, "Esc to close")


func _refresh() -> void:
	if _list == null:
		return
	_list.clear()
	_ids.clear()
	var total := BestiaryService.entry_count()
	if total <= 0:
		_list.add_item(tr("BESTIARY_EMPTY"))
		_set_detail("")
		if _summary_label:
			_summary_label.text = ""
		return
	var rows: Array[Dictionary] = []
	for enemy_id in BestiaryService.get_all_ids():
		var revealed := BestiaryService.get_revealed(enemy_id)
		if revealed.is_empty():
			continue
		rows.append(revealed)
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_biome := str(a.get("biomeId", ""))
			var b_biome := str(b.get("biomeId", ""))
			if a_biome != b_biome:
				return a_biome < b_biome
			return _display_name(a) < _display_name(b)
	)
	var sighted := 0
	for row in rows:
		var tier := int(row.get("tier", BestiaryService.TIER_UNKNOWN))
		if tier >= BestiaryService.TIER_SIGHTED:
			sighted += 1
		_list.add_item(_row_text(row))
		_ids.append(str(row.get("enemyId", "")))
	if _summary_label:
		_summary_label.text = (
			"Sighted %d / %d — studied %d — mastered %d"
			% [sighted, total, BestiaryService.studied_count(), BestiaryService.mastered_count()]
		)
		if BestiaryService.is_complete():
			_summary_label.text += " — codex complete"
	if _list.item_count > 0:
		_list.select(0)
		_on_entry_selected(0)


func _tier_label(tier: int) -> String:
	if tier >= BestiaryService.TIER_MASTERED:
		return "Mastered"
	if tier >= BestiaryService.TIER_STUDIED:
		return "Studied"
	if tier >= BestiaryService.TIER_SIGHTED:
		return "Sighted"
	return "Unrecorded"


func _row_text(row: Dictionary) -> String:
	var tier := int(row.get("tier", BestiaryService.TIER_UNKNOWN))
	return "[%s] %s" % [_tier_label(tier), _display_name(row)]


func _display_name(row: Dictionary) -> String:
	var entry_name := str(row.get("name", ""))
	if entry_name != "":
		return entry_name
	return "Unknown quarry"


func _on_entry_selected(index: int) -> void:
	if index < 0 or index >= _ids.size():
		_set_detail("")
		return
	_set_detail_for(BestiaryService.get_revealed(_ids[index]))


func _set_detail_for(revealed: Dictionary) -> void:
	if revealed.is_empty():
		_set_detail("")
		return
	var enemy_id := str(revealed.get("enemyId", ""))
	var tier := int(revealed.get("tier", BestiaryService.TIER_UNKNOWN))
	var lines: Array[String] = [_display_name(revealed)]
	var biome := str(revealed.get("biomeId", ""))
	if biome != "":
		lines.append(biome.capitalize())
	lines.append("Slain %d — %s" % [int(revealed.get("kills", 0)), _tier_label(tier)])
	lines.append("")
	if tier < BestiaryService.TIER_SIGHTED:
		lines.append("Nothing of this one has been written down.")
	else:
		lines.append(str(revealed.get("sighted", "")))
	if tier >= BestiaryService.TIER_STUDIED:
		lines.append("")
		lines.append(str(revealed.get("studied", "")))
	if tier >= BestiaryService.TIER_MASTERED:
		lines.append("")
		lines.append(str(revealed.get("mastered", "")))
	var remaining := BestiaryService.kills_to_next_tier(enemy_id)
	if remaining > 0:
		lines.append("")
		lines.append("%d more killed, and the page fills further." % remaining)
	_set_detail("\n".join(lines))


func _set_detail(text: String) -> void:
	if _detail_label:
		_detail_label.text = text


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if MenuStack != null:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_cancel_requested() -> void:
	close()

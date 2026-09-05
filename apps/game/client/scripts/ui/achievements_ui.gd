extends Control

## UX-01: the achievements screen used to be a flat ItemList of "[Locked] Name — description"
## rows. This renders it as a grid of cells grouped by `catalog.json`'s `category` field, with a
## locked/unlocked visual state and a progress bar per cell (binary full/empty -- the catalog and
## `AchievementService` only track unlocked/not, no fractional counters, so a fully-filled bar is
## the honest representation of "done" rather than fabricating a fake percentage).


signal closed

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")

const CELL_MIN_SIZE := Vector2(210, 92)
const GRID_COLUMNS := 3

const CATEGORY_GLYPHS := {
	"combat": "⚔",
	"biome": "⛰",
	"speed": "⏱",
	"loot": "◆",
}
const DEFAULT_GLYPH := "★"

var _open := false
var _list_vbox: VBoxContainer
var _detail_label: Label
var _described_id := ""


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
	if _list_vbox != null and is_instance_valid(_list_vbox):
		return
	for child in get_children():
		child.queue_free()
	GameUISkinScript.ensure_full_rect(self)
	var shell: Dictionary = MenuShellScript.build_modal(
		self, "Achievements", GameUISkinScript.PANEL_HALF_W, GameUISkinScript.PANEL_HALF_H
	)
	var content_vbox: VBoxContainer = shell["content_vbox"]

	var split := HBoxContainer.new()
	split.name = "AchievementsSplit"
	split.add_theme_constant_override("separation", GameUISkinScript.SECTION_SEPARATION)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(split)

	var list_frame := GameUISkinScript.make_pixel_frame("Progress")
	list_frame.name = "AchievementsListFrame"
	list_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_frame.size_flags_stretch_ratio = 2.4
	split.add_child(list_frame)
	var scroller := ScrollContainer.new()
	scroller.name = "AchievementsScroll"
	scroller.custom_minimum_size = Vector2(660, 380)
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	GameUISkinScript.pixel_frame_content(list_frame).add_child(scroller)
	_list_vbox = VBoxContainer.new()
	_list_vbox.name = "AchievementsCategories"
	_list_vbox.add_theme_constant_override("separation", int(GameUISkinScript.SECTION_SEPARATION * 0.5))
	scroller.add_child(_list_vbox)

	var detail_frame := GameUISkinScript.make_pixel_frame("Notes")
	detail_frame.name = "AchievementsDetailFrame"
	detail_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(detail_frame)
	_detail_label = Label.new()
	_detail_label.name = "AchievementsDetail"
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_detail_label.custom_minimum_size = Vector2(220, 320)
	GameUISkinScript.style_body_label(_detail_label)
	GameUISkinScript.pixel_frame_content(detail_frame).add_child(_detail_label)

	var close_btn := MenuShellScript.make_menu_button(tr("UI_CLOSE"), close)
	content_vbox.add_child(close_btn)
	MenuShellScript.add_hint(content_vbox, "Esc to close")


func _refresh() -> void:
	if _list_vbox == null:
		return
	for child in _list_vbox.get_children():
		child.queue_free()
	_set_detail("")
	if not AchievementService:
		var unavailable := Label.new()
		unavailable.text = tr("ACHIEVEMENTS_UNAVAILABLE")
		GameUISkinScript.style_body_label(unavailable)
		_list_vbox.add_child(unavailable)
		return
	var by_category: Dictionary = {}
	var order: Array[String] = []
	for def in AchievementService.get_all_definitions():
		if not def is Dictionary:
			continue
		var visible_entry := bool((def as Dictionary).get("hidden", false)) == false
		if not visible_entry and not AchievementService.is_unlocked(str((def as Dictionary).get("id", ""))):
			continue
		var category := str((def as Dictionary).get("category", "misc"))
		if not by_category.has(category):
			by_category[category] = []
			order.append(category)
		(by_category[category] as Array).append(def)
	order.sort()
	var first_id := ""
	for category in order:
		_add_category_section(category, by_category[category])
		if first_id == "":
			first_id = str((by_category[category][0] as Dictionary).get("id", ""))
	if first_id != "":
		_describe(first_id)


func _add_category_section(category: String, defs: Array) -> void:
	var header := Label.new()
	header.text = category.capitalize()
	GameUISkinScript.style_section_title(header)
	_list_vbox.add_child(header)
	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", GameUISkinScript.GRID_GAP)
	grid.add_theme_constant_override("v_separation", GameUISkinScript.GRID_GAP)
	_list_vbox.add_child(grid)
	defs.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_unlocked := AchievementService.is_unlocked(str(a.get("id", "")))
			var b_unlocked := AchievementService.is_unlocked(str(b.get("id", "")))
			if a_unlocked != b_unlocked:
				return a_unlocked
			return str(a.get("name", "")) < str(b.get("name", ""))
	)
	for def in defs:
		_make_cell(grid, def as Dictionary, category)


func _make_cell(grid: GridContainer, def: Dictionary, category: String) -> void:
	var id: String = str(def.get("id", ""))
	var unlocked := AchievementService.is_unlocked(id)
	var frame := GameUISkinScript.make_pixel_frame("")
	frame.name = "Achievement_%s" % id
	frame.custom_minimum_size = CELL_MIN_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.focus_mode = Control.FOCUS_ALL
	frame.modulate = Color(1, 1, 1, 1) if unlocked else Color(0.55, 0.55, 0.6, 0.8)
	grid.add_child(frame)
	var content := GameUISkinScript.pixel_frame_content(frame)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	content.add_child(header_row)
	var glyph := Label.new()
	glyph.text = str(CATEGORY_GLYPHS.get(category, DEFAULT_GLYPH))
	GameUISkinScript.style_section_title(glyph)
	if unlocked:
		glyph.add_theme_color_override("font_color", GameUISkinScript.GOLD)
	header_row.add_child(glyph)
	var name_label := Label.new()
	name_label.text = str(def.get("name", id))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameUISkinScript.style_body_label(name_label)
	header_row.add_child(name_label)

	var bar := GameUISkinScript.make_meter_bar(
		GameUISkinScript.GOLD if unlocked else GameUISkinScript.HINT_COLOR
	)
	bar.value = 1.0 if unlocked else 0.0
	content.add_child(bar)

	frame.gui_input.connect(_on_cell_gui_input.bind(id))
	frame.mouse_entered.connect(_on_cell_hover.bind(id))
	frame.focus_entered.connect(_on_cell_hover.bind(id))


func _on_cell_gui_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_describe(id)
		accept_event()


func _on_cell_hover(id: String) -> void:
	_describe(id)


func _describe(id: String) -> void:
	_described_id = id
	var def: Dictionary = {}
	for entry in AchievementService.get_all_definitions():
		if entry is Dictionary and str((entry as Dictionary).get("id", "")) == id:
			def = entry
			break
	if def.is_empty():
		_set_detail("")
		return
	var unlocked := AchievementService.is_unlocked(id)
	var lines: Array[String] = [
		str(def.get("name", id)),
		"Unlocked" if unlocked else "Locked",
		"",
		str(def.get("description", "")),
	]
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

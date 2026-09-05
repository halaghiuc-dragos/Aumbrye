extends Control

## UX-01: the bestiary used to be a flat ItemList of "[Tier] Name" rows. This renders it as a
## grid of enemy portraits instead -- each revealed entry gets a live 3D bust built the same way
## `character_create_ui.gd` builds its player preview (a SubViewport around a small preview rig;
## see `enemy_preview_rig.gd`), plus a tier progress ring and the progressive reveal text from
## `BestiaryService.get_revealed()`.


signal closed

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const EnemyPreviewRigScript := preload("res://scripts/ui/enemy_preview_rig.gd")
const CharacterSkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")

const CELL_MIN_SIZE := Vector2(148, 168)
const PORTRAIT_SIZE := Vector2(120, 92)
const GRID_COLUMNS := 4

## Small radial "how close to the next tier" indicator drawn next to each portrait.
class TierRing extends Control:
	var ratio := 0.0
	var ring_color := Color(0.8, 0.64, 0.32)

	func _draw() -> void:
		var r: float = size.x * 0.5 - 2.0
		var center := size * 0.5
		draw_arc(center, r, -PI * 0.5, -PI * 0.5 + TAU * clampf(ratio, 0.0, 1.0), 24, ring_color, 3.0, true)
		draw_arc(center, r, 0.0, TAU, 24, Color(1, 1, 1, 0.12), 1.0, true)

## Enum, not just a bool, matches the existing enum-based POINTER/CURSOR split `inventory_ui.gd`
## uses (see its `InputMode`) so hover and keyboard focus never fight over which entry is
## "described" — mouse presence always wins until the keyboard moves focus again.
enum InputMode { POINTER, CURSOR }

var _open := false
var _grid: GridContainer
var _summary_label: Label
var _detail_label: Label
var _cells: Dictionary = {}
var _rows: Array[Dictionary] = []
var _input_mode: InputMode = InputMode.CURSOR
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
	if _grid and _grid.get_child_count() > 0:
		(_grid.get_child(0) as Control).grab_focus()


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
	if _grid != null and is_instance_valid(_grid):
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

	var grid_frame := GameUISkinScript.make_pixel_frame("Records")
	grid_frame.name = "BestiaryGridFrame"
	grid_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_frame.size_flags_stretch_ratio = 2.2
	split.add_child(grid_frame)
	var scroller := ScrollContainer.new()
	scroller.name = "BestiaryScroll"
	scroller.custom_minimum_size = Vector2(620, 380)
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	GameUISkinScript.pixel_frame_content(grid_frame).add_child(scroller)
	_grid = GridContainer.new()
	_grid.name = "BestiaryGrid"
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", GameUISkinScript.GRID_GAP)
	_grid.add_theme_constant_override("v_separation", GameUISkinScript.GRID_GAP)
	scroller.add_child(_grid)

	var detail_frame := GameUISkinScript.make_pixel_frame("Field Notes")
	detail_frame.name = "BestiaryDetailFrame"
	detail_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(detail_frame)
	_detail_label = Label.new()
	_detail_label.name = "BestiaryDetail"
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_label.custom_minimum_size = Vector2(260, 360)
	GameUISkinScript.style_body_label(_detail_label)
	GameUISkinScript.pixel_frame_content(detail_frame).add_child(_detail_label)

	var close_btn := MenuShellScript.make_menu_button(tr("UI_CLOSE"), close)
	content_vbox.add_child(close_btn)
	MenuShellScript.add_hint(content_vbox, "Esc to close")


func _refresh() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.queue_free()
	_cells.clear()
	_rows.clear()
	var total := BestiaryService.entry_count()
	if total <= 0:
		if _summary_label:
			_summary_label.text = tr("BESTIARY_EMPTY")
		_set_detail("")
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
	_rows = rows
	var sighted := 0
	for row in rows:
		var tier := int(row.get("tier", BestiaryService.TIER_UNKNOWN))
		if tier >= BestiaryService.TIER_SIGHTED:
			sighted += 1
		_make_cell(row)
	if _summary_label:
		_summary_label.text = (
			"Sighted %d / %d — studied %d — mastered %d"
			% [sighted, total, BestiaryService.studied_count(), BestiaryService.mastered_count()]
		)
		if BestiaryService.is_complete():
			_summary_label.text += " — codex complete"
	if not rows.is_empty():
		_describe(str(rows[0].get("enemyId", "")))


func _make_cell(row: Dictionary) -> void:
	var enemy_id := str(row.get("enemyId", ""))
	var tier := int(row.get("tier", BestiaryService.TIER_UNKNOWN))
	var frame := GameUISkinScript.make_pixel_frame("")
	frame.name = "Entry_%s" % enemy_id
	frame.custom_minimum_size = CELL_MIN_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.focus_mode = Control.FOCUS_ALL
	_grid.add_child(frame)
	var content := GameUISkinScript.pixel_frame_content(frame)

	var portrait_wrap := AspectRatioContainer.new()
	portrait_wrap.custom_minimum_size = PORTRAIT_SIZE
	content.add_child(portrait_wrap)
	if tier >= BestiaryService.TIER_SIGHTED:
		_build_portrait(portrait_wrap, enemy_id)
	else:
		var unknown := Label.new()
		unknown.text = "?"
		unknown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unknown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		GameUISkinScript.style_section_title(unknown)
		portrait_wrap.add_child(unknown)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	content.add_child(footer)
	var ring := TierRing.new()
	ring.custom_minimum_size = Vector2(20, 20)
	var kills := int(row.get("kills", 0))
	var remaining := BestiaryService.kills_to_next_tier(enemy_id)
	ring.ratio = 1.0 if remaining <= 0 else clampf(float(kills) / float(kills + remaining), 0.0, 1.0)
	ring.ring_color = _tier_color(tier)
	footer.add_child(ring)
	var name_label := Label.new()
	name_label.text = _row_text(row)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameUISkinScript.style_body_label(name_label)
	footer.add_child(name_label)

	frame.gui_input.connect(_on_cell_gui_input.bind(enemy_id))
	frame.mouse_entered.connect(_on_cell_mouse_entered.bind(enemy_id))
	frame.focus_entered.connect(_on_cell_focus_entered.bind(enemy_id))
	_cells[enemy_id] = frame


## Same SubViewport approach `character_create_ui.gd` uses for the player: an owned 3D world in a
## SubViewport, a diorama body built into it, and a stretch-shrunk container to keep it pixel-art
## crisp at grid-cell scale.
func _build_portrait(parent: Control, enemy_id: String) -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(container)
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	viewport.size = Vector2i(180, 138)
	container.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = GameUISkinScript.FRAME_BG.darkened(0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.36, 0.48)
	env.ambient_light_energy = 0.32
	world_env.environment = env
	stage.add_child(world_env)
	var rig := EnemyPreviewRigScript.new()
	stage.add_child(rig)
	var data := EnemyCatalog.get_definition(enemy_id)
	var enemy_type := CharacterSkinScript.profile_for_enemy_data(data)
	var enemy_theme := CharacterSkinScript.theme_for_enemy_id(enemy_id)
	rig.show_enemy(enemy_id, enemy_type, enemy_theme, data)


func _tier_color(tier: int) -> Color:
	if tier >= BestiaryService.TIER_MASTERED:
		return Color(0.62, 0.78, 0.58)
	if tier >= BestiaryService.TIER_STUDIED:
		return GameUISkinScript.GOLD
	return GameUISkinScript.HINT_COLOR


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
	return entry_name if entry_name != "" else "Unknown quarry"


func _on_cell_gui_input(event: InputEvent, enemy_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_input_mode = InputMode.POINTER
		_describe(enemy_id)
		accept_event()


func _on_cell_mouse_entered(enemy_id: String) -> void:
	_input_mode = InputMode.POINTER
	_describe(enemy_id)


func _on_cell_focus_entered(enemy_id: String) -> void:
	_input_mode = InputMode.CURSOR
	_describe(enemy_id)


func _describe(enemy_id: String) -> void:
	_described_id = enemy_id
	_set_detail_for(BestiaryService.get_revealed(enemy_id))


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

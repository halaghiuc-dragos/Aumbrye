extends Control

## Character creation — class cards, live preview, naming, and appearance rows.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const CharacterAppearanceScript := preload("res://scripts/save/character_appearance.gd")
const AppearanceCatalogScript := preload("res://scripts/ui/appearance_catalog.gd")
const AppearanceRowScript := preload("res://scripts/ui/appearance_row.gd")
const ClassCardScript := preload("res://scripts/ui/class_card.gd")
const WardenPreviewRigScript := preload("res://scripts/ui/warden_preview_rig.gd")
const NameValidatorScript := preload("res://scripts/ui/name_validator.gd")
const ItemIconAtlasScript := preload("res://scripts/ui/item_icon_atlas.gd")

## Enough for the twelve stat rows plus the header; scrolls beyond that.
const COMPARISON_TABLE_HEIGHT := 232.0
## Shared by the name field and the Suggest Name button below it.
const NAME_ROW_HEIGHT := 32
const STAT_NAME_COLUMN_WIDTH := 140.0
const RESOLVED_COLUMN_WIDTH := 84.0
const CLASS_COLUMN_WIDTH := 72.0
const UNSELECTED_ALPHA := Color(1, 1, 1, 0.4)

## Canonical stat order. ClassCatalog owns it so the table, the class cards and the balance check
## can never disagree about which twelve stats a class has or what order they come in.
const STAT_ORDER: PackedStringArray = ClassCatalog.RATING_STATS

signal completed(class_id: String, character_name: String, appearance: Dictionary)
signal cancelled
signal appearance_saved(appearance: Dictionary)

var _class_cards: Array[ClassCard] = []
var _class_cards_box: VBoxContainer
var _name_input: LineEdit
var _name_error: Label
var _aspect_row: AppearanceRow
var _frame_row: AppearanceRow
var _head_row: AppearanceRow
var _trim_row: AppearanceRow
var _skin_row: AppearanceRow
var _hair_row: AppearanceRow
var _hair_color_row: AppearanceRow
var _face_row: AppearanceRow
var _preview_viewport: SubViewport
var _preview_rig: WardenPreviewRig
var _preview_caption: Label
var _comparison_grid: GridContainer
var _comparison_cells: Array[Array] = []
var _comparison_headers: Array[Label] = []
var _resolved_cells: Array[Label] = []
var _resolved_header: Label
var _perk_line: Label
## Guards `_on_perk_line_resized`: padding the label changes its height, which re-emits `resized`.
var _padding_perk := false
var _weapon_line: Label
var _weapon_icon: TextureRect
var _class_empty_label: Label
var _back_button: Button
var _randomize_button: Button
var _begin_button: Button
var _random_name_button: Button
var _classes: Array[Dictionary] = []
var _selected_class_index := -1
var _edit_mode := false
var _class_column: VBoxContainer
var _name_column: VBoxContainer
var _initial_focus_card: ClassCard


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func is_open() -> bool:
	return visible


func open_creation() -> void:
	_edit_mode = false
	_class_column.visible = true
	_name_column.visible = true
	GameUISkinScript.ensure_full_rect(self)
	_reload_classes()
	_reload_aspect_options()
	visible = true
	_seed_from_defaults_and_last()
	_refresh_class_detail()
	_refresh_preview()
	_update_name_validation()
	_register_menu_stack()
	_focus_initial()


func open_edit_mode() -> void:
	_edit_mode = true
	_class_column.visible = false
	_name_column.visible = false
	GameUISkinScript.ensure_full_rect(self)
	_reload_aspect_options()
	visible = true
	var profile := LocalSave.get_appearance_profile()
	_apply_profile_to_controls(profile)
	_refresh_preview()
	_register_menu_stack()
	if _aspect_row:
		_aspect_row.grab_focus()


func _exit_tree() -> void:
	_unregister_menu_stack()


func _build_ui() -> void:
	var shell: Dictionary = MenuShellScript.build_modal(
		self, tr("CREATE_TITLE"), 880.0, 494.0
	)
	var outer_vbox: VBoxContainer = shell["content_vbox"]
	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	outer_vbox.add_child(columns)
	_class_column = _build_class_column(columns)
	_build_preview_column(columns)
	_build_detail_column(columns)
	_build_comparison_table(outer_vbox)
	_wire_focus_neighbors()
	# Last, once every widget the refresh touches exists. The perk label is padded to the tallest
	# perk in the roster, and line count means nothing until layout has given the label a width —
	# this is what redoes the padding once it has one.
	_perk_line.resized.connect(_on_perk_line_resized)


## Every class's full stat profile at once, so the pick is a comparison rather than a guess.
##
## The detail card beside the preview describes only the highlighted class, which meant judging a
## tradeoff required selecting each of the seven in turn and remembering what the others said.
func _build_comparison_table(parent: VBoxContainer) -> void:
	parent.add_child(_column_header(tr("CREATE_COMPARE_HEADER")))
	# Scrolled and height-capped: the table grows with the class roster, and letting it size freely
	# pushed the modal taller than the screen — the panel grows from its centre, so the overflow
	# clipped the title off the top and the last class off the bottom at the same time.
	var scroll := ScrollContainer.new()
	scroll.name = "ComparisonScroll"
	scroll.custom_minimum_size = Vector2(0, COMPARISON_TABLE_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	_comparison_grid = GridContainer.new()
	_comparison_grid.name = "ClassComparison"
	_comparison_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_comparison_grid.add_theme_constant_override("h_separation", 8)
	_comparison_grid.add_theme_constant_override("v_separation", 3)
	scroll.add_child(_comparison_grid)


## A stat-by-class matrix: twelve stat rows against one rating column per class, plus a leading
## column showing what the *currently selected* class actually reaches on that stat.
##
## Ratings share one scale, so a row can be scanned to see who is best and worst at a stat and a
## column read as everything a class trades. The resolved column is what turns the ratings back
## into numbers the player will meet in the dungeon, and it is the part that tracks the selection.
func _populate_comparison_table() -> void:
	if _comparison_grid == null:
		return
	for child in _comparison_grid.get_children():
		_comparison_grid.remove_child(child)
		child.queue_free()
	_comparison_cells.clear()
	_resolved_cells.clear()
	_comparison_grid.columns = _classes.size() + 2
	var corner := Label.new()
	corner.text = tr("CREATE_COMPARE_COL_STAT")
	GameUISkinScript.style_hint_label(corner)
	corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	corner.custom_minimum_size = Vector2(STAT_NAME_COLUMN_WIDTH, 0)
	_comparison_grid.add_child(corner)
	_resolved_header = Label.new()
	_resolved_header.text = tr("CREATE_COMPARE_COL_YOU")
	GameUISkinScript.style_hint_label(_resolved_header)
	_resolved_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resolved_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resolved_header.custom_minimum_size = Vector2(RESOLVED_COLUMN_WIDTH, 0)
	_comparison_grid.add_child(_resolved_header)
	_comparison_headers.clear()
	for class_def in _classes:
		var head := Label.new()
		head.text = str(class_def.get("name", class_def.get("id", "")))
		GameUISkinScript.style_hint_label(head)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.custom_minimum_size = Vector2(CLASS_COLUMN_WIDTH, 0)
		_comparison_grid.add_child(head)
		_comparison_headers.append(head)
	for stat_name in STAT_ORDER:
		var label := Label.new()
		label.text = _format_stat_name(stat_name)
		GameUISkinScript.style_body_label(label)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_comparison_grid.add_child(label)
		var resolved := Label.new()
		resolved.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		resolved.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		GameUISkinScript.style_stat_value(resolved)
		_comparison_grid.add_child(resolved)
		_resolved_cells.append(resolved)
		var column: Array[Label] = []
		for class_def in _classes:
			var ratings: Dictionary = class_def.get("statRatings", {})
			var rating := int(round(float(ratings.get(stat_name, ClassCatalog.RATING_STANDARD))))
			var cell := Label.new()
			cell.text = str(rating)
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if rating == ClassCatalog.RATING_STANDARD:
				GameUISkinScript.style_stat_value(cell)
			else:
				GameUISkinScript.style_stat_delta(cell, rating > ClassCatalog.RATING_STANDARD)
			_comparison_grid.add_child(cell)
			column.append(cell)
		_comparison_cells.append(column)
	_refresh_comparison_selection()


## Retargets the matrix at the selected class: fades every rating column but theirs, and rewrites
## the resolved column with the values their ratings actually produce.
##
## This is the part that has to run on every selection change rather than only on rebuild — the
## ratings themselves are fixed per class, but which of them is *yours* is not.
func _refresh_comparison_selection() -> void:
	for i in _comparison_headers.size():
		_comparison_headers[i].add_theme_color_override(
			"font_color",
			(
				GameUISkinScript.TITLE_COLOR
				if i == _selected_class_index
				else GameUISkinScript.HINT_COLOR.darkened(0.35)
			)
		)
	for row in _comparison_cells:
		for i in row.size():
			var cell: Label = row[i]
			cell.modulate = Color(1, 1, 1, 1) if i == _selected_class_index else UNSELECTED_ALPHA
	var selected_ratings: Dictionary = {}
	if _selected_class_index >= 0 and _selected_class_index < _classes.size():
		var ratings: Variant = _classes[_selected_class_index].get("statRatings", {})
		if ratings is Dictionary:
			selected_ratings = ratings
	if _resolved_header:
		_resolved_header.text = (
			str(_classes[_selected_class_index].get("name", ""))
			if _selected_class_index >= 0 and _selected_class_index < _classes.size()
			else tr("CREATE_COMPARE_COL_YOU")
		)
	for i in _resolved_cells.size():
		if i >= STAT_ORDER.size():
			break
		var stat_name := STAT_ORDER[i]
		if selected_ratings.is_empty():
			_resolved_cells[i].text = "—"
			continue
		var rating := float(selected_ratings.get(stat_name, ClassCatalog.RATING_STANDARD))
		_resolved_cells[i].text = _format_resolved(stat_name, rating)


func _build_class_column(parent: HBoxContainer) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "ClassColumn"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 3.0
	parent.add_child(col)
	var header := Label.new()
	header.text = tr("CREATE_CLASS_HEADER")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_section_title(header)
	col.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 280)
	# Nothing in a class card wants horizontal scrolling, and leaving the mode on meant the
	# vertical bar's width could push the cards wide enough to ask for a horizontal one too.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_class_cards_box = VBoxContainer.new()
	_class_cards_box.name = "ClassCards"
	_class_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_class_cards_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_class_cards_box)
	_class_empty_label = Label.new()
	_class_empty_label.text = tr("CREATE_NO_CLASSES")
	_class_empty_label.visible = false
	_class_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_danger_text(_class_empty_label)
	col.add_child(_class_empty_label)
	return col


func _build_preview_column(parent: HBoxContainer) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "PreviewColumn"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 4.0
	parent.add_child(col)
	var viewport_frame := PanelContainer.new()
	viewport_frame.name = "PreviewFrame"
	viewport_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	GameUISkinScript.style_panel(viewport_frame)
	col.add_child(viewport_frame)
	# Pinned to a 3:4 portrait. Left to fill the column the preview became a very tall, very narrow
	# slot, and since Godot keeps the vertical FOV and derives the horizontal one from the aspect,
	# a narrow frame crops the warden's shoulders no matter how far back the camera stands.
	var aspect := AspectRatioContainer.new()
	aspect.name = "PreviewAspect"
	aspect.ratio = 0.75
	aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_frame.add_child(aspect)
	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "PreviewViewport"
	viewport_container.custom_minimum_size = Vector2(270, 360)
	viewport_container.stretch = true
	# The preview is the one place a player studies their warden closely, and it was the one place
	# rendering it at native desktop resolution: every other view of a character goes through the
	# pixel viewport at 480x270 and is upscaled with nearest filtering. At full resolution the
	# surface shader's stitch and dither patterns are finer than a pixel of the intended look, so
	# armour read as a translucent mesh and the figure a player approved in creation was not the
	# figure the game then drew.
	#
	# `stretch_shrink` renders the SubViewport at 1/N and scales it back up, which is the same
	# trick the main pipeline uses. N comes from the player's own resolution preset rather than a
	# constant, so the portrait keeps matching the game when they change it.
	viewport_container.stretch_shrink = _preview_pixel_shrink()
	viewport_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	aspect.add_child(viewport_container)
	_preview_viewport = SubViewport.new()
	# Size is driven by the container because `stretch` is on; setting it here did nothing.
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.own_world_3d = true
	viewport_container.add_child(_preview_viewport)
	var stage := Node3D.new()
	stage.name = "PreviewStage"
	_preview_viewport.add_child(stage)
	# Without an environment the SubViewport clears to the engine's default grey, which is what
	# made the portrait read as a flat placeholder box cut out of the panel.
	var world_env := WorldEnvironment.new()
	world_env.name = "PreviewEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = GameUISkinScript.FRAME_BG.darkened(0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Low enough that the key light still decides which faces are lit. See WardenPreviewRig.
	env.ambient_light_color = Color(0.34, 0.36, 0.48)
	env.ambient_light_energy = 0.32
	world_env.environment = env
	stage.add_child(world_env)
	# Camera and lights belong to the rig; adding a second set here left two cameras fighting over
	# which one was current.
	_preview_rig = WardenPreviewRigScript.new()
	_preview_rig.name = "WardenPreviewRig"
	stage.add_child(_preview_rig)
	var controls := HBoxContainer.new()
	controls.name = "PreviewControls"
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 8)
	var rotate_left := MenuShellScript.make_menu_button(
		"<", func() -> void: _preview_rig.rotate_left()
	)
	rotate_left.custom_minimum_size = Vector2(48, 32)
	var rotate_right := MenuShellScript.make_menu_button(
		">", func() -> void: _preview_rig.rotate_right()
	)
	rotate_right.custom_minimum_size = Vector2(48, 32)
	controls.add_child(rotate_left)
	controls.add_child(rotate_right)
	col.add_child(controls)
	_preview_caption = Label.new()
	_preview_caption.name = "PreviewCaption"
	_preview_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_hint_label(_preview_caption)
	col.add_child(_preview_caption)
	return col


func _build_detail_column(parent: HBoxContainer) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "DetailColumn"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 3.0
	parent.add_child(col)
	_name_column = VBoxContainer.new()
	_name_column.name = "NameColumn"
	_name_column.add_theme_constant_override("separation", 6)
	col.add_child(_name_column)
	_name_column.add_child(_column_header(tr("CREATE_NAME_HEADER"), true))
	_name_input = LineEdit.new()
	_name_input.name = "NameInput"
	_name_input.placeholder_text = tr("CREATE_NAME_PLACEHOLDER")
	_name_input.max_length = NameValidatorScript.MAX_LENGTH
	_name_input.text_changed.connect(_on_name_changed)
	# The field and the button under it are one control in the player's head — you type a name or you
	# ask for one — so they are the same height. The LineEdit had no minimum and sat at whatever the
	# theme's font and padding produced, which was several pixels shorter than the button.
	_name_input.custom_minimum_size = Vector2(0, NAME_ROW_HEIGHT)
	_name_column.add_child(_name_input)
	_name_error = Label.new()
	_name_error.name = "NameError"
	_name_error.visible = false
	_name_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_error.theme_type_variation = GameUISkinScript.VAR_DANGER_TEXT
	_name_column.add_child(_name_error)
	_random_name_button = MenuShellScript.make_menu_button(
		tr("CREATE_RANDOM_NAME"), _on_random_name_pressed
	)
	_random_name_button.custom_minimum_size = Vector2(0, NAME_ROW_HEIGHT)
	_name_column.add_child(_random_name_button)
	var appearance_box := VBoxContainer.new()
	appearance_box.name = "AppearanceRows"
	appearance_box.add_theme_constant_override("separation", 4)
	col.add_child(appearance_box)
	appearance_box.add_child(_column_header(tr("CREATE_APPEARANCE_HEADER"), true))
	_aspect_row = _make_appearance_row(tr("CREATE_ROW_ASPECT"), [])
	appearance_box.add_child(_aspect_row)
	_frame_row = _make_appearance_row(
		tr("CREATE_ROW_FRAME"), CharacterAppearanceScript.FRAME_LABELS
	)
	appearance_box.add_child(_frame_row)
	_head_row = _make_appearance_row(
		tr("CREATE_ROW_HEAD"), CharacterAppearanceScript.HEAD_LABELS
	)
	appearance_box.add_child(_head_row)
	_trim_row = _make_appearance_row(
		tr("CREATE_ROW_TRIM"), CharacterAppearanceScript.TRIM_LABELS
	)
	appearance_box.add_child(_trim_row)
	_skin_row = _make_appearance_row(
		_row_label("CREATE_ROW_SKIN", "Complexion"), CharacterAppearanceScript.SKIN_TONE_LABELS
	)
	appearance_box.add_child(_skin_row)
	_hair_row = _make_appearance_row(
		_row_label("CREATE_ROW_HAIR", "Hair"), CharacterAppearanceScript.HAIR_LABELS
	)
	appearance_box.add_child(_hair_row)
	_hair_color_row = _make_appearance_row(
		_row_label("CREATE_ROW_HAIR_COLOR", "Hair colour"),
		CharacterAppearanceScript.HAIR_COLOR_LABELS
	)
	appearance_box.add_child(_hair_color_row)
	_face_row = _make_appearance_row(
		_row_label("CREATE_ROW_FACE", "Countenance"), CharacterAppearanceScript.FACE_LABELS
	)
	appearance_box.add_child(_face_row)
	# The class stats, perk and starting weapon all describe the selected class, so they live in one
	# titled card rather than as three loose strips floating under the appearance rows.
	var stats_card := PanelContainer.new()
	stats_card.name = "ClassStatsCard"
	col.add_child(stats_card)
	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 8)
	stats_card.add_child(stats_box)
	stats_box.add_child(_column_header(tr("CREATE_CLASS_DETAIL_HEADER"), true))
	# The twelve-stat list that used to live here is now the All Classes matrix below, which shows
	# the same numbers for the selected class alongside every other class and a Base column. Two
	# copies of it cost more vertical space than the modal has, and the matrix is the more useful
	# of the two. What remains is what only applies to the current pick.
	_perk_line = Label.new()
	_perk_line.name = "PerkLine"
	_perk_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(_perk_line)
	stats_box.add_child(_perk_line)
	var weapon_row := HBoxContainer.new()
	weapon_row.name = "WeaponRow"
	weapon_row.add_theme_constant_override("separation", 8)
	stats_box.add_child(weapon_row)
	_weapon_icon = TextureRect.new()
	_weapon_icon.name = "WeaponIcon"
	_weapon_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_weapon_icon.custom_minimum_size = Vector2(24, 24)
	_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	weapon_row.add_child(_weapon_icon)
	_weapon_line = Label.new()
	_weapon_line.name = "WeaponLine"
	_weapon_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameUISkinScript.style_body_label(_weapon_line)
	weapon_row.add_child(_weapon_line)
	var spacer := Control.new()
	spacer.name = "FooterSpacer"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 10)
	col.add_child(footer)
	_back_button = MenuShellScript.make_menu_button(tr("CREATE_BACK"), _on_back_pressed)
	_randomize_button = MenuShellScript.make_menu_button(
		tr("CREATE_RANDOMIZE"), _on_randomize_pressed
	)
	_begin_button = MenuShellScript.make_menu_button(tr("CREATE_BEGIN"), _on_confirm_pressed)
	footer.add_child(_back_button)
	footer.add_child(_randomize_button)
	footer.add_child(_begin_button)
	return col


## Section heading with an accent rule under it, so the three columns read as labelled groups
## instead of one continuous run of controls.
## `centered` for the headers that sit over a column, matching "Choose Your Class" — the class
## column builds its own header and has always centred it. The full-width comparison table keeps a
## left-aligned header: centred over the whole modal it reads as a title for the screen rather than
## a label for the table under it.
func _column_header(text: String, centered: bool = false) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var label := Label.new()
	label.text = text
	GameUISkinScript.style_section_title(label)
	label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	)
	box.add_child(label)
	var rule := ColorRect.new()
	rule.color = GameUISkinScript.ACCENT_BAR
	rule.custom_minimum_size = Vector2(0, 2)
	box.add_child(rule)
	return box


func _make_appearance_row(label_text: String, options: PackedStringArray) -> AppearanceRow:
	var row := AppearanceRowScript.new()
	row.value_changed.connect(_on_appearance_row_changed)
	row.setup(label_text, options, 0)
	return row


func _wire_focus_neighbors() -> void:
	if _class_cards.is_empty():
		return
	for i in _class_cards.size():
		var card := _class_cards[i]
		var prev := _class_cards[i - 1] if i > 0 else card
		var next := _class_cards[i + 1] if i < _class_cards.size() - 1 else card
		card.focus_neighbor_top = prev.get_path()
		card.focus_neighbor_bottom = next.get_path()
		if i == 0:
			card.focus_neighbor_left = card.get_path()
		if i == _class_cards.size() - 1:
			card.focus_neighbor_right = _name_input.get_path()
	_name_input.focus_neighbor_left = _class_cards[0].get_path()
	_name_input.focus_neighbor_right = _random_name_button.get_path()
	_random_name_button.focus_neighbor_left = _name_input.get_path()
	_random_name_button.focus_neighbor_right = _aspect_row.get_path()
	_aspect_row.focus_neighbor_left = _random_name_button.get_path()
	_aspect_row.focus_neighbor_bottom = _frame_row.get_path()
	_frame_row.focus_neighbor_top = _aspect_row.get_path()
	_frame_row.focus_neighbor_bottom = _head_row.get_path()
	_head_row.focus_neighbor_top = _frame_row.get_path()
	_head_row.focus_neighbor_bottom = _trim_row.get_path()
	_trim_row.focus_neighbor_top = _head_row.get_path()
	_trim_row.focus_neighbor_bottom = _back_button.get_path()
	_back_button.focus_neighbor_top = _trim_row.get_path()
	_back_button.focus_neighbor_right = _randomize_button.get_path()
	_randomize_button.focus_neighbor_left = _back_button.get_path()
	_randomize_button.focus_neighbor_right = _begin_button.get_path()
	_begin_button.focus_neighbor_left = _randomize_button.get_path()


func _reload_classes() -> void:
	_classes = ClassCatalog.get_all_classes()
	for card in _class_cards:
		if is_instance_valid(card):
			card.queue_free()
	_class_cards.clear()
	_class_empty_label.visible = _classes.is_empty()
	for class_def in _classes:
		var card := ClassCardScript.new()
		card.pressed.connect(_on_class_card_pressed.bind(card))
		_class_cards_box.add_child(card)
		card.setup(class_def)
		_class_cards.append(card)
	_populate_comparison_table()
	_wire_focus_neighbors()


func _row_label(key: String, fallback: String) -> String:
	var translated := tr(key)
	return fallback if translated == key else translated


func _reload_aspect_options() -> void:
	var labels := PackedStringArray()
	for i in AppearanceCatalogScript.unlocked_aspect_count():
		labels.append(AppearanceCatalogScript.unlocked_aspect_label(i))
	_aspect_row.setup(tr("CREATE_ROW_ASPECT"), labels, 0)


func _seed_from_defaults_and_last() -> void:
	var profile := CharacterAppearanceScript.default_profile()
	var last: Variant = LocalSave.get_last_creation_profile()
	if last is Dictionary and not (last as Dictionary).is_empty():
		profile = CharacterAppearanceScript.sanitize(last)
	_name_input.text = str(profile.get("draftName", ""))
	_apply_profile_to_controls(profile)
	if _class_cards.size() > 0:
		_select_class_index(0)


func _apply_profile_to_controls(profile: Dictionary) -> void:
	var clean := CharacterAppearanceScript.sanitize(profile)
	_aspect_row.select(
		AppearanceCatalogScript.unlocked_aspect_index_for_theme(int(clean.get("theme", 0)))
	)
	_frame_row.select(
		CharacterAppearanceScript.FRAME_VARIANTS.find(clean.get("frame", "standard"))
	)
	match clean.get("head", CharacterAppearanceScript.HEAD_VISOR):
		CharacterAppearanceScript.HEAD_OPEN:
			_head_row.select(0)
		CharacterAppearanceScript.HEAD_HOOD:
			_head_row.select(2)
		_:
			_head_row.select(1)
	_trim_row.select(int(clean.get("trim", 1)))
	_skin_row.select(
		maxi(0, CharacterAppearanceScript.SKIN_TONES.find(clean.get("skinTone", "neutral")))
	)
	_hair_row.select(maxi(0, CharacterAppearanceScript.HAIR_STYLES.find(clean.get("hair", "none"))))
	_hair_color_row.select(
		maxi(0, CharacterAppearanceScript.HAIR_COLORS.find(clean.get("hairColor", "brown")))
	)
	_face_row.select(maxi(0, CharacterAppearanceScript.FACE_STYLES.find(clean.get("face", "open"))))


func _select_class_index(index: int) -> void:
	if index < 0 or index >= _class_cards.size():
		_selected_class_index = -1
		return
	_selected_class_index = index
	for i in _class_cards.size():
		_class_cards[i].button_pressed = i == index
		_class_cards[i].set_selected_mark(i == index)
	_initial_focus_card = _class_cards[index]
	_refresh_comparison_selection()
	# Rebuild the warden, not just the text. Default clothing is per class, so picking a different
	# card has to re-dress the preview — otherwise the figure keeps the previous class's outfit
	# until some unrelated appearance row is touched, which reads as the picker being ignored.
	_refresh_preview()


func _on_class_card_pressed(card: ClassCard) -> void:
	for i in _class_cards.size():
		if _class_cards[i] == card:
			_select_class_index(i)
			return


func _refresh_class_detail() -> void:
	if _selected_class_index < 0 or _selected_class_index >= _classes.size():
		_perk_line.text = ""
		_weapon_line.text = ""
		_weapon_icon.texture = null
		_preview_caption.text = ""
		return
	var class_def := _classes[_selected_class_index]
	_perk_line.text = _pad_perk_text(_perk_text(class_def))
	var weapon_id := str(class_def.get("startingWeaponItemId", ""))
	var weapon_def := ItemCatalog.get_definition(weapon_id)
	var weapon_name := str(weapon_def.get("name", weapon_id))
	_weapon_line.text = tr("CREATE_STARTING_WEAPON") % weapon_name
	_weapon_icon.texture = ItemIconAtlasScript.get_icon(
		weapon_id, str(weapon_def.get("iconPath", ""))
	)
	var aspect_label := AppearanceCatalogScript.unlocked_aspect_label(
		_aspect_row.get_selected_index()
	)
	_preview_caption.text = "%s — %s" % [str(class_def.get("name", "")), aspect_label]






func _on_perk_line_resized() -> void:
	if _padding_perk:
		return
	# `add_child` emits `resized` synchronously, so connecting this at the point the label is built
	# fired it while the rest of the card — the weapon row, the caption — was still nil, and the
	# refresh assigned `text` on nothing. Connected after the whole screen exists now, and still
	# guarded: the card is refreshed by a dozen paths and none of them should depend on build order.
	if _weapon_line == null or _weapon_icon == null or _preview_caption == null:
		return
	_padding_perk = true
	_refresh_class_detail()
	_padding_perk = false


func _perk_text(class_def: Dictionary) -> String:
	return (
		tr("CREATE_PERK")
		% [
			_row_label(str(class_def.get("perkName", "")), str(class_def.get("perkNameText", ""))),
			_row_label(
				str(class_def.get("perkDescription", "")),
				str(class_def.get("perkDescriptionText", "")),
			),
		]
	)


## Blank lines under the perk so the card is the same height whichever class is highlighted.
##
## The perk paragraph wraps to however many lines its wording needs, and the card is sized by its
## contents — so Sentinel, whose perk is a line shorter than the rest, made the whole detail block
## jump up by a line and drag the starting-weapon row with it. Padding to the tallest perk in the
## roster holds the weapon row still. Measured rather than hardcoded to Sentinel: the wording is
## content, and a wrap point moves the moment anyone edits a string or changes the font.
func _pad_perk_text(text: String) -> String:
	# Line count is meaningless before the label has a width to wrap against — leave it unpadded
	# and let the `resized` pass below redo it once layout has run.
	if _perk_line.size.x <= 1.0:
		return text
	# The loop below writes to the label repeatedly to measure it, and each write can queue a
	# resize. Held down so none of them re-enter this through `_on_perk_line_resized`.
	var was_padding := _padding_perk
	_padding_perk = true
	var restore := _perk_line.text
	var tallest := 0
	for class_def: Dictionary in _classes:
		_perk_line.text = _perk_text(class_def)
		tallest = maxi(tallest, _perk_line.get_line_count())
	_perk_line.text = text
	var own := _perk_line.get_line_count()
	_perk_line.text = restore
	_padding_perk = was_padding
	if own >= tallest:
		return text
	return text + "\n".repeat(tallest - own)


## The figure a rating actually produces in play — "145", "18%", "112%".
##
## Stats divide into three shapes: pools and armour points read as plain numbers, chances and
## reductions as a percentage of themselves, and the multiplier stats as a percentage of the
## baseline (a x1.12 damage multiplier reads as 112%).
func _format_resolved(stat_name: String, rating: float) -> String:
	var value := ClassCatalog.resolved_value(stat_name, rating)
	match stat_name:
		"blockReduction", "critChance":
			return "%d%%" % int(round(value * 100.0))
		"physicalDamage", "poiseDamage", "moveSpeed", "staminaRegen", "manaRegen":
			return "%d%%" % int(round(value * 100.0))
		_:
			return str(int(round(value)))


func _format_stat_name(stat_name: String) -> String:
	match stat_name:
		"maxHealth":
			return tr("CREATE_STAT_HEALTH")
		"armor":
			return tr("CREATE_STAT_ARMOR")
		"moveSpeed":
			return tr("CREATE_STAT_SPEED")
		"critChance":
			return tr("STAT_CRIT")
		"physicalDamage":
			return tr("STAT_DAMAGE")
		"poiseDamage":
			return tr("STAT_POISE_DMG")
		"staminaRegen":
			return tr("STAT_STAMINA_REGEN")
		"staminaMax":
			return tr("CREATE_STAT_STAMINA")
		"poise":
			return tr("CREATE_STAT_POISE")
		"blockReduction":
			return tr("STAT_BLOCK")
		"manaMax":
			return tr("CREATE_STAT_MANA")
		"manaRegen":
			return tr("CREATE_STAT_MANA_REGEN")
		_:
			return stat_name


func _build_appearance_profile() -> Dictionary:
	var profile := CharacterAppearanceScript.profile_from_indices(
		AppearanceCatalogScript.unlocked_aspect_theme(_aspect_row.get_selected_index()),
		_frame_row.get_selected_index(),
		_head_row.get_selected_index(),
		_trim_row.get_selected_index(),
		_skin_row.get_selected_index(),
		_hair_row.get_selected_index(),
		_face_row.get_selected_index(),
		_hair_color_row.get_selected_index()
	)
	if _selected_class_index >= 0 and _selected_class_index < _classes.size():
		profile["classId"] = str(_classes[_selected_class_index].get("id", ""))
	# Title is not part of character creation. It stays on the profile — earned titles are awarded
	# elsewhere and `CharacterAppearance.sanitize` preserves whatever is already there — but it is
	# not something the player picks alongside their hair.
	return profile


## How many screen pixels one preview pixel should cover, so the portrait has the same pixel
## density as the world. Derived from the window height against the internal buffer height the
## player's resolution preset asks for — at the 1080p window and the default 480x270 preset that
## is 4, and at the native-HD preset it collapses to 1, which is the correct answer for a preset
## that has deliberately turned the pixel look off.
func _preview_pixel_shrink() -> int:
	var internal := PixelDioramaSettings.viewport_internal_size()
	if internal.y <= 0:
		return 1
	var window_height := float(get_viewport_rect().size.y)
	if window_height <= 0.0:
		return 1
	return clampi(int(round(window_height / float(internal.y))), 1, 8)


func _refresh_preview() -> void:
	if _preview_rig:
		_preview_rig.apply_profile(_build_appearance_profile())
	_refresh_class_detail()


func _on_appearance_row_changed(_index: int) -> void:
	_refresh_preview()
	_save_draft_profile()
	if _edit_mode:
		_perk_line.text = CharacterAppearanceScript.describe(_build_appearance_profile())


func _on_name_changed(_text: String) -> void:
	_update_name_validation()
	_save_draft_profile()


func _update_name_validation() -> void:
	var result := NameValidatorScript.validate(
		_name_input.text, LocalSave.list_warden_names()
	)
	var ok := bool(result.get("ok", false))
	_name_error.visible = not ok and _name_input.text.strip_edges().length() > 0
	if _name_error.visible:
		var key := str(result.get("reason_key", ""))
		_name_error.text = tr(key) if key != "" else ""
	_begin_button.disabled = not ok or _selected_class_index < 0


func _existing_names_for_validation() -> PackedStringArray:
	return LocalSave.list_warden_names()


func _on_random_name_pressed() -> void:
	_name_input.text = NameValidatorScript.random_valid_name(_existing_names_for_validation())
	_update_name_validation()


## Randomises every row the player can set.
##
## Complexion, hair, countenance and title were skipped, so Randomize left four of the nine rows
## on whatever they already were — pressing it repeatedly could never produce a warden with, say,
## different hair. Aspect and title are drawn from the *unlocked* lists rather than the full
## catalogue, so this cannot hand the player something they have not earned.
func _on_randomize_pressed() -> void:
	_aspect_row.select(randi() % maxi(AppearanceCatalogScript.unlocked_aspect_count(), 1))
	_frame_row.select(randi() % CharacterAppearanceScript.FRAME_LABELS.size())
	_head_row.select(randi() % CharacterAppearanceScript.HEAD_LABELS.size())
	_trim_row.select(randi() % CharacterAppearanceScript.TRIM_LABELS.size())
	_skin_row.select(randi() % maxi(CharacterAppearanceScript.SKIN_TONE_LABELS.size(), 1))
	_hair_row.select(randi() % maxi(CharacterAppearanceScript.HAIR_LABELS.size(), 1))
	_hair_color_row.select(randi() % maxi(CharacterAppearanceScript.HAIR_COLOR_LABELS.size(), 1))
	_face_row.select(randi() % maxi(CharacterAppearanceScript.FACE_LABELS.size(), 1))
	_name_input.text = NameValidatorScript.random_valid_name(_existing_names_for_validation())
	_refresh_preview()
	_update_name_validation()
	_save_draft_profile()


func _save_draft_profile() -> void:
	if _edit_mode:
		return
	var draft := _build_appearance_profile()
	draft["draftName"] = _name_input.text
	draft["classId"] = (
		str(_classes[_selected_class_index].get("id", ""))
		if _selected_class_index >= 0 and _selected_class_index < _classes.size()
		else ""
	)
	LocalSave.set_last_creation_profile(draft)


func _on_confirm_pressed() -> void:
	if _edit_mode:
		var profile := _build_appearance_profile()
		if LocalSave.set_appearance_profile(profile):
			visible = false
			_unregister_menu_stack()
			appearance_saved.emit(profile)
		return
	if _classes.is_empty():
		_class_empty_label.visible = true
		return
	var result := NameValidatorScript.validate(
		_name_input.text, LocalSave.list_warden_names()
	)
	if not bool(result.get("ok", false)):
		_update_name_validation()
		return
	if _selected_class_index < 0:
		return
	var class_def := _classes[_selected_class_index]
	var class_id: String = str(class_def.get("id", ""))
	var character_name := _name_input.text.strip_edges()
	var class_display_name := str(class_def.get("name", class_id))
	AudioDirector.play_ui_sfx()
	MenuShellScript.show_confirmation(
		self,
		tr("CREATE_CONFIRM_TITLE"),
		tr("CREATE_CONFIRM_MESSAGE") % [class_display_name, character_name],
		func() -> void:
			visible = false
			_unregister_menu_stack()
			completed.emit(class_id, character_name, _build_appearance_profile()),
		Callable(),
		tr("CREATE_BEGIN"),
		tr("CREATE_BACK")
	)


func _on_back_pressed() -> void:
	_save_draft_profile()
	visible = false
	_unregister_menu_stack()
	cancelled.emit()


func _register_menu_stack() -> void:
	if MenuStack:
		MenuStack.push(self)


func _unregister_menu_stack() -> void:
	if MenuStack:
		MenuStack.pop(self)


func _focus_initial() -> void:
	if _initial_focus_card and is_instance_valid(_initial_focus_card):
		_initial_focus_card.grab_focus()
	elif _class_cards.size() > 0:
		_class_cards[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_page_next"):
		_preview_rig.rotate_right()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_prev"):
		_preview_rig.rotate_left()
		get_viewport().set_input_as_handled()

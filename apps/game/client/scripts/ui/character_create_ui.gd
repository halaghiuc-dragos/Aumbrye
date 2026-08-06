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

signal completed(class_id: String, character_name: String, appearance: Dictionary)
signal cancelled
signal appearance_saved(appearance: Dictionary)

var _class_cards: Array[ClassCard] = []
var _class_cards_box: VBoxContainer
var _name_input: LineEdit
var _name_error: Label
var _aspect_row: AppearanceRow
var _stature_row: AppearanceRow
var _build_row: AppearanceRow
var _head_row: AppearanceRow
var _trim_row: AppearanceRow
var _preview_viewport: SubViewport
var _preview_rig: WardenPreviewRig
var _preview_caption: Label
var _stats_grid: GridContainer
var _perk_line: Label
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
		self, tr("CREATE_TITLE"), 760.0, 520.0
	)
	var outer_vbox: VBoxContainer = shell["content_vbox"]
	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	outer_vbox.add_child(columns)
	_class_column = _build_class_column(columns)
	var preview_column := _build_preview_column(columns)
	columns.add_child(preview_column)
	var detail_column := _build_detail_column(columns)
	columns.add_child(detail_column)
	_wire_focus_neighbors()


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
	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "PreviewViewport"
	viewport_container.custom_minimum_size = Vector2(200, 260)
	viewport_container.stretch = true
	col.add_child(viewport_container)
	_preview_viewport = SubViewport.new()
	_preview_viewport.size = Vector2i(200, 260)
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.own_world_3d = true
	viewport_container.add_child(_preview_viewport)
	var stage := Node3D.new()
	stage.name = "PreviewStage"
	_preview_viewport.add_child(stage)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.1, 2.4)
	camera.rotation.x = deg_to_rad(-12.0)
	camera.current = true
	stage.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(35.0), 0.0)
	light.light_energy = 1.1
	stage.add_child(light)
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
	_name_input = LineEdit.new()
	_name_input.name = "NameInput"
	_name_input.placeholder_text = tr("CREATE_NAME_PLACEHOLDER")
	_name_input.max_length = NameValidatorScript.MAX_LENGTH
	_name_input.text_changed.connect(_on_name_changed)
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
	_random_name_button.custom_minimum_size = Vector2(0, 32)
	_name_column.add_child(_random_name_button)
	var appearance_box := VBoxContainer.new()
	appearance_box.name = "AppearanceRows"
	appearance_box.add_theme_constant_override("separation", 4)
	col.add_child(appearance_box)
	_aspect_row = _make_appearance_row(tr("CREATE_ROW_ASPECT"), [])
	appearance_box.add_child(_aspect_row)
	_stature_row = _make_appearance_row(
		tr("CREATE_ROW_STATURE"), CharacterAppearanceScript.HEIGHT_LABELS
	)
	appearance_box.add_child(_stature_row)
	_build_row = _make_appearance_row(
		tr("CREATE_ROW_BUILD"), CharacterAppearanceScript.BULK_LABELS
	)
	appearance_box.add_child(_build_row)
	_head_row = _make_appearance_row(
		tr("CREATE_ROW_HEAD"), CharacterAppearanceScript.HEAD_LABELS
	)
	appearance_box.add_child(_head_row)
	_trim_row = _make_appearance_row(
		tr("CREATE_ROW_TRIM"), CharacterAppearanceScript.TRIM_LABELS
	)
	appearance_box.add_child(_trim_row)
	var stats_card := PanelContainer.new()
	stats_card.name = "ClassStatsCard"
	col.add_child(stats_card)
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 3
	_stats_grid.add_theme_constant_override("h_separation", 8)
	_stats_grid.add_theme_constant_override("v_separation", 4)
	stats_card.add_child(_stats_grid)
	_perk_line = Label.new()
	_perk_line.name = "PerkLine"
	_perk_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(_perk_line)
	col.add_child(_perk_line)
	var weapon_row := HBoxContainer.new()
	weapon_row.name = "WeaponRow"
	weapon_row.add_theme_constant_override("separation", 8)
	col.add_child(weapon_row)
	_weapon_icon = TextureRect.new()
	_weapon_icon.name = "WeaponIcon"
	_weapon_icon.custom_minimum_size = Vector2(24, 24)
	_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	weapon_row.add_child(_weapon_icon)
	_weapon_line = Label.new()
	_weapon_line.name = "WeaponLine"
	_weapon_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameUISkinScript.style_body_label(_weapon_line)
	weapon_row.add_child(_weapon_line)
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
	_aspect_row.focus_neighbor_bottom = _stature_row.get_path()
	_stature_row.focus_neighbor_top = _aspect_row.get_path()
	_stature_row.focus_neighbor_bottom = _build_row.get_path()
	_build_row.focus_neighbor_top = _stature_row.get_path()
	_build_row.focus_neighbor_bottom = _head_row.get_path()
	_head_row.focus_neighbor_top = _build_row.get_path()
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
	_wire_focus_neighbors()


func _reload_aspect_options() -> void:
	var labels := PackedStringArray()
	for i in AppearanceCatalogScript.aspect_count():
		labels.append(AppearanceCatalogScript.label_for_index(i))
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
	_aspect_row.select(AppearanceCatalogScript.index_for_theme(int(clean.get("theme", 0))))
	_stature_row.select(
		CharacterAppearanceScript.HEIGHT_VARIANTS.find(clean.get("heightVariant", "standard"))
	)
	_build_row.select(
		CharacterAppearanceScript.BULK_VARIANTS.find(clean.get("bulkVariant", "standard"))
	)
	match clean.get("head", CharacterAppearanceScript.HEAD_VISOR):
		CharacterAppearanceScript.HEAD_OPEN:
			_head_row.select(0)
		CharacterAppearanceScript.HEAD_HOOD:
			_head_row.select(2)
		_:
			_head_row.select(1)
	_trim_row.select(int(clean.get("trim", 1)))


func _select_class_index(index: int) -> void:
	if index < 0 or index >= _class_cards.size():
		_selected_class_index = -1
		return
	_selected_class_index = index
	for i in _class_cards.size():
		_class_cards[i].button_pressed = i == index
		_class_cards[i].set_selected_mark(i == index)
	_initial_focus_card = _class_cards[index]
	_refresh_class_detail()


func _on_class_card_pressed(card: ClassCard) -> void:
	for i in _class_cards.size():
		if _class_cards[i] == card:
			_select_class_index(i)
			return


func _refresh_class_detail() -> void:
	if _selected_class_index < 0 or _selected_class_index >= _classes.size():
		_stats_grid.visible = false
		_perk_line.text = ""
		_weapon_line.text = ""
		_weapon_icon.texture = null
		_preview_caption.text = ""
		return
	var class_def := _classes[_selected_class_index]
	_populate_stats_grid(class_def)
	var perk_name_key := str(class_def.get("perkName", ""))
	var perk_desc_key := str(class_def.get("perkDescription", ""))
	_perk_line.text = "%s: %s" % [tr(perk_name_key), tr(perk_desc_key)]
	var weapon_id := str(class_def.get("startingWeaponItemId", ""))
	var weapon_def := ItemCatalog.get_definition(weapon_id)
	var weapon_name := str(weapon_def.get("name", weapon_id))
	_weapon_line.text = tr("CREATE_STARTING_WEAPON") % weapon_name
	_weapon_icon.texture = ItemIconAtlasScript.get_icon(
		weapon_id, str(weapon_def.get("iconPath", ""))
	)
	var aspect_label := AppearanceCatalogScript.label_for_index(_aspect_row.get_selected_index())
	_preview_caption.text = "%s — %s" % [str(class_def.get("name", "")), aspect_label]


func _populate_stats_grid(class_def: Dictionary) -> void:
	for child in _stats_grid.get_children():
		child.queue_free()
	_stats_grid.visible = true
	var bonuses: Dictionary = class_def.get("statBonuses", {})
	for stat_name in bonuses.keys():
		var name_label := Label.new()
		name_label.text = _format_stat_name(str(stat_name))
		GameUISkinScript.style_body_label(name_label)
		_stats_grid.add_child(name_label)
		var base_label := Label.new()
		base_label.text = _base_stat_value(str(stat_name))
		GameUISkinScript.style_stat_value(base_label)
		_stats_grid.add_child(base_label)
		var delta_label := Label.new()
		var delta := float(bonuses[stat_name])
		delta_label.text = "+%s" % _format_delta(delta, str(stat_name))
		GameUISkinScript.style_stat_delta(delta_label, delta >= 0.0)
		_stats_grid.add_child(delta_label)


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
		_:
			return stat_name


func _base_stat_value(stat_name: String) -> String:
	match stat_name:
		"maxHealth":
			return "100"
		"armor":
			return "0"
		"moveSpeed":
			return "100%"
		"critChance":
			return "5%"
		"physicalDamage":
			return "100%"
		"poiseDamage":
			return "100%"
		"staminaRegen":
			return "12/s"
		"staminaMax":
			return "100"
		"poise":
			return "50"
		"blockReduction":
			return "0%"
		_:
			return "—"


func _format_delta(delta: float, stat_name: String) -> String:
	if stat_name in ["moveSpeed", "critChance", "physicalDamage", "poiseDamage", "blockReduction"]:
		return "%d%%" % int(round(delta * 100.0))
	if stat_name == "staminaRegen":
		return "%.1f/s" % delta
	return str(int(round(delta)))


func _build_appearance_profile() -> Dictionary:
	return CharacterAppearanceScript.profile_from_indices(
		AppearanceCatalogScript.theme_for_index(_aspect_row.get_selected_index()),
		_stature_row.get_selected_index(),
		_build_row.get_selected_index(),
		_head_row.get_selected_index(),
		_trim_row.get_selected_index()
	)


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


func _on_randomize_pressed() -> void:
	_aspect_row.select(randi() % maxi(AppearanceCatalogScript.aspect_count(), 1))
	_stature_row.select(randi() % CharacterAppearanceScript.HEIGHT_LABELS.size())
	_build_row.select(randi() % CharacterAppearanceScript.BULK_LABELS.size())
	_head_row.select(randi() % CharacterAppearanceScript.HEAD_LABELS.size())
	_trim_row.select(randi() % CharacterAppearanceScript.TRIM_LABELS.size())
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
	if MenuStack.is_registered(self):
		return
	MenuStack.register(self, _on_back_pressed)


func _unregister_menu_stack() -> void:
	if MenuStack.is_registered(self):
		MenuStack.unregister(self)


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

extends Control

## Character creation — class, mandatory name, and full warden appearance.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const CharacterAppearanceScript := preload("res://scripts/save/character_appearance.gd")
const CharacterSkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")

signal completed(class_id: String, character_name: String, appearance: Dictionary)
signal cancelled
signal appearance_saved(appearance: Dictionary)

var _class_list: ItemList
var _name_input: LineEdit
var _name_error: Label
var _appearance_options: OptionButton
var _height_options: OptionButton
var _bulk_options: OptionButton
var _skin_options: OptionButton
var _hair_options: OptionButton
var _face_options: OptionButton
var _head_options: OptionButton
var _trim_options: OptionButton
var _preview_viewport: SubViewport
var _preview_stage: Node3D
var _preview_camera: Camera3D
var _preview_light: DirectionalLight3D
var _detail_label: Label
var _classes: Array[Dictionary] = []
var _edit_mode := false
var _class_row: Control
var _name_row: Control
var _preview_yaw := 0.0


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_reload_classes()


func _process(delta: float) -> void:
	if not visible or _preview_stage == null:
		return
	_preview_yaw += delta * 0.35
	_preview_stage.rotation.y = _preview_yaw


func _build_ui() -> void:
	var shell: Dictionary = MenuShellScript.build_modal(self, "Create Your Warden", 520.0, 500.0)
	var vbox: VBoxContainer = shell["content_vbox"]
	_class_row = VBoxContainer.new()
	_class_list = ItemList.new()
	_class_list.custom_minimum_size = Vector2(0, 120)
	_class_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_class_row.add_child(_class_list)
	vbox.add_child(_class_row)
	_name_row = VBoxContainer.new()
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Warden name (required)"
	_name_input.text_changed.connect(_on_name_changed)
	_name_row.add_child(_name_input)
	_name_error = Label.new()
	_name_error.text = "Name your warden before entering the tower."
	_name_error.visible = false
	GameUISkinScript.style_hint_label(_name_error)
	_name_error.add_theme_color_override("font_color", Color(0.95, 0.45, 0.35))
	_name_row.add_child(_name_error)
	vbox.add_child(_name_row)
	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 12)
	var preview_container := SubViewportContainer.new()
	preview_container.custom_minimum_size = Vector2(140, 200)
	preview_container.stretch = true
	_preview_viewport = SubViewport.new()
	_preview_viewport.size = Vector2i(140, 200)
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.own_world_3d = true
	preview_container.add_child(_preview_viewport)
	_preview_stage = Node3D.new()
	_preview_stage.name = "PreviewStage"
	_preview_viewport.add_child(_preview_stage)
	_preview_camera = Camera3D.new()
	_preview_camera.name = "PreviewCamera"
	_preview_camera.position = Vector3(0.0, 1.1, 2.4)
	_preview_camera.rotation.x = deg_to_rad(-12.0)
	_preview_camera.current = true
	_preview_stage.add_child(_preview_camera)
	_preview_light = DirectionalLight3D.new()
	_preview_light.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(35.0), 0.0)
	_preview_light.light_energy = 1.1
	_preview_stage.add_child(_preview_light)
	preview_row.add_child(preview_container)
	vbox.add_child(preview_row)
	_appearance_options = _add_option_row(vbox, "Aspect", 1)
	_appearance_options.item_selected.connect(_on_appearance_selected)
	_height_options = _add_option_row(
		vbox, "Stature", CharacterAppearanceScript.HEIGHT_LABELS.size()
	)
	_height_options.item_selected.connect(_on_appearance_selected)
	for i in CharacterAppearanceScript.HEIGHT_LABELS.size():
		_height_options.set_item_text(i, CharacterAppearanceScript.HEIGHT_LABELS[i])
	_bulk_options = _add_option_row(vbox, "Build", CharacterAppearanceScript.BULK_LABELS.size())
	_bulk_options.item_selected.connect(_on_appearance_selected)
	for i in CharacterAppearanceScript.BULK_LABELS.size():
		_bulk_options.set_item_text(i, CharacterAppearanceScript.BULK_LABELS[i])
	_skin_options = _add_option_row(vbox, "Skin", CharacterAppearanceScript.SKIN_TONE_LABELS.size())
	_skin_options.item_selected.connect(_on_appearance_selected)
	for i in CharacterAppearanceScript.SKIN_TONE_LABELS.size():
		_skin_options.set_item_text(i, CharacterAppearanceScript.SKIN_TONE_LABELS[i])
	_hair_options = _add_option_row(vbox, "Hair", CharacterAppearanceScript.HAIR_LABELS.size())
	_hair_options.item_selected.connect(_on_appearance_selected)
	for i in CharacterAppearanceScript.HAIR_LABELS.size():
		_hair_options.set_item_text(i, CharacterAppearanceScript.HAIR_LABELS[i])
	_face_options = _add_option_row(vbox, "Face", CharacterAppearanceScript.FACE_LABELS.size())
	_face_options.item_selected.connect(_on_appearance_selected)
	for i in CharacterAppearanceScript.FACE_LABELS.size():
		_face_options.set_item_text(i, CharacterAppearanceScript.FACE_LABELS[i])
	_head_options = _add_option_row(vbox, "Head", CharacterAppearanceScript.HEAD_LABELS.size())
	_head_options.item_selected.connect(_on_appearance_selected)
	for i in CharacterAppearanceScript.HEAD_LABELS.size():
		_head_options.set_item_text(i, CharacterAppearanceScript.HEAD_LABELS[i])
	_trim_options = _add_option_row(vbox, "Trim", CharacterAppearanceScript.TRIM_LABELS.size())
	_trim_options.item_selected.connect(_on_appearance_selected)
	for i in CharacterAppearanceScript.TRIM_LABELS.size():
		_trim_options.set_item_text(i, CharacterAppearanceScript.TRIM_LABELS[i])
	_detail_label = Label.new()
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(_detail_label)
	vbox.add_child(_detail_label)
	(
		MenuShellScript
		. add_button_row(
			vbox,
			[
				MenuShellScript.make_menu_button("Back", _on_back_pressed),
				MenuShellScript.make_menu_button("Begin", _on_confirm_pressed),
			]
		)
	)
	_class_list.item_selected.connect(_on_class_selected)


func _add_option_row(parent: VBoxContainer, label_text: String, count: int) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in count:
		option.add_item("?", i)
	row.add_child(option)
	parent.add_child(row)
	return option


func open_creation() -> void:
	_edit_mode = false
	_class_row.visible = true
	_name_row.visible = true
	GameUISkinScript.ensure_full_rect(self)
	_reload_classes()
	_reload_theme_options()
	visible = true
	_name_input.text = ""
	_name_error.visible = false
	if _class_list.item_count > 0:
		_class_list.select(0)
		_on_class_selected(0)
	if _appearance_options.item_count > 0:
		_appearance_options.select(0)
	_height_options.select(1)
	_bulk_options.select(1)
	_skin_options.select(1)
	_hair_options.select(0)
	_face_options.select(0)
	_head_options.select(1)
	_trim_options.select(1)
	_on_appearance_selected(0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func open_edit_mode() -> void:
	_edit_mode = true
	_class_row.visible = false
	_name_row.visible = false
	GameUISkinScript.ensure_full_rect(self)
	_reload_theme_options()
	visible = true
	var profile := LocalSave.get_appearance_profile()
	_apply_profile_to_controls(profile)
	_on_appearance_selected(0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_open() -> bool:
	return visible


func _reload_classes() -> void:
	_classes = ClassCatalog.get_all_classes()
	_class_list.clear()
	for class_def in _classes:
		_class_list.add_item(str(class_def.get("name", class_def.get("id", ""))))


func _reload_theme_options() -> void:
	_appearance_options.clear()
	var options := CharacterAppearanceScript.available_theme_options()
	for i in options.size():
		_appearance_options.add_item(str(options[i].get("label", "?")), i)
	_appearance_options.select(0)


func _apply_profile_to_controls(profile: Dictionary) -> void:
	var clean := CharacterAppearanceScript.sanitize(profile)
	var theme := int(clean.get("theme", 0))
	var options := CharacterAppearanceScript.available_theme_options()
	for i in options.size():
		if int(options[i].get("theme", -1)) == theme:
			_appearance_options.select(i)
			break
	_height_options.select(
		CharacterAppearanceScript.HEIGHT_VARIANTS.find(clean.get("heightVariant", "standard"))
	)
	_bulk_options.select(
		CharacterAppearanceScript.BULK_VARIANTS.find(clean.get("bulkVariant", "standard"))
	)
	_skin_options.select(
		CharacterAppearanceScript.SKIN_TONES.find(clean.get("skinTone", "neutral"))
	)
	_hair_options.select(CharacterAppearanceScript.HAIR_STYLES.find(clean.get("hair", "none")))
	_face_options.select(CharacterAppearanceScript.FACE_STYLES.find(clean.get("face", "open")))
	match clean.get("head", CharacterAppearanceScript.HEAD_VISOR):
		CharacterAppearanceScript.HEAD_OPEN:
			_head_options.select(0)
		CharacterAppearanceScript.HEAD_HOOD:
			_head_options.select(2)
		_:
			_head_options.select(1)
	_trim_options.select(int(clean.get("trim", 1)))


func _on_class_selected(index: int) -> void:
	if index < 0 or index >= _classes.size():
		_detail_label.text = ""
		return
	var class_def := _classes[index]
	_detail_label.text = (
		"%s\nStarting weapon: %s"
		% [
			class_def.get("description", ""),
			class_def.get("startingWeaponItemId", ""),
		]
	)


func _on_appearance_selected(_index: int = 0) -> void:
	_rebuild_preview()
	if _edit_mode:
		_detail_label.text = CharacterAppearanceScript.describe(_build_appearance_profile())


func _rebuild_preview() -> void:
	if _preview_stage == null:
		return
	CharacterSkinScript.build_preview_body(_preview_stage, _build_appearance_profile())


func _on_name_changed(_text: String) -> void:
	_name_error.visible = _name_input.text.strip_edges().length() < 2


func _selected_appearance_theme() -> int:
	var idx := _appearance_options.selected
	var options := CharacterAppearanceScript.available_theme_options()
	if idx < 0 or idx >= options.size():
		return PixelStyle.PaletteTheme.CASTLE
	return int(options[idx].get("theme", PixelStyle.PaletteTheme.CASTLE))


func _build_appearance_profile() -> Dictionary:
	return CharacterAppearanceScript.profile_from_indices(
		_selected_appearance_theme(),
		_height_options.selected,
		_bulk_options.selected,
		_head_options.selected,
		_trim_options.selected,
		_skin_options.selected,
		_hair_options.selected,
		_face_options.selected
	)


func _on_confirm_pressed() -> void:
	if _edit_mode:
		var profile := _build_appearance_profile()
		if LocalSave.set_appearance_profile(profile):
			visible = false
			appearance_saved.emit(profile)
		return
	var character_name := _name_input.text.strip_edges()
	if character_name.length() < 2:
		_name_error.visible = true
		return
	var index := _class_list.get_selected_items()
	if index.is_empty():
		return
	var class_def := _classes[index[0]]
	var class_id: String = str(class_def.get("id", ""))
	visible = false
	completed.emit(class_id, character_name, _build_appearance_profile())


func _on_back_pressed() -> void:
	visible = false
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()

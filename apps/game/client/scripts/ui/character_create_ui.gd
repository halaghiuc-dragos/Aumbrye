extends Control

## Character creation — class, mandatory name, and full warden appearance.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const CharacterAppearanceScript := preload("res://scripts/save/character_appearance.gd")

signal completed(class_id: String, character_name: String, appearance: Dictionary)
signal cancelled

const APPEARANCE_OPTIONS: Array[Dictionary] = [
	{"label": "Castle iron", "theme": PixelStyle.PaletteTheme.CASTLE},
	{"label": "Crystal frost", "theme": PixelStyle.PaletteTheme.CRYSTAL},
	{"label": "Umbral void", "theme": PixelStyle.PaletteTheme.UMBRAL},
	{"label": "Cathedral gold", "theme": PixelStyle.PaletteTheme.CATHEDRAL},
	{"label": "Hub ember", "theme": PixelStyle.PaletteTheme.HUB},
]

var _class_list: ItemList
var _name_input: LineEdit
var _name_error: Label
var _appearance_options: OptionButton
var _height_options: OptionButton
var _bulk_options: OptionButton
var _head_options: OptionButton
var _trim_options: OptionButton
var _preview_wrap: Control
var _preview_swatch: ColorRect
var _detail_label: Label
var _classes: Array[Dictionary] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_reload_classes()


func _build_ui() -> void:
	var shell: Dictionary = MenuShellScript.build_modal(self, "Create Your Warden", 520.0, 500.0)
	var vbox: VBoxContainer = shell["content_vbox"]
	_class_list = ItemList.new()
	_class_list.custom_minimum_size = Vector2(0, 120)
	_class_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_class_list)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Warden name (required)"
	_name_input.text_changed.connect(_on_name_changed)
	vbox.add_child(_name_input)
	_name_error = Label.new()
	_name_error.text = "Name your warden before entering the tower."
	_name_error.visible = false
	GameUISkinScript.style_hint_label(_name_error)
	_name_error.add_theme_color_override("font_color", Color(0.95, 0.45, 0.35))
	vbox.add_child(_name_error)
	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 12)
	_preview_wrap = Control.new()
	_preview_wrap.custom_minimum_size = Vector2(140, 200)
	GameUISkinScript.build_human_silhouette(_preview_wrap, 28, 4, 1.35)
	preview_row.add_child(_preview_wrap)
	_preview_swatch = ColorRect.new()
	_preview_swatch.custom_minimum_size = Vector2(48, 200)
	preview_row.add_child(_preview_swatch)
	vbox.add_child(preview_row)
	_appearance_options = _add_option_row(vbox, "Aspect", APPEARANCE_OPTIONS.size())
	for i in APPEARANCE_OPTIONS.size():
		_appearance_options.set_item_text(i, str(APPEARANCE_OPTIONS[i].get("label", "?")))
	_appearance_options.item_selected.connect(_on_appearance_selected)
	_height_options = _add_option_row(vbox, "Stature", CharacterAppearanceScript.HEIGHT_LABELS.size())
	_height_options.item_selected.connect(_on_appearance_selected)
	for i in CharacterAppearanceScript.HEIGHT_LABELS.size():
		_height_options.set_item_text(i, CharacterAppearanceScript.HEIGHT_LABELS[i])
	_bulk_options = _add_option_row(vbox, "Build", CharacterAppearanceScript.BULK_LABELS.size())
	_bulk_options.item_selected.connect(_on_appearance_selected)
	for i in CharacterAppearanceScript.BULK_LABELS.size():
		_bulk_options.set_item_text(i, CharacterAppearanceScript.BULK_LABELS[i])
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
	MenuShellScript.add_button_row(
		vbox,
		[
			MenuShellScript.make_menu_button("Back", _on_back_pressed),
			MenuShellScript.make_menu_button("Begin", _on_confirm_pressed),
		]
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
	GameUISkinScript.ensure_full_rect(self)
	_reload_classes()
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
	_head_options.select(1)
	_trim_options.select(1)
	_on_appearance_selected(0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_open() -> bool:
	return visible


func _reload_classes() -> void:
	_classes = ClassCatalog.get_all_classes()
	_class_list.clear()
	for class_def in _classes:
		_class_list.add_item(str(class_def.get("name", class_def.get("id", ""))))


func _on_class_selected(index: int) -> void:
	if index < 0 or index >= _classes.size():
		_detail_label.text = ""
		return
	var class_def := _classes[index]
	_detail_label.text = "%s\nStarting weapon: %s" % [
		class_def.get("description", ""),
		class_def.get("startingWeaponItemId", ""),
	]


func _on_appearance_selected(_index: int = 0) -> void:
	var palette_theme: int = _selected_appearance_theme()
	var palette := PixelStyle.get_palette(palette_theme)
	_preview_swatch.color = palette[PixelStyle.PaletteSlot.ACCENT]


func _on_name_changed(_text: String) -> void:
	_name_error.visible = _name_input.text.strip_edges().length() < 2


func _selected_appearance_theme() -> int:
	var idx := _appearance_options.selected
	if idx < 0 or idx >= APPEARANCE_OPTIONS.size():
		return PixelStyle.PaletteTheme.CASTLE
	return int(APPEARANCE_OPTIONS[idx].get("theme", PixelStyle.PaletteTheme.CASTLE))


func _build_appearance_profile() -> Dictionary:
	return CharacterAppearanceScript.profile_from_indices(
		_selected_appearance_theme(),
		_height_options.selected,
		_bulk_options.selected,
		_head_options.selected,
		_trim_options.selected
	)


func _on_confirm_pressed() -> void:
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

extends Control

## Character creation — class, name, and appearance before entering the hub.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")

signal completed(class_id: String, character_name: String, appearance_theme: int)
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
var _appearance_options: OptionButton
var _preview_swatch: ColorRect
var _detail_label: Label
var _classes: Array[Dictionary] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_reload_classes()


func _build_ui() -> void:
	var shell: Dictionary = MenuShellScript.build_modal(self, "Create Your Warden", 400.0, 360.0)
	var vbox: VBoxContainer = shell["content_vbox"]
	_class_list = ItemList.new()
	_class_list.custom_minimum_size = Vector2(0, 140)
	_class_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_class_list)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Warden name"
	vbox.add_child(_name_input)
	var appearance_row := HBoxContainer.new()
	appearance_row.add_theme_constant_override("separation", 10)
	var appearance_label := Label.new()
	appearance_label.text = "Aspect"
	appearance_row.add_child(appearance_label)
	_appearance_options = OptionButton.new()
	_appearance_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in APPEARANCE_OPTIONS.size():
		_appearance_options.add_item(str(APPEARANCE_OPTIONS[i].get("label", "?")), i)
	_appearance_options.item_selected.connect(_on_appearance_selected)
	appearance_row.add_child(_appearance_options)
	_preview_swatch = ColorRect.new()
	_preview_swatch.custom_minimum_size = Vector2(36, 28)
	appearance_row.add_child(_preview_swatch)
	vbox.add_child(appearance_row)
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


func open_creation() -> void:
	GameUISkinScript.ensure_full_rect(self)
	_reload_classes()
	visible = true
	_name_input.text = ""
	if _class_list.item_count > 0:
		_class_list.select(0)
		_on_class_selected(0)
	if _appearance_options.item_count > 0:
		_appearance_options.select(0)
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


func _on_appearance_selected(index: int) -> void:
	if index < 0 or index >= APPEARANCE_OPTIONS.size():
		return
	var palette_theme: int = int(APPEARANCE_OPTIONS[index].get("theme", PixelStyle.PaletteTheme.CASTLE))
	var palette := PixelStyle.get_palette(palette_theme)
	_preview_swatch.color = palette[PixelStyle.PaletteSlot.ACCENT]


func _selected_appearance_theme() -> int:
	var idx := _appearance_options.selected
	if idx < 0 or idx >= APPEARANCE_OPTIONS.size():
		return PixelStyle.PaletteTheme.CASTLE
	return int(APPEARANCE_OPTIONS[idx].get("theme", PixelStyle.PaletteTheme.CASTLE))


func _on_confirm_pressed() -> void:
	var index := _class_list.get_selected_items()
	if index.is_empty():
		return
	var class_def := _classes[index[0]]
	var class_id: String = str(class_def.get("id", ""))
	var character_name := _name_input.text.strip_edges()
	if character_name == "":
		character_name = str(class_def.get("name", "Warden"))
	visible = false
	completed.emit(class_id, character_name, _selected_appearance_theme())


func _on_back_pressed() -> void:
	visible = false
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()

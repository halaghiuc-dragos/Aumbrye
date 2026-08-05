class_name GameUISkin
extends RefCounted

## Global modal menu styling — inventory, settings, talents, hub portals.

const BACKDROP_COLOR := Color(0.01, 0.01, 0.04, 0.78)

const PANEL_HALF_W := 580.0
const PANEL_HALF_H := 360.0
const SETTINGS_HALF_W := 340.0
const SETTINGS_HALF_H := 300.0
const MENU_HALF_W := 260.0
const MENU_HALF_H := 150.0

const PANEL_MARGIN := 18
const SECTION_SEPARATION := 22
const GRID_GAP := 4

const HEADER_FONT_SIZE := 16
const TITLE_FONT_SIZE := 22
const TITLE_COLOR := Color(0.92, 0.86, 0.72)
const BODY_COLOR := Color(0.82, 0.78, 0.72)
const HINT_COLOR := Color(0.68, 0.68, 0.74)
const HINT_FONT_SIZE := 12
const ACCENT_BAR := Color(0.72, 0.58, 0.32, 0.9)
const FRAME_BG := Color(0.06, 0.06, 0.09, 0.97)
const FRAME_BORDER := Color(0.42, 0.36, 0.28)
const SILHOUETTE_COLOR := Color(0.14, 0.13, 0.17, 0.55)

const CELL_SIZE := 56
const EQUIP_CELL_SIZE := 64

const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")


static func make_backdrop(parent: Control, name: String = "Backdrop") -> ColorRect:
	var backdrop := ColorRect.new()
	backdrop.name = name
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = BACKDROP_COLOR
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(backdrop)
	backdrop.show_behind_parent = true
	return backdrop


static func make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = FRAME_BG
	style.border_color = FRAME_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(PANEL_MARGIN)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 8
	return style


static func style_panel(panel: PanelContainer) -> void:
	panel.add_theme_stylebox_override("panel", make_panel_style())


static func ensure_full_rect(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func clamped_panel_half_size(half_w: float, half_h: float, parent: Control) -> Vector2:
	var viewport_size := parent.get_viewport().get_visible_rect().size
	return Vector2(
		minf(half_w, viewport_size.x * 0.48),
		minf(half_h, viewport_size.y * 0.48)
	)


static func make_center_panel(
	parent: Control,
	half_w: float = PANEL_HALF_W,
	half_h: float = PANEL_HALF_H,
	panel_name: String = "Panel"
) -> PanelContainer:
	var clamped := clamped_panel_half_size(half_w, half_h, parent)
	half_w = clamped.x
	half_h = clamped.y
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -half_w
	panel.offset_top = -half_h
	panel.offset_right = half_w
	panel.offset_bottom = half_h
	style_panel(panel)
	parent.add_child(panel)
	return panel


static func make_section_frame(title: String) -> PanelContainer:
	var frame := PanelContainer.new()
	style_panel(frame)
	var margin := MarginContainer.new()
	frame.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)
	var header_row := HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header_row)
	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(36, 3)
	accent.color = ACCENT_BAR
	header_row.add_child(accent)
	var header := Label.new()
	header.text = title.to_upper()
	style_section_title(header)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header)
	var accent_r := ColorRect.new()
	accent_r.custom_minimum_size = Vector2(36, 3)
	accent_r.color = ACCENT_BAR
	header_row.add_child(accent_r)
	frame.set_meta("content_vbox", vbox)
	return frame


static func section_content(frame: PanelContainer) -> VBoxContainer:
	return frame.get_meta("content_vbox") as VBoxContainer


static func style_section_title(label: Label, text: String = "") -> void:
	if text != "":
		label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	label.add_theme_color_override("font_color", TITLE_COLOR)


static func style_menu_title(label: Label, text: String = "") -> void:
	if text != "":
		label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	label.add_theme_color_override("font_color", TITLE_COLOR)


static func style_body_label(label: Label) -> void:
	label.add_theme_color_override("font_color", BODY_COLOR)
	label.add_theme_font_size_override("font_size", 14)


static func style_hint_label(label: Label) -> void:
	label.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	label.add_theme_color_override("font_color", HINT_COLOR)


static func ensure_backdrop(root: Control) -> ColorRect:
	var backdrop := root.get_node_or_null("Backdrop") as ColorRect
	if backdrop == null:
		backdrop = root.get_node_or_null("Dimmer") as ColorRect
	if backdrop == null:
		backdrop = make_backdrop(root)
		backdrop.name = "Backdrop"
		root.move_child(backdrop, 0)
	else:
		backdrop.color = BACKDROP_COLOR
		backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	return backdrop


static func apply_modal_menu(
	root: Control,
	panel_path: String = "MainPanel",
	dimmer_path: String = "Dimmer",
	fallback_panel_path: String = "Panel"
) -> void:
	ensure_backdrop(root)
	var dimmer := root.get_node_or_null(dimmer_path) as ColorRect
	if dimmer:
		dimmer.color = BACKDROP_COLOR
	var panel := root.get_node_or_null(panel_path) as PanelContainer
	if panel == null:
		panel = root.get_node_or_null(fallback_panel_path) as PanelContainer
	if panel:
		style_panel(panel)
	for child in root.find_children("*", "Label", true, false):
		var label := child as Label
		if label == null:
			continue
		if label.name.to_lower().contains("title"):
			style_menu_title(label)
		elif label.name.to_lower().contains("hint"):
			style_hint_label(label)
		elif label.name.to_lower().contains("status"):
			style_body_label(label)


static func build_human_silhouette(parent: Control, cell_size: int, gap: int) -> void:
	var layer := Control.new()
	layer.name = "Silhouette"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(layer)
	layer.show_behind_parent = true
	var col_w := float(cell_size + gap)
	var row_h := float(cell_size + gap)
	var center_x := col_w * 1.5
	var add_part := func(size: Vector2, pos: Vector2) -> void:
		var part := ColorRect.new()
		part.color = SILHOUETTE_COLOR
		part.custom_minimum_size = size
		part.size = size
		part.position = pos
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(part)
	add_part.call(Vector2(cell_size * 0.72, cell_size * 0.72), Vector2(center_x - cell_size * 0.36, row_h * 0.15))
	add_part.call(Vector2(cell_size * 1.05, cell_size * 1.35), Vector2(center_x - cell_size * 0.52, row_h * 1.05))
	add_part.call(Vector2(cell_size * 0.42, cell_size * 1.05), Vector2(center_x - cell_size * 1.12, row_h * 1.1))
	add_part.call(Vector2(cell_size * 0.42, cell_size * 1.05), Vector2(center_x + cell_size * 0.7, row_h * 1.1))
	add_part.call(Vector2(cell_size * 0.38, cell_size * 1.2), Vector2(center_x - cell_size * 0.62, row_h * 2.35))
	add_part.call(Vector2(cell_size * 0.38, cell_size * 1.2), Vector2(center_x + cell_size * 0.24, row_h * 2.35))


static func wire_button_sfx(button: BaseButton) -> void:
	if button.has_meta(&"ui_sfx_wired"):
		return
	button.set_meta(&"ui_sfx_wired", true)
	button.pressed.connect(func() -> void:
		if AudioDirector:
			AudioDirector.play_ui_sfx()
	)


static func make_item_cell_style(rarity: String, filled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = RarityRegistryScript.slot_background_color(rarity)
	style.border_color = RarityRegistryScript.display_color(rarity)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.shadow_color = RarityRegistryScript.display_color(rarity) * Color(1, 1, 1, 0.35)
	style.shadow_size = 3 if filled else 0
	return style

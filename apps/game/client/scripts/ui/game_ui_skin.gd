class_name GameUISkin
extends RefCounted

## Global modal menu styling — inventory, settings, talents, hub portals.

const THEME_PATH := "res://assets/ui/aumbrye_ui.tres"
const FONT_PATH := "res://assets/ui/fonts/aumbrye_pixel.ttf"
const PAPERDOLL_TEXTURE_PATH := "res://assets/ui/paperdoll_silhouette.png"

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

const FONT_SIZE_TITLE := 22
const FONT_SIZE_HEADER := 16
const FONT_SIZE_BODY := 14
const FONT_SIZE_SMALL := 12
const FONT_SIZE_MICRO := 10

const HEADER_FONT_SIZE := FONT_SIZE_HEADER
const TITLE_FONT_SIZE := FONT_SIZE_TITLE
const HINT_FONT_SIZE := FONT_SIZE_SMALL
const TITLE_COLOR := Color(0.92, 0.86, 0.72)
const BODY_COLOR := Color(0.82, 0.78, 0.72)
const HINT_COLOR := Color(0.68, 0.68, 0.74)
const DANGER_COLOR := Color(0.95, 0.45, 0.35)
const STAT_DELTA_POSITIVE := Color(0.65, 0.9, 0.65)
const STAT_DELTA_NEGATIVE := Color(0.95, 0.45, 0.45)
const ACCENT_BAR := Color(0.72, 0.58, 0.32, 0.9)
const FRAME_BG := Color(0.06, 0.06, 0.09, 0.97)
const FRAME_BORDER := Color(0.42, 0.36, 0.28)

const PANEL_CORNER_RADIUS_HD := 8
const PANEL_CORNER_RADIUS_PIXEL := 0
const PANEL_SHADOW_SIZE_HD := 8
const PANEL_SHADOW_SIZE_PIXEL := 0
const PANEL_BORDER_WIDTH := 2
const FOCUS_RING_COLOR := Color(0.95, 0.82, 0.40)

const INVENTORY_PANEL_HALF_W := 720.0
const INVENTORY_PANEL_HALF_H := 480.0
const INVENTORY_CELL_SIZE := 64
const INVENTORY_EQUIP_CELL_SIZE := 82

const VAR_MENU_TITLE := &"MenuTitle"
const VAR_SECTION_TITLE := &"SectionTitle"
const VAR_BODY_TEXT := &"BodyText"
const VAR_HINT_TEXT := &"HintText"
const VAR_STAT_VALUE := &"StatValue"
const VAR_STAT_DELTA := &"StatDelta"
const VAR_DANGER_TEXT := &"DangerText"

const LABEL_VARIATIONS: PackedStringArray = [
	VAR_MENU_TITLE,
	VAR_SECTION_TITLE,
	VAR_BODY_TEXT,
	VAR_HINT_TEXT,
	VAR_STAT_VALUE,
	VAR_STAT_DELTA,
	VAR_DANGER_TEXT,
]

const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const PixelDioramaSettingsScript := preload("res://scripts/art/pipeline/pixel_diorama_settings.gd")

const PIXEL_BAR_STEPS := 8


static func make_backdrop(parent: Control, name: String = "Backdrop") -> ColorRect:
	var backdrop := ColorRect.new()
	backdrop.name = name
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = BACKDROP_COLOR
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(backdrop)
	backdrop.show_behind_parent = true
	return backdrop


static func _panel_corner_radius() -> int:
	return PANEL_CORNER_RADIUS_PIXEL if is_pixel_ui() else PANEL_CORNER_RADIUS_HD


static func _panel_shadow_size() -> int:
	return PANEL_SHADOW_SIZE_PIXEL if is_pixel_ui() else PANEL_SHADOW_SIZE_HD


static func make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = FRAME_BG
	style.border_color = FRAME_BORDER
	style.set_border_width_all(PANEL_BORDER_WIDTH)
	style.set_corner_radius_all(_panel_corner_radius())
	style.set_content_margin_all(PANEL_MARGIN)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = _panel_shadow_size()
	return style


static func make_button_style(state: StringName) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var radius := _panel_corner_radius()
	style.set_corner_radius_all(radius)
	style.set_border_width_all(PANEL_BORDER_WIDTH)
	style.border_color = FRAME_BORDER
	style.set_content_margin_all(8)
	match state:
		&"hover":
			style.bg_color = FRAME_BG.lightened(0.12)
		&"pressed":
			style.bg_color = FRAME_BG.darkened(0.08)
			style.border_color = ACCENT_BAR
		&"disabled":
			style.bg_color = FRAME_BG.darkened(0.2)
			style.border_color = FRAME_BORDER.darkened(0.25)
		&"focus":
			style.bg_color = Color(FRAME_BG.r, FRAME_BG.g, FRAME_BG.b, 0.0)
			style.border_color = FOCUS_RING_COLOR
			style.set_border_width_all(2)
		_:
			style.bg_color = FRAME_BG
	return style


static func make_list_style(state: StringName) -> StyleBoxFlat:
	var style := make_panel_style()
	match state:
		&"selected":
			style.bg_color = FRAME_BG.lightened(0.1)
			style.border_color = ACCENT_BAR
		&"focus":
			style.bg_color = Color(FRAME_BG.r, FRAME_BG.g, FRAME_BG.b, 0.0)
			style.border_color = FOCUS_RING_COLOR
			style.shadow_size = 0
		&"cursor":
			style.bg_color = FRAME_BG.lightened(0.06)
		_:
			pass
	return style


static func make_focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = FOCUS_RING_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(_panel_corner_radius())
	style.shadow_size = 0
	return style


static func make_line_edit_style() -> StyleBoxFlat:
	var style := make_panel_style()
	style.set_content_margin_all(6)
	return style


static func make_checkbox_style() -> StyleBoxFlat:
	return make_button_style(&"normal")


static func make_slider_style(part: StringName) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var radius := _panel_corner_radius()
	style.set_corner_radius_all(radius)
	if part == &"grabber_area":
		style.bg_color = FRAME_BG.darkened(0.05)
		style.border_color = FRAME_BORDER
		style.set_border_width_all(1)
	elif part == &"grabber":
		style.bg_color = ACCENT_BAR
		style.set_corner_radius_all(radius)
	else:
		style.bg_color = FRAME_BG
		style.border_color = FRAME_BORDER
		style.set_border_width_all(1)
	return style


static func style_panel(panel: PanelContainer) -> void:
	panel.add_theme_stylebox_override("panel", make_panel_style())


static func ensure_full_rect(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func clamped_panel_half_size(half_w: float, half_h: float, parent: Control) -> Vector2:
	var text_scale := 1.0
	if Engine.get_main_loop() is SceneTree:
		var tree := Engine.get_main_loop() as SceneTree
		var display_service := tree.root.get_node_or_null("DisplayService")
		if display_service and "ui_text_scale" in display_service:
			text_scale = float(display_service.get("ui_text_scale"))
	half_w *= text_scale
	half_h *= text_scale
	var viewport := parent.get_viewport()
	if viewport == null:
		return Vector2(half_w, half_h)
	var viewport_size := viewport.get_visible_rect().size
	return Vector2(minf(half_w, viewport_size.x * 0.48), minf(half_h, viewport_size.y * 0.48))


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


static func _apply_label_variation(label: Label, variation: StringName) -> void:
	label.theme_type_variation = variation
	if variation == VAR_BODY_TEXT or variation == VAR_DANGER_TEXT:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.clip_text = true
	if variation == VAR_HINT_TEXT or variation == VAR_MENU_TITLE or variation == VAR_SECTION_TITLE:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if variation == VAR_HINT_TEXT:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


static func style_section_title(label: Label, text: String = "") -> void:
	if text != "":
		label.text = text
	_apply_label_variation(label, VAR_SECTION_TITLE)


static func style_menu_title(label: Label, text: String = "") -> void:
	if text != "":
		label.text = text
	_apply_label_variation(label, VAR_MENU_TITLE)


static func style_body_label(label: Label) -> void:
	_apply_label_variation(label, VAR_BODY_TEXT)


static func style_hint_label(label: Label) -> void:
	_apply_label_variation(label, VAR_HINT_TEXT)


static func make_symbol_caption_row(glyph: String, caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "HintRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	var glyph_label := Label.new()
	glyph_label.text = glyph
	style_section_title(glyph_label)
	row.add_child(glyph_label)
	var cap := Label.new()
	cap.text = caption
	style_hint_label(cap)
	row.add_child(cap)
	return row


static func style_stat_value(label: Label) -> void:
	_apply_label_variation(label, VAR_STAT_VALUE)


static func style_stat_delta(label: Label, positive: bool = true) -> void:
	_apply_label_variation(label, VAR_STAT_DELTA)
	label.add_theme_color_override(
		"font_color", STAT_DELTA_POSITIVE if positive else STAT_DELTA_NEGATIVE
	)


static func style_danger_text(label: Label) -> void:
	_apply_label_variation(label, VAR_DANGER_TEXT)


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
	apply_pixel_theme(root)
	var dimmer := root.get_node_or_null(dimmer_path) as ColorRect
	if dimmer:
		dimmer.color = BACKDROP_COLOR
	var panel := root.get_node_or_null(panel_path) as PanelContainer
	if panel == null:
		panel = root.get_node_or_null(fallback_panel_path) as PanelContainer
	if panel:
		style_panel(panel)
	for child in root.find_children("*", "BaseButton", true, false):
		var button := child as BaseButton
		if button:
			wire_button_sfx(button)


static func build_paperdoll_backdrop(parent: Control, cell_size: int, gap: int) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = "PaperdollBackdrop"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.show_behind_parent = true
	if ResourceLoader.exists(PAPERDOLL_TEXTURE_PATH):
		rect.texture = load(PAPERDOLL_TEXTURE_PATH) as Texture2D
		parent.add_child(rect)
	else:
		push_warning("GameUISkin: missing %s — paperdoll backdrop skipped" % PAPERDOLL_TEXTURE_PATH)
	return rect


static func make_button(text: String, variation: StringName = &"") -> Button:
	var btn := Button.new()
	btn.text = text
	if variation != &"":
		btn.theme_type_variation = variation
	wire_button_sfx(btn)
	return btn


static func wire_button_sfx(button: BaseButton) -> void:
	if button.has_meta(&"ui_sfx_wired"):
		return
	button.set_meta(&"ui_sfx_wired", true)
	button.pressed.connect(
		func() -> void:
			var loop := Engine.get_main_loop()
			if loop == null or loop.root == null:
				return
			var audio := loop.root.get_node_or_null("AudioDirector") as Node
			if audio and audio.has_method("play_ui_sfx"):
				audio.play_ui_sfx()
	)


static func is_pixel_ui() -> bool:
	if PixelDioramaSettingsScript.is_native_hd_preset():
		return false
	return PixelDioramaSettingsScript.low_res_viewport_enabled


static func apply_pixel_theme(root: Control) -> void:
	var native_hd := PixelDioramaSettingsScript.is_native_hd_preset()
	if not is_pixel_ui() and not native_hd:
		return
	if not is_pixel_ui():
		root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		return
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var label_type := &"Label"
	for child in root.find_children("*", label_type):
		var label := child as Label
		if label:
			label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var button_type := &"Button"
	for child in root.find_children("*", button_type):
		var button := child as BaseButton
		if button:
			button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var bar_type := &"ProgressBar"
	for child in root.find_children("*", bar_type):
		var bar := child as ProgressBar
		if bar:
			bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# TextureRect carries the actual sprite art — icons, portraits, HUD symbols. Leaving it on the
	# default filter is what makes pixel icons read as soft next to crisp text and panels.
	var texture_rect_type := &"TextureRect"
	for child in root.find_children("*", texture_rect_type):
		var rect := child as TextureRect
		if rect:
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var nine_patch_type := &"NinePatchRect"
	for child in root.find_children("*", nine_patch_type):
		var patch := child as NinePatchRect
		if patch:
			patch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


static func restyle_tree(root: Control) -> void:
	if root == null:
		return
	apply_pixel_theme(root)
	for child in root.find_children("*", "PanelContainer", true, false):
		var panel := child as PanelContainer
		if panel:
			style_panel(panel)


static func hub_palette_color(slot: int) -> Color:
	return PixelStyle.get_palette_color(PixelStyle.PaletteTheme.HUB, slot)


static func _register_label_variation(
	theme: Theme,
	variation: StringName,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	theme.set_type_variation(variation, "Label")
	theme.set_font_size("font_size", variation, font_size)
	theme.set_color("font_color", variation, color)
	if alignment != HORIZONTAL_ALIGNMENT_LEFT:
		theme.set_constant("align", variation, alignment)


static func build_theme() -> Theme:
	var theme := Theme.new()
	var font: Font = null
	if ResourceLoader.exists(FONT_PATH):
		font = load(FONT_PATH) as Font
	if font:
		theme.default_font = font
	theme.default_font_size = FONT_SIZE_BODY

	var panel_style := make_panel_style()
	theme.set_stylebox("panel", "Panel", panel_style)
	theme.set_stylebox("panel", "PanelContainer", panel_style.duplicate())

	theme.set_color("font_color", "Label", BODY_COLOR)
	theme.set_font_size("font_size", "Label", FONT_SIZE_BODY)

	_register_label_variation(theme, VAR_MENU_TITLE, FONT_SIZE_TITLE, TITLE_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_register_label_variation(theme, VAR_SECTION_TITLE, FONT_SIZE_HEADER, TITLE_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_register_label_variation(theme, VAR_BODY_TEXT, FONT_SIZE_BODY, BODY_COLOR)
	_register_label_variation(theme, VAR_HINT_TEXT, FONT_SIZE_SMALL, HINT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_register_label_variation(theme, VAR_STAT_VALUE, FONT_SIZE_BODY, TITLE_COLOR)
	_register_label_variation(theme, VAR_STAT_DELTA, FONT_SIZE_SMALL, STAT_DELTA_POSITIVE)
	_register_label_variation(theme, VAR_DANGER_TEXT, FONT_SIZE_SMALL, DANGER_COLOR)

	for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		theme.set_stylebox(state, "Button", make_button_style(state))

	theme.set_color("font_color", "Button", BODY_COLOR)
	theme.set_color("font_hover_color", "Button", TITLE_COLOR)
	theme.set_color("font_disabled_color", "Button", BODY_COLOR.darkened(0.45))

	for state in [&"panel", &"selected", &"focus", &"cursor"]:
		theme.set_stylebox(state, "ItemList", make_list_style(state))

	for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		theme.set_stylebox(state, "OptionButton", make_button_style(state))
	theme.set_color("font_color", "OptionButton", BODY_COLOR)
	theme.set_color("font_hover_color", "OptionButton", TITLE_COLOR)
	theme.set_color("font_disabled_color", "OptionButton", BODY_COLOR.darkened(0.45))

	theme.set_stylebox("normal", "CheckBox", make_checkbox_style())
	theme.set_stylebox("focus", "CheckBox", make_focus_style())
	theme.set_color("font_color", "CheckBox", BODY_COLOR)

	theme.set_stylebox("slider", "HSlider", make_slider_style(&"slider"))
	theme.set_stylebox("grabber_area", "HSlider", make_slider_style(&"grabber_area"))
	theme.set_stylebox("grabber_area_highlight", "HSlider", make_slider_style(&"grabber_area"))
	theme.set_stylebox("grabber", "HSlider", make_slider_style(&"grabber"))

	theme.set_stylebox("normal", "LineEdit", make_line_edit_style())
	theme.set_stylebox("focus", "LineEdit", make_focus_style())
	theme.set_color("font_color", "LineEdit", BODY_COLOR)
	theme.set_color("font_placeholder_color", "LineEdit", HINT_COLOR)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = FRAME_BG.darkened(0.05)
	bar_bg.border_color = FRAME_BORDER
	bar_bg.set_border_width_all(PANEL_BORDER_WIDTH)
	bar_bg.set_corner_radius_all(_panel_corner_radius())
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = ACCENT_BAR
	bar_fill.set_corner_radius_all(maxi(0, _panel_corner_radius() - 1))
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)

	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = FRAME_BG.darkened(0.08)
	scroll_bg.set_corner_radius_all(_panel_corner_radius())
	theme.set_stylebox("panel", "ScrollContainer", scroll_bg)

	return theme


static var _base_theme: Theme = null


static func get_base_theme() -> Theme:
	if _base_theme != null:
		return _base_theme
	if ResourceLoader.exists(THEME_PATH):
		_base_theme = load(THEME_PATH) as Theme
	else:
		_base_theme = build_theme()
	return _base_theme


static func build_scaled_theme(scale: float) -> Theme:
	var base := get_base_theme()
	if is_equal_approx(scale, 1.0):
		return base
	var scaled := base.duplicate(true)
	_scale_theme_font_sizes(scaled, base, scale)
	return scaled


static func _scale_theme_font_sizes(scaled: Theme, base: Theme, scale: float) -> void:
	var default_size := base.get_font_size(&"font_size", &"Label")
	if default_size > 0:
		scaled.default_font_size = maxi(1, int(round(float(default_size) * scale)))
	for variation in LABEL_VARIATIONS:
		var size := base.get_font_size(&"font_size", variation)
		if size > 0:
			scaled.set_font_size(&"font_size", variation, maxi(1, int(round(float(size) * scale))))
	for control_type in [&"Button", &"OptionButton", &"CheckBox", &"LineEdit"]:
		var size := base.get_font_size(&"font_size", control_type)
		if size > 0:
			scaled.set_font_size(
				&"font_size", control_type, maxi(1, int(round(float(size) * scale)))
			)


static func style_progress_bar(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	bar.show_percentage = false
	var pixel := is_pixel_ui()
	var radius := 0 if pixel else 4
	var inner_radius := 0 if pixel else 3
	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_color
	bg.border_color = FRAME_BORDER
	bg.set_border_width_all(2 if pixel else 1)
	bg.set_corner_radius_all(radius)
	bg.set_content_margin_all(2 if pixel else 2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(inner_radius)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	if pixel:
		bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var steps := maxi(2, PIXEL_BAR_STEPS)
		if bar.max_value > 0.0:
			bar.step = bar.max_value / float(steps)


## One authored pixel unit for UI. Every frame border, inset and gap in the pixel layouts is
## a whole multiple of this, so the screens quantise to the same grid the world does.
const PIXEL_UNIT := 2
const FRAME_OUTER := Color(0.02, 0.02, 0.03, 0.98)
const FRAME_INNER := Color(0.09, 0.08, 0.11, 0.98)
const FRAME_BEVEL_LIGHT := Color(0.34, 0.29, 0.22)
const FRAME_BEVEL_DARK := Color(0.02, 0.02, 0.03)
const LADDER_LOCKED := Color(0.30, 0.29, 0.31)
const LADDER_CLEARED := Color(0.62, 0.78, 0.58)
const LADDER_CURRENT := Color(0.95, 0.82, 0.40)


## Hard-edged frame with no corner rounding and no drop shadow: the pixel-art equivalent of
## a nine-slice. `depth` multiplies the border weight in whole pixel units.
static func make_pixel_frame_style(
	fill: Color = FRAME_INNER, border: Color = FRAME_BEVEL_LIGHT, depth: int = 1
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(PIXEL_UNIT * maxi(depth, 1))
	style.set_corner_radius_all(0)
	style.set_content_margin_all(PIXEL_UNIT * 3)
	style.shadow_size = 0
	style.anti_aliasing = false
	return style


## Two nested hard frames — an outer black keyline and an inner bevel — which is what makes a
## panel read as authored pixel art rather than as a rounded control container. Returns the
## outer PanelContainer; use `pixel_frame_content()` for the VBox to fill.
static func make_pixel_frame(title: String = "") -> PanelContainer:
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override(
		"panel", make_pixel_frame_style(FRAME_OUTER, FRAME_BEVEL_DARK, 1)
	)
	outer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var inner := PanelContainer.new()
	inner.add_theme_stylebox_override(
		"panel", make_pixel_frame_style(FRAME_INNER, FRAME_BEVEL_LIGHT, 1)
	)
	outer.add_child(inner)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", PIXEL_UNIT * 3)
	inner.add_child(vbox)
	if title != "":
		var header := Label.new()
		header.text = title.to_upper()
		style_section_title(header)
		vbox.add_child(header)
		var rule := ColorRect.new()
		rule.color = FRAME_BEVEL_LIGHT
		rule.custom_minimum_size = Vector2(0, PIXEL_UNIT)
		vbox.add_child(rule)
	outer.set_meta("content_vbox", vbox)
	return outer


static func pixel_frame_content(frame: PanelContainer) -> VBoxContainer:
	return frame.get_meta("content_vbox") as VBoxContainer


## Thin quantised meter used for status build-up. Unlike the resource bars it has no label and
## snaps its fill to whole pixel steps so a rising meter ticks rather than creeps.
static func make_meter_bar(fill_color: Color, width_px: int = 96) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	bar.custom_minimum_size = Vector2(width_px, PIXEL_UNIT * 3)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := make_pixel_frame_style(Color(0.05, 0.05, 0.07, 0.9), FRAME_BEVEL_DARK, 1)
	bg.set_content_margin_all(PIXEL_UNIT * 0.5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(0)
	fill.anti_aliasing = false
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bar.step = 1.0 / float(maxi(2, PIXEL_BAR_STEPS * 2))
	return bar


## Styles one rung of the difficulty ladder in place. The rung stays a Button so focus, toggle
## and controller navigation keep working; only the look becomes an authored pixel plate whose
## border colour carries the tier state.
static func style_ladder_button(button: Button, state: StringName) -> void:
	if button == null:
		return
	var border := LADDER_LOCKED
	var fill := Color(0.05, 0.05, 0.07, 0.95)
	var text_color := LADDER_LOCKED
	match state:
		&"cleared":
			border = LADDER_CLEARED
			text_color = LADDER_CLEARED
		&"available":
			border = FRAME_BEVEL_LIGHT
			text_color = BODY_COLOR
		_:
			pass
	var normal := make_pixel_frame_style(fill, border, 1)
	var hover := make_pixel_frame_style(fill.lightened(0.10), LADDER_CURRENT, 1)
	var pressed := make_pixel_frame_style(Color(0.11, 0.09, 0.05, 0.97), LADDER_CURRENT, 1)
	var disabled := make_pixel_frame_style(Color(0.04, 0.04, 0.05, 0.9), LADDER_LOCKED, 1)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.add_theme_stylebox_override("focus", make_focus_style())
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", LADDER_CURRENT)
	button.add_theme_color_override("font_pressed_color", LADDER_CURRENT)
	button.add_theme_color_override("font_disabled_color", LADDER_LOCKED)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


static func make_item_cell_style(rarity: String, filled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = RarityRegistryScript.slot_background_color(rarity)
	style.border_color = RarityRegistryScript.display_color(rarity)
	if is_pixel_ui():
		style.set_border_width_all(PIXEL_UNIT)
		style.set_corner_radius_all(0)
		style.anti_aliasing = false
		style.shadow_size = 0
		if filled:
			style.set_expand_margin_all(PIXEL_UNIT)
		return style
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.shadow_color = RarityRegistryScript.display_color(rarity) * Color(1, 1, 1, 0.35)
	style.shadow_size = 3 if filled else 0
	return style


static func make_symbol_rect(tex: Texture2D, size_px: int = 16) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tex
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2i(size_px, size_px)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func make_symbol_icon_caption_row(tex: AtlasTexture, caption: String, size_px: int = 16) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	row.add_child(make_symbol_rect(tex, size_px))
	var label := Label.new()
	label.text = caption
	label.theme_type_variation = VAR_HINT_TEXT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return row


static func make_symbol_badge(tex: AtlasTexture, stacks: int, ratio: float, size_px: int = 16) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(size_px + 4, size_px + 8)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var arc := TextureProgressBar.new()
	arc.name = "DurationArc"
	arc.custom_minimum_size = Vector2(size_px + 4, size_px + 4)
	arc.max_value = 1.0
	arc.value = clampf(ratio, 0.0, 1.0)
	arc.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	arc.show_percentage = false
	arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(arc)
	var icon := make_symbol_rect(tex, size_px)
	icon.name = "Icon"
	root.add_child(icon)
	var stack_label := Label.new()
	stack_label.name = "StackLabel"
	stack_label.theme_type_variation = VAR_BODY_TEXT
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	stack_label.offset_left = size_px - 6
	stack_label.offset_top = size_px - 4
	stack_label.custom_minimum_size = Vector2(size_px, 12)
	stack_label.visible = stacks > 1
	stack_label.text = "x%d" % stacks
	stack_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stack_label)
	return root

extends Control
class_name TitleWordmark


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

const GLYPH_W := 8
const GLYPH_H := 9
const GLYPH_GAP := 4

const GLYPHS := {
	"A": [
		".######.",
		"##....##",
		"##....##",
		"##....##",
		"########",
		"##....##",
		"##....##",
		"##....##",
		"##....##",
	],
	"U": [
		"##....##",
		"##....##",
		"##....##",
		"##....##",
		"##....##",
		"##....##",
		"##....##",
		"##....##",
		".######.",
	],
	"M": [
		"##....##",
		"###..###",
		"########",
		"##.##.##",
		"##.##.##",
		"##....##",
		"##....##",
		"##....##",
		"##....##",
	],
	"B": [
		"#######.",
		"##....##",
		"##....##",
		"##....##",
		"#######.",
		"##....##",
		"##....##",
		"##....##",
		"#######.",
	],
	"R": [
		".######.",
		"##....##",
		"##....##",
		"##....##",
		"#######.",
		"##..##..",
		"##..##..",
		"##...##.",
		"##....##",
	],
	"Y": [
		"##....##",
		"##....##",
		"##....##",
		".######.",
		"...##...",
		"...##...",
		"...##...",
		"...##...",
		"...##...",
	],
	"E": [
		".#######",
		"##......",
		"##......",
		"##......",
		"######..",
		"##......",
		"##......",
		"##......",
		".#######",
	],
}

const WORD := "AUMBRYE"

const CONTOUR_CELLS := 1
const SHADOW_OFFSET := Vector2i(2, 2)

const MIN_CELL := 8
const MAX_CELL := 24

const FACE := Color(0.97, 0.89, 0.64)
const FACE_SHADE := Color(0.72, 0.56, 0.34)
const CONTOUR := Color(0.45, 0.30, 0.72)
const DROP := Color(0.16, 0.09, 0.30)
const GLOW := Color(0.55, 0.42, 0.85)

const CELL_EDGE_RATIO := 0.12
const CELL_EDGE_DARKEN := 0.28

var _mark: Control
var _subtitle_host: Control
var _cell := 16
var _glow_alpha := 0.0
var _glow_pulsing := false
var _block_height := 0.0
var _mask: Dictionary = {}
var _contour_cells: Dictionary = {}
var _grid_size := Vector2i.ZERO


func build() -> void:
	for child in get_children():
		child.queue_free()
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_compose_mask()
	_cell = _pick_cell_size()

	_mark = Control.new()
	_mark.name = "Mark"
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_mark.draw.connect(_draw_mark)
	add_child(_mark)

	var mark_h := float(
		(_grid_size.y + CONTOUR_CELLS * 2 + SHADOW_OFFSET.y) * _cell
	)
	_mark.offset_top = 0.0
	_mark.offset_bottom = mark_h

	_build_subtitle(mark_h)
	_block_height = mark_h + _subtitle_host.size.y + float(_cell)


func _compose_mask() -> void:
	_mask.clear()
	var x := 0
	for i in WORD.length():
		var rows: Array = GLYPHS[WORD[i]]
		for row in GLYPH_H:
			var line: String = rows[row]
			for col in GLYPH_W:
				if line[col] == "#":
					_mask[Vector2i(x + col, row)] = true
		x += GLYPH_W + GLYPH_GAP
	_grid_size = Vector2i(WORD.length() * GLYPH_W + (WORD.length() - 1) * GLYPH_GAP, GLYPH_H)
	_contour_cells = _ring(_mask, CONTOUR_CELLS)


func _ring(source: Dictionary, reach: int) -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in source:
		for dx in range(-reach, reach + 1):
			for dy in range(-reach, reach + 1):
				var probe := cell + Vector2i(dx, dy)
				if not source.has(probe):
					out[probe] = true
	return out


func _pick_cell_size() -> int:
	var viewport := get_viewport_rect().size
	var cols := _grid_size.x + CONTOUR_CELLS * 2 + SHADOW_OFFSET.x
	var rows := _grid_size.y + CONTOUR_CELLS * 2 + SHADOW_OFFSET.y
	var by_width := maxf(320.0, viewport.x) * 0.74 / float(cols)
	var by_height := maxf(240.0, viewport.y) * 0.30 / float(rows)
	return clampi(int(floor(minf(by_width, by_height))), MIN_CELL, MAX_CELL)


func _draw_mark() -> void:
	var origin := Vector2(
		(_mark.size.x - float((_grid_size.x + SHADOW_OFFSET.x) * _cell)) * 0.5,
		float(CONTOUR_CELLS * _cell)
	)

	for cell: Vector2i in _contour_cells:
		_draw_cell(origin, cell + SHADOW_OFFSET, DROP)
	for cell: Vector2i in _mask:
		_draw_cell(origin, cell + SHADOW_OFFSET, DROP)
	var keyline := CONTOUR.lerp(GLOW, _glow_alpha)
	for cell: Vector2i in _contour_cells:
		_draw_cell(origin, cell, keyline)
	for cell: Vector2i in _mask:
		_draw_cell(origin, cell, _face_tone(cell))


func _face_tone(cell: Vector2i) -> Color:
	var across := float(cell.x) / maxf(1.0, float(_grid_size.x - 1))
	var down := float(cell.y) / maxf(1.0, float(_grid_size.y - 1))
	return FACE.lerp(FACE_SHADE, clampf(across * 0.35 + down * 0.65, 0.0, 1.0))


func _draw_cell(origin: Vector2, cell: Vector2i, color: Color) -> void:
	var rect := Rect2(
		origin + Vector2(float(cell.x * _cell), float(cell.y * _cell)),
		Vector2(float(_cell), float(_cell))
	)
	var edge := maxf(1.0, floorf(float(_cell) * CELL_EDGE_RATIO))
	_mark.draw_rect(rect, Color(color.darkened(CELL_EDGE_DARKEN), color.a))
	_mark.draw_rect(rect.grow(-edge), color)


func _build_subtitle(top: float) -> void:
	var sub_size := maxi(16, int(round(float(_cell) * 1.25 / 8.0)) * 8)
	var font := _font(maxi(1, roundi(float(sub_size) / 4.0)))
	var text := tr("MENU_SUBTITLE")
	var keyline := maxi(1, roundi(float(sub_size) / 8.0))

	_subtitle_host = Control.new()
	_subtitle_host.name = "Subtitle"
	_subtitle_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_host.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var height := (font.get_height(sub_size) if font else float(sub_size)) + float(keyline * 2)
	_subtitle_host.offset_top = top + float(_cell)
	_subtitle_host.offset_bottom = _subtitle_host.offset_top + height
	add_child(_subtitle_host)

	for dx in [-keyline, 0, keyline]:
		for dy in [-keyline, 0, keyline]:
			if dx == 0 and dy == 0:
				continue
			_subtitle_host.add_child(
				_text_layer(text, font, sub_size, CONTOUR, Vector2(dx, dy))
			)
	_subtitle_host.add_child(
		_text_layer(text, font, sub_size, GameUISkinScript.BODY_COLOR, Vector2.ZERO)
	)


func _text_layer(
	text: String, font: Font, font_size: int, color: Color, offset: Vector2
) -> Label:
	var label := Label.new()
	label.text = text
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.offset_left = offset.x
	label.offset_right = offset.x
	label.offset_top = offset.y
	label.offset_bottom = offset.y
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _font(tracking: int) -> Font:
	if not ResourceLoader.exists(GameUISkinScript.FONT_PATH):
		return null
	var base := load(GameUISkinScript.FONT_PATH) as Font
	if base == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base
	variation.spacing_glyph = tracking
	return variation


func place_at(y: float) -> void:
	offset_left = 0.0
	offset_right = 0.0
	offset_top = y
	offset_bottom = y + block_height()


func block_height() -> float:
	return _block_height


func set_glow_pulsing(on: bool) -> void:
	_glow_pulsing = on
	if not on:
		_glow_alpha = 0.0
		if _mark and is_instance_valid(_mark):
			_mark.queue_redraw()


func _process(_delta: float) -> void:
	if not _glow_pulsing or _mark == null or not is_instance_valid(_mark):
		return
	_glow_alpha = 0.28 + 0.28 * sin(Time.get_ticks_msec() * 0.0022)
	_mark.queue_redraw()

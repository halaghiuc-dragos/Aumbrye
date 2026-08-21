extends Control
class_name TitleWordmark

## The AUMBRYE wordmark and its subtitle, as one block.
##
## Both the boot intro and the resting front end show this — the intro centres it, then slides it up
## to sit above the menu panel. It is one node so that the two states are the same object moving,
## rather than two drawings of the same logo that have to be kept in step.
##
## **It is drawn small and magnified, the same way the game draws its world.** The whole mark is
## built inside a SubViewport at 1/SHRINK scale and upscaled with nearest filtering, exactly as
## `PixelDioramaViewport` renders the 3D scene at 480x270. Rendering it at final size instead left
## one thing on the screen that was not pixel art: FreeType's outline stroker draws a *soft* edge,
## so the halo faded off in smooth gradients while every other edge in the game is a hard block.
## Through the low-res pass that halo lands on the pixel grid and steps like everything else, and
## the glyph edges are quantised to the same grid rather than to screen pixels.
##
## Press Start 2P is drawn on an 8x8 grid, so the *internal* size is a multiple of 8 and the upscale
## is an integer — a 40px mark magnified 4x is the same letterform as a 160px one, with every other
## dimension a whole `unit = font_size / 8`: one unit of tracking, a one-unit keyline, a one-unit
## bevel, a two-unit shadow offset.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

const WORDMARK_TEXT := "AUMBRYE"

## Magnification. Every internal pixel becomes a SHRINK x SHRINK block on screen.
const SHRINK := 4
const MIN_SIZE := 8
const MAX_SIZE := 40

## The lit face of the letters and the shaded edge under it. `ACCENT_BAR` is the old gold used for
## every panel rule and divider in the game, so the shade is the interface's own accent rather than
## a second yellow invented for the logo.
const FACE := Color(0.96, 0.88, 0.62)
const SHADE := Color(0.72, 0.58, 0.32)
const OUTLINE := Color(0.05, 0.04, 0.09)
const SHADOW := Color(0.20, 0.12, 0.34, 1.0)
const GLOW := Color(0.55, 0.42, 0.85)

var _glow: Control
var _stage: VBoxContainer
var _glow_pulsing := false
var _block_height := 0.0


func build() -> void:
	for child in get_children():
		child.queue_free()
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var host := SubViewportContainer.new()
	host.name = "PixelHost"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.stretch = true
	host.stretch_shrink = SHRINK
	host.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The container would otherwise hand mouse events down into the viewport, and the mark sits over
	# the whole width of the screen.
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)

	var view := SubViewport.new()
	view.name = "PixelViewport"
	view.transparent_bg = true
	view.disable_3d = true
	view.msaa_2d = Viewport.MSAA_DISABLED
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	# The halo breathes during the intro, so the viewport cannot be drawn once and cached.
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(view)

	_stage = VBoxContainer.new()
	_stage.name = "Stage"
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_stage)

	var font_size := _font_size()
	var unit := maxi(1, roundi(font_size / 8.0))
	var font := _font(unit)
	_stage.add_theme_constant_override("separation", unit * 2)
	_build_mark(font, font_size, unit)
	_stage.add_child(_subtitle(font_size))

	# Internal height, magnified: what the block occupies on screen.
	_block_height = _stage.get_combined_minimum_size().y * SHRINK
	custom_minimum_size = Vector2(0, _block_height)


func _build_mark(font: Font, font_size: int, unit: int) -> void:
	var mark := Control.new()
	mark.name = "Mark"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The glyph box plus three units of air above and below. The layers are vertically centred, so
	# the padding is symmetric: it holds the bevel (one unit up), the shadow (two down) and the
	# halo, which is drawn outside the letterform and is clipped by the SubViewport's edge if the
	# block is only as tall as the glyphs — the first pass cut the halo off square and it read as a
	# dirty rectangle behind the word rather than as a glow.
	var line_height := font.get_height(font_size) if font else float(font_size)
	mark.custom_minimum_size = Vector2(0, line_height + unit * 6)
	_stage.add_child(mark)

	# The halo is two hollow copies — no fill, just a thick outline. Offset copies were the first
	# attempt and read as double vision: a second, misregistered AUMBRYE floating above the first.
	# An outline follows the letterform, so the glow sits around the letters the way a light source
	# would rather than beside them; the low-res pass is what makes its falloff step.
	_glow = Control.new()
	_glow.name = "Glow"
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_child(_glow)
	# Kept tight. At seven units the rings of adjacent letters merged into one slab, which the
	# low-res pass then quantised into a solid block — soft falloff hid that, hard pixels do not.
	_glow.add_child(_halo(font, font_size, unit * 3, 0.10))
	_glow.add_child(_halo(font, font_size, unit, 0.18))

	# A hard drop shadow two grid steps down and across, dilated like the keyline is — what shows
	# past the letters is then a clean two-unit band rather than whatever fragments of an undilated
	# silhouette happened to escape the keyline.
	_add_block(mark, font, font_size, SHADOW, Vector2(unit * 2, unit * 2), unit)
	# The dark keyline. An `outline_size` would be the obvious way, but FreeType's stroker rounds
	# corners at the stroke radius — the square corners of the glyphs came out visibly bevelled.
	# Copies offset by exactly one unit dilate the letterform on its own grid, which is what a pixel
	# artist would draw.
	# Twice, because the letters below are two copies a unit apart and the keyline has to wrap their
	# union — dilating only the lower one left the lit face's top-left edge with no keyline at all.
	_add_block(mark, font, font_size, OUTLINE, Vector2.ZERO, unit)
	_add_block(mark, font, font_size, OUTLINE, Vector2(-unit, -unit), unit)

	# The letters, in two tones: the shaded copy sits where the glyph belongs and the lit face is
	# lifted one unit up and left, so a single font-pixel of shade is left along the bottom and
	# right edges. That inner bevel is how a pixel artist gives a letterform depth — flat fill and a
	# keyline alone read as big text rather than as a drawn logo.
	mark.add_child(_layer(font, font_size, SHADE, Vector2.ZERO))
	mark.add_child(_layer(font, font_size, FACE, Vector2(-unit, -unit)))


## Vertical placement. Anchored top-wide, so the block spans the window and only its top and bottom
## edges move; `position` would collapse it to its own width — see `_layer()`.
func place_at(y: float) -> void:
	offset_left = 0.0
	offset_right = 0.0
	offset_top = y
	offset_bottom = y + block_height()


func block_height() -> float:
	return _block_height


## Whether the halo breathes. The intro turns it on once the screen will accept a key, which is the
## only signal there is that it is waiting — there is no separate blinking hint.
func set_glow_pulsing(on: bool) -> void:
	_glow_pulsing = on
	if not on and _glow != null and is_instance_valid(_glow):
		_glow.modulate = Color(1.0, 1.0, 1.0, 0.35)


func _process(_delta: float) -> void:
	if _glow == null or not is_instance_valid(_glow) or not _glow_pulsing:
		return
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.0022)
	_glow.modulate = Color(1.0, 1.0, 1.0, pulse)


## The largest multiple of 8 that, once magnified, clears a margin on both sides and still leaves
## the menu panel room underneath. Press Start 2P is monospaced at one em per glyph, so the width is
## simply glyphs x (size + tracking), and tracking is one unit — hence the 1.125.
func _font_size() -> int:
	var viewport := get_viewport_rect().size
	var by_width := maxf(320.0, viewport.x) * 0.72 / (float(WORDMARK_TEXT.length()) * 1.125)
	var by_height := maxf(240.0, viewport.y) / 6.0
	var limit := int(minf(by_width, by_height) / float(SHRINK))
	var best := MIN_SIZE
	var candidate := MIN_SIZE
	while candidate <= MAX_SIZE:
		if candidate <= limit:
			best = candidate
		candidate += 8
	return best


func _font(tracking: int) -> Font:
	if not ResourceLoader.exists(GameUISkinScript.FONT_PATH):
		return null
	var base := load(GameUISkinScript.FONT_PATH) as Font
	if base == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base
	# One grid step of tracking. Press Start 2P sets its glyphs edge to edge; without this the
	# letters of a large wordmark read as a single block.
	variation.spacing_glyph = tracking
	return variation


func _subtitle(font_size: int) -> Label:
	var label := Label.new()
	label.name = "Subtitle"
	label.text = tr("MENU_SUBTITLE")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.style_body_label(label)
	# A quarter of the mark, rounded onto the same 8px grid, so the pair reads as one piece of
	# lettering rather than the logo with a caption typed under it.
	var sub_size := maxi(MIN_SIZE, int(round(font_size / 4.0 / 8.0)) * 8)
	label.add_theme_font_size_override("font_size", sub_size)
	var font := _font(maxi(1, roundi(sub_size / 4.0)))
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", GameUISkinScript.BODY_COLOR)
	return label


## The wordmark as a solid silhouette grown by one grid unit in every direction — the keyline and
## the drop shadow are both this shape, at different offsets.
func _add_block(
	parent: Control, font: Font, font_size: int, color: Color, origin: Vector2, unit: int
) -> void:
	for dx in [-unit, 0, unit]:
		for dy in [-unit, 0, unit]:
			parent.add_child(_layer(font, font_size, color, origin + Vector2(dx, dy)))


## A copy of the wordmark with no fill, drawn only as an outline — one ring of the halo.
func _halo(font: Font, font_size: int, thickness: int, alpha: float) -> Label:
	var label := _layer(font, font_size, Color(FACE, 0.0), Vector2.ZERO)
	label.add_theme_constant_override("outline_size", thickness)
	label.add_theme_color_override("font_outline_color", Color(GLOW, alpha))
	return label


func _layer(font: Font, font_size: int, color: Color, offset: Vector2) -> Label:
	var label := Label.new()
	label.text = WORDMARK_TEXT
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Shifted by moving all four offsets, not by setting `position`. The position setter derives
	# offsets from the control's *current* size, and at build time these labels are not in the tree
	# yet, so their size is their text width rather than the parent's — every copy ended up
	# left-aligned in a box the width of the word instead of centred across the screen.
	label.offset_left = offset.x
	label.offset_right = offset.x
	label.offset_top = offset.y
	label.offset_bottom = offset.y
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

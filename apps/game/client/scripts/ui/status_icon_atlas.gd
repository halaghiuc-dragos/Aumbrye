extends RefCounted
class_name StatusIconAtlas

## Procedural nearest-filtered status glyphs (replaces ColorRect squares).

const ICON_SIZE := 22

static var _cache: Dictionary = {}


static func get_icon(status_id: String, fallback_color: Color = Color.WHITE) -> Texture2D:
	if _cache.has(status_id):
		return _cache[status_id]
	var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := Vector2(ICON_SIZE * 0.5, ICON_SIZE * 0.5)
	var radius := ICON_SIZE * 0.42
	_draw_glyph(image, status_id, center, radius, fallback_color)
	var tex := ImageTexture.create_from_image(image)
	_cache[status_id] = tex
	return tex


static func _draw_glyph(
	image: Image,
	status_id: String,
	center: Vector2,
	radius: float,
	color: Color
) -> void:
	match status_id:
		"burn":
			_fill_circle(image, center, radius, Color(1.0, 0.45, 0.1))
			_fill_circle(image, center, radius * 0.35, Color(1.0, 0.9, 0.3))
		"poison", "venom":
			_fill_circle(image, center, radius, Color(0.35, 0.9, 0.25))
			_fill_ring(image, center, radius * 0.55, radius * 0.75, Color(0.1, 0.35, 0.1))
		"frost", "chill":
			_fill_diamond(image, center, radius, Color(0.55, 0.85, 1.0))
		"stun", "shock":
			_fill_bolt(image, center, radius, Color(1.0, 0.92, 0.2))
		"bleed":
			_fill_circle(image, center, radius, Color(0.85, 0.12, 0.12))
		_:
			_fill_circle(image, center, radius, color)
			_fill_ring(image, center, radius * 0.6, radius * 0.85, color.darkened(0.35))


static func _fill_circle(image: Image, center: Vector2, radius: float, color: Color) -> void:
	var r2 := radius * radius
	for y in ICON_SIZE:
		for x in ICON_SIZE:
			var dx := float(x) + 0.5 - center.x
			var dy := float(y) + 0.5 - center.y
			if dx * dx + dy * dy <= r2:
				image.set_pixel(x, y, color)


static func _fill_ring(image: Image, center: Vector2, inner: float, outer: float, color: Color) -> void:
	var inner2 := inner * inner
	var outer2 := outer * outer
	for y in ICON_SIZE:
		for x in ICON_SIZE:
			var dx := float(x) + 0.5 - center.x
			var dy := float(y) + 0.5 - center.y
			var d2 := dx * dx + dy * dy
			if d2 >= inner2 and d2 <= outer2:
				image.set_pixel(x, y, color)


static func _fill_diamond(image: Image, center: Vector2, radius: float, color: Color) -> void:
	for y in ICON_SIZE:
		for x in ICON_SIZE:
			var dx := absf(float(x) + 0.5 - center.x) / radius
			var dy := absf(float(y) + 0.5 - center.y) / radius
			if dx + dy <= 1.0:
				image.set_pixel(x, y, color)


static func _fill_bolt(image: Image, center: Vector2, radius: float, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius * 0.35, -radius * 0.1),
		center + Vector2(radius * 0.1, radius * 0.15),
		center + Vector2(radius * 0.45, radius),
		center + Vector2(-radius * 0.05, radius * 0.2),
		center + Vector2(radius * 0.2, -radius * 0.35),
	])
	for y in ICON_SIZE:
		for x in ICON_SIZE:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				image.set_pixel(x, y, color)

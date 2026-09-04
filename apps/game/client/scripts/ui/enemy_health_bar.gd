extends Node3D
class_name EnemyHealthBar


const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const IntentGlyphScript := preload("res://scripts/ui/enemy_intent_glyph.gd")
## The attack-class colours live on VfxService, so the wind-up meter and the ground telegraph
## cannot drift apart.

const BAR_TEX_W := 28
const BAR_TEX_H := 3
const FILL_TEX_W := BAR_TEX_W - 2
const FILL_TEX_H := 1
const BAR_WORLD_W := BAR_TEX_W * PixelStyle.WORLD_PIXEL
const BAR_WORLD_H := BAR_TEX_H * PixelStyle.WORLD_PIXEL
const ATTACK_BAR_OFFSET_PIXELS := -4

const POISE_BAR_OFFSET_PIXELS := 4
const ATTACK_BAR_OFFSET_Y := ATTACK_BAR_OFFSET_PIXELS * PixelStyle.WORLD_PIXEL
const POISE_BAR_OFFSET_Y := POISE_BAR_OFFSET_PIXELS * PixelStyle.WORLD_PIXEL
const FILL_WORLD_W := FILL_TEX_W * PixelStyle.WORLD_PIXEL
const BAR_BORDER_COLOR := Color(0.02, 0.02, 0.02, 1.0)
const BAR_WELL_COLOR := Color(0.04, 0.04, 0.04, 1.0)
const HEALTH_FILL_COLOR := Color(0.9, 0.15, 0.1, 1.0)
const POISE_FILL_COLOR := Color(0.82, 0.74, 0.45, 1.0)
## Draw order for the stacked quads. `BILLBOARD_FIXED_Y` turns the *quad* to face the camera and
## leaves the node's own axes alone, so neither `position.z` nor `position.x` can be used to
## order or align these — local axes are fixed world directions unrelated to the bar on screen.
## Sprite3D quads are transparent and write no depth, so coplanar layers composite purely by
## render priority, which is the same from every angle and still hides correctly behind walls.
const BAR_PRIORITY_BG := 0
const BAR_PRIORITY_FILL := 1
## `Sprite3D` quads write no depth, so the glyph must outrank the fill it sits above (`EN-04`'s
## trap) or it composites underneath instead of over it.
const BAR_PRIORITY_GLYPH := 2
const DEFAULT_HEIGHT := 2.2
const MAX_VISIBLE_DISTANCE := 25.0
const DISTANCE_CHECK_INTERVAL := 0.5

var _bg_sprite: Sprite3D
var _fill_sprite: Sprite3D
var _attack_bg_sprite: Sprite3D
var _attack_fill_sprite: Sprite3D
var _intent_glyph: Sprite3D
var _health: Health
var _poise_bg_sprite: Sprite3D
var _poise_fill_sprite: Sprite3D
var _poise: Poise
var _alive := true
var _in_range := true
var _distance_timer: Timer


func setup(health: Health, height_offset: float = DEFAULT_HEIGHT, poise: Poise = null) -> void:
	_health = health
	position.y = height_offset
	_build_sprites()
	_build_distance_timer()
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	_on_health_changed(health.current, health.max_health)
	if poise:
		_poise = poise
		poise.poise_changed.connect(_on_poise_changed)
		poise.poise_broken.connect(_on_poise_broken)


func _build_distance_timer() -> void:
	_distance_timer = Timer.new()
	_distance_timer.wait_time = DISTANCE_CHECK_INTERVAL
	_distance_timer.autostart = true
	_distance_timer.timeout.connect(_check_distance)
	add_child(_distance_timer)


func _check_distance() -> void:
	var camera := PixelDioramaViewport.get_gameplay_camera()
	if camera == null:
		return
	var dist_sq := camera.global_position.distance_squared_to(global_position)
	_in_range = dist_sq <= MAX_VISIBLE_DISTANCE * MAX_VISIBLE_DISTANCE
	_apply_visibility()


func _apply_visibility() -> void:
	visible = _alive and _in_range


func _build_sprites() -> void:
	_bg_sprite = _make_bar_sprite("Background", BAR_PRIORITY_BG, 0.0, Color.WHITE, _bar_texture())
	_fill_sprite = _make_bar_sprite(
		"Fill", BAR_PRIORITY_FILL, 0.0, HEALTH_FILL_COLOR, _fill_step_texture(FILL_TEX_W)
	)
	_attack_bg_sprite = _make_bar_sprite(
		"AttackBackground", BAR_PRIORITY_BG, ATTACK_BAR_OFFSET_Y, Color.WHITE, _bar_texture()
	)
	_attack_fill_sprite = _make_bar_sprite(
		"AttackFill",
		BAR_PRIORITY_FILL,
		ATTACK_BAR_OFFSET_Y,
		AccessibilitySettings.get_telegraph_class_color("blockable"),
		_fill_step_texture(FILL_TEX_W)
	)
	_poise_bg_sprite = _make_bar_sprite(
		"PoiseBackground", BAR_PRIORITY_BG, POISE_BAR_OFFSET_Y, Color.WHITE, _bar_texture()
	)
	_poise_fill_sprite = _make_bar_sprite(
		"PoiseFill",
		BAR_PRIORITY_FILL,
		POISE_BAR_OFFSET_Y,
		POISE_FILL_COLOR,
		_fill_step_texture(FILL_TEX_W)
	)
	_intent_glyph = IntentGlyphScript.build(self, BAR_PRIORITY_GLYPH)
	for sprite in [_attack_bg_sprite, _attack_fill_sprite, _poise_bg_sprite, _poise_fill_sprite]:
		sprite.visible = false


func _make_bar_sprite(
	sprite_name: String, priority: int, offset_y: float, tint: Color, texture: Texture2D
) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	sprite.modulate = tint
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	PixelStyle.configure_pixel_sprite(sprite)
	sprite.render_priority = priority
	sprite.position.y = offset_y
	add_child(sprite)
	return sprite


func _on_poise_changed(current: float, max_value: float) -> void:
	if _poise_fill_sprite == null or max_value <= 0.0:
		return
	var ratio := clampf(current / max_value, 0.0, 1.0)
	var should_show := ratio < 0.999 and _alive
	_poise_bg_sprite.visible = should_show
	_poise_fill_sprite.visible = should_show
	if should_show:
		_apply_fill(_poise_fill_sprite, ratio)
		if ratio > 0.001:
			_poise_fill_sprite.modulate = POISE_FILL_COLOR


func _on_poise_broken() -> void:
	if _poise_fill_sprite == null:
		return
	_poise_fill_sprite.modulate = Color(0.95, 0.4, 0.25, 1.0)




func begin_attack_telegraph(_duration: float, attack_class: String = "blockable") -> void:
	if _attack_fill_sprite:
		# The same source as the ground telegraph, so the bar over an enemy's head and the ring
		# under its feet never disagree about whether an attack can be blocked.
		_attack_fill_sprite.modulate = AccessibilitySettings.get_telegraph_class_color(
			attack_class
		)
	if _attack_bg_sprite:
		_attack_bg_sprite.visible = true
	if _attack_fill_sprite:
		_attack_fill_sprite.visible = true
	IntentGlyphScript.show_for_class(_intent_glyph, attack_class)
	set_attack_telegraph_progress(0.0)


func set_attack_telegraph_progress(ratio: float) -> void:
	if _attack_fill_sprite == null:
		return
	_apply_fill(_attack_fill_sprite, ratio)


func hide_attack_telegraph() -> void:
	if _attack_bg_sprite:
		_attack_bg_sprite.visible = false
	if _attack_fill_sprite:
		_attack_fill_sprite.visible = false
	IntentGlyphScript.hide_glyph(_intent_glyph)


static var _step_textures: Array[ImageTexture] = []


static func _fill_step_texture(step: int) -> ImageTexture:
	if _step_textures.is_empty():
		for i in FILL_TEX_W + 1:
			var img := Image.create(FILL_TEX_W, FILL_TEX_H, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			for x in i:
				img.set_pixel(x, 0, Color.WHITE)
			_step_textures.append(ImageTexture.create_from_image(img))
	return _step_textures[clampi(step, 0, FILL_TEX_W)]


func _apply_fill(sprite: Sprite3D, ratio: float) -> void:
	var steps := int(round(clampf(ratio, 0.0, 1.0) * float(FILL_TEX_W)))
	sprite.texture = _fill_step_texture(steps)


## The empty frame every bar sits in: a dark border round a darker well. Identical for all three
## bars and for every enemy, so it is built once and shared.
static var _frame_texture: ImageTexture


static func _bar_texture() -> ImageTexture:
	if _frame_texture != null:
		return _frame_texture
	var img := Image.create(BAR_TEX_W, BAR_TEX_H, false, Image.FORMAT_RGBA8)
	for y in BAR_TEX_H:
		for x in BAR_TEX_W:
			var border := x == 0 or x == BAR_TEX_W - 1 or y == 0 or y == BAR_TEX_H - 1
			img.set_pixel(x, y, BAR_BORDER_COLOR if border else BAR_WELL_COLOR)
	_frame_texture = ImageTexture.create_from_image(img)
	return _frame_texture
func _on_health_changed(current: float, max_value: float) -> void:
	if _fill_sprite == null:
		return
	var ratio: float = 0.0 if max_value <= 0.0 else clampf(current / max_value, 0.0, 1.0)
	_apply_fill(_fill_sprite, ratio)
	_alive = ratio > 0.0
	_apply_visibility()


func _on_died() -> void:
	if _poise_bg_sprite:
		_poise_bg_sprite.visible = false
	if _poise_fill_sprite:
		_poise_fill_sprite.visible = false
	_alive = false
	_apply_visibility()

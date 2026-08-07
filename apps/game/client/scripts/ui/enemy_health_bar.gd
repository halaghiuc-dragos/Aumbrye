extends Node3D
class_name EnemyHealthBar

## Billboard HP bar above enemies — nearest-filtered Sprite3D quads.

const BAR_TEX_W := 32
const BAR_TEX_H := 4
const ATTACK_BAR_TEX_H := 3
const BAR_WORLD_W := 1.1
const BAR_WORLD_H := 0.12
const ATTACK_BAR_WORLD_H := 0.08
const ATTACK_BAR_OFFSET_Y := -0.16
const DEFAULT_HEIGHT := 2.2
const MAX_VISIBLE_DISTANCE := 25.0
const DISTANCE_CHECK_INTERVAL := 0.5
const FILL_WORLD_W := BAR_WORLD_W - 0.03
const FILL_TEX_SIZE := 2

var _bg_sprite: Sprite3D
var _fill_sprite: Sprite3D
var _attack_bg_sprite: Sprite3D
var _attack_fill_sprite: Sprite3D
var _health: Health
var _bg_texture: ImageTexture
var _fill_texture: ImageTexture
var _attack_bg_texture: ImageTexture
var _attack_fill_texture: ImageTexture
var _alive := true
var _in_range := true
var _distance_timer: Timer


func setup(health: Health, height_offset: float = DEFAULT_HEIGHT) -> void:
	_health = health
	position.y = height_offset
	_build_sprites()
	_build_distance_timer()
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	_on_health_changed(health.current, health.max_health)


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
	_bg_texture = _make_bar_texture(Color(0.04, 0.04, 0.04, 1.0), 1.0)
	_fill_texture = _make_solid_texture(Color(0.9, 0.15, 0.1, 1.0))

	_bg_sprite = Sprite3D.new()
	_bg_sprite.name = "Background"
	_bg_sprite.texture = _bg_texture
	_bg_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_bg_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_bg_sprite.pixel_size = BAR_WORLD_W / float(BAR_TEX_W)
	_bg_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bg_sprite)

	_fill_sprite = Sprite3D.new()
	_fill_sprite.name = "Fill"
	_fill_sprite.texture = _fill_texture
	_fill_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_fill_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_fill_sprite.pixel_size = FILL_WORLD_W / float(FILL_TEX_SIZE)
	_fill_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fill_sprite.position.z = -0.02
	add_child(_fill_sprite)
	_build_attack_sprites()


func _build_attack_sprites() -> void:
	_attack_bg_texture = _make_bar_texture(Color(0.04, 0.04, 0.04, 1.0), 1.0, ATTACK_BAR_TEX_H)
	_attack_fill_texture = _make_solid_texture(Color(0.95, 0.55, 0.15, 1.0))

	_attack_bg_sprite = Sprite3D.new()
	_attack_bg_sprite.name = "AttackBackground"
	_attack_bg_sprite.texture = _attack_bg_texture
	_attack_bg_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_attack_bg_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_attack_bg_sprite.pixel_size = BAR_WORLD_W / float(BAR_TEX_W)
	_attack_bg_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_attack_bg_sprite.position.y = ATTACK_BAR_OFFSET_Y
	_attack_bg_sprite.visible = false
	add_child(_attack_bg_sprite)

	_attack_fill_sprite = Sprite3D.new()
	_attack_fill_sprite.name = "AttackFill"
	_attack_fill_sprite.texture = _attack_fill_texture
	_attack_fill_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_attack_fill_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_attack_fill_sprite.pixel_size = FILL_WORLD_W / float(FILL_TEX_SIZE)
	_attack_fill_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_attack_fill_sprite.position.y = ATTACK_BAR_OFFSET_Y
	_attack_fill_sprite.position.z = -0.02
	_attack_fill_sprite.visible = false
	add_child(_attack_fill_sprite)


func begin_attack_telegraph(_duration: float) -> void:
	if _attack_bg_sprite:
		_attack_bg_sprite.visible = true
	if _attack_fill_sprite:
		_attack_fill_sprite.visible = true
	set_attack_telegraph_progress(0.0)


func set_attack_telegraph_progress(ratio: float) -> void:
	if _attack_fill_sprite == null:
		return
	var fill_ratio := clampf(ratio, 0.0, 1.0)
	var fill_w := FILL_WORLD_W * fill_ratio
	_attack_fill_sprite.position.x = FILL_WORLD_W * 0.5 - fill_w * 0.5
	_attack_fill_sprite.scale.x = maxf(fill_ratio, 0.001)


func hide_attack_telegraph() -> void:
	if _attack_bg_sprite:
		_attack_bg_sprite.visible = false
	if _attack_fill_sprite:
		_attack_fill_sprite.visible = false


func _make_bar_texture(
	color: Color, fill_ratio: float, bar_height: int = BAR_TEX_H
) -> ImageTexture:
	var img := Image.create(BAR_TEX_W, bar_height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var fill_w := int(round(float(BAR_TEX_W - 2) * clampf(fill_ratio, 0.0, 1.0)))
	for y in bar_height:
		for x in BAR_TEX_W:
			var border := x == 0 or x == BAR_TEX_W - 1 or y == 0 or y == bar_height - 1
			if border:
				img.set_pixel(x, y, Color(0.02, 0.02, 0.02, 1.0))
			elif x >= 1 and x < 1 + fill_w:
				img.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(img)
	return tex


func _make_solid_texture(color: Color) -> ImageTexture:
	var img := Image.create(FILL_TEX_SIZE, FILL_TEX_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _on_health_changed(current: float, max_value: float) -> void:
	if _fill_sprite == null:
		return
	var ratio: float = 0.0 if max_value <= 0.0 else clampf(current / max_value, 0.0, 1.0)
	var fill_w := FILL_WORLD_W * ratio
	_fill_sprite.position.x = FILL_WORLD_W * 0.5 - fill_w * 0.5
	_fill_sprite.scale.x = maxf(ratio, 0.001)
	_alive = ratio > 0.0
	_apply_visibility()


func _on_died() -> void:
	_alive = false
	_apply_visibility()

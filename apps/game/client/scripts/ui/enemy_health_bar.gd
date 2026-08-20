extends Node3D
class_name EnemyHealthBar

## Billboard HP bar above enemies — nearest-filtered Sprite3D quads.

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")

const BAR_TEX_W := 28
const BAR_TEX_H := 3
const ATTACK_BAR_TEX_H := 3
const FILL_TEX_W := BAR_TEX_W - 2
const FILL_TEX_H := 1
const BAR_WORLD_W := BAR_TEX_W * PixelStyle.WORLD_PIXEL
const BAR_WORLD_H := BAR_TEX_H * PixelStyle.WORLD_PIXEL
const ATTACK_BAR_OFFSET_PIXELS := -4

## C-96: the enemy bar had a health strip and a wind-up strip and no poise readout, so a
## stagger-focused build could not see the one value it exists to drive down. Sits below the health
## bar, thinner, and only appears once the enemy has actually taken poise damage — a full poise bar
## on every idle enemy is noise.
const POISE_BAR_OFFSET_PIXELS := 4
const ATTACK_BAR_OFFSET_Y := ATTACK_BAR_OFFSET_PIXELS * PixelStyle.WORLD_PIXEL
const POISE_BAR_OFFSET_Y := POISE_BAR_OFFSET_PIXELS * PixelStyle.WORLD_PIXEL
const FILL_WORLD_W := FILL_TEX_W * PixelStyle.WORLD_PIXEL
const FILL_DEPTH_OFFSET := -0.02
const DEFAULT_HEIGHT := 2.2
const MAX_VISIBLE_DISTANCE := 25.0
const DISTANCE_CHECK_INTERVAL := 0.5

var _bg_sprite: Sprite3D
var _fill_sprite: Sprite3D
var _attack_bg_sprite: Sprite3D
var _attack_fill_sprite: Sprite3D
var _health: Health
var _bg_texture: ImageTexture
var _fill_texture: ImageTexture
var _attack_bg_texture: ImageTexture
var _attack_fill_texture: ImageTexture
var _poise_bg_sprite: Sprite3D
var _poise_fill_sprite: Sprite3D
var _poise_bg_texture: ImageTexture
var _poise_fill_texture: ImageTexture
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
	# C-96: optional — the training dummy and some scripted actors have no Poise node.
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
	_bg_texture = _make_bar_texture(Color(0.04, 0.04, 0.04, 1.0), 1.0)
	_fill_texture = _make_solid_texture(Color(0.9, 0.15, 0.1, 1.0))

	_bg_sprite = Sprite3D.new()
	_bg_sprite.name = "Background"
	_bg_sprite.texture = _bg_texture
	_bg_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	PixelStyle.configure_pixel_sprite(_bg_sprite)
	add_child(_bg_sprite)

	_fill_sprite = Sprite3D.new()
	_fill_sprite.name = "Fill"
	_fill_sprite.texture = _fill_texture
	_fill_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	PixelStyle.configure_pixel_sprite(_fill_sprite)
	_fill_sprite.position.z = FILL_DEPTH_OFFSET
	add_child(_fill_sprite)
	_build_attack_sprites()
	_build_poise_sprites()


func _build_attack_sprites() -> void:
	_attack_bg_texture = _make_bar_texture(Color(0.04, 0.04, 0.04, 1.0), 1.0, ATTACK_BAR_TEX_H)
	_attack_fill_texture = _make_solid_texture(Color(0.95, 0.55, 0.15, 1.0))

	_attack_bg_sprite = Sprite3D.new()
	_attack_bg_sprite.name = "AttackBackground"
	_attack_bg_sprite.texture = _attack_bg_texture
	_attack_bg_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	PixelStyle.configure_pixel_sprite(_attack_bg_sprite)
	_attack_bg_sprite.position.y = ATTACK_BAR_OFFSET_Y
	_attack_bg_sprite.visible = false
	add_child(_attack_bg_sprite)

	_attack_fill_sprite = Sprite3D.new()
	_attack_fill_sprite.name = "AttackFill"
	_attack_fill_sprite.texture = _attack_fill_texture
	_attack_fill_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	PixelStyle.configure_pixel_sprite(_attack_fill_sprite)
	_attack_fill_sprite.position.y = ATTACK_BAR_OFFSET_Y
	_attack_fill_sprite.position.z = FILL_DEPTH_OFFSET
	_attack_fill_sprite.visible = false
	add_child(_attack_fill_sprite)


func _build_poise_sprites() -> void:
	_poise_bg_texture = _make_bar_texture(Color(0.04, 0.04, 0.04, 1.0), 1.0, ATTACK_BAR_TEX_H)
	_poise_fill_texture = _make_solid_texture(Color(0.82, 0.74, 0.45, 1.0))

	_poise_bg_sprite = Sprite3D.new()
	_poise_bg_sprite.name = "PoiseBackground"
	_poise_bg_sprite.texture = _poise_bg_texture
	_poise_bg_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	PixelStyle.configure_pixel_sprite(_poise_bg_sprite)
	_poise_bg_sprite.position.y = POISE_BAR_OFFSET_Y
	_poise_bg_sprite.visible = false
	add_child(_poise_bg_sprite)

	_poise_fill_sprite = Sprite3D.new()
	_poise_fill_sprite.name = "PoiseFill"
	_poise_fill_sprite.texture = _poise_fill_texture
	_poise_fill_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	PixelStyle.configure_pixel_sprite(_poise_fill_sprite)
	_poise_fill_sprite.position.y = POISE_BAR_OFFSET_Y
	_poise_fill_sprite.position.z = FILL_DEPTH_OFFSET
	_poise_fill_sprite.visible = false
	add_child(_poise_fill_sprite)


func _on_poise_changed(current: float, max_value: float) -> void:
	if _poise_fill_sprite == null or max_value <= 0.0:
		return
	var ratio := clampf(current / max_value, 0.0, 1.0)
	# Only worth showing once the player has started breaking it.
	var show := ratio < 0.999 and _alive
	_poise_bg_sprite.visible = show
	_poise_fill_sprite.visible = show
	if show:
		_apply_fill(_poise_fill_sprite, ratio)


func _on_poise_broken() -> void:
	if _poise_fill_sprite == null:
		return
	_poise_fill_sprite.modulate = Color(0.95, 0.4, 0.25, 1.0)


## C-125: the wind-up meter existed and was always orange. Tinting it by attack class is the
## consumer §4 asked for — white/amber for blockable, red for unblockable, blue for parryable — and
## unlike the world-space telegraph it cannot be pointed backwards (C-70).
const TELEGRAPH_CLASS_TINTS := {
	"blockable": Color(0.95, 0.55, 0.15, 1.0),
	"unblockable": Color(0.95, 0.22, 0.16, 1.0),
	"parryable": Color(0.45, 0.78, 1.0, 1.0),
}


func begin_attack_telegraph(_duration: float, attack_class: String = "blockable") -> void:
	if _attack_fill_sprite:
		_attack_fill_sprite.modulate = TELEGRAPH_CLASS_TINTS.get(
			attack_class, TELEGRAPH_CLASS_TINTS["blockable"]
		)
	if _attack_bg_sprite:
		_attack_bg_sprite.visible = true
	if _attack_fill_sprite:
		_attack_fill_sprite.visible = true
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


func _apply_fill(sprite: Sprite3D, ratio: float) -> void:
	var fill_ratio := PixelStyle.snap_fill_ratio(ratio, FILL_TEX_W)
	var fill_w := FILL_WORLD_W * fill_ratio
	sprite.position.x = FILL_WORLD_W * 0.5 - fill_w * 0.5
	sprite.scale.x = maxf(fill_ratio, 0.001)


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
	var img := Image.create(FILL_TEX_W, FILL_TEX_H, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


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

extends RefCounted
class_name EnemyIntentGlyph

## `EN-04`: the pixel intent glyph shown above an enemy's wind-up bar. Colour alone is a weak
## channel -- `AccessibilitySettings` already has to remap it three ways for colourblind modes --
## so the glyph gives shape a say too: a sword for `blockable`, a broken shield for `unblockable`,
## a parry star for `parryable`, a hand for `grab`. Turning on `colorblind_mode` changes the tint;
## it never changes which glyph is showing.

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const AtlasScript := preload("res://scripts/ui/enemy_intent_glyph_atlas.gd")

## `EnemyHealthBar.ATTACK_BAR_OFFSET_PIXELS` is -4; the glyph sits one more bar's height above
## that so it reads as "over the wind-up bar", not "part of it".
const OFFSET_PIXELS := -12

const POP_DURATION := 0.09
const POP_OVERSHOOT_SCALE := 1.15
const POP_START_SCALE := 0.6


static func build(parent: Node3D, priority: int) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = "IntentGlyph"
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	PixelStyle.configure_pixel_sprite(sprite)
	sprite.render_priority = priority
	sprite.position.y = OFFSET_PIXELS * PixelStyle.WORLD_PIXEL
	sprite.visible = false
	parent.add_child(sprite)
	return sprite


static func show_for_class(sprite: Sprite3D, attack_class: String) -> void:
	if sprite == null:
		return
	sprite.texture = AtlasScript.get_glyph_for_class(attack_class)
	sprite.modulate = AccessibilitySettings.get_telegraph_class_color(attack_class)
	sprite.visible = true
	_pop_in(sprite)


static func hide_glyph(sprite: Sprite3D) -> void:
	if sprite == null:
		return
	sprite.visible = false


## A one-frame scale overshoot so the glyph *arrives* rather than fades in -- it should read as a
## small, decisive pop, the pixel-art equivalent of a UI element that snaps into place.
static func _pop_in(sprite: Sprite3D) -> void:
	sprite.scale = Vector3.ONE * POP_START_SCALE
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "scale", Vector3.ONE * POP_OVERSHOOT_SCALE, POP_DURATION * 0.6)
	tween.tween_property(sprite, "scale", Vector3.ONE, POP_DURATION * 0.4)

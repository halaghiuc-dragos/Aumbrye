extends Node3D
class_name ArenaHazard

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

enum State { TELEGRAPH, ACTIVE, FADE }

const FADE_TIME := 0.5

## `BS-04`: every arena hazard reads as an unblockable attack -- there is nowhere to sidestep a
## quadrant flood or a raised floor, only somewhere to not be standing.
const HAZARD_ATTACK_CLASS := "unblockable"

@export var damage := 8.0
@export var poise_damage := 5.0
@export var telegraph_time := 1.0
@export var active_time := 2.5

@onready var _telegraph: MeshInstance3D = $TelegraphMesh
@onready var _active_zone: MeshInstance3D = $ActiveMesh
@onready var _damage_area: Area3D = $DamageArea

var _state := State.TELEGRAPH
var _timer := 0.0


func _ready() -> void:
	_build_visual()
	_telegraph.material_override = DioramaSkin.make_telegraph_material(
		AccessibilitySettings.emphasise_telegraph_tint(_telegraph_tint())
	)
	_active_zone.material_override = DioramaSkin.make_telegraph_material(_active_tint())
	_active_zone.visible = false
	_damage_area.monitoring = false
	_damage_area.damage = damage
	if _damage_area.get("poise_damage") != null:
		_damage_area.poise_damage = poise_damage
	_timer = telegraph_time


## Overridden by a hazard that has geometry of its own beyond the two zone meshes.
func _build_visual() -> void:
	pass


## Routed through `AccessibilitySettings.get_telegraph_class_color()` only under a colourblind
## mode, matching `MaterialFlash.tint_for_damage_type()`'s precedent: keep the authored hue for
## sighted players, remap it only when the remap is what actually helps.
func _telegraph_tint() -> Color:
	if AccessibilitySettings.colorblind_mode != "default":
		var tint := AccessibilitySettings.get_telegraph_class_color(HAZARD_ATTACK_CLASS)
		tint.a = 0.5
		return tint
	return Color(1, 0.5, 0, 0.5)


func _active_tint() -> Color:
	if AccessibilitySettings.colorblind_mode != "default":
		var tint := AccessibilitySettings.get_telegraph_class_color(HAZARD_ATTACK_CLASS)
		tint.a = 0.9
		return tint
	return Color(1, 0.2, 0, 0.9)


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	match _state:
		State.TELEGRAPH:
			_state = State.ACTIVE
			_timer = active_time
			_telegraph.visible = false
			_active_zone.visible = true
			_damage_area.monitoring = true
		State.ACTIVE:
			_state = State.FADE
			_timer = FADE_TIME
			_damage_area.monitoring = false
		State.FADE:
			queue_free()

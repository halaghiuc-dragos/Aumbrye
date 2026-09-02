extends Area3D
class_name Projectile


const PixelStyleScript := preload("res://scripts/art/style/pixel_diorama_style.gd")
const LightEmbersScript := preload("res://scripts/art/vfx/light_embers.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")

@onready var _hitbox: Hitbox = $Hitbox
@onready var _visual: Node3D = $Visual

@export var team: String = "enemy"

@export var pierce := 0

## Lighter than real-world fall (9.8) so an arrow shot across a typical arena still reads as aimed
## rather than lobbed, while still visibly arcing instead of flying like a laser.
const GRAVITY := 9.0

## A shot launched dead level would fall short of dead-level -- the arc has to start on its way up
## to still cross the target's height by the time it gets there. Scaled off the shot's own speed so
## a slow lob and a hard draw both keep roughly the same *shape* of arc rather than the fast one
## flattening out.
const ARC_LIFT_RATIO := 0.12

var _velocity := Vector3.ZERO
var _lifetime := 4.0
var _owner_node: Node
var _pierce_remaining := 0


func _ready() -> void:
	monitoring = true
	_hitbox.team = team
	_hitbox.disable()
	if not _hitbox.hit_landed.is_connected(_on_hit_landed):
		_hitbox.hit_landed.connect(_on_hit_landed)


func launch(
	direction: Vector3,
	speed: float,
	damage: float,
	poise: float,
	shooter: Node,
	dmg_type: String = DamageInfo.TYPE_PHYSICAL,
	apply_status: String = "",
	status_stacks: int = 1,
	crit_chance: float = 0.0,
	crit_multiplier: float = 1.5
) -> void:
	_owner_node = shooter
	var heading := direction.normalized()
	_velocity = heading * speed
	_velocity.y += speed * ARC_LIFT_RATIO
	_lifetime = 4.0
	_hitbox.set_combat_owner(shooter)
	_hitbox.set_attack_values(
		damage, poise, dmg_type, apply_status, status_stacks, crit_chance, crit_multiplier
	)
	_pierce_remaining = maxi(0, pierce)
	_hitbox.enable()
	_face_velocity()
	_build_visual(dmg_type)


func _build_visual(dmg_type: String) -> void:
	if _visual == null:
		return
	for child in _visual.get_children():
		_visual.remove_child(child)
		child.queue_free()
	var element := MaterialFlashScript.tint_for_damage_type(dmg_type)
	var shaft_mat := PixelStyleScript.make_material(Color(0.42, 0.30, 0.18))
	var head_mat := PixelStyleScript.make_glow_material(element, element.darkened(0.35), 1.9)
	var fletch_mat := PixelStyleScript.make_material(element.lightened(0.25))
	_add_part(Vector3(0.05, 0.05, 0.62), Vector3(0.0, 0.0, 0.06), shaft_mat, "Shaft")
	_add_part(Vector3(0.09, 0.09, 0.18), Vector3(0.0, 0.0, -0.32), head_mat, "Head")
	for i in 2:
		var axis: Vector3 = Vector3.RIGHT if i == 0 else Vector3.UP
		_add_part(
			Vector3(0.02, 0.02, 0.16) + axis * 0.14,
			Vector3(0.0, 0.0, 0.3),
			fletch_mat,
			"Fletch%d" % i
		)
	if dmg_type != DamageInfo.TYPE_PHYSICAL:
		LightEmbersScript.attach(_visual, Vector3(0.0, 0.0, -0.2), element, 0.7, 0.5)


func _add_part(size: Vector3, pos: Vector3, mat: Material, part_name: String) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = part_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(mesh)


func _on_hit_landed(_target: Node) -> void:
	if _pierce_remaining > 0:
		_pierce_remaining -= 1
		return
	_hitbox.disable()
	queue_free()


func _physics_process(delta: float) -> void:
	_velocity.y -= GRAVITY * delta
	var motion := _velocity * delta
	if motion.length_squared() > 0.0:
		var space := get_world_3d().direct_space_state
		if space:
			var params := PhysicsRayQueryParameters3D.create(
				global_position, global_position + motion
			)
			params.collision_mask = CombatLayers.WORLD_OCCLUDERS
			params.collide_with_areas = false
			params.collide_with_bodies = true
			if space.intersect_ray(params):
				queue_free()
				return
	global_position += motion
	_face_velocity()
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()


## Points the shaft down the arrow's actual path rather than where it was aimed at launch, so the
## fall reads in the model's pitch and not just the position -- the difference between an arrow
## dropping and an arrow that visibly stops caring about gravity.
func _face_velocity() -> void:
	if _velocity.length_squared() < 0.0001:
		return
	var horizontal := Vector3(_velocity.x, 0.0, _velocity.z)
	var up := Vector3.UP if horizontal.length_squared() > 0.0001 else Vector3.FORWARD
	look_at(global_position + _velocity, up)

extends Area3D
class_name Projectile


const PixelStyleScript := preload("res://scripts/art/style/pixel_diorama_style.gd")
const LightEmbersScript := preload("res://scripts/art/vfx/light_embers.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")

@onready var _hitbox: Hitbox = $Hitbox
@onready var _visual: Node3D = $Visual

@export var team: String = "enemy"

@export var pierce := 0

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
	_velocity = direction.normalized() * speed
	_lifetime = 4.0
	_hitbox.set_combat_owner(shooter)
	_hitbox.set_attack_values(
		damage, poise, dmg_type, apply_status, status_stacks, crit_chance, crit_multiplier
	)
	_pierce_remaining = maxi(0, pierce)
	_hitbox.enable()
	look_at(global_position + direction)
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
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()

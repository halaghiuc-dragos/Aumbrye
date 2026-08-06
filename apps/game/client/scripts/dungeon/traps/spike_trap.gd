extends Node3D

## Spike trap — telegraphed floor spikes (TRAP-2.1).

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

enum State { IDLE, TELEGRAPH, ACTIVE, COOLDOWN }

@export var damage := 18.0
@export var poise_damage := 10.0
@export var telegraph_time := 1.2
@export var active_time := 0.6
@export var cooldown_time := 2.5
@export var trigger_radius := 3.0

@onready var _telegraph_mesh: MeshInstance3D = $TelegraphMesh
var _spikes_mesh: Node3D
@onready var _hitbox: TrapDamageArea = $DamageArea

var _state := State.IDLE
var _timer := 0.0
var _player: Node3D


func _ready() -> void:
	var biome := DioramaSkin.resolve_biome(self)
	_spikes_mesh = DioramaSkin.build_spikes(self, biome)
	_spikes_mesh.visible = false
	_telegraph_mesh.material_override = DioramaSkin.make_telegraph_material(Color(1, 0.2, 0.2, 0.5))
	_telegraph_mesh.visible = false
	_hitbox.damage = damage
	_hitbox.poise_damage = poise_damage
	_hitbox.set_damage_active(false)
	_sync_trigger_radius_from_hitbox()
	_player = get_tree().get_first_node_in_group("player")


func _physics_process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	match _state:
		State.IDLE:
			if _player and global_position.distance_to(_player.global_position) <= trigger_radius:
				_state = State.TELEGRAPH
				_timer = telegraph_time
				_telegraph_mesh.visible = true
		State.TELEGRAPH:
			_timer -= delta
			if _timer <= 0.0:
				_activate_spikes()
		State.ACTIVE:
			_timer -= delta
			if _timer <= 0.0:
				_deactivate_spikes()
		State.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.IDLE


func _activate_spikes() -> void:
	_state = State.ACTIVE
	_timer = active_time
	_telegraph_mesh.visible = false
	_spikes_mesh.visible = true
	_hitbox.set_damage_active(true)


func _deactivate_spikes() -> void:
	_state = State.COOLDOWN
	_timer = cooldown_time
	_spikes_mesh.visible = false
	_hitbox.set_damage_active(false)


func _sync_trigger_radius_from_hitbox() -> void:
	var shape_node := _hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return
	var horizontal := 0.0
	var shape := shape_node.shape
	if shape is BoxShape3D:
		var box := shape as BoxShape3D
		horizontal = maxf(box.size.x, box.size.z) * 0.5
	elif shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		horizontal = cap.radius
	elif shape is CylinderShape3D:
		var cyl := shape as CylinderShape3D
		horizontal = cyl.radius
	trigger_radius = maxf(trigger_radius, horizontal + 0.5)

extends Node3D

## Spike trap — telegraphed floor spikes (TRAP-2.1).

enum State { IDLE, TELEGRAPH, ACTIVE, COOLDOWN }

@export var damage := 18.0
@export var poise_damage := 10.0
@export var telegraph_time := 1.2
@export var active_time := 0.6
@export var cooldown_time := 2.5
@export var trigger_radius := 3.0

@onready var _telegraph_mesh: MeshInstance3D = $TelegraphMesh
@onready var _spikes_mesh: MeshInstance3D = $SpikesMesh
@onready var _hitbox: Area3D = $DamageArea

var _state := State.IDLE
var _timer := 0.0
var _player: Node3D


func _ready() -> void:
	_spikes_mesh.visible = false
	_telegraph_mesh.visible = false
	_hitbox.monitoring = false
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
	_hitbox.monitoring = true


func _deactivate_spikes() -> void:
	_state = State.COOLDOWN
	_timer = cooldown_time
	_spikes_mesh.visible = false
	_hitbox.monitoring = false

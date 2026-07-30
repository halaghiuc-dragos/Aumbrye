extends Node3D

## Falling block trap — ceiling telegraph then crush (TRAP-2.1).

enum State { IDLE, TELEGRAPH, FALLING, RESET }

@export var damage := 25.0
@export var poise_damage := 20.0
@export var telegraph_time := 1.5
@export var fall_speed := 12.0
@export var trigger_radius := 2.5

@onready var _block: Node3D = $FallingBlock
@onready var _telegraph: MeshInstance3D = $TelegraphShadow
@onready var _hitbox: Area3D = $FallingBlock/DamageArea

var _state := State.IDLE
var _timer := 0.0
var _rest_y := 0.0
var _player: Node3D


func _ready() -> void:
	_rest_y = _block.position.y
	_telegraph.visible = false
	_hitbox.monitoring = false
	_player = get_tree().get_first_node_in_group("player")


func _physics_process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	match _state:
		State.IDLE:
			if _player and _block.global_position.distance_to(_player.global_position) <= trigger_radius:
				_state = State.TELEGRAPH
				_timer = telegraph_time
				_telegraph.visible = true
		State.TELEGRAPH:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.FALLING
				_telegraph.visible = false
				_hitbox.monitoring = true
		State.FALLING:
			_block.position.y -= fall_speed * delta
			if _block.position.y <= 0.2:
				_block.position.y = 0.2
				_state = State.RESET
				_timer = 2.0
				_hitbox.monitoring = false
		State.RESET:
			_timer -= delta
			if _timer <= 0.0:
				_block.position.y = _rest_y
				_state = State.IDLE

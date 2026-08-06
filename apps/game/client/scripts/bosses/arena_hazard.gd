extends Node3D

## Phase 2 arena hazard — telegraphed fire zone (BOSS-2.2).

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

enum State { TELEGRAPH, ACTIVE, FADE }

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
	_telegraph.material_override = DioramaSkin.make_telegraph_material(Color(1, 0.5, 0, 0.5))
	_active_zone.material_override = DioramaSkin.make_telegraph_material(Color(1, 0.2, 0, 0.9))
	_active_zone.visible = false
	_damage_area.monitoring = false
	if _damage_area:
		_damage_area.damage = damage
		if _damage_area.get("poise_damage") != null:
			_damage_area.poise_damage = poise_damage
	_timer = telegraph_time


func _physics_process(delta: float) -> void:
	match _state:
		State.TELEGRAPH:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.ACTIVE
				_timer = active_time
				_telegraph.visible = false
				_active_zone.visible = true
				_damage_area.monitoring = true
		State.ACTIVE:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.FADE
				_timer = 0.5
				_damage_area.monitoring = false
		State.FADE:
			_timer -= delta
			if _timer <= 0.0:
				queue_free()

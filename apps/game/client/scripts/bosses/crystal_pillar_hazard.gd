extends Node3D

## Crystal pillar hazard — telegraphed arcane zone (BOSS-5.1).

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

enum State { TELEGRAPH, ACTIVE, FADE }

@export var damage := 10.0
@export var telegraph_time := 1.2
@export var active_time := 3.0

@onready var _telegraph: MeshInstance3D = $TelegraphMesh
@onready var _active_zone: MeshInstance3D = $ActiveMesh
@onready var _damage_area: Area3D = $DamageArea

var _state := State.TELEGRAPH
var _timer := 0.0


func _ready() -> void:
	DioramaSkin.build_crystal_pillar(self)
	# C-31: three omissions against the sibling `arena_hazard.gd`. The telegraph tint skipped
	# `emphasise_telegraph_tint`, so the accessibility telegraph-emphasis setting worked on fire
	# zones and not on pillars; `_active_zone` had no material at all, so the live damaging zone
	# and the harmless telegraph could render identically; and `_damage_area.damage` was never
	# assigned, leaving the `@export var damage` dead and the hazard dealing whatever the scene
	# default happened to be.
	_telegraph.material_override = DioramaSkin.make_telegraph_material(
		AccessibilitySettings.emphasise_telegraph_tint(Color(0.4, 0.7, 1, 0.5))
	)
	_active_zone.material_override = DioramaSkin.make_telegraph_material(Color(0.5, 0.85, 1, 0.9))
	_active_zone.visible = false
	_damage_area.monitoring = false
	if _damage_area:
		_damage_area.damage = damage
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

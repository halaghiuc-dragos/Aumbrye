class_name WavesArenaMutator
extends Node3D

## MD-01: "every fifth wave, change the arena" -- kept to lighting/hazard/fog changes rather than
## new solid geometry (a raised platform, pillars) because the Vigil arena has no baked
## `NavigationRegion3D`: `castle_enemy_base.gd`'s `NavigationAgent3D` has nothing to route through
## here, so a new solid obstacle would just get walked straight through rather than navigated
## around. These three states are either non-solid (a damage trigger) or purely visual.

const TrapDamageAreaScript := preload("res://scripts/combat/trap_damage_area.gd")
const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

const STATES: Array[String] = ["open", "dimmed", "hazard", "fog"]
const HAZARD_RADIUS := 8.0
const HAZARD_RING_DIST := 20.0
const FOG_BOOST := 2.2

var _torchlight: Node3D


## Explicit cleanup for run-end -- distinct from `apply_block()` so a caller never has to fake an
## index to reach the "open" state (negative indices wrap from the end of `STATES` in GDScript).
func clear_state() -> void:
	_clear()


func apply_block(block_index: int, torchlight: Node3D, states: Array[String] = []) -> void:
	_torchlight = torchlight
	_clear()
	var pool := states if not states.is_empty() else STATES
	match pool[block_index % pool.size()]:
		"dimmed":
			_apply_dimmed()
		"hazard":
			_build_hazard(block_index)
		"fog":
			_apply_fog()
		_:
			pass


func _clear() -> void:
	for child in get_children():
		child.queue_free()
	if _torchlight and is_instance_valid(_torchlight):
		if _torchlight.has_method("set_far_ring_lit"):
			_torchlight.call("set_far_ring_lit", true)
		if _torchlight.has_method("set_fog_override"):
			_torchlight.call("set_fog_override", 1.0)


## Kills the outer pyre ring for the block -- the plan's own suggested "take something away"
## reads truest as light, and it needs no new collision at all.
func _apply_dimmed() -> void:
	if _torchlight and is_instance_valid(_torchlight) and _torchlight.has_method("set_far_ring_lit"):
		_torchlight.call("set_far_ring_lit", false)


func _apply_fog() -> void:
	if _torchlight and is_instance_valid(_torchlight) and _torchlight.has_method("set_fog_override"):
		_torchlight.call("set_fog_override", FOG_BOOST)


## A standing damage ring the player must route around -- an `Area3D` trigger only, so it changes
## where it is safe to fight without touching enemy pathing.
func _build_hazard(block_index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = block_index * 733 + 11
	var angle := rng.randf_range(0.0, TAU)
	var pos := Vector3(cos(angle) * HAZARD_RING_DIST, 0.0, sin(angle) * HAZARD_RING_DIST)
	var area := Area3D.new()
	area.set_script(TrapDamageAreaScript)
	area.name = "ArenaHazardZone"
	area.position = pos
	area.collision_layer = 4
	area.collision_mask = 8
	area.set("damage", 6.0)
	area.set("poise_damage", 0.0)
	area.set("hit_interval", 0.8)
	add_child(area)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var cyl := CylinderShape3D.new()
	cyl.radius = HAZARD_RADIUS
	cyl.height = 3.0
	shape.shape = cyl
	shape.position = Vector3(0.0, 1.5, 0.0)
	area.add_child(shape)
	var visual := MeshInstance3D.new()
	visual.name = "HazardVisual"
	var mesh := CylinderMesh.new()
	mesh.top_radius = HAZARD_RADIUS
	mesh.bottom_radius = HAZARD_RADIUS
	mesh.height = 0.05
	visual.mesh = mesh
	visual.position = Vector3(0.0, 0.03, 0.0)
	visual.material_override = DioramaSkin.make_telegraph_material(Color(0.85, 0.2, 0.15, 0.65))
	area.add_child(visual)
	area.call_deferred("set_damage_active", true)

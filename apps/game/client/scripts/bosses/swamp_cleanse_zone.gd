extends Node3D

## Swamp cleanse window — safe zone during poison phase (BOSS-5.2).

@export var cleanse_duration := 4.0
@export var cleanse_radius := 2.5

@onready var _zone_mesh: MeshInstance3D = $ZoneMesh

var _timer := 0.0
var _zone_material: StandardMaterial3D


func _ready() -> void:
	_timer = cleanse_duration
	# C-33: one duplicate, owned for the life of the zone.
	if _zone_mesh:
		var mat := _zone_mesh.get_surface_override_material(0)
		if mat == null:
			mat = _zone_mesh.mesh.surface_get_material(0) if _zone_mesh.mesh else null
		if mat is StandardMaterial3D:
			_zone_material = (mat as StandardMaterial3D).duplicate()
			_zone_mesh.set_surface_override_material(0, _zone_material)


func _physics_process(delta: float) -> void:
	_timer -= delta
	_clear_poison_on_player()
	if _timer <= 0.0:
		queue_free()
	elif _zone_mesh:
		# C-33: this duplicated the material every physics frame to animate one alpha value,
		# allocating a StandardMaterial3D per frame for the whole cleanse. The override is
		# duplicated once in `_ready` and then mutated in place.
		var alpha := clampf(_timer / cleanse_duration, 0.2, 1.0)
		if _zone_material:
			_zone_material.albedo_color.a = alpha * 0.5


func is_cleanse_active() -> bool:
	return _timer > 0.0


func _clear_poison_on_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var offset := player.global_position - global_position
	offset.y = 0.0
	if offset.length() > cleanse_radius:
		return
	# C-30: this called `clear_all()`, which wipes the entire status table — relic buffs,
	# consumable buffs, weapon buffs, everything. The mechanic that exists to make the poison phase
	# survivable deleted the player's build the moment they used it. It removes the poison it is
	# named for.
	var status_ctrl := player.get_node_or_null("StatusController") as StatusController
	if status_ctrl:
		status_ctrl.remove_status("poison")

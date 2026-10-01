extends Node3D


const MaterialDissolveScript := preload("res://scripts/art/characters/material_dissolve.gd")
const INTERACT_RANGE := 2.2

var _secret_room_id: String = ""
var _builder: DungeonBuilder = null
var _revealed := false
var _barrier: StaticBody3D
var _tell_floor: StaticBody3D


func configure(secret_room_id: String, builder: DungeonBuilder) -> void:
	_secret_room_id = secret_room_id
	_builder = builder
	_skin(DioramaInteractableSkin.resolve_biome(self))


## An illusory wall has one job: to be indistinguishable from the wall it sits in.
##
## Its mesh carried no material at all, so it rendered in Godot's default grey -- a pale slab in a
## dark stone doorway, which is both the ugliest thing on screen and a free answer to every secret
## in the game. Taking the biome's own wall material is the whole trick.
func _skin(biome_id: String) -> void:
	var mesh_instance := get_node_or_null("StaticBody3D/MeshInstance3D") as MeshInstance3D
	if mesh_instance == null:
		return
	var wall := BiomeRegistry.get_wall_material(biome_id)
	if wall:
		# Walls carry no dissolve, so this one wall gets the surface shader that does: it is the
		# panel that dissolves away when found.
		var dissolving := wall.duplicate() as Material
		if dissolving is ShaderMaterial:
			(dissolving as ShaderMaterial).shader = load(PixelDioramaStyle.SHADER_PATH) as Shader
		mesh_instance.material_override = dissolving


func mark_revealed() -> void:
	_revealed = true
	_disable_barrier()
	visible = false


func _ready() -> void:
	# Skinned on entry as well as on configure: a wall placed by a room template rather than by the
	# builder never gets configured, and it still has to look like the wall around it.
	_skin(DioramaInteractableSkin.resolve_biome(self))
	_barrier = get_node_or_null("StaticBody3D") as StaticBody3D
	# No prompt: a secret panel must not announce itself.
	DungeonInteractionService.register_candidate(
		self, self, INTERACT_RANGE, 1, Callable(self, "_reveal"), Callable(self, "_can_reveal")
	)
	_build_tell()


## The tell must be ignorable -- a very slow, very faint dust-mote drift in front of the
## panel, plus a distinct footstep sound within 1.5m of it. A player not looking should just walk
## past; a player who is looking should feel clever for noticing. Anything louder turns a secret
## into a waypoint.
func _build_tell() -> void:
	if _revealed:
		return
	LightEmbers.attach(self, Vector3(0.0, 1.2, -0.4), Color(0.85, 0.82, 0.7, 0.35), 0.3, 0.6)
	_tell_floor = StaticBody3D.new()
	_tell_floor.name = "HollowFloorTell"
	_tell_floor.collision_layer = 1
	_tell_floor.collision_mask = 0
	_tell_floor.position = Vector3(0.0, 0.02, -1.0)
	_tell_floor.set_meta("surface", "hollow")
	add_child(_tell_floor)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Thin and raised a hair above the room's own floor so a downward probe ray hits this patch
	# first instead of tying with (or losing to) the floor collider underneath it.
	box.size = Vector3(3.0, 0.06, 3.0)
	shape.shape = box
	_tell_floor.add_child(shape)


func _can_reveal() -> bool:
	return not _revealed


func _reveal() -> void:
	if _revealed:
		return
	_revealed = true
	MaterialDissolveScript.dissolve(self)
	_disable_barrier()
	if _builder:
		_builder.reveal_secret(_secret_room_id)


func _disable_barrier() -> void:
	if _barrier:
		_barrier.collision_layer = 0
		_barrier.visible = false

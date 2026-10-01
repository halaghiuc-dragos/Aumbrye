extends Node3D


const INTERACT_RANGE := 2.0

var _secret_room_id: String = ""
var _builder: DungeonBuilder = null
var _used := false


func configure(secret_room_id: String, builder: DungeonBuilder) -> void:
	_secret_room_id = secret_room_id
	_builder = builder
	var flag_id := _flag_id()
	if WorldState.has_flag(flag_id):
		mark_used()


func mark_used() -> void:
	_used = true
	visible = false


func _flag_id() -> String:
	return WorldFlags.secret_opened(_secret_room_id)


func _ready() -> void:
	_skin()
	# No prompt: a hidden lever is only found by looking.
	DungeonInteractionService.register_candidate(
		self, self, INTERACT_RANGE, 1, Callable(self, "_pull"), Callable(self, "_can_pull")
	)


func _can_pull() -> bool:
	return not _used


func _pull() -> void:
	if _used:
		return
	_used = true
	WorldState.set_flag(_flag_id(), true)
	# Finding a secret should sound like finding one, not like every other interact.
	AudioDirector.play_stinger("secret_found")
	if _builder:
		_builder.reveal_secret(_secret_room_id)
	mark_used()


## The lever's mesh carried no material, so the one interactive object in a room was also the one
## grey object in it. It takes the biome accent, the same as every other lever in the game.
func _skin() -> void:
	var mesh_instance := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance == null or mesh_instance.material_override != null:
		return
	var accent := BiomeRegistry.get_accent_material(
		DioramaInteractableSkin.resolve_biome(self)
	)
	if accent:
		mesh_instance.material_override = accent

extends Node3D


var _secret_room_id: String = ""
var _builder: DungeonBuilder = null
var _interact_area: Area3D
var _near_player := false
var _used := false


func configure(secret_room_id: String, builder: DungeonBuilder) -> void:
	_secret_room_id = secret_room_id
	_builder = builder
	var flag_id := _flag_id()
	if WorldState.has_flag(flag_id):
		mark_used()


func mark_used() -> void:
	_used = true
	if _interact_area:
		_interact_area.monitoring = false
	visible = false


func _flag_id() -> String:
	return WorldFlags.secret_opened(_secret_room_id)


func _ready() -> void:
	_skin()
	_interact_area = get_node_or_null("InteractArea") as Area3D
	if _interact_area:
		_interact_area.body_entered.connect(_on_body_entered)
		_interact_area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false


func _unhandled_input(event: InputEvent) -> void:
	if _used or not _near_player:
		return
	if PlayerInput.interact_just_pressed(event):
		_pull()
		get_viewport().set_input_as_handled()


func _pull() -> void:
	if _used:
		return
	_used = true
	WorldState.set_flag(_flag_id(), true)
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

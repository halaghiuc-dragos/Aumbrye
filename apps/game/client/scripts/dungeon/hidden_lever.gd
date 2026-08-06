extends Node3D

## Hidden lever that opens a secret room and persists via WorldState.

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
	if event.is_action_pressed("interact"):
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

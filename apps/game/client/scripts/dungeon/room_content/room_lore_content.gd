extends "res://scripts/dungeon/room_content/room_content_base.gd"

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

var _dialogue_id := "dungeon_lore_default"
var _near_player := false


func configure(entry: Dictionary, _definition: Dictionary) -> void:
	_dialogue_id = str(entry.get("dialogueId", _dialogue_id))
	var prop := Node3D.new()
	prop.name = "LoreProp"
	var interact := Area3D.new()
	interact.name = "InteractArea"
	interact.collision_layer = 0
	interact.collision_mask = 2
	interact.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.5, 2.0)
	shape.shape = box
	interact.add_child(shape)
	prop.add_child(interact)
	interact.body_entered.connect(_on_body_entered)
	interact.body_exited.connect(_on_body_exited)
	prop.position = _anchor(0).position
	DioramaSkin.build_lectern(prop, DioramaSkin.resolve_biome(self))
	_content_root().add_child(prop)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _near_player:
		return
	var dialogue_ui := get_tree().get_first_node_in_group("dialogue_ui")
	if dialogue_ui and dialogue_ui.has_method("start_dialogue"):
		if dialogue_ui.call("start_dialogue", _dialogue_id):
			get_viewport().set_input_as_handled()

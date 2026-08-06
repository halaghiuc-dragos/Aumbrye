extends "res://scripts/dungeon/room_content/room_content_base.gd"

const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")

var _quest_key_id := ""
var _dialogue_id := "dungeon_npc_stranded"
var _npc: Node3D
var _interact_area: Area3D


func configure(entry: Dictionary, _definition: Dictionary) -> void:
	_quest_key_id = str(entry.get("questKeyId", ""))
	_dialogue_id = str(entry.get("dialogueId", _dialogue_id))
	_npc = Node3D.new()
	_npc.name = "QuestNpc"
	DIORAMA_SKIN.build_npc(_npc, DIORAMA_SKIN.resolve_biome(self))
	_interact_area = Area3D.new()
	_interact_area.name = "InteractArea"
	_interact_area.collision_layer = 0
	_interact_area.collision_mask = 2
	_interact_area.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 2.5, 2.5)
	shape.shape = box
	_interact_area.add_child(shape)
	_npc.add_child(_interact_area)
	_interact_area.body_entered.connect(_on_body_entered.bind(_interact_area))
	_interact_area.body_exited.connect(_on_body_exited.bind(_interact_area))
	_npc.position = _anchor(0).position
	_content_root().add_child(_npc)


func _on_body_entered(body: Node3D, area: Area3D) -> void:
	if body.is_in_group("player"):
		area.set_meta("near_player", true)


func _on_body_exited(body: Node3D, area: Area3D) -> void:
	if body.is_in_group("player"):
		area.set_meta("near_player", false)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if _interact_area == null or not _interact_area.get_meta("near_player", false):
		return
	var dialogue_ui := get_tree().get_first_node_in_group("dialogue_ui")
	if dialogue_ui and dialogue_ui.has_method("start_dialogue"):
		if dialogue_ui.call("start_dialogue", _dialogue_id):
			get_viewport().set_input_as_handled()
			return
	if _quest_key_id != "":
		WorldState.set_flag(WorldFlags.secret_opened(_quest_key_id), true)
	get_viewport().set_input_as_handled()

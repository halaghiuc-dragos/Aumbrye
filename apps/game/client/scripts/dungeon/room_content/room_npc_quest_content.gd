extends "res://scripts/dungeon/room_content/room_content_base.gd"

var _quest_key_id := ""


func configure(entry: Dictionary, _definition: Dictionary) -> void:
	_quest_key_id = str(entry.get("questKeyId", ""))
	var npc := Node3D.new()
	npc.name = "QuestNpc"
	var interact := Area3D.new()
	interact.name = "InteractArea"
	interact.collision_layer = 0
	interact.collision_mask = 2
	interact.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 2.5, 2.5)
	shape.shape = box
	interact.add_child(shape)
	npc.add_child(interact)
	interact.body_entered.connect(_on_body_entered.bind(interact))
	interact.body_exited.connect(_on_body_exited.bind(interact))
	npc.position = Vector3(-2.0, 0.0, 1.0)
	_content_root().add_child(npc)


func _on_body_entered(body: Node3D, area: Area3D) -> void:
	if body.is_in_group("player"):
		area.set_meta("near_player", true)


func _on_body_exited(body: Node3D, area: Area3D) -> void:
	if body.is_in_group("player"):
		area.set_meta("near_player", false)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	var area := get_node_or_null("QuestNpc/InteractArea") as Area3D
	if area == null or not area.get_meta("near_player", false):
		return
	if _quest_key_id != "":
		WorldState.set_flag("quest_%s_active" % _quest_key_id, true)
	get_viewport().set_input_as_handled()

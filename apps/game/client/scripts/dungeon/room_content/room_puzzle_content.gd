extends "res://scripts/dungeon/room_content/room_content_base.gd"

var _flag_id := ""
var _gate_room_id := ""


func configure(entry: Dictionary, definition: Dictionary) -> void:
	for puzzle in definition.get("puzzles", []):
		if puzzle.get("triggerRoomId", "") == entry.get("roomId", ""):
			_flag_id = str(puzzle.get("flagId", ""))
			_gate_room_id = str(puzzle.get("gateRoomId", ""))
			break
	var lever := Node3D.new()
	lever.name = "PuzzleLever"
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
	lever.add_child(interact)
	interact.body_entered.connect(_on_body_entered.bind(interact))
	interact.body_exited.connect(_on_body_exited.bind(interact))
	lever.position = Vector3(3.0, 0.0, 0.0)
	_content_root().add_child(lever)


func _on_body_entered(body: Node3D, area: Area3D) -> void:
	if body.is_in_group("player"):
		area.set_meta("near_player", true)


func _on_body_exited(body: Node3D, area: Area3D) -> void:
	if body.is_in_group("player"):
		area.set_meta("near_player", false)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	var lever := get_node_or_null("PuzzleLever/InteractArea") as Area3D
	if lever == null or not lever.get_meta("near_player", false):
		return
	if _flag_id != "":
		WorldState.set_flag(_flag_id, true)
	get_viewport().set_input_as_handled()

extends "res://scripts/dungeon/room_content/room_content_base.gd"

const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")

var _flag_id := ""
var _solution_order: Array = []
var _pull_order: Array[int] = []
var _lever_areas: Array[Area3D] = []
var _lever_nodes: Array[Node3D] = []
var _solved := false


func configure(entry: Dictionary, definition: Dictionary) -> void:
	var puzzle := _puzzle_for_room(entry, definition)
	if puzzle.is_empty():
		push_error(
			(
				"RoomPuzzleContent: room '%s' has a puzzle_lever_gate entry with no matching"
				+ " `puzzles` record — skipping rather than spawning an unsolvable lever."
			)
			% str(entry.get("roomId", "?"))
		)
		return
	_flag_id = str(puzzle.get("flagId", ""))
	_solution_order = puzzle.get("solutionOrder", [])
	var lever_count := int(puzzle.get("leverCount", 1))
	if _flag_id != "" and WorldState.is_flag_true(WorldFlags.lever_pulled(_flag_id)):
		_solved = true
	for i in lever_count:
		var lever := Node3D.new()
		lever.name = "PuzzleLever_%d" % i
		DIORAMA_SKIN.build_lever(lever, DIORAMA_SKIN.resolve_biome(self))
		var interact := Area3D.new()
		interact.name = "InteractArea"
		interact.collision_layer = 0
		interact.collision_mask = 2
		interact.monitoring = true
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.0, 2.0, 2.0)
		shape.shape = box
		interact.add_child(shape)
		lever.add_child(interact)
		interact.body_entered.connect(_on_body_entered.bind(interact))
		interact.body_exited.connect(_on_body_exited.bind(interact))
		lever.position = _anchor(i).position
		_content_root().add_child(lever)
		_lever_areas.append(interact)
		_lever_nodes.append(lever)
	if _solved:
		_hide_levers()


func _puzzle_for_room(entry: Dictionary, definition: Dictionary) -> Dictionary:
	var room_id := str(entry.get("roomId", ""))
	for puzzle in definition.get("puzzles", []):
		if str(puzzle.get("roomId", "")) == room_id:
			return puzzle
	return {}


func _on_body_entered(body: Node3D, area: Area3D) -> void:
	if body.is_in_group("player"):
		area.set_meta("near_player", true)


func _on_body_exited(body: Node3D, area: Area3D) -> void:
	if body.is_in_group("player"):
		area.set_meta("near_player", false)


func _unhandled_input(event: InputEvent) -> void:
	if _solved or not PlayerInput.interact_just_pressed(event):
		return
	for i in _lever_areas.size():
		var area := _lever_areas[i]
		if not area.get_meta("near_player", false):
			continue
		_pull_lever(i)
		get_viewport().set_input_as_handled()
		return


func _pull_lever(index: int) -> void:
	if _solved:
		return
	_pull_order.append(index)
	if _pull_order.size() > _solution_order.size():
		_reset_levers()
		return
	var expected: int = int(_solution_order[_pull_order.size() - 1])
	if expected != index:
		_reset_levers()
		return
	if _pull_order.size() == _solution_order.size():
		_solve()


func _solve() -> void:
	_solved = true
	if _flag_id != "":
		WorldState.set_flag(WorldFlags.lever_pulled(_flag_id), true)
	_hide_levers()


func _reset_levers() -> void:
	_pull_order.clear()
	for lever in _lever_nodes:
		lever.rotation.z = 0.0


func _hide_levers() -> void:
	for lever in _lever_nodes:
		lever.visible = false

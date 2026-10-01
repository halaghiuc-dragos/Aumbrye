extends "res://scripts/dungeon/room_content/room_content_base.gd"

const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")

const INTERACT_RANGE := 1.9
## Braziers above the levers light in the solution order, a beat apiece, then the cycle repeats.
const CLUE_STEP_SECONDS := 0.9
const CLUE_PAUSE_SECONDS := 3.0
const BRAZIER_DIM_ENERGY := 0.15
const BRAZIER_LIT_ENERGY := 2.6
const BRAZIER_LIT_COLOR := Color(1.0, 0.72, 0.3)
const BRAZIER_DIM_COLOR := Color(0.25, 0.12, 0.06)

var _flag_id := ""
var _solution_order: Array = []
var _pull_order: Array[int] = []
var _lever_nodes: Array[Node3D] = []
var _lever_prompts: Array[InteractPrompt] = []
var _braziers: Array[MeshInstance3D] = []
var _brazier_lights: Array[OmniLight3D] = []
var _brazier_material: StandardMaterial3D
var _solved := false
var _clue_time := 0.0


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
		lever.position = _anchor(i).position
		_content_root().add_child(lever)
		_lever_nodes.append(lever)
		_add_number_plate(lever, i)
		_add_brazier(lever)
		var prompt := InteractPrompt.build(lever, Vector3(0.0, 2.4, 0.0))
		_lever_prompts.append(prompt)
		DungeonInteractionService.register_candidate(
			lever,
			lever,
			INTERACT_RANGE,
			3,
			Callable(self, "_pull_lever").bind(i),
			Callable(self, "_can_pull"),
			Callable(self, "_set_lever_prompt").bind(i)
		)
	if _solved:
		_finish_levers()
	else:
		set_process(true)


func _add_number_plate(lever: Node3D, index: int) -> void:
	var plate := Label3D.new()
	plate.name = "NumberPlate"
	plate.text = str(index + 1)
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.font_size = 40
	plate.outline_size = 12
	plate.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	plate.position = Vector3(0.0, 1.35, 0.0)
	lever.add_child(plate)


## The clue is in the room, not on a label: the brazier over each lever is lit in turn.
func _add_brazier(lever: Node3D) -> void:
	if _brazier_material == null:
		_brazier_material = StandardMaterial3D.new()
		_brazier_material.emission_enabled = true
	var brazier := MeshInstance3D.new()
	brazier.name = "ClueBrazier"
	brazier.mesh = PropLibrary.bare_mesh("fx/clue_bowl")
	brazier.material_override = _brazier_material.duplicate() as StandardMaterial3D
	brazier.position = Vector3(0.0, 2.9, 0.0)
	lever.add_child(brazier)
	var light := OmniLight3D.new()
	light.omni_range = 6.0
	light.shadow_enabled = false
	brazier.add_child(light)
	_braziers.append(brazier)
	_brazier_lights.append(light)
	_set_brazier(_braziers.size() - 1, false)


func _set_brazier(index: int, lit: bool) -> void:
	var material := _braziers[index].material_override as StandardMaterial3D
	var color := BRAZIER_LIT_COLOR if lit else BRAZIER_DIM_COLOR
	material.albedo_color = color
	material.emission = color
	material.emission_energy_multiplier = 2.0 if lit else 0.3
	_brazier_lights[index].light_color = color
	_brazier_lights[index].light_energy = BRAZIER_LIT_ENERGY if lit else BRAZIER_DIM_ENERGY


func _process(delta: float) -> void:
	if _solved or _solution_order.is_empty():
		return
	var cycle := float(_solution_order.size()) * CLUE_STEP_SECONDS + CLUE_PAUSE_SECONDS
	_clue_time = fmod(_clue_time + delta, cycle)
	var step := int(_clue_time / CLUE_STEP_SECONDS)
	var lit := int(_solution_order[step]) if step < _solution_order.size() else -1
	for i in _braziers.size():
		_set_brazier(i, i == lit)


func _puzzle_for_room(entry: Dictionary, definition: Dictionary) -> Dictionary:
	var room_id := str(entry.get("roomId", ""))
	for puzzle in definition.get("puzzles", []):
		if str(puzzle.get("roomId", "")) == room_id:
			return puzzle
	return {}


func _can_pull() -> bool:
	return not _solved


func _set_lever_prompt(active: bool, index: int) -> void:
	if active and not _solved:
		_lever_prompts[index].show_action(tr("PUZZLE_PULL_LEVER"))
	else:
		_lever_prompts[index].hide_prompt()


func _pull_lever(index: int) -> void:
	if _solved:
		return
	_pull_order.append(index)
	_lever_nodes[index].rotation.z = -0.55
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
	_finish_levers()


## A wrong order puts every lever back with a thud, so the reset is never silent.
func _reset_levers() -> void:
	_pull_order.clear()
	for lever in _lever_nodes:
		lever.rotation.z = 0.0
	if not _lever_nodes.is_empty():
		AudioDirector.play_sfx("resource_denied", _lever_nodes[0].global_position)
	VfxService.request_shake(0.18, 260)


func _finish_levers() -> void:
	set_process(false)
	for lever in _lever_nodes:
		lever.rotation.z = -0.55
	for i in _braziers.size():
		_set_brazier(i, true)
	for prompt in _lever_prompts:
		prompt.hide_prompt()

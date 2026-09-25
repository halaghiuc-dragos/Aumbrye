extends Node

## IX08: Dungeon content registers an action here instead of competing through independent
## `_unhandled_input` callbacks.  The service owns both the selected prompt and the action, so a
## prompt can never advertise a different object from the one that will receive Interact.

const HYSTERESIS_MARGIN := 0.35

var _candidates: Dictionary = {}
var _selected_id := 0


func register_candidate(
		node: Node3D,
		focus: Node3D,
		range_meters: float,
		priority: int,
		action: Callable,
		availability: Callable = Callable(),
		prompt: Callable = Callable(),
		requires_los: bool = false
	) -> void:
	if node == null or focus == null or not action.is_valid():
		push_error("DungeonInteractionService: candidate needs node, focus and action")
		return
	var candidate_id := node.get_instance_id()
	_candidates[candidate_id] = {
		"node": node,
		"focus": focus,
		"range": maxf(0.1, range_meters),
		"priority": priority,
		"action": action,
		"availability": availability,
		"prompt": prompt,
		"requires_los": requires_los,
	}
	if not node.tree_exiting.is_connected(_on_candidate_tree_exiting.bind(candidate_id)):
		node.tree_exiting.connect(_on_candidate_tree_exiting.bind(candidate_id), CONNECT_ONE_SHOT)
	refresh()


func unregister_candidate(node: Node) -> void:
	if node == null:
		return
	_remove_candidate(node.get_instance_id())


func refresh() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var camera := get_viewport().get_camera_3d()
	var previous := _selected_id
	_selected_id = _find_best_candidate(player, camera)
	if previous == _selected_id:
		return
	_update_prompts(previous, _selected_id)


func selected_candidate_id() -> int:
	return _selected_id


func _physics_process(_delta: float) -> void:
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not PlayerInput.interact_just_pressed(event):
		return
	refresh()
	var selected: Dictionary = _candidates.get(_selected_id, {}) as Dictionary
	if selected.is_empty():
		return
	var action: Callable = selected.get("action", Callable()) as Callable
	if action.is_valid():
		action.call()
		get_viewport().set_input_as_handled()
		refresh()


func _find_best_candidate(player: Node3D, camera: Camera3D) -> int:
	if player == null:
		return 0
	var best_id := 0
	var best_score := INF
	var current_score := INF
	for candidate_id_value in _candidates.keys():
		var candidate_id := int(candidate_id_value)
		var candidate: Dictionary = _candidates[candidate_id] as Dictionary
		if not _candidate_available(candidate, player):
			continue
		var score := _candidate_score(candidate, player, camera)
		if is_inf(score):
			continue
		if candidate_id == _selected_id:
			current_score = score
		if score < best_score:
			best_score = score
			best_id = candidate_id
	if _selected_id != 0 and current_score <= best_score + HYSTERESIS_MARGIN:
		return _selected_id
	return best_id


func _candidate_available(candidate: Dictionary, player: Node3D) -> bool:
	var node := candidate.get("node") as Node3D
	var focus := candidate.get("focus") as Node3D
	if node == null or focus == null or not is_instance_valid(node) or not is_instance_valid(focus):
		return false
	if player.global_position.distance_to(focus.global_position) > float(candidate.get("range", 0.0)):
		return false
	var availability: Callable = candidate.get("availability", Callable()) as Callable
	if availability.is_valid() and not bool(availability.call()):
		return false
	return not bool(candidate.get("requires_los", false)) or _has_line_of_sight(player, focus, node)


func _candidate_score(candidate: Dictionary, player: Node3D, camera: Camera3D) -> float:
	var focus := candidate.get("focus") as Node3D
	var distance := player.global_position.distance_to(focus.global_position)
	var direction_penalty := 0.0
	if camera != null:
		var to_focus := (focus.global_position - camera.global_position).normalized()
		direction_penalty = (1.0 - maxf(-1.0, camera.global_transform.basis.z.dot(-to_focus))) * 0.4
	return distance + direction_penalty - float(candidate.get("priority", 0)) * 0.15


func _has_line_of_sight(player: Node3D, focus: Node3D, candidate_node: Node3D) -> bool:
	var world := player.get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, focus.global_position)
	query.exclude = [player.get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider := hit.get("collider") as Node
	return collider == candidate_node or candidate_node.is_ancestor_of(collider)


func _update_prompts(previous: int, current: int) -> void:
	_set_prompt_active(previous, false)
	_set_prompt_active(current, true)


func _set_prompt_active(candidate_id: int, active: bool) -> void:
	var candidate: Dictionary = _candidates.get(candidate_id, {}) as Dictionary
	var prompt: Callable = candidate.get("prompt", Callable()) as Callable
	if prompt.is_valid():
		prompt.call(active)


func _on_candidate_tree_exiting(candidate_id: int) -> void:
	_remove_candidate(candidate_id)


func _remove_candidate(candidate_id: int) -> void:
	if candidate_id == _selected_id:
		_set_prompt_active(candidate_id, false)
		_selected_id = 0
	_candidates.erase(candidate_id)
	refresh()

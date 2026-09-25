extends Node3D

var _failures := 0
var _actions: Dictionary = {}
var _prompts: Dictionary = {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _ready() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	var merchant := _candidate("merchant", Vector3(0.0, 0.0, -1.0))
	var lore := _candidate("lore", Vector3(0.5, 0.0, -1.0))
	DungeonInteractionService.register_candidate(merchant, merchant, 3.0, 4, Callable(self, "_action").bind("merchant"), Callable(), Callable(self, "_prompt").bind("merchant"))
	DungeonInteractionService.register_candidate(lore, lore, 3.0, 1, Callable(self, "_action").bind("lore"), Callable(), Callable(self, "_prompt").bind("lore"))
	DungeonInteractionService.refresh()
	_check(DungeonInteractionService.selected_candidate_id() == merchant.get_instance_id(), "Merchant wins a nearby lore overlap by priority")
	_check(bool(_prompts.get("merchant", false)) and not bool(_prompts.get("lore", false)), "Only the selected candidate owns the visible prompt")
	_activate_interact()
	_check(int(_actions.get("merchant", 0)) == 1 and int(_actions.get("lore", 0)) == 0, "Interact activates only the selected candidate")

	DungeonInteractionService.unregister_candidate(merchant)
	DungeonInteractionService.unregister_candidate(lore)
	merchant.queue_free()
	lore.queue_free()
	var blocked := _candidate("blocked", Vector3(0.0, 0.0, -3.0))
	var visible_candidate := _candidate("visible", Vector3(1.0, 0.0, -1.0))
	_add_wall(Vector3(0.0, 1.0, -1.5))
	DungeonInteractionService.register_candidate(blocked, blocked, 4.0, 5, Callable(self, "_action").bind("blocked"), Callable(), Callable(), true)
	DungeonInteractionService.register_candidate(visible_candidate, visible_candidate, 4.0, 1, Callable(self, "_action").bind("visible"), Callable(), Callable(), true)
	await get_tree().physics_frame
	DungeonInteractionService.refresh()
	_check(DungeonInteractionService.selected_candidate_id() == visible_candidate.get_instance_id(), "An obstructed higher-priority interaction cannot beat a visible candidate")
	player.position = Vector3(0.7, 0.0, 0.0)
	DungeonInteractionService.refresh()
	_check(DungeonInteractionService.selected_candidate_id() == visible_candidate.get_instance_id(), "Selection remains stable while moving between nearby prompts")
	print("DUNGEON INTERACTION RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _candidate(candidate_name: String, position_value: Vector3) -> Node3D:
	var candidate := Node3D.new()
	candidate.name = candidate_name
	candidate.position = position_value
	add_child(candidate)
	return candidate


func _add_wall(position_value: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.position = position_value
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 2.0, 0.2)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)


func _activate_interact() -> void:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	DungeonInteractionService._unhandled_input(event)


func _action(candidate_id: String) -> void:
	_actions[candidate_id] = int(_actions.get(candidate_id, 0)) + 1


func _prompt(active: bool, candidate_id: String) -> void:
	_prompts[candidate_id] = active

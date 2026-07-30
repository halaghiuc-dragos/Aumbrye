extends RefCounted
class_name DialogueRunner

## Executes JSON branching dialogue trees (DLG-4.1).

signal line_changed(speaker: String, text: String, choices: Array)
signal dialogue_ended
signal action_triggered(action: Dictionary)

var _dialogue: Dictionary = {}
var _current_node_id: String = ""
var _active := false


func is_active() -> bool:
	return _active


func start(dialogue_id: String) -> bool:
	_dialogue = DialogueCatalog.get_dialogue(dialogue_id)
	if _dialogue.is_empty():
		return false
	_current_node_id = str(_dialogue.get("startNode", "start"))
	_active = true
	_advance_to_node(_current_node_id)
	return true


func select_choice(index: int) -> void:
	if not _active:
		return
	var node: Dictionary = _get_current_node()
	var choices: Array = _get_visible_choices(node)
	if index < 0 or index >= choices.size():
		return
	var choice: Dictionary = choices[index]
	_apply_actions(choice.get("actions", []))
	var next_id: String = str(choice.get("next", ""))
	if next_id.is_empty() or next_id == "end":
		end_dialogue()
		return
	_current_node_id = next_id
	_advance_to_node(_current_node_id)


func advance() -> void:
	if not _active:
		return
	var node: Dictionary = _get_current_node()
	var choices: Array = _get_visible_choices(node)
	if choices.is_empty():
		var next_id: String = str(node.get("next", ""))
		if next_id.is_empty() or next_id == "end":
			end_dialogue()
			return
		_current_node_id = next_id
		_advance_to_node(_current_node_id)


func end_dialogue() -> void:
	_active = false
	_dialogue.clear()
	_current_node_id = ""
	dialogue_ended.emit()


func _advance_to_node(node_id: String) -> void:
	var node: Dictionary = _get_node(node_id)
	if node.is_empty():
		end_dialogue()
		return
	if not DialogueConditions.evaluate(node.get("condition")):
		var fallback: String = str(node.get("fallback", ""))
		if fallback != "":
			_advance_to_node(fallback)
		else:
			end_dialogue()
		return
	_apply_actions(node.get("actions", []))
	var speaker: String = str(node.get("speaker", ""))
	var text: String = str(node.get("text", ""))
	var choices: Array = _get_visible_choices(node)
	line_changed.emit(speaker, text, choices)
	if choices.is_empty() and not node.has("next"):
		return
	if choices.is_empty():
		var next_id: String = str(node.get("next", ""))
		if next_id.is_empty() or next_id == "end":
			end_dialogue()
			return
		_current_node_id = next_id
		_advance_to_node(_current_node_id)


func _get_current_node() -> Dictionary:
	return _get_node(_current_node_id)


func _get_node(node_id: String) -> Dictionary:
	var nodes: Variant = _dialogue.get("nodes", {})
	if nodes is Dictionary:
		var node: Variant = nodes.get(node_id, {})
		return node if node is Dictionary else {}
	return {}


func _get_visible_choices(node: Dictionary) -> Array:
	var result: Array = []
	for choice in node.get("choices", []):
		if choice is Dictionary and DialogueConditions.evaluate(choice.get("condition")):
			result.append(choice)
	return result


func _apply_actions(actions: Variant) -> void:
	if not actions is Array:
		return
	for action in actions:
		if action is Dictionary:
			_execute_action(action)


func _execute_action(action: Dictionary) -> void:
	var action_type: String = str(action.get("type", ""))
	match action_type:
		"set_flag":
			CharacterService.set_flag(str(action.get("flag", "")), action.get("value", true))
		"add_gold":
			CharacterService.add_gold(int(action.get("amount", 0)))
		"start_quest":
			QuestService.accept_quest(str(action.get("questId", "")))
		"complete_quest":
			QuestService.complete_quest(str(action.get("questId", "")))
		"open_blacksmith", "open_merchant", "open_quest_board", "open_storage":
			action_triggered.emit(action)
		_:
			action_triggered.emit(action)

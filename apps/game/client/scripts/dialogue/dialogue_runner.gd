extends RefCounted
class_name DialogueRunner


signal line_changed(speaker: String, text: String, choices: Array)
signal dialogue_ended
signal action_triggered(action: Dictionary)

const RELATIONSHIP_FLAG_PREFIX := "rel_"
const STORY_BEAT_FLAG := "story_beat"

const UI_ACTIONS := [
	"open_blacksmith",
	"open_merchant",
	"open_quest_board",
	"open_storage",
]

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
	_dialogue = {}
	_current_node_id = ""
	dialogue_ended.emit()


func _advance_to_node(node_id: String) -> void:
	var visited: Dictionary = {}
	var current_id := node_id
	while true:
		if visited.has(current_id):
			push_error("DialogueRunner: cyclic dialogue graph detected at node '%s'" % current_id)
			end_dialogue()
			return
		visited[current_id] = true
		var node: Dictionary = _get_node(current_id)
		if node.is_empty():
			end_dialogue()
			return
		if not DialogueConditions.evaluate(node.get("condition")):
			var fallback: String = str(node.get("fallback", ""))
			if fallback != "":
				current_id = fallback
				continue
			end_dialogue()
			return
		_apply_actions(node.get("actions", []))
		var speaker: String = str(node.get("speaker", ""))
		var text: String = str(node.get("text", ""))
		var choices: Array = _get_visible_choices(node)
		_current_node_id = current_id
		line_changed.emit(speaker, text, choices)
		if not choices.is_empty():
			return
		if not node.get("auto", false):
			return
		var next_id: String = str(node.get("next", ""))
		if next_id.is_empty() or next_id == "end":
			end_dialogue()
			return
		current_id = next_id


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
		"increment_flag":
			var counter_id: String = str(action.get("flag", ""))
			var amount: int = int(action.get("amount", 1))
			CharacterService.set_flag(counter_id, DialogueConditions.flag_number(counter_id) + amount)
		"add_gold":
			CharacterService.add_gold(int(action.get("amount", 0)))
		"start_quest":
			QuestService.accept_quest(str(action.get("questId", "")))
		"complete_quest":
			QuestService.complete_quest(str(action.get("questId", "")))
		"give_item":
			InventoryService.add_item(
				str(action.get("itemId", "")), int(action.get("quantity", 1))
			)
		"take_item":
			InventoryService.inventory.remove_items_by_id(
				str(action.get("itemId", "")), int(action.get("quantity", 1))
			)
		"unlock_recipe":
			LocalSave.add_recipe(str(action.get("recipeId", "")))
		"set_relationship":
			_apply_relationship(action)
		"play_sfx":
			AudioDirector.play_sfx(str(action.get("sfxId", "ui")))
		"advance_story_beat":
			var beat: int = int(action.get("beat", 0))
			if beat > DialogueConditions.flag_number(STORY_BEAT_FLAG):
				CharacterService.set_flag(STORY_BEAT_FLAG, beat)
		"record_discovery":
			QuestService.register_discovery(str(action.get("discoveryId", "")))
		"record_rescue":
			QuestService.register_rescue(str(action.get("npcId", "")))
		_:
			if action_type not in UI_ACTIONS:
				push_error("DialogueRunner: unrecognized action type '%s'" % action_type)
				assert(false, "DialogueRunner: unrecognized action type '%s'" % action_type)
			action_triggered.emit(action)


func _apply_relationship(action: Dictionary) -> void:
	var npc_key: String = str(action.get("npc", ""))
	if npc_key == "":
		return
	var flag_id := "%s%s" % [RELATIONSHIP_FLAG_PREFIX, npc_key]
	if action.has("value"):
		CharacterService.set_flag(flag_id, int(action.get("value", 0)))
		return
	CharacterService.set_flag(flag_id, DialogueConditions.flag_number(flag_id) + int(action.get("delta", 1)))


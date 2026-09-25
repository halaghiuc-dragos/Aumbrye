extends RefCounted
class_name DialogueRunner


signal line_changed(speaker: String, text: String, choices: Array)
signal dialogue_ended
signal action_triggered(action: Dictionary)
signal action_failed(message: String)

const RELATIONSHIP_FLAG_PREFIX := "rel_"
const STORY_BEAT_FLAG := "story_beat"
const DungeonQuestCatalogScript := preload("res://scripts/quests/dungeon_quest_catalog.gd")

const UI_ACTIONS := [
	"open_blacksmith",
	"open_merchant",
	"open_quest_board",
	"open_storage",
]

var _dialogue: Dictionary = {}
var _current_node_id: String = ""
var _active := false
var _presented_choices: Dictionary = {}
var _ignore_conditions := false
var _suppressed_action_types: Dictionary = {}

enum StartResult { FAILED, COMPLETED, OPENED }


func is_active() -> bool:
	return _active


func start(
	dialogue_id: String,
	start_node_override: String = "",
	ignore_conditions: bool = false,
	suppressed_action_types: Array[String] = []
) -> StartResult:
	var candidate := DialogueCatalog.get_dialogue(dialogue_id)
	if candidate.is_empty():
		return StartResult.FAILED
	var start_node_id := start_node_override if start_node_override != "" else str(candidate.get("startNode", "start"))
	var nodes: Variant = candidate.get("nodes", {})
	if not nodes is Dictionary or not (nodes as Dictionary).get(start_node_id) is Dictionary:
		return StartResult.FAILED
	_dialogue = candidate
	_ignore_conditions = ignore_conditions
	_suppressed_action_types.clear()
	for action_type in suppressed_action_types:
		_suppressed_action_types[action_type] = true
	_current_node_id = start_node_id
	_active = true
	_advance_to_node(_current_node_id)
	return StartResult.OPENED if _active else StartResult.COMPLETED


func select_choice(index: int) -> void:
	if not _active:
		return
	var choices: Array = _presented_choices.values()
	if index < 0 or index >= choices.size():
		return
	select_choice_id(str((choices[index] as Dictionary).get("_choiceId", "")))


func select_choice_id(choice_id: String) -> void:
	if not _active or not _presented_choices.has(choice_id):
		return
	var choice: Dictionary = _presented_choices[choice_id]
	if not DialogueConditions.evaluate(choice.get("condition")):
		action_failed.emit("That choice is no longer available.")
		_advance_to_node(_current_node_id)
		return
	if not _apply_actions(choice.get("actions", [])):
		return
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
	if not _active:
		return
	_active = false
	_dialogue = {}
	_current_node_id = ""
	_presented_choices.clear()
	_ignore_conditions = false
	_suppressed_action_types.clear()
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
		if not _conditions_met(node.get("condition")):
			var fallback: String = str(node.get("fallback", ""))
			if fallback != "":
				current_id = fallback
				continue
			end_dialogue()
			return
		if not _apply_actions(node.get("actions", [])):
			return
		var speaker: String = str(node.get("speaker", ""))
		var text: String = str(node.get("text", ""))
		var choices: Array = _get_visible_choices(node, current_id)
		_presented_choices.clear()
		for choice in choices:
			_presented_choices[str((choice as Dictionary).get("_choiceId", ""))] = choice
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


func _get_visible_choices(node: Dictionary, node_id: String = "") -> Array:
	var result: Array = []
	var identity_node := node_id if node_id != "" else _current_node_id
	var authored_choices: Array = node.get("choices", [])
	for choice_index in authored_choices.size():
		var choice: Variant = authored_choices[choice_index]
		if choice is Dictionary and _conditions_met(choice.get("condition")):
			var presented := (choice as Dictionary).duplicate(true)
			presented["_choiceId"] = str(
				presented.get("id", "%s:%d" % [identity_node, choice_index])
			)
			result.append(presented)
	return result


func _apply_actions(actions: Variant) -> bool:
	if not actions is Array:
		return true
	var inventory_actions: Array[Dictionary] = []
	var payment_receipts: Array[String] = []
	for raw in actions:
		if not raw is Dictionary:
			continue
		var action: Dictionary = raw
		var action_type := str(action.get("type", ""))
		if action_type in ["give_item", "take_item"]:
			inventory_actions.append(action)
		elif action_type == "grant_dungeon_payment":
			var payment := _payment_action(action)
			if payment.is_empty():
				return false
			inventory_actions.append(payment)
			payment_receipts.append(str(payment.get("receiptFlag", "")))
	if not inventory_actions.is_empty():
		var inv := InventoryService.inventory
		var working := GridInventory.new(inv.grid_width, inv.grid_height)
		working.from_save_dict(inv.to_save_dict())
		for action in inventory_actions:
			var item_id := str(action.get("itemId", ""))
			var quantity := maxi(1, int(action.get("quantity", 1)))
			if str(action.get("type", "")) == "take_item":
				if working.count_by_id(item_id) < quantity:
					action_failed.emit("Required items are no longer available.")
					return false
				working.remove_items_by_id(item_id, quantity)
			else:
				if not working.add_item(item_id, quantity):
					action_failed.emit("Inventory is full. Make room and try again.")
					return false
		inv.from_save_dict(working.to_save_dict())
		for receipt_flag in payment_receipts:
			CharacterService.set_flag(receipt_flag, true)
	for action in actions:
		if action is Dictionary:
			if _suppressed_action_types.has(str((action as Dictionary).get("type", ""))):
				continue
			if str(action.get("type", "")) in ["give_item", "take_item", "grant_dungeon_payment"]:
				continue
			_execute_action(action)
	return true


func _payment_action(action: Dictionary) -> Dictionary:
	var quest_id := str(action.get("questId", ""))
	var quest := DungeonQuestCatalogScript.quest_for_id(quest_id)
	var delivery := DungeonQuestCatalogScript.delivery_for_quest(quest)
	var item_id := str(delivery.get("itemId", ""))
	var receipt_flag := str(delivery.get("receiptFlag", ""))
	if str(delivery.get("kind", "")) != "npc_payment" or item_id == "" or receipt_flag == "":
		action_failed.emit("This payment is not configured correctly.")
		return {}
	if CharacterService.is_flag_truthy(receipt_flag):
		action_failed.emit("That payment has already been received.")
		return {}
	return {"type": "give_item", "itemId": item_id, "quantity": 1, "receiptFlag": receipt_flag}


func _conditions_met(condition: Variant) -> bool:
	return _ignore_conditions or DialogueConditions.evaluate(condition)


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
		"set_rescue_state":
			QuestService.set_rescue_state(str(action.get("npcId", "")), str(action.get("state", "")))
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

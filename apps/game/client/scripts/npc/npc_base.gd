extends Node3D
class_name NpcBase

## Data-driven hub NPC — spawns from catalog and routes interact by type (NPC-4.1).

signal dialogue_requested(npc_id: String, dialogue_id: String)
signal shop_requested(npc_id: String, shop_type: String)

@export var npc_id: String = ""

var _data: Dictionary = {}
var _interactable: HubInteractable
var _greeted_this_visit := false


func _ready() -> void:
	_data = NpcCatalog.get_definition(npc_id)
	_interactable = get_node_or_null("InteractArea") as HubInteractable
	if _interactable == null:
		push_warning("NpcBase %s: missing InteractArea" % npc_id)
		return
	_interactable.interact_id = "npc:%s" % npc_id
	var display_name: String = _data.get("displayName", npc_id)
	_interactable.prompt_text = "%s (E)" % display_name
	_interactable.interacted.connect(_on_interacted)
	_interactable.player_exited.connect(_on_player_exited)
	_update_label()


func get_npc_id() -> String:
	return npc_id


func get_data() -> Dictionary:
	return _data


func is_player_near() -> bool:
	return _interactable != null and _interactable.is_player_near()


func trigger_interact() -> void:
	if _interactable != null:
		_interactable.trigger_interact()


func _on_player_exited() -> void:
	_greeted_this_visit = false


func _on_interacted() -> void:
	if _data.is_empty():
		return
	var interact_type: String = _data.get("interactType", "dialogue")
	match interact_type:
		"dialogue":
			var dialogue_id: String = _data.get("dialogueId", "")
			if dialogue_id != "":
				dialogue_requested.emit(npc_id, dialogue_id)
		"blacksmith", "merchant":
			var greet_id: String = _data.get("dialogueId", "")
			if greet_id != "" and not _greeted_this_visit:
				_greeted_this_visit = true
				dialogue_requested.emit(npc_id, greet_id)
				return
			_emit_shop_for_type(interact_type)
		"quest_board":
			shop_requested.emit(npc_id, "quest_board")
		_:
			var fallback_dialogue: String = _data.get("dialogueId", "")
			if fallback_dialogue != "":
				dialogue_requested.emit(npc_id, fallback_dialogue)


func _emit_shop_for_type(interact_type: String) -> void:
	match interact_type:
		"blacksmith":
			shop_requested.emit(npc_id, "blacksmith")
		"merchant":
			shop_requested.emit(npc_id, "merchant")


func _update_label() -> void:
	var label := get_node_or_null("NameLabel") as Label3D
	if label == null:
		return
	label.text = _data.get("displayName", npc_id)

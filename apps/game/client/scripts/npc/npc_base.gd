extends Node3D
class_name NpcBase

## Data-driven hub NPC — spawns from catalog and routes interact by type (NPC-4.1).

signal dialogue_requested(npc_id: String, dialogue_id: String)
signal shop_requested(npc_id: String, shop_type: String)

## Interact types that open a hub service instead of only talking. Adding one is data plus a
## routing entry in hub.gd, never a new branch here.
const SERVICE_BY_INTERACT_TYPE := {
	"blacksmith": "blacksmith",
	"merchant": "merchant",
	"quest_board": "quest_board",
	"storage": "storage",
	"bounty_board": "bounty_board",
}

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


func requires_flag() -> String:
	return str(_data.get("requiresFlag", ""))


func is_available() -> bool:
	var gate := requires_flag()
	if gate == "":
		return true
	return CharacterService != null and CharacterService.is_flag_truthy(gate)


func set_available(available: bool) -> void:
	visible = available
	if _interactable != null:
		_interactable.set_deferred("monitoring", available)


func is_player_near() -> bool:
	return _interactable != null and _interactable.is_player_near()


func trigger_interact() -> void:
	if _interactable != null:
		_interactable.trigger_interact()


func _on_player_exited() -> void:
	_greeted_this_visit = false


func resolve_dialogue_id() -> String:
	for rule in _data.get("dialogueRules", []):
		if not rule is Dictionary:
			continue
		var candidate: String = str(rule.get("dialogueId", ""))
		if candidate == "":
			continue
		if DialogueConditions.evaluate(rule.get("condition")):
			return candidate
	return str(_data.get("dialogueId", ""))


func _on_interacted() -> void:
	if _data.is_empty():
		return
	var interact_type: String = str(_data.get("interactType", "dialogue"))
	var dialogue_id := resolve_dialogue_id()
	var service: String = str(SERVICE_BY_INTERACT_TYPE.get(interact_type, ""))
	if service == "":
		if dialogue_id != "":
			dialogue_requested.emit(npc_id, dialogue_id)
		return
	if dialogue_id != "" and not _greeted_this_visit:
		_greeted_this_visit = true
		dialogue_requested.emit(npc_id, dialogue_id)
		return
	shop_requested.emit(npc_id, service)


func _update_label() -> void:
	var label := get_node_or_null("NameLabel") as Label3D
	if label == null:
		return
	label.text = _data.get("displayName", npc_id)

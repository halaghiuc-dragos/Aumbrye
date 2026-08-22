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
	# C-92: the skin is built by the hub after this node enters the tree.
	call_deferred("_resolve_visual")


## C-92: ten authored NPCs and 34 dialogue files sat behind figures that never shifted weight,
## never turned to look at the player and never reacted to anything — `npc_base` had no
## `_physics_process` and no animation calls at all, so an NPC was a static skin with an interaction
## volume, and the hub read as a menu with geometry.
##
## Two cheap signals of life, both on the box skin the hub actually builds (`build_npc` — these are
## not full rigs, so the `DioramaAnimController` idle clips do not apply here): the figure turns to
## watch the player approach, and it breathes. Throttled to the same 0.1 s cadence the minimap uses,
## and idle work stops entirely when no player is near.
const LOOK_RADIUS := 6.0
const LOOK_TURN_SPEED := 3.0
const IDLE_BOB_HEIGHT := 0.025
const IDLE_BOB_SPEED := 1.6

var _visual: Node3D
var _visual_base_y := 0.0
var _idle_phase := 0.0
var _player: Node3D


func _resolve_visual() -> void:
	for child in get_children():
		if child is Node3D and child.name.begins_with("Diorama"):
			_visual = child as Node3D
			break
	if _visual == null:
		for child in get_children():
			if child is Node3D and not (child is Area3D):
				_visual = child as Node3D
				break
	if _visual:
		_visual_base_y = _visual.position.y


func _physics_process(delta: float) -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() > LOOK_RADIUS * LOOK_RADIUS:
		return
	# Breathing: a quarter-pixel rise and fall, so it reads as alive without reading as floating.
	_idle_phase = fmod(_idle_phase + delta * IDLE_BOB_SPEED, TAU)
	_visual.position.y = _visual_base_y + sin(_idle_phase) * IDLE_BOB_HEIGHT
	if to_player.length_squared() < 0.04:
		return
	# The project's forward is +Z (see `CombatFacing`), which is what `atan2(x, z)` produces.
	var target_yaw := atan2(to_player.x, to_player.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(LOOK_TURN_SPEED * delta, 0.0, 1.0))


func get_npc_id() -> String:
	return npc_id


func get_data() -> Dictionary:
	return _data


func requires_flag() -> String:
	return str(_data.get("requiresFlag", ""))


## The inverse gate: an NPC is hidden while this flag is truthy.
##
## `requiresFlag` can only bring someone into the world. Losing one needs the opposite, and a
## character who leaves and can be brought back needs both directions to run off a single flag —
## the rite that returns them just sets it false again.
func absent_flag() -> String:
	return str(_data.get("absentFlag", ""))


## Lowest unlocked difficulty tier at which this character is in the hub at all.
##
## Read straight off `DungeonTierService` rather than mirrored into a flag, because that is the same
## source the `minTier` dialogue condition already uses — one number, so an NPC's arrival and the
## quest they arrive with cannot drift apart.
func requires_tier() -> int:
	return int(_data.get("requiresTier", 0))


func is_available() -> bool:
	if CharacterService == null:
		return requires_flag() == ""
	var absent := absent_flag()
	if absent != "" and CharacterService.is_flag_truthy(absent):
		return false
	var tier := requires_tier()
	if tier > 0:
		if DungeonTierService == null or DungeonTierService.get_max_unlocked_tier() < tier:
			return false
	var gate := requires_flag()
	if gate == "":
		return true
	return CharacterService.is_flag_truthy(gate)


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

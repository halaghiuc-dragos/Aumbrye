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

## How far past the figure's own silhouette the interact zone reaches. The zone is a capsule fitted
## to the model rather than the fixed r=0.6, h=1.8 capsule the scene ships with: every authored
## figure measures 0.60-0.96m across and 1.16-1.64m tall, so that capsule was up to twice the width
## of the person inside it and stood 0.45m over their head. Talking to someone you were nowhere
## near, and a prompt that appeared before you reached them, both came out of that gap.
const INTERACT_REACH := 0.45
## Never smaller than this, whatever the model measures — a child or a seated figure still needs a
## zone a walking player can hit.
const INTERACT_MIN_RADIUS := 0.55
const INTERACT_MIN_HEIGHT := 1.3

var _visual: Node3D
var _visual_base_y := 0.0
var _idle_phase := 0.0
var _player: Node3D
var _zone_shape: CollisionShape3D
var _zone_base_y := 0.0


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
	_fit_interact_to_model()


## Sizes the interact capsule to the figure the player can actually see.
##
## Measured off the built skin rather than authored, because the skin is procedural: hoods, helms
## and pauldrons are per-character, and a fixed capsule cannot be right for a child and a knight at
## the same time.
func _fit_interact_to_model() -> void:
	if _interactable == null or _visual == null or not is_instance_valid(_visual):
		return
	if _zone_shape == null:
		_zone_shape = _interactable.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _zone_shape == null:
		return
	var bounds := _model_bounds()
	if bounds.size.y <= 0.01:
		# Nothing measurable yet — an NPC gated out of this visit is hidden, and a hidden skin has
		# no bounds. Leave the authored capsule; `set_available` re-fits when they turn up.
		return
	var capsule := _zone_shape.shape as CapsuleShape3D
	if capsule == null:
		capsule = CapsuleShape3D.new()
		_zone_shape.shape = capsule
	else:
		# Shared between every NPC instance as it comes out of the scene file, so resizing it in
		# place would resize all of them to whoever was measured last.
		capsule = capsule.duplicate() as CapsuleShape3D
		_zone_shape.shape = capsule
	var half_width := maxf(bounds.size.x, bounds.size.z) * 0.5
	capsule.radius = maxf(half_width + INTERACT_REACH, INTERACT_MIN_RADIUS)
	capsule.height = maxf(bounds.size.y + INTERACT_REACH, INTERACT_MIN_HEIGHT)
	# Centred on the figure, so the zone sits where the person is instead of over their head.
	_zone_base_y = bounds.get_center().y
	_zone_shape.position = Vector3(bounds.get_center().x, _zone_base_y, bounds.get_center().z)


## The skin's extent in this NPC's own space.
##
## Visibility is judged only as far up as this node: an NPC hidden by an availability gate must
## still measure, and the parts a character does not wear (visor, hood) must not.
func _model_bounds() -> AABB:
	var box := AABB()
	var found := false
	var into_npc_space := global_transform.affine_inverse()
	var stack: Array[Node] = [_visual]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var mesh := node as MeshInstance3D
		if mesh == null or not _visible_up_to_self(mesh):
			continue
		var local := mesh.get_aabb()
		var xf := into_npc_space * mesh.global_transform
		for i in 8:
			var point: Vector3 = xf * local.get_endpoint(i)
			if not found:
				box = AABB(point, Vector3.ZERO)
				found = true
			else:
				box = box.expand(point)
	return box


func _visible_up_to_self(node: Node3D) -> bool:
	var walker: Node = node
	while walker != null and walker != self:
		var as_3d := walker as Node3D
		if as_3d != null and not as_3d.visible:
			return false
		walker = walker.get_parent()
	return true


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
	var bob := sin(_idle_phase) * IDLE_BOB_HEIGHT
	_visual.position.y = _visual_base_y + bob
	# The zone rides the breath with the figure rather than hanging fixed in the air behind it.
	if _zone_shape != null and is_instance_valid(_zone_shape):
		_zone_shape.position.y = _zone_base_y + bob
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
	var was_visible := visible
	visible = available
	if _interactable != null:
		_interactable.set_deferred("monitoring", available)
	if available and not was_visible:
		# Arrivals are skinned while hidden, so this is the first moment they can be measured.
		call_deferred("_fit_interact_to_model")


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

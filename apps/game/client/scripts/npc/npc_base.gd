extends Node3D
class_name NpcBase


signal dialogue_requested(npc_id: String, dialogue_id: String)
signal shop_requested(npc_id: String, shop_type: String)

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


const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")


func _ready() -> void:
	_skin_body()
	_data = NpcCatalog.get_definition(npc_id)
	_interactable = get_node_or_null("InteractArea") as HubInteractable
	if _interactable == null:
		push_warning("NpcBase %s: missing InteractArea" % npc_id)
		return
	_interactable.interact_id = "npc:%s" % npc_id
	_interactable.set_display_name(str(_data.get("displayName", npc_id)))
	_interactable.interacted.connect(_on_interacted)
	_interactable.player_exited.connect(_on_player_exited)
	_murmur_timer = MURMUR_MIN + fposmod(float(npc_id.hash()), MURMUR_MAX - MURMUR_MIN)
	call_deferred("_resolve_visual")


const LOOK_RADIUS := 6.0
const LOOK_TURN_SPEED := 3.0
const IDLE_BOB_HEIGHT := 0.025
const IDLE_BOB_SPEED := 1.6

const INTERACT_REACH := 0.45
const INTERACT_MIN_RADIUS := 0.55
const INTERACT_MIN_HEIGHT := 1.3

const MURMUR_MIN := 11.0
const MURMUR_MAX := 27.0
const MURMUR_RADIUS := 7.5

var _visual: Node3D
var _visual_base_y := 0.0
var _idle_phase := 0.0
var _murmur_timer := 0.0
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


func _fit_interact_to_model() -> void:
	if _interactable == null or _visual == null or not is_instance_valid(_visual):
		return
	if _zone_shape == null:
		_zone_shape = _interactable.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _zone_shape == null:
		return
	var bounds := _model_bounds()
	if bounds.size.y <= 0.01:
		return
	var capsule := _zone_shape.shape as CapsuleShape3D
	if capsule == null:
		capsule = CapsuleShape3D.new()
		_zone_shape.shape = capsule
	else:
		capsule = capsule.duplicate() as CapsuleShape3D
		_zone_shape.shape = capsule
	var half_width := maxf(bounds.size.x, bounds.size.z) * 0.5
	capsule.radius = maxf(half_width + INTERACT_REACH, INTERACT_MIN_RADIUS)
	capsule.height = maxf(bounds.size.y + INTERACT_REACH, INTERACT_MIN_HEIGHT)
	_zone_base_y = bounds.get_center().y
	_zone_shape.position = Vector3(bounds.get_center().x, _zone_base_y, bounds.get_center().z)


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
	_advance_murmur(delta, to_player.length_squared())
	if to_player.length_squared() > LOOK_RADIUS * LOOK_RADIUS:
		return
	_idle_phase = fmod(_idle_phase + delta * IDLE_BOB_SPEED, TAU)
	var bob := sin(_idle_phase) * IDLE_BOB_HEIGHT
	_visual.position.y = _visual_base_y + bob
	if _zone_shape != null and is_instance_valid(_zone_shape):
		_zone_shape.position.y = _zone_base_y + bob
	if to_player.length_squared() < 0.04:
		return
	var target_yaw := atan2(to_player.x, to_player.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(LOOK_TURN_SPEED * delta, 0.0, 1.0))


func _advance_murmur(delta: float, distance_squared: float) -> void:
	if not visible or distance_squared > MURMUR_RADIUS * MURMUR_RADIUS:
		return
	_murmur_timer -= delta
	if _murmur_timer > 0.0:
		return
	_murmur_timer = randf_range(MURMUR_MIN, MURMUR_MAX)
	AudioDirector.play_sfx("npc_murmur", global_position)


func get_npc_id() -> String:
	return npc_id


func requires_flag() -> String:
	return str(_data.get("requiresFlag", ""))


func absent_flag() -> String:
	return str(_data.get("absentFlag", ""))


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


## The NPC body mesh carried no material, so every villager in the hub was a grey block until
## something else happened to skin it. Uses the hub's own palette rather than a biome accent,
## because the hub is where these stand.
func _skin_body() -> void:
	var body := get_node_or_null("Body") as MeshInstance3D
	if body == null or body.material_override != null:
		return
	body.material_override = PixelStyle.make_prop_material(
		PixelStyle.theme_from_biome(BiomeRegistry.BIOME_CASTLE), false
	)

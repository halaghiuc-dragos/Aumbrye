extends RefCounted
class_name PlayerInput


enum Group { MOVEMENT, COMBAT, INTERACT, CAMERA }

const GROUP_BY_ACTION := {
	&"move_forward": Group.MOVEMENT,
	&"move_back": Group.MOVEMENT,
	&"move_left": Group.MOVEMENT,
	&"move_right": Group.MOVEMENT,
	&"sprint": Group.MOVEMENT,
	&"jump": Group.MOVEMENT,
	&"dodge": Group.MOVEMENT,
	&"light_attack": Group.COMBAT,
	&"heavy_attack": Group.COMBAT,
	&"block": Group.COMBAT,
	&"weapon_art": Group.COMBAT,
	&"two_hand": Group.COMBAT,
	&"heal": Group.COMBAT,
	&"quick_slot_use": Group.COMBAT,
	&"quick_slot_cycle": Group.COMBAT,
	&"interact": Group.INTERACT,
	&"lock_on": Group.CAMERA,
	&"zoom_in": Group.CAMERA,
	&"zoom_out": Group.CAMERA,
	&"look_left": Group.CAMERA,
	&"look_right": Group.CAMERA,
	&"look_up": Group.CAMERA,
	&"look_down": Group.CAMERA,
	&"toggle_camera": Group.CAMERA,
}

static var _group_leases: Dictionary = {}
static var _next_lease_id := 1


static func block_groups(groups: Array) -> int:
	var lease_id := _next_lease_id
	_next_lease_id += 1
	_group_leases[lease_id] = groups.duplicate()
	return lease_id


static func release_group_block(lease_id: int) -> void:
	_group_leases.erase(lease_id)


## Compatibility helper: removes only a lease with the exact group set, never another owner's
## overlapping locks. New callers should retain and release the returned lease handle.
static func unblock_groups(groups: Array) -> void:
	for lease_id in _group_leases.keys():
		if _group_leases[lease_id] == groups:
			_group_leases.erase(lease_id)
			return


static func clear_group_blocks() -> void:
	_group_leases.clear()


static func group_blocked(group: Group) -> bool:
	for groups in _group_leases.values():
		if group in groups:
			return true
	return false


static func blocked() -> bool:
	return PlayerControls != null and PlayerControls.gameplay_input_blocked()


static func is_gameplay_blocked() -> bool:
	return blocked()


static func _action_blocked(action: StringName) -> bool:
	if blocked():
		return true
	if not GROUP_BY_ACTION.has(action):
		return false
	return group_blocked(GROUP_BY_ACTION[action])


static func pump_frame() -> void:
	RunReplay.pump()


static func move_vector() -> Vector2:
	if RunReplay.is_playing():
		return RunReplay.playback_move_vector()
	if blocked() or group_blocked(Group.MOVEMENT):
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


static func pressed(action: StringName) -> bool:
	if RunReplay.is_playing():
		return RunReplay.playback_pressed(action)
	if _action_blocked(action):
		return false
	return Input.is_action_pressed(action)


static func just_pressed(action: StringName) -> bool:
	if RunReplay.is_playing():
		return RunReplay.playback_just_pressed(action)
	if _action_blocked(action):
		return false
	return Input.is_action_just_pressed(action)


static func interact_just_pressed(event: InputEvent = null) -> bool:
	if RunReplay.is_playing():
		return RunReplay.playback_just_pressed(&"interact")
	if _action_blocked(&"interact"):
		return false
	if event != null:
		return event.is_action_pressed(&"interact")
	return Input.is_action_just_pressed(&"interact")

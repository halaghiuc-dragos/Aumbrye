extends RefCounted
class_name PlayerInput

## Static gameplay input gate — blocks polling while meta UI or pause menu is open, and
## is the single seam where a run's input stream is captured or played back.


## C-85: the gate used to be one global boolean for every gameplay action, so a context that wanted
## to keep the camera live while stopping attacks — a dialogue overlay, a cutscene, a boss intro —
## had no way to say so. `InputRebindService.get_context_groups()` already sketched the right model
## and nothing consumed it. Actions are grouped, and a context can suppress groups independently.
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

## Groups suppressed on top of the global gate. Set by whichever context needs partial control;
## cleared by `clear_group_blocks()`.
static var _blocked_groups := 0


static func block_groups(groups: Array) -> void:
	for group in groups:
		_blocked_groups |= 1 << int(group)


static func unblock_groups(groups: Array) -> void:
	for group in groups:
		_blocked_groups &= ~(1 << int(group))


static func clear_group_blocks() -> void:
	_blocked_groups = 0


static func group_blocked(group: Group) -> bool:
	return (_blocked_groups & (1 << int(group))) != 0


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


## C-84: every accessor used to open with `RunReplay.pump()`. `WeaponController._physics_process`
## alone queries `just_pressed` five times a frame, `Dodge` three, `Guard` two, `Locomotion` two,
## `PlayerHeal` one — well over a dozen pumps per physics frame for a system that advances once.
## `RunFlow` pumps once per physics frame through `pump_frame()`; the accessors are pure reads.
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


## C-87: eighteen files read the `interact` action straight off the `InputEvent` (two of them polled
## `Input` directly), bypassing this class entirely — so `RunReplay` could walk a floor but never
## open a door, pull a lever, take a rest, loot a chest or buy anything, and the two polled sites
## fired through open menus. `interact` is already in `RunReplay.ACTIONS`; routing through here is
## what makes it reachable.
##
## Event-driven callers pass the event they are already handling, so consumption stays with
## `_unhandled_input` where it belongs.
static func interact_just_pressed(event: InputEvent = null) -> bool:
	if RunReplay.is_playing():
		return RunReplay.playback_just_pressed(&"interact")
	if _action_blocked(&"interact"):
		return false
	if event != null:
		return event.is_action_pressed(&"interact")
	return Input.is_action_just_pressed(&"interact")

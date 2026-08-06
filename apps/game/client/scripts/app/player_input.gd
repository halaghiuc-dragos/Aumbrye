extends RefCounted
class_name PlayerInput

## Static gameplay input gate — blocks polling while meta UI or pause menu is open.


static func blocked() -> bool:
	return PlayerControls != null and PlayerControls.gameplay_input_blocked()


static func is_gameplay_blocked() -> bool:
	return blocked()


static func move_vector() -> Vector2:
	if blocked():
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


static func pressed(action: StringName) -> bool:
	if blocked():
		return false
	return Input.is_action_pressed(action)


static func just_pressed(action: StringName) -> bool:
	if blocked():
		return false
	return Input.is_action_just_pressed(action)

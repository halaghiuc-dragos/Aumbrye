extends RefCounted
class_name PlayerInput

## Static gameplay input gate — blocks polling while meta UI or pause menu is open, and
## is the single seam where a run's input stream is captured or played back.


static func blocked() -> bool:
	return PlayerControls != null and PlayerControls.gameplay_input_blocked()


static func is_gameplay_blocked() -> bool:
	return blocked()


static func move_vector() -> Vector2:
	RunReplay.pump()
	if RunReplay.is_playing():
		return RunReplay.playback_move_vector()
	if blocked():
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


static func pressed(action: StringName) -> bool:
	RunReplay.pump()
	if RunReplay.is_playing():
		return RunReplay.playback_pressed(action)
	if blocked():
		return false
	return Input.is_action_pressed(action)


static func just_pressed(action: StringName) -> bool:
	RunReplay.pump()
	if RunReplay.is_playing():
		return RunReplay.playback_just_pressed(action)
	if blocked():
		return false
	return Input.is_action_just_pressed(action)

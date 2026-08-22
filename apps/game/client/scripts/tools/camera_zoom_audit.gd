extends Node3D

## Does the scroll wheel move the third-person camera, and does leaving first person put it back?
##
## Both were reported broken and neither is visible from reading the camera: the zoom actions are
## bound, clamped and applied, and the first-person toggle stores and restores the arm length. This
## drives the real node with real input events and prints what the arm actually does.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _camera: Node


func _ready() -> void:
	var player := PLAYER_SCENE.instantiate()
	add_child(player)
	await get_tree().process_frame
	_camera = player.get_node_or_null("CameraPivot/SpringArm3D")
	if _camera == null:
		print("ZOOM FAIL: no SpringArm3D under CameraPivot")
		get_tree().quit(1)
		return
	var fails := 0
	# Start from a known mode. The save decides which the camera boots into, and an audit that
	# reports "zoom does nothing" because the save happened to be in first person is worthless.
	if _camera.is_first_person():
		_action("toggle_camera")
		await _settle()
	_report("start")

	var before := _target()
	_wheel("zoom_in", 3)
	await _settle()
	_report("after 3x zoom_in")
	if is_equal_approx(_target(), before):
		print("ZOOM FAIL: scrolling in did not move the target")
		fails += 1
	fails += _assert_arm_follows("zoom in")

	before = _target()
	_wheel("zoom_out", 6)
	await _settle()
	_report("after 6x zoom_out")
	if is_equal_approx(_target(), before):
		print("ZOOM FAIL: scrolling out did not move the target")
		fails += 1
	fails += _assert_arm_follows("zoom out")

	# Park it away from the default, so "returned to default" and "kept my zoom" are tellable apart.
	_wheel("zoom_in", 2)
	await _settle()
	var parked := _target()
	_action("toggle_camera")
	await _settle()
	_report("first person")
	if not _camera.is_first_person():
		print("ZOOM FAIL: toggle did not enter first person")
		fails += 1
	_action("toggle_camera")
	await _settle()
	_report("back to third (parked at %.2f)" % parked)
	if _camera.is_first_person():
		print("ZOOM FAIL: toggle did not leave first person")
		fails += 1
	if _target() <= 0.5:
		print("ZOOM FAIL: third person came back at the first-person target")
		fails += 1
	fails += _assert_arm_follows("leaving first person")
	print("ZOOM RESULT %d failures" % fails)
	get_tree().quit(0)


## The target is not the camera. Both reported faults were the arm failing to follow a target that
## was moving correctly all along, so checking `_target_zoom` alone would have passed on the bug.
func _assert_arm_follows(what: String) -> int:
	if absf(_camera.spring_length - _target()) <= 0.05:
		return 0
	print("ZOOM FAIL: after %s the arm is %.2f but the target is %.2f"
		% [what, _camera.spring_length, _target()])
	return 1


func _report(stage: String) -> void:
	print(
		"ZOOM %-28s target=%.2f  arm=%.2f  smoothed=%.2f  blend=%.2f  fp=%s  phys=%d"
		% [
			stage,
			_target(),
			_camera.spring_length,
			float(_camera.get("_smoothed_arm_length")),
			float(_camera.get("_fp_blend")),
			_camera.is_first_person(),
			Engine.get_physics_frames(),
		]
	)


func _target() -> float:
	return float(_camera.get("_target_zoom"))


## Physics frames, not idle frames: the arm is driven from `_physics_process`. Ninety of them, not
## forty: pushing the arm back out from first person is a 6-per-second lerp from zero and takes the
## better part of a second, so a shorter wait reports a converging arm as a stuck one.
func _settle() -> void:
	for i in 90:
		await get_tree().physics_frame


## A real wheel event through the real input path, not a direct call: the question is whether the
## event reaches the camera at all, and calling the handler would answer a different question.
func _wheel(action: StringName, times: int) -> void:
	for i in times:
		_action(action)


func _action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)

extends Node

## Walks the player and reports whether the camera follows it rigidly.
##
## Pass `-- --no-snap` to force the gameplay pixel snap off for a comparison run.
##
## Two symptoms to separate: a camera that does not track the player at all, and one that tracks but
## jitters. Sampling the camera's world position against the player's each frame catches both — the
## first as a gap that grows without bound, the second as a per-frame step much larger than the
## pixel-snap grid.

const HUB_SCENE := "res://scenes/hub/hub.tscn"


func _ready() -> void:
	await get_tree().process_frame
	var hub := (load(HUB_SCENE) as PackedScene).instantiate()
	add_child(hub)
	for i in 60:
		await get_tree().process_frame

	var player := _find(hub, "CharacterBody3D")
	var camera := _find(hub, "Camera3D")
	if player == null or camera == null:
		print("PROBE: player=%s camera=%s" % [str(player != null), str(camera != null)])
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if str(arg) == "--no-snap":
			PixelDioramaSettings.gameplay_camera_snap_enabled = false
	print("snap enabled: %s" % str(PixelDioramaSettings.gameplay_camera_snap_enabled))

	# Measured as the camera-to-player *offset*, not the camera's absolute step.
	#
	# Absolute steps are meaningless here: this probe advances the player from `_process` while the
	# spring arm follows in `_physics_process`, so the camera legitimately catches up in bursts and
	# the step size reports the probe's frame pacing rather than the camera's stability. A rigid
	# follow keeps the offset constant whatever the pacing, and a camera that fights its own spring
	# arm does not.
	var offsets: Array[Vector3] = []
	var moved := 0.0
	for step in 150:
		player.global_position += Vector3(0.03, 0.0, 0.0)
		moved += 0.03
		await get_tree().process_frame
		if step >= 100:
			var offset := camera.global_position - player.global_position
			offsets.append(offset)

	var mean := Vector3.ZERO
	for value in offsets:
		mean += value
	mean /= float(maxi(1, offsets.size()))
	var worst := 0.0
	var worst_axis := Vector3.ZERO
	for value in offsets:
		worst = maxf(worst, (value - mean).length())
		var spread := (value - mean).abs()
		worst_axis = Vector3(
			maxf(worst_axis.x, spread.x), maxf(worst_axis.y, spread.y), maxf(worst_axis.z, spread.z)
		)
	print("worst deviation per axis: %s" % str(worst_axis))
	print("player moved %.2f m over %d sampled frames" % [moved, offsets.size()])
	print("camera offset from player: mean %s" % str(mean))
	print("worst deviation from that offset: %.4f m" % worst)
	# The pixel snap quantises the camera onto a ~0.03 m grid, so a rigid follow wobbles by about
	# one grid step and no more.
	var rigid := worst < 0.08
	print("RESULT: follow is %s" % ("rigid" if rigid else "UNSTABLE"))
	get_tree().quit(0 if rigid else 1)


func _find(root: Node, type_name: String) -> Node3D:
	for node in root.find_children("*", type_name, true, false):
		return node as Node3D
	return null

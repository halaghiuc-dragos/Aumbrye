extends Node


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
	var rigid := worst < 0.08
	print("RESULT: follow is %s" % ("rigid" if rigid else "UNSTABLE"))
	get_tree().quit(0 if rigid else 1)


func _find(root: Node, type_name: String) -> Node3D:
	for node in root.find_children("*", type_name, true, false):
		return node as Node3D
	return null

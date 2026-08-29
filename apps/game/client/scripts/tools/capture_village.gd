extends Node

## Renders the background village from a few viewpoints so it can actually be looked at.
## Diagnostic only -- it builds the skyline on a bare root rather than loading the hub,
## so what it shows is the village and nothing else.

const OUTPUT_DIR := "user://village_captures"
const SETTLE_FRAMES := 90

## Height, distance and pitch of each viewpoint. The village is meant to be read from
## the hub looking outward, so these sit on the plateau and look out and down.
const SHOTS: Array[Dictionary] = [
	{"name": "near", "pos": Vector3(0.0, 6.0, 0.0), "yaw": 0.0, "pitch": -9.0, "fov": 62.0},
	{"name": "wide", "pos": Vector3(0.0, 14.0, 0.0), "yaw": 2.1, "pitch": -13.0, "fov": 78.0},
	{"name": "street", "pos": Vector3(0.0, 2.5, 0.0), "yaw": 4.3, "pitch": -4.0, "fov": 55.0},
	{"name": "high", "pos": Vector3(0.0, 60.0, 0.0), "yaw": 1.0, "pitch": -34.0, "fov": 80.0},
	{"name": "high2", "pos": Vector3(0.0, 70.0, 0.0), "yaw": 4.2, "pitch": -30.0, "fov": 85.0},
	# Down on the innermost ring road, looking along it, to check the crowd and the
	# street surfaces close up. Ground is at GROUND_DROP (-26), so these sit above it.
	{"name": "crowd", "pos": Vector3(0.0, -20.0, 46.0), "yaw": -1.5708, "pitch": -6.0, "fov": 52.0},
	{"name": "crowd2", "pos": Vector3(78.0, -21.0, 0.0), "yaw": 3.1416, "pitch": -5.0, "fov": 52.0},
]


## Count what the background actually costs: draw calls are one per MultiMesh, so these
## totals are the budget.
func _report(root: Node) -> void:
	var batches := 0
	var instances := 0
	var nodes := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		nodes += 1
		var mmi := node as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null:
			batches += 1
			instances += mmi.multimesh.instance_count
		for child in node.get_children():
			stack.append(child)
	print("BUDGET multimesh_batches=%d instances=%d nodes=%d" % [batches, instances, nodes])
	var crowd := root.find_child("Villagers", true, false)
	if crowd == null:
		print("BUDGET crowd MISSING")
		return
	var lines: Array[String] = []
	for child in crowd.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null:
			lines.append("%s=%d" % [mmi.name, mmi.multimesh.instance_count])
	print("BUDGET crowd %s" % " ".join(lines))


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	get_tree().current_scene = null
	# The game renders through a low-res pixel viewport. Capturing the root viewport
	# while that is attached grabs the wrong texture, so detach it for the capture.
	PixelDioramaSettings.low_res_viewport_enabled = false
	PixelDioramaViewport.detach()
	await get_tree().process_frame

	var root := Node3D.new()
	get_tree().root.add_child(root)
	VisualLighting.apply_hub(root)

	var camera := Camera3D.new()
	camera.current = true
	camera.far = 4000.0
	root.add_child(camera)

	for _i in SETTLE_FRAMES:
		await get_tree().process_frame

	for shot in SHOTS:
		camera.fov = float(shot["fov"])
		camera.position = shot["pos"]
		camera.rotation = Vector3(
			deg_to_rad(float(shot["pitch"])), float(shot["yaw"]), 0.0
		)
		for _i in 12:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		var path := "%s/village_%s.png" % [OUTPUT_DIR, shot["name"]]
		image.save_png(ProjectSettings.globalize_path(path))
		print("CAPTURE %s -> %s" % [shot["name"], ProjectSettings.globalize_path(path)])

	_report(root)
	print("CAPTURE done")
	get_tree().quit(0)

extends Node

## Measures what the background village costs in the hub, by timing the same scene
## with the skyline shown and then hidden. The difference is the village's whole
## budget: geometry, crowd tick and all.

const SETTLE_FRAMES := 600
const SAMPLE_FRAMES := 240


func _ready() -> void:
	get_tree().current_scene = null
	# The hub only dresses itself once there is a character to dress it for.
	if CharacterService != null and CharacterService.get_class_id() == "":
		CharacterService.set_class_id("knight")
	if LocalSave != null:
		LocalSave.set_character_profile("Perf Warden", CharacterService.get_class_id())
	var packed := load("res://scenes/hub/hub.tscn") as PackedScene
	if packed == null:
		print("PERF hub scene missing")
		get_tree().quit(1)
		return
	var hub := packed.instantiate()
	get_tree().root.add_child.call_deferred(hub)
	await get_tree().process_frame
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame

	# The skyline is attached to whatever root the lighting was applied to, which is not
	# necessarily the hub node itself, so search the whole tree.
	var skyline := get_tree().root.find_child("DistantSkyline", true, false)
	if skyline == null:
		print("PERF no DistantSkyline in the hub")
		get_tree().quit(1)
		return

	var with_village := await _sample()
	(skyline as Node3D).visible = false
	for _i in 40:
		await get_tree().process_frame
	var without := await _sample()

	print(
		"PERF hub_with_village=%.2fms (%.0f fps)  hub_without=%.2fms (%.0f fps)  village_cost=%.2fms"
		% [
			with_village,
			1000.0 / maxf(with_village, 0.001),
			without,
			1000.0 / maxf(without, 0.001),
			with_village - without,
		]
	)
	get_tree().quit(0)


## Mean frame time in milliseconds over SAMPLE_FRAMES.
func _sample() -> float:
	var total := 0.0
	for _i in SAMPLE_FRAMES:
		await get_tree().process_frame
		total += get_process_delta_time()
	return total / float(SAMPLE_FRAMES) * 1000.0

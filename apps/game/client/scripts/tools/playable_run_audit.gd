extends Node

const PlayerRunState := preload("res://scripts/player/player_run_state.gd")
var _failures := 0
var _capture_dir := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Stay alive while testing the real scene router.
	get_tree().current_scene = null
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			_capture_dir = argument.trim_prefix("--capture-dir=")
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", message])
	if not condition:
		_failures += 1


func _wait_for_castle(previous_id: int = 0) -> Node:
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene == null or scene.get_instance_id() == previous_id:
			continue
		if not scene.is_in_group("castle_run"):
			continue
		if (scene.get("_room_neighbors") as Dictionary).is_empty():
			continue
		for _frame in 5:
			await get_tree().process_frame
		_choose_relics()
		for enemy in get_tree().get_nodes_in_group("enemy"):
			enemy.process_mode = Node.PROCESS_MODE_DISABLED
		return scene
	_check(false, "Timed out waiting for a fully built playable floor")
	get_tree().quit(1)
	return null


func _choose_relics() -> void:
	for offer in get_tree().get_nodes_in_group("relic_offer_ui"):
		if offer.call("is_open"):
			var options: Array = offer.get("_offer_ids")
			if not options.is_empty():
				offer.call("_take", options[0])


func _defeat_boss(castle: Node) -> void:
	var boss: Node = castle.get("_builder").get_boss()
	_check(boss != null, "Floor has a boss")
	if boss:
		var health := boss.get_node_or_null("Health") as Health
		_check(health != null, "Boss has a damageable health component")
		if health and not health.is_dead():
			health.take_damage(health.max_health * 100.0)
	for _frame in 8:
		await get_tree().process_frame
	_choose_relics()
	_check(bool(castle.get("_boss_defeated")), "Boss death unlocks the floor")


func _capture(label: String) -> void:
	if _capture_dir == "" or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(_capture_dir.path_join(label + ".png"))
	_check(result == OK, "Captured " + label)


func _run() -> void:
	LocalSave.queue_boot_new_game("knight", "Journey Audit", CharacterAppearance.default_profile())
	_check(LocalSave.execute_boot(), "New character boots")
	_check(RunModeCatalog.is_unlocked("ember_expedition"), "Expedition is available to new characters")
	RunFlow.start_alternate_mode_run("ember_expedition")
	var castle := await _wait_for_castle()
	if castle == null:
		return
	_check(RunFlow.max_floors == 3, "Expedition has three floors")
	_check(not RunFlow.is_final_floor(), "First floor is not the finale")
	await _capture("expedition-entry")
	var player := castle.get("_player") as Node
	var health := player.get_node("Health") as Health
	var heal := player.get_node("PlayerHeal") as PlayerHeal
	var arrows := player.get_node("PlayerArrows") as PlayerArrows
	health.current = 43.0
	heal.current_charges = 1
	arrows.current_arrows = 3
	castle.call("_persist_snapshot")
	var state: Dictionary = LocalSave.get_active_run().get("snapshot", {}).get("player", {})
	_check(int(state.get("flaskCharges", -1)) == 1 and int(state.get("arrows", -1)) == 3, "Run save contains depleted supplies")
	var old_id := castle.get_instance_id()
	RunFlow.continue_castle_run()
	castle = await _wait_for_castle(old_id)
	if castle == null:
		return
	player = castle.get("_player")
	heal = player.get_node("PlayerHeal")
	health = player.get_node("Health")
	arrows = player.get_node("PlayerArrows")
	_check(heal.current_charges == 1 and arrows.current_arrows == 3, "Continue does not refill supplies")
	_check(is_equal_approx(health.current, 43.0), "Continue preserves health")
	_check(RunFlow._active_alternate_mode == "ember_expedition", "Continue preserves the selected mode")
	RunFlow.rest_at_bonfire(player)
	_check(heal.current_charges == heal.max_charges, "Bonfire refills flasks")
	_check(LocalSave.get_active_run().has("checkpointDefinition"), "Bonfire saves its map")
	await _defeat_boss(castle)
	heal.current_charges = 2
	health.current = 71.0
	old_id = castle.get_instance_id()
	RunFlow.ascend_floor()
	castle = await _wait_for_castle(old_id)
	if castle == null:
		return
	player = castle.get("_player")
	heal = player.get_node("PlayerHeal")
	health = player.get_node("Health")
	_check(RunFlow.current_floor == 2, "Stairs reach floor two")
	_check(heal.current_charges == 2 and is_equal_approx(health.current, 71.0), "Stairs preserve health and flasks")
	old_id = castle.get_instance_id()
	RunFlow.on_player_died()
	castle = await _wait_for_castle(old_id)
	if castle == null:
		return
	_check(RunFlow.current_floor == 1, "Death returns to the checkpoint floor")
	_check(int(RunFlow.current_dungeon_definition.get("floorIndex", 0)) == 1, "Checkpoint loads its matching map")
	_check((castle.get("_player").get_node("PlayerHeal") as PlayerHeal).current_charges == 3, "Checkpoint restores rested supplies")
	for floor_number in range(1, 4):
		_check(RunFlow.current_floor == floor_number, "Playing floor %d" % floor_number)
		await _defeat_boss(castle)
		if floor_number < 3:
			old_id = castle.get_instance_id()
			RunFlow.ascend_floor()
			castle = await _wait_for_castle(old_id)
			if castle == null:
				return
	_check(RunFlow.is_final_floor(), "Third floor is the finale")
	_check(bool(RunFlow.current_dungeon_definition.get("isFinalFloor", false)), "Finale generates an extraction arena")
	_check(RunFlow.can_escape_run(), "Final boss unlocks extraction")
	await _capture("expedition-cleared")
	RunFlow.complete_run_via_portal()
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene and scene.scene_file_path.ends_with("results_screen.tscn"):
			break
	_check(not RunFlow.is_run_active() and not RunFlow.last_run_results.is_empty(), "Extraction produces results and ends the run")
	_check(RunFlow.can_repeat_run(), "Completed run can be repeated")
	_check(not DungeonTierService.is_difficulty_tier_cleared("forgotten_castle", 1), "Short expedition does not unlock campaign tiers")
	await _capture("expedition-results")
	print("PLAYABLE RUN RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

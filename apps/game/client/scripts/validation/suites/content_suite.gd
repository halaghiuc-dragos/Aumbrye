extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "content"


func run() -> void:
	_test_enemy_catalog()
	_test_items()
	_test_scenes_and_scripts()
	_test_room_templates()
	_test_audio_director()


func _test_enemy_catalog() -> void:
	var start := Time.get_ticks_msec()
	var missing_enemies: PackedStringArray = []
	for enemy_id in TC.REQUIRED_ENEMIES:
		if not EnemyCatalog.has_enemy(enemy_id):
			missing_enemies.append(enemy_id)
		elif EnemyCatalog.get_scene(enemy_id) == null:
			missing_enemies.append("%s(scene)" % enemy_id)
	ctx.timed_record(
		"content.enemies",
		get_category(),
		missing_enemies.is_empty(),
		"enemy catalog + scenes" if missing_enemies.is_empty() else "missing: %s" % ", ".join(missing_enemies),
		start,
		"M2.content.enemies"
	)

	start = Time.get_ticks_msec()
	var shield := EnemyCatalog.get_definition("castle_shield")
	ctx.timed_record(
		"content.shield_block_stats",
		get_category(),
		shield.has("block_mitigation") and shield.has("block_angle_deg"),
		"shield-bearer has block stats from JSON",
		start,
		"M2.combat.shield_stats"
	)

	start = Time.get_ticks_msec()
	for enemy_id in TC.REQUIRED_ENEMIES:
		var def := EnemyCatalog.get_definition(enemy_id)
		var scene := EnemyCatalog.get_scene(enemy_id)
		var json_path: String = EnemyCatalog.get_content_path(enemy_id)
		var json_ok := FileAccess.file_exists(ContentLoader.content_path(json_path))
		var scene_ok := scene != null and ResourceLoader.exists(scene.resource_path)
		ctx.timed_record(
			"content.enemy_json_scene_%s" % enemy_id,
			get_category(),
			json_ok and scene_ok and not def.is_empty(),
			"%s JSON + scene aligned" % enemy_id,
			start
		)


func _test_items() -> void:
	var start := Time.get_ticks_msec()
	var missing_items: PackedStringArray = []
	for item_id in TC.REQUIRED_ITEMS:
		if not ItemCatalog.has_item(item_id):
			missing_items.append(item_id)
	ctx.timed_record(
		"content.items",
		get_category(),
		missing_items.is_empty(),
		"item catalog entries" if missing_items.is_empty() else "missing: %s" % ", ".join(missing_items),
		start,
		"M2.content.items"
	)

	start = Time.get_ticks_msec()
	var sword_path := ItemCatalog.get_content_path("castle_sword")
	ctx.timed_record(
		"content.item_folder_layout",
		get_category(),
		"equipment" in sword_path,
		"castle_sword under equipment/ (%s)" % sword_path,
		start
	)


func _test_scenes_and_scripts() -> void:
	var content_checks: Array[Dictionary] = [
		{"id": "content.loot_chest_scene", "path": "res://scenes/loot/loot_chest.tscn", "ref": "M2.loot.chest"},
		{"id": "content.loot_chest_script", "path": "res://scripts/loot/loot_chest.gd", "ref": "M2.loot.chest"},
		{"id": "content.spike_trap_scene", "path": "res://scenes/traps/spike_trap.tscn", "ref": "M2.traps.spike"},
		{"id": "content.falling_trap_scene", "path": "res://scenes/traps/falling_trap.tscn", "ref": "M2.traps.falling"},
		{"id": "content.results_screen", "path": "res://scenes/ui/results_screen.tscn", "ref": "M3.flow.results"},
		{"id": "content.inventory_ui_script", "path": "res://scripts/ui/inventory_ui.gd", "ref": "M2.inventory.ui"},
		{"id": "content.world_pickup_script", "path": "res://scripts/inventory/world_item_pickup.gd", "ref": "M2.inventory.pickup"},
		{"id": "content.boss_knight_script", "path": "res://scripts/bosses/castle_knight.gd", "ref": "M2.boss.knight"},
		{"id": "content.doorway_socket_script", "path": "res://scripts/dungeon/doorway_socket.gd", "ref": "M2.dungeon.sockets"},
		{"id": "content.room_template_script", "path": "res://scripts/dungeon/room_template.gd", "ref": "M2.dungeon.rooms"},
	]
	for check in content_checks:
		var start := Time.get_ticks_msec()
		var path: String = check["path"]
		ctx.timed_record(
			check["id"],
			get_category(),
			ResourceLoader.exists(path) or FileAccess.file_exists(path),
			"exists: %s" % path,
			start,
			check.get("ref", "")
		)


func _test_room_templates() -> void:
	for template_id in TC.ROOM_TEMPLATE_SCENES:
		var start := Time.get_ticks_msec()
		var path: String = TC.ROOM_TEMPLATE_SCENES[template_id]
		ctx.timed_record(
			"content.room_template_%s" % template_id,
			get_category(),
			ResourceLoader.exists(path),
			"room template scene: %s" % path,
			start,
			"M2.dungeon.%s" % template_id
		)


func _test_audio_director() -> void:
	var methods := [
		"play_dungeon_ambience",
		"play_boss_music",
		"stop_all",
		"play_sfx",
		"play_combat_sfx",
		"play_ui_sfx",
		"register_combat_engagement",
		"unregister_combat_engagement",
	]
	for method_name in methods:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"content.audio_%s" % method_name,
			get_category(),
			AudioDirector.has_method(method_name),
			"AudioDirector.%s() exists" % method_name,
			start,
			"M2.audio.director"
		)
	_test_audio_profile_files()


func _test_audio_profile_files() -> void:
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var start := Time.get_ticks_msec()
		var path := BiomeRegistry.get_audio_profile_path(biome_id)
		var profile: Dictionary = ContentLoader.load_json(path)
		var ambience_path: String = profile.get("ambiencePath", "")
		var boss_path: String = profile.get("bossPath", "")
		var ambience_ok := ambience_path == "" or _audio_profile_path_exists(ambience_path)
		var boss_ok := boss_path == "" or _audio_profile_path_exists(boss_path)
		ctx.timed_record(
			"content.audio_profile_%s" % biome_id,
			get_category(),
			not profile.is_empty() and ambience_ok and boss_ok,
			"audio profile resolves for %s" % biome_id,
			start,
			"M2.audio.profile.%s" % biome_id
		)


func _audio_profile_path_exists(path: String) -> bool:
	if path == "":
		return true
	if ResourceLoader.exists(path):
		return true
	if path.ends_with(".ogg"):
		return ResourceLoader.exists(path.substr(0, path.length() - 4) + ".wav")
	if path.ends_with(".wav"):
		return ResourceLoader.exists(path.substr(0, path.length() - 4) + ".ogg")
	return false

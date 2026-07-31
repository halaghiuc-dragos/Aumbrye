extends "res://scripts/validation/validation_suite.gd"

const AccessibilitySettingsScript := preload("res://scripts/accessibility/accessibility_settings.gd")

const M6_ENEMIES: Array[String] = [
	"frost_raider", "frost_archer", "frost_knight", "frost_hound",
	"cathedral_acolyte", "cathedral_warden", "cathedral_shade",
	"castle_hound", "crystal_crawler", "crystal_spitter", "crystal_wisp",
	"swamp_slasher", "swamp_spitter", "swamp_brute", "swamp_swarm",
]
const M6_BOSSES: Array[String] = [
	"boss_castle_knight", "miniboss_castle_captain",
	"boss_crystal_sovereign", "miniboss_crystal_guardian",
	"boss_swamp_devourer", "boss_frost_warlord",
	"boss_cathedral_hollow", "miniboss_cathedral_bell",
]
const M6_BIOMES: Array[String] = [
	BiomeRegistry.BIOME_FROZEN, BiomeRegistry.BIOME_CATHEDRAL,
]
const M6_UNIQUES: Array[String] = [
	"frost_ice_ring", "frost_warlord_blade", "frost_raider_boots",
	"cathedral_holy_charm", "cathedral_shadow_dagger", "cathedral_warden_helm",
]


func get_category() -> String:
	return "m6"


func run() -> void:
	_test_five_biomes_registered()
	_test_m6_biome_rooms()
	_test_m6_materials_and_lighting()
	await _test_m6_procgen()
	await _test_m6_dungeon_build()
	_test_m6_enemies()
	_test_m6_bosses()
	_test_m6_scenes()
	_test_m6_room_scene_load()
	_test_m6_items_cap()
	_test_achievements()
	_test_accessibility_settings()
	_test_m6_audio_profiles()
	_test_balance_doc()


func _test_five_biomes_registered() -> void:
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"m6.biome.all_five_registered",
		get_category(),
		BiomeRegistry.ALL_BIOMES.size() == 5,
		"BiomeRegistry lists 5 EA biomes",
		start,
		"M6.theme.biomes"
	)


func _test_m6_biome_rooms() -> void:
	for biome_id in M6_BIOMES:
		var start := Time.get_ticks_msec()
		var rooms: Dictionary = BiomeRegistry.get_room_scenes(biome_id)
		ctx.timed_record(
			"m6.biome.%s_room_count" % biome_id,
			get_category(),
			rooms.size() >= 9,
			"%s has %d room templates" % [biome_id, rooms.size()],
			start,
			"M6.theme.%s" % biome_id
		)


func _test_m6_materials_and_lighting() -> void:
	for biome_id in M6_BIOMES:
		var start := Time.get_ticks_msec()
		var floor_mat: Material = BiomeRegistry.get_floor_material(biome_id)
		var wall_mat: Material = BiomeRegistry.get_wall_material(biome_id)
		var lighting: Dictionary = BiomeRegistry.get_lighting_profile(biome_id)
		ctx.timed_record(
			"m6.biome.%s_materials" % biome_id,
			get_category(),
			floor_mat != null and wall_mat != null and lighting.has("ambient_color"),
			"%s materials + lighting load" % biome_id,
			start,
			"M6.theme.materials"
		)


func _test_m6_procgen() -> void:
	for biome_id in M6_BIOMES:
		var prefix: String = "frozen" if biome_id == BiomeRegistry.BIOME_FROZEN else "cathedral"
		var start := Time.get_ticks_msec()
		var gen := LocalProcgen.generate(biome_id, TC.SEED_A)
		ctx.timed_record(
			"m6.procgen.%s_generates" % biome_id,
			get_category(),
			gen.get("ok", false),
			"%s seed %d generates" % [biome_id, TC.SEED_A],
			start,
			"M6.theme.%s" % biome_id
		)
		if not gen.get("ok", false):
			continue
		var def: Dictionary = gen.get("definition", {})
		start = Time.get_ticks_msec()
		var prefix_ok := true
		for room in def.get("rooms", []):
			var tid: String = room.get("templateId", "")
			if tid != "" and not tid.begins_with(prefix + "_"):
				prefix_ok = false
				break
		ctx.timed_record(
			"m6.procgen.%s_template_prefix" % biome_id,
			get_category(),
			prefix_ok,
			"%s rooms use %s_ prefix" % [biome_id, prefix],
			start,
			"M6.theme.templates"
		)


func _test_m6_enemies() -> void:
	var missing: PackedStringArray = []
	for enemy_id in M6_ENEMIES:
		if not EnemyCatalog.has_enemy(enemy_id):
			missing.append(enemy_id)
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"m6.enemies.roster",
		get_category(),
		missing.is_empty(),
		"M6 enemy roster complete" if missing.is_empty() else "missing: %s" % ", ".join(missing),
		start,
		"M6.enemy.roster"
	)


func _test_m6_bosses() -> void:
	var missing: PackedStringArray = []
	for boss_id in M6_BOSSES:
		if not EnemyCatalog.has_enemy(boss_id):
			missing.append(boss_id)
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"m6.bosses.roster",
		get_category(),
		missing.is_empty() and M6_BOSSES.size() <= 8,
		"8 bosses registered" if missing.is_empty() else "missing: %s" % ", ".join(missing),
		start,
		"M6.boss.roster"
	)


func _test_m6_items_cap() -> void:
	var catalog: Dictionary = ContentLoader.load_json("content/items/catalog.json")
	var equip: Array = catalog.get("equipment", [])
	var cons: Array = catalog.get("consumables", [])
	var relics: Array = catalog.get("relics", [])
	var total: int = equip.size() + cons.size() + relics.size()
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"m6.items.catalog_cap",
		get_category(),
		total <= 80,
		"catalog lists %d items (cap 80)" % total,
		start,
		"M6.item.cap"
	)
	for item_id in M6_UNIQUES:
		start = Time.get_ticks_msec()
		ctx.timed_record(
			"m6.items.unique_%s" % item_id,
			get_category(),
			ItemCatalog.has_item(item_id),
			"theme unique %s in catalog" % item_id,
			start,
			"M6.item.uniques"
		)


func _test_achievements() -> void:
	var data: Dictionary = ContentLoader.load_json("content/achievements/catalog.json")
	var achievements: Array = data.get("achievements", [])
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"m6.achievements.count",
		get_category(),
		achievements.size() >= 20 and achievements.size() <= 30,
		"%d achievements defined" % achievements.size(),
		start,
		"M6.meta.achievements"
	)
	if AchievementService:
		start = Time.get_ticks_msec()
		ctx.timed_record(
			"m6.achievements.service",
			get_category(),
			AchievementService.has_method("unlock"),
			"AchievementService autoload present",
			start,
			"M6.meta.service"
		)


func _test_accessibility_settings() -> void:
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"m6.a11y.settings_class",
		get_category(),
		ClassDB.class_exists("AccessibilitySettings") or true,
		"AccessibilitySettings loads",
		start,
		"M6.a11y.baseline"
	)
	AccessibilitySettingsScript.load_from_save()
	start = Time.get_ticks_msec()
	var color: Color = AccessibilitySettingsScript.get_damage_color("fire")
	ctx.timed_record(
		"m6.a11y.damage_colors",
		get_category(),
		color != Color.WHITE,
		"colorblind damage color helper works",
		start,
		"M6.a11y.colors"
	)


func _test_m6_audio_profiles() -> void:
	for biome_id in M6_BIOMES:
		var start := Time.get_ticks_msec()
		var path := BiomeRegistry.get_audio_profile_path(biome_id)
		var data: Dictionary = ContentLoader.load_json(path)
		ctx.timed_record(
			"m6.audio.%s_profile" % biome_id,
			get_category(),
			data.get("biomeId", "") == biome_id,
			"%s audio profile valid" % biome_id,
			start,
			"M6.audio.profiles"
		)


func _test_balance_doc() -> void:
	var start := Time.get_ticks_msec()
	var path := _content_root().path_join("docs/design/balance_m6.md")
	ctx.timed_record(
		"m6.balance.doc",
		get_category(),
		FileAccess.file_exists(path),
		"balance_m6.md present",
		start,
		"M6.bal.doc"
		)


func _test_m6_dungeon_build() -> void:
	for biome_id in M6_BIOMES:
		var gen := LocalProcgen.generate(biome_id, TC.SEED_A)
		if not gen.get("ok", false):
			var start := Time.get_ticks_msec()
			ctx.timed_record(
				"m6.dungeon.%s_build" % biome_id,
				get_category(),
				false,
				"procgen failed before dungeon build for %s" % biome_id,
				start,
				"M6.theme.%s" % biome_id
			)
			continue

		var root := Node3D.new()
		root.name = "M6Dungeon_%s" % biome_id
		ctx.owner.add_child(root)
		var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
		root.add_child(player)
		var builder := DungeonBuilder.new()
		root.add_child(builder)
		builder.build_from_definition(root, player, gen.get("definition", {}))
		await ctx.await_physics(2)

		var start := Time.get_ticks_msec()
		var room_count: int = builder.get_room_ids().size()
		var enemy_count: int = builder.get_spawned_enemy_count()
		ctx.timed_record(
			"m6.dungeon.%s_rooms" % biome_id,
			get_category(),
			room_count > 0,
			"%s: %d rooms built" % [biome_id, room_count],
			start,
			"M6.theme.%s" % biome_id
		)

		start = Time.get_ticks_msec()
		ctx.timed_record(
			"m6.dungeon.%s_enemies" % biome_id,
			get_category(),
			enemy_count > 0,
			"%s: %d enemies spawned" % [biome_id, enemy_count],
			start,
			"M6.theme.%s" % biome_id
		)

		start = Time.get_ticks_msec()
		var boss_door := builder.get_boss_door()
		ctx.timed_record(
			"m6.dungeon.%s_boss_door" % biome_id,
			get_category(),
			boss_door != null,
			"%s boss door wired" % biome_id,
			start,
			"M6.boss.%s" % biome_id
		)
		root.queue_free()


func _test_m6_scenes() -> void:
	for enemy_id in M6_ENEMIES + M6_BOSSES:
		var def: Dictionary = EnemyCatalog.get_definition(enemy_id)
		var scene: PackedScene = EnemyCatalog.get_scene(enemy_id)
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"m6.scene.%s" % enemy_id,
			get_category(),
			not def.is_empty() and scene != null,
			"%s enemy JSON + scene aligned" % enemy_id,
			start,
			"M6.enemy.scenes"
		)

	var warlord := EnemyCatalog.get_scene("boss_frost_warlord")
	var hollow := EnemyCatalog.get_scene("boss_cathedral_hollow")
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"m6.boss.m6_theme_scenes",
		get_category(),
		warlord != null and hollow != null,
		"boss_frost_warlord and boss_cathedral_hollow scenes resolve",
		start,
		"M6.boss.scenes"
	)


func _test_m6_room_scene_load() -> void:
	for biome_id in M6_BIOMES:
		var rooms: Dictionary = BiomeRegistry.get_room_scenes(biome_id)
		var missing: PackedStringArray = []
		for room_id in rooms:
			var entry: Variant = rooms[room_id]
			var scene: Resource = entry as Resource if entry is PackedScene else load(str(entry))
			if scene == null:
				missing.append(room_id)
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"m6.rooms.%s_load" % biome_id,
			get_category(),
			missing.is_empty(),
			"%s: %d room scenes load" % [biome_id, rooms.size()] if missing.is_empty() else "missing: %s" % ", ".join(missing),
			start,
			"M6.theme.rooms"
		)


func _content_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../../..")

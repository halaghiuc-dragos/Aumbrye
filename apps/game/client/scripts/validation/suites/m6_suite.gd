extends "res://scripts/validation/validation_suite.gd"

const AccessibilitySettingsScript := preload(
	"res://scripts/accessibility/accessibility_settings.gd"
)

const M6_ENEMIES: Array[String] = [
	"frost_raider",
	"frost_archer",
	"frost_knight",
	"frost_hound",
	"cathedral_acolyte",
	"cathedral_warden",
	"cathedral_shade",
	"castle_hound",
	"crystal_crawler",
	"crystal_spitter",
	"crystal_wisp",
	"swamp_slasher",
	"swamp_spitter",
	"swamp_brute",
	"swamp_swarm",
]
const M6_BOSSES: Array[String] = [
	"boss_castle_knight",
	"miniboss_castle_captain",
	"boss_crystal_sovereign",
	"miniboss_crystal_guardian",
	"boss_swamp_devourer",
	"boss_frost_warlord",
	"boss_cathedral_hollow",
	"miniboss_cathedral_bell",
]
const M6_BIOMES: Array[String] = [
	BiomeRegistry.BIOME_FROZEN,
	BiomeRegistry.BIOME_CATHEDRAL,
]
const M6_UNIQUES: Array[String] = [
	"frost_ice_ring",
	"frost_warlord_blade",
	"frost_raider_boots",
	"cathedral_holy_charm",
	"cathedral_shadow_dagger",
	"cathedral_warden_helm",
]
const M7_EXPANSION_BIOMES: Array[String] = [
	BiomeRegistry.BIOME_VAULT,
	BiomeRegistry.BIOME_PRISM,
	BiomeRegistry.BIOME_MIRE,
	BiomeRegistry.BIOME_HOLLOW,
	BiomeRegistry.BIOME_UMBRAL,
]


func get_category() -> String:
	return "m6"


func run() -> void:
	_test_ten_biomes_registered()
	_test_m6_biome_rooms()
	_test_m6_materials_and_lighting()
	await _test_m6_procgen()
	await _test_m7_expansion_procgen()
	await _test_m6_dungeon_build()
	_test_m6_enemies()
	_test_m6_bosses()
	_test_m6_scenes()
	_test_m6_room_scene_load()
	_test_m6_items_cap()
	_test_achievements()
	await _test_accessibility_settings()
	_test_m6_audio_profiles()
	_test_balance_doc()
	_test_leaderboards()
	_test_web_pages()
	_test_performance_doc()
	_test_balance_export_schema()
	_test_achievement_catalog_quality()
	_test_escape_meta_wiring()
	_test_content_catalog_loader()
	_test_item_catalog_strict_mode()
	_test_content_reload_command()


func _test_content_catalog_loader() -> void:
	var catalogs := [
		"res://scripts/content/item_catalog.gd",
		"res://scripts/content/enemy_catalog.gd",
		"res://scripts/content/class_catalog.gd",
		"res://scripts/content/relic_catalog.gd",
		"res://scripts/quests/quest_catalog.gd",
		"res://scripts/dialogue/dialogue_catalog.gd",
	]
	var start := Time.get_ticks_msec()
	var uses_shared := true
	for path in catalogs:
		if not ctx.file_contains(path, "ContentDirLoader.load_id_map"):
			uses_shared = false
			break
	ctx.timed_record(
		"m6.content.shared_dir_loader",
		get_category(),
		uses_shared,
		"six catalogs share ContentDirLoader.load_id_map",
		start,
		"CCT-02"
	)
	start = Time.get_ticks_msec()
	var no_dup_walk := true
	for path in catalogs:
		if ctx.file_contains(path, "list_dir_begin"):
			no_dup_walk = false
			break
	ctx.timed_record(
		"m6.content.no_duplicate_dir_walk",
		get_category(),
		no_dup_walk,
		"catalogs do not reimplement DirAccess walks",
		start,
		"CCT-02"
	)


func _test_item_catalog_strict_mode() -> void:
	var orphan_id := "_m6_strict_orphan_item"
	var orphan_path := ContentLoader.content_path("content/items/equipment/%s.json" % orphan_id)
	var had_orphan := FileAccess.file_exists(orphan_path)
	var prior_strict: Variant = ProjectSettings.get_setting("aumbrye/strict_item_catalog", false)
	ProjectSettings.set_setting("aumbrye/strict_item_catalog", true)
	ItemCatalog.clear_cache()
	var file := FileAccess.open(orphan_path, FileAccess.WRITE)
	if file:
		(
			file
			. store_string(
				(
					JSON
					. stringify(
						{
							"id": orphan_id,
							"itemType": "weapon",
							"name": "Strict Orphan",
							"description": "M6 strict-mode fixture.",
							"value": 1,
						}
					)
				)
			)
		)
	ItemCatalog.clear_cache()
	var loaded_with_orphan := ItemCatalog.has_item(orphan_id)
	ItemCatalog.clear_cache()
	ProjectSettings.set_setting("aumbrye/strict_item_catalog", prior_strict)
	if FileAccess.file_exists(orphan_path) and not had_orphan:
		DirAccess.remove_absolute(orphan_path)
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"m6.content.strict_rejects_orphan",
		get_category(),
		not loaded_with_orphan,
		"strict mode excludes equipment JSON absent from catalog.json",
		start,
		"CCT-01"
	)


func _test_content_reload_command() -> void:
	var start := Time.get_ticks_msec()
	var has_command := (
		ctx.file_contains("res://scripts/debug/debug_console.gd", "content_reload")
		and ctx.file_contains("res://scripts/app/content_loader.gd", "func clear_all_caches")
	)
	ctx.timed_record(
		"m6.content.reload_command",
		get_category(),
		has_command,
		"debug content_reload clears catalog caches",
		start,
		"CCT-03"
	)
	start = Time.get_ticks_msec()
	ItemCatalog.clear_cache()
	var before := ItemCatalog.has_item("castle_sword")
	ContentLoader.clear_all_caches()
	var after_clear := ItemCatalog.has_item("castle_sword")
	ctx.timed_record(
		"m6.content.cache_clear_reload",
		get_category(),
		before and after_clear,
		"clear_all_caches repopulates ItemCatalog on next access",
		start,
		"CCT-03"
	)


func _test_ten_biomes_registered() -> void:
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"m6.biome.all_ten_registered",
		get_category(),
		BiomeRegistry.ALL_BIOMES.size() == 10,
		"BiomeRegistry lists 10 EA biomes",
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


func _test_m7_expansion_procgen() -> void:
	for biome_id in M7_EXPANSION_BIOMES:
		var prefix: String = biome_id.split("_")[0]
		if biome_id == BiomeRegistry.BIOME_PRISM:
			prefix = "prism"
		elif biome_id == BiomeRegistry.BIOME_MIRE:
			prefix = "mire"
		elif biome_id == BiomeRegistry.BIOME_HOLLOW:
			prefix = "hollow"
		elif biome_id == BiomeRegistry.BIOME_UMBRAL:
			prefix = "umbral"
		elif biome_id == BiomeRegistry.BIOME_VAULT:
			prefix = "vault"
		var start := Time.get_ticks_msec()
		var gen := LocalProcgen.generate(biome_id, TC.SEED_A)
		ctx.timed_record(
			"m7.procgen.%s_generates" % biome_id,
			get_category(),
			gen.get("ok", false),
			"%s seed %d generates" % [biome_id, TC.SEED_A],
			start,
			"M7.theme.%s" % biome_id
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
			"m7.procgen.%s_template_prefix" % biome_id,
			get_category(),
			prefix_ok,
			"%s rooms use %s_ prefix" % [biome_id, prefix],
			start,
			"M7.theme.templates"
		)
		start = Time.get_ticks_msec()
		var rooms: Dictionary = BiomeRegistry.get_room_scenes(biome_id)
		ctx.timed_record(
			"m7.biome.%s_room_count" % biome_id,
			get_category(),
			rooms.size() >= 9,
			"%s has %d room templates" % [biome_id, rooms.size()],
			start,
			"M7.theme.%s" % biome_id
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
	var total: int = equip.size() + cons.size()
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"m6.items.catalog_cap",
		get_category(),
		total <= 84,
		"catalog lists %d items (cap 84)" % total,
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
		ResourceLoader.exists("res://scripts/accessibility/accessibility_settings.gd"),
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
	start = Time.get_ticks_msec()
	AccessibilitySettingsScript.ui_scale = 1.25
	AccessibilitySettingsScript.subtitle_scale = 1.5
	AccessibilitySettingsScript.reduce_camera_shake = true
	var ok := (
		AccessibilitySettingsScript.ui_scale == 1.25
		and AccessibilitySettingsScript.subtitle_scale == 1.5
		and AccessibilitySettingsScript.reduce_camera_shake
	)
	ctx.timed_record(
		"m6.a11y.ui_settings",
		get_category(),
		ok,
		"UI scale, subtitle scale, and camera shake settings writable",
		start,
		"M6.a11y.baseline"
	)
	start = Time.get_ticks_msec()
	var has_consumer := (
		ctx.file_contains("res://scripts/combat/damage_number.gd", "get_damage_color")
		or ctx.file_contains("res://scripts/ui/combat_hud.gd", "get_damage_color")
	)
	ctx.timed_record(
		"a11y.colorblind.has_consumer",
		get_category(),
		has_consumer,
		"get_damage_color called from combat or UI presentation",
		start,
		"A11-01"
	)
	start = Time.get_ticks_msec()
	AccessibilitySettingsScript.colorblind_mode = "default"
	var default_fire: Color = AccessibilitySettingsScript.get_damage_color("fire")
	AccessibilitySettingsScript.colorblind_mode = "protanopia"
	var protanopia_fire: Color = AccessibilitySettingsScript.get_damage_color("fire")
	ctx.timed_record(
		"a11y.colorblind.protanopia_fire_differs",
		get_category(),
		default_fire != protanopia_fire,
		"protanopia fire color differs from default",
		start,
		"A11-01"
	)
	start = Time.get_ticks_msec()
	var no_hardcoded_hit_colors := not ctx.file_contains(
		"res://scripts/combat/damage_number.gd", "Color(1.0, 0.35"
	)
	ctx.timed_record(
		"a11y.colorblind.no_hardcoded_hit_colors",
		get_category(),
		no_hardcoded_hit_colors,
		"damage numbers use get_damage_color not hardcoded red",
		start,
		"A11-04"
	)
	var dialogue_scene := load("res://scenes/ui/dialogue_ui.tscn") as PackedScene
	if dialogue_scene != null and ctx.owner != null:
		var dialogue_ui: Control = dialogue_scene.instantiate() as Control
		ctx.owner.add_child(dialogue_ui)
		await ctx.await_frame()
		AccessibilitySettingsScript.subtitle_scale = 1.5
		dialogue_ui.call("_on_line_changed", "Test", "Line", [])
		var speaker_label := dialogue_ui.get_node("Panel/Margin/VBox/SpeakerLabel") as Label
		var font_size := speaker_label.get_theme_font_size("font_size")
		start = Time.get_ticks_msec()
		ctx.timed_record(
			"a11y.subtitle.applies_on_line",
			get_category(),
			font_size == 21,
			"subtitle_scale 1.5 yields speaker font size 21",
			start,
			"A11-02"
		)
		dialogue_ui.queue_free()
	else:
		start = Time.get_ticks_msec()
		ctx.timed_record(
			"a11y.subtitle.applies_on_line",
			get_category(),
			false,
			"dialogue_ui scene or validation owner missing",
			start,
			"A11-02"
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
	var path := _content_root().path_join("docs/existing_codebase/content-data.md")
	ctx.timed_record(
		"m6.balance.doc",
		get_category(),
		FileAccess.file_exists(path),
		"content data doc present",
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
		var player: CharacterBody3D = (
			load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
		)
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
		var door_ok := boss_door != null
		if door_ok and boss_door.has_method("open_door"):
			boss_door.call("open_door")
			door_ok = boss_door.call("is_opened")
			boss_door.call("seal_door")
			door_ok = door_ok and boss_door.call("is_sealed")
			boss_door.call("release_door")
			door_ok = door_ok and boss_door.call("is_opened")
		ctx.timed_record(
			"m6.dungeon.%s_boss_door" % biome_id,
			get_category(),
			door_ok,
			"%s boss door open/seal/release" % biome_id,
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
			(
				"%s: %d room scenes load" % [biome_id, rooms.size()]
				if missing.is_empty()
				else "missing: %s" % ", ".join(missing)
			),
			start,
			"M6.theme.rooms"
		)


func _test_leaderboards() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = ResourceLoader.exists("res://scripts/meta/leaderboard_settings.gd")
	ctx.timed_record(
		"m6.leaderboard.settings",
		get_category(),
		ok,
		"LeaderboardSettings opt-in class present",
		start,
		"META-6.2"
	)
	start = Time.get_ticks_msec()
	ok = ctx.file_contains("res://scripts/net/api_client.gd", "func submit_leaderboard")
	ctx.timed_record(
		"m6.leaderboard.api_client",
		get_category(),
		ok,
		"ApiClient.submit_leaderboard wired",
		start,
		"META-6.2"
	)
	start = Time.get_ticks_msec()
	ok = ctx.file_contains("res://scripts/app/run_flow.gd", "LeaderboardSettings.opt_in")
	ctx.timed_record(
		"m6.leaderboard.escape_submit",
		get_category(),
		ok,
		"escape flow checks leaderboard opt-in",
		start,
		"META-6.2"
	)


func _test_web_pages() -> void:
	var root := _content_root().path_join("apps/web/src/pages")
	var pages: Array[String] = [
		"Landing.tsx",
		"Account.tsx",
		"PatchNotes.tsx",
		"Wiki.tsx",
		"Leaderboards.tsx",
	]
	for page in pages:
		var start := Time.get_ticks_msec()
		var path := root.path_join(page)
		ctx.timed_record(
			"m6.web.%s" % page.get_basename().to_lower(),
			get_category(),
			FileAccess.file_exists(path),
			"web page %s exists" % page,
			start,
			"WEB-6.1"
		)


func _test_performance_doc() -> void:
	var start := Time.get_ticks_msec()
	var ok = ctx.file_contains("res://scripts/combat/enemy_pool.gd", "class_name EnemyPool")
	ctx.timed_record(
		"m6.perf.enemy_pool",
		get_category(),
		ok,
		"EnemyPool module present for M6 perf",
		start,
		"PERF-6.1"
	)


func _test_balance_export_schema() -> void:
	var start := Time.get_ticks_msec()
	var export_path := _content_root().path_join("reports/balance_export.json")
	var schema_path := _content_root().path_join("content/schemas/balance-export.v1.json")
	var ok := false
	if FileAccess.file_exists(export_path) and FileAccess.file_exists(schema_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(export_path))
		if parsed is Dictionary:
			var report: Dictionary = parsed
			ok = (
				int(report.get("schemaVersion", 0)) == 1
				and report.has("enemies")
				and report.has("items")
				and report.has("weapons")
				and report.has("progression")
				and report.has("outliers")
				and report.get("enemies", {}).has("threatCostHistogram")
				and report.get("items", {}).has("statTotalsByRarity")
			)
	ctx.timed_record(
		"m6.balance.export_schema",
		get_category(),
		ok,
		"reports/balance_export.json matches balance-export schema shape",
		start,
		"BAL-6.1"
	)


func _test_achievement_catalog_quality() -> void:
	var data: Dictionary = ContentLoader.load_json("content/achievements/catalog.json")
	var achievements: Array = data.get("achievements", [])
	var ids: Dictionary = {}
	var duplicates := false
	for entry in achievements:
		if not entry is Dictionary:
			continue
		var id: String = str(entry.get("id", ""))
		if id == "" or ids.has(id):
			duplicates = true
			break
		ids[id] = true
	var required: Array[String] = [
		"frozen_clear",
		"cathedral_clear",
		"leaderboard_submit",
		"ten_floor_clear",
	]
	var missing: PackedStringArray = []
	for req_id in required:
		if not ids.has(req_id):
			missing.append(req_id)
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"m6.achievements.unique_ids",
		get_category(),
		not duplicates and achievements.size() >= 25,
		"%d achievements with unique IDs" % achievements.size(),
		start,
		"META-6.1"
	)
	start = Time.get_ticks_msec()
	ctx.timed_record(
		"m6.achievements.required_ids",
		get_category(),
		missing.is_empty(),
		(
			"M6 meta achievement IDs present"
			if missing.is_empty()
			else "missing: %s" % ", ".join(missing)
		),
		start,
		"META-6.1"
	)
	start = Time.get_ticks_msec()
	ctx.timed_record(
		"m6.achievements.toast_scene",
		get_category(),
		ResourceLoader.exists("res://scenes/ui/achievement_toast.tscn"),
		"achievement toast scene exists",
		start,
		"META-6.1"
	)


func _test_escape_meta_wiring() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = (
		ctx.file_contains("res://scripts/app/run_flow.gd", "func _handle_escape_meta")
		and ctx.file_contains(
			"res://scripts/app/run_flow.gd", "AchievementService.unlock_for_biome_clear"
		)
	)
	ctx.timed_record(
		"m6.meta.escape_achievements",
		get_category(),
		ok,
		"escape meta unlocks achievements on boss clear",
		start,
		"META-6.1"
	)


func _content_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../../..")

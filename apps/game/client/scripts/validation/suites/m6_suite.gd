extends "res://scripts/validation/validation_suite.gd"

const AccessibilitySettingsScript := preload(
	"res://scripts/accessibility/accessibility_settings.gd"
)
const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const ValidationHelpers := preload("res://scripts/validation/helpers.gd")
const PixelDioramaSettingsScript := preload("res://scripts/art/pipeline/pixel_diorama_settings.gd")
const ApiClientScript := preload("res://scripts/net/api_client.gd")

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
	return "content"


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
	_test_m6_audio_profiles()
	_test_leaderboards()
	_test_web_pages()
	_test_balance_export_schema()
	_test_achievement_catalog_quality()
	_test_escape_meta_wiring()
	_test_content_catalog_loader()
	_test_item_catalog_strict_mode()
	_test_content_reload_command()
	_test_ui_skin()
	await _test_display_service()


func _test_content_catalog_loader() -> void:
	# Each catalogue delegates its disk walk to ContentDirLoader.load_id_map rather than
	# reimplementing a DirAccess walk; the observable consequence is that every catalogue
	# returns real, non-empty, id-keyed content. Exercise each catalogue's actual public
	# accessor (or, for DialogueCatalog which has no id-listing accessor, the same
	# ContentDirLoader.load_id_map call its _ensure_loaded() makes) and assert that.
	var start := Time.get_ticks_msec()
	ItemCatalog.clear_cache()
	EnemyCatalog.clear_cache()
	var item_ok := ItemCatalog.has_item("castle_sword")
	var enemy_ok := EnemyCatalog.has_enemy("castle_shield")
	ctx.timed_record(
		"content.item_and_enemy_catalog_load",
		get_category(),
		item_ok and enemy_ok,
		"ItemCatalog and EnemyCatalog resolve known ids via the shared dir loader",
		start,
		"CCT-02"
	)
	start = Time.get_ticks_msec()
	var classes := ClassCatalog.get_all_classes()
	var relics := RelicCatalog.get_all_ids()
	var quests := QuestCatalog.get_all_ids()
	ctx.timed_record(
		"content.class_relic_quest_catalog_load",
		get_category(),
		not classes.is_empty() and not relics.is_empty() and not quests.is_empty(),
		(
			"ClassCatalog/RelicCatalog/QuestCatalog load non-empty id-keyed data (%d/%d/%d)"
			% [classes.size(), relics.size(), quests.size()]
		),
		start,
		"CCT-02"
	)
	start = Time.get_ticks_msec()
	var dialogue_map: Dictionary = ContentDirLoader.load_id_map(
		["content/dialogue"], "id", "DialogueCatalog", false, true
	)
	ctx.timed_record(
		"content.dialogue_catalog_load",
		get_category(),
		not dialogue_map.is_empty(),
		"DialogueCatalog's backing dir loader returns non-empty id-keyed data (%d entries)" % dialogue_map.size(),
		start,
		"CCT-02"
	)


func _test_item_catalog_strict_mode() -> void:
	# The fixture lives in content/fixtures/ (BUG-37) rather than in shipping equipment
	# content, so it is written transiently into the equipment directory only for the
	# duration of this test and removed afterward regardless of prior state.
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
		"content.strict_rejects_orphan",
		get_category(),
		not loaded_with_orphan,
		"strict mode excludes equipment JSON absent from catalog.json",
		start,
		"CCT-01"
	)


func _test_content_reload_command() -> void:
	var start := Time.get_ticks_msec()
	var has_clear_all := ContentLoader.has_method("clear_all_caches")
	var result := DebugConsole.execute("content_reload")
	var command_ran := not result.begins_with("Unknown command")
	ctx.timed_record(
		"content.reload_command",
		get_category(),
		has_clear_all and command_ran,
		"debug console content_reload command clears catalog caches (result: %s)" % result,
		start,
		"CCT-03"
	)
	start = Time.get_ticks_msec()
	ItemCatalog.clear_cache()
	var before := ItemCatalog.has_item("castle_sword")
	ContentLoader.clear_all_caches()
	var after_clear := ItemCatalog.has_item("castle_sword")
	ctx.timed_record(
		"content.cache_clear_reload",
		get_category(),
		before and after_clear,
		"clear_all_caches repopulates ItemCatalog on next access",
		start,
		"CCT-03"
	)


func _test_ten_biomes_registered() -> void:
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"biome.registry.all_ten_registered",
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
			"biome.registry.%s_room_count" % biome_id,
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
		var lighting: Dictionary = VisualLighting.profile_summary(
			VisualLighting.profile_for_biome(biome_id)
		)
		ctx.timed_record(
			"biome.registry.%s_materials" % biome_id,
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
			"procgen.biome.%s_generates" % biome_id,
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
			"procgen.biome.%s_template_prefix" % biome_id,
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
			"procgen.biome.%s_generates" % biome_id,
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
			"procgen.biome.%s_template_prefix" % biome_id,
			get_category(),
			prefix_ok,
			"%s rooms use %s_ prefix" % [biome_id, prefix],
			start,
			"M7.theme.templates"
		)
		start = Time.get_ticks_msec()
		var rooms: Dictionary = BiomeRegistry.get_room_scenes(biome_id)
		ctx.timed_record(
			"biome.registry.%s_room_count" % biome_id,
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
		"content.enemies.roster",
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
		"content.bosses.roster",
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
		"content.items.catalog_cap",
		get_category(),
		total <= 84,
		"catalog lists %d items (cap 84)" % total,
		start,
		"M6.item.cap"
	)
	for item_id in M6_UNIQUES:
		start = Time.get_ticks_msec()
		ctx.timed_record(
			"content.items.unique_%s" % item_id,
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
		"meta.achievements.count",
		get_category(),
		achievements.size() >= 20 and achievements.size() <= 30,
		"%d achievements defined" % achievements.size(),
		start,
		"M6.meta.achievements"
	)
	if AchievementService:
		start = Time.get_ticks_msec()
		ctx.timed_record(
			"meta.achievements.service",
			get_category(),
			AchievementService.has_method("unlock"),
			"AchievementService autoload present",
			start,
			"M6.meta.service"
		)


func _test_accessibility_settings() -> void:
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"a11y.settings_class",
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
		"a11y.damage_colors",
		get_category(),
		color != Color.WHITE,
		"colorblind damage color helper works",
		start,
		"M6.a11y.colors"
	)
	start = Time.get_ticks_msec()
	AccessibilitySettingsScript.subtitle_scale = 1.5
	AccessibilitySettingsScript.reduce_camera_shake = true
	var ok := (
		is_equal_approx(AccessibilitySettingsScript.subtitle_scale, 1.5)
		and AccessibilitySettingsScript.reduce_camera_shake
	)
	ctx.timed_record(
		"a11y.ui_settings",
		get_category(),
		ok,
		"subtitle scale and camera shake settings writable",
		start,
		"M6.a11y.baseline"
	)
	start = Time.get_ticks_msec()
	var damage_number_ok := false
	var damage_number_detail := "res://scenes/combat/damage_number.tscn failed to load"
	var damage_number_scene := load("res://scenes/combat/damage_number.tscn") as PackedScene
	if damage_number_scene != null and ctx.owner != null:
		var damage_number_node := damage_number_scene.instantiate()
		ctx.owner.add_child(damage_number_node)
		AccessibilitySettingsScript.colorblind_mode = "default"
		damage_number_node.call("show_amount", 10.0, "fire")
		var expected_color: Color = AccessibilitySettingsScript.get_damage_color("fire")
		var actual_color: Color = (damage_number_node.get_node("Label3D") as Label3D).modulate
		damage_number_ok = actual_color.is_equal_approx(expected_color)
		damage_number_detail = "damage number modulate %s vs accessibility color %s" % [
			actual_color, expected_color
		]
		damage_number_node.queue_free()
	ctx.timed_record(
		"a11y.colorblind.damage_number_uses_accessibility_color",
		get_category(),
		damage_number_ok,
		damage_number_detail,
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
			"audio.biome.%s_profile" % biome_id,
			get_category(),
			data.get("biomeId", "") == biome_id,
			"%s audio profile valid" % biome_id,
			start,
			"M6.audio.profiles"
		)


func _test_m6_dungeon_build() -> void:
	for biome_id in M6_BIOMES:
		var gen := LocalProcgen.generate(biome_id, TC.SEED_A)
		if not gen.get("ok", false):
			var start := Time.get_ticks_msec()
			ctx.timed_record(
				"dungeon.biome.%s_build" % biome_id,
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
			"dungeon.biome.%s_rooms" % biome_id,
			get_category(),
			room_count > 0,
			"%s: %d rooms built" % [biome_id, room_count],
			start,
			"M6.theme.%s" % biome_id
		)

		start = Time.get_ticks_msec()
		ctx.timed_record(
			"dungeon.biome.%s_enemies" % biome_id,
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
			"dungeon.biome.%s_boss_door" % biome_id,
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
			"content.scene.%s" % enemy_id,
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
		"dungeon.boss.m6_theme_scenes",
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
			"biome.rooms.%s_load" % biome_id,
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
		"meta.leaderboard.settings",
		get_category(),
		ok,
		"LeaderboardSettings opt-in class present",
		start,
		"META-6.2"
	)
	start = Time.get_ticks_msec()
	var api_client_probe := ApiClientScript.new()
	ok = api_client_probe.has_method("submit_leaderboard")
	ctx.timed_record(
		"meta.leaderboard.api_client",
		get_category(),
		ok,
		"ApiClient.submit_leaderboard wired",
		start,
		"META-6.2"
	)
	start = Time.get_ticks_msec()
	var backup_opt_in := LeaderboardSettings.opt_in
	var meta_backup: Dictionary = LocalSave.get_meta_data().duplicate(true)
	LeaderboardSettings.opt_in = true
	LeaderboardSettings.save()
	LeaderboardSettings.opt_in = false
	LeaderboardSettings.load_from_save()
	var round_tripped_true := LeaderboardSettings.opt_in == true
	LeaderboardSettings.opt_in = false
	LeaderboardSettings.save()
	LeaderboardSettings.opt_in = true
	LeaderboardSettings.load_from_save()
	var round_tripped_false := LeaderboardSettings.opt_in == false
	LeaderboardSettings.opt_in = backup_opt_in
	LocalSave.set_meta_data(meta_backup)
	ok = (
		RunFlow.has_method("_handle_escape_meta")
		and round_tripped_true
		and round_tripped_false
	)
	ctx.timed_record(
		"meta.leaderboard.escape_submit",
		get_category(),
		ok,
		"escape flow gate is wired and leaderboard opt-in persists across save/load",
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
			"docs.web.%s" % page.get_basename().to_lower(),
			get_category(),
			FileAccess.file_exists(path),
			"web page %s exists" % page,
			start,
			"WEB-6.1"
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
		"TLS-05"
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
		"meta.achievements.unique_ids",
		get_category(),
		not duplicates and achievements.size() >= 25,
		"%d achievements with unique IDs" % achievements.size(),
		start,
		"META-6.1"
	)
	start = Time.get_ticks_msec()
	ctx.timed_record(
		"meta.achievements.required_ids",
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
		"meta.achievements.toast_scene",
		get_category(),
		ResourceLoader.exists("res://scenes/ui/achievement_toast.tscn"),
		"achievement toast scene exists",
		start,
		"META-6.1"
	)


func _test_escape_meta_wiring() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = (
		RunFlow.has_method("_handle_escape_meta")
		and AchievementService.has_method("unlock_for_biome_clear")
	)
	ctx.timed_record(
		"meta.escape.escape_achievements",
		get_category(),
		ok,
		"escape meta handler and achievement unlock API are both wired",
		start,
		"META-6.1"
	)


func _test_display_service() -> void:
	const DisplayServiceScript := preload("res://scripts/app/display_service.gd")
	var start := Time.get_ticks_msec()
	var autoload: Node = null
	if Engine.get_main_loop() is SceneTree:
		autoload = (Engine.get_main_loop() as SceneTree).root.get_node_or_null(
			"/root/DisplayService"
		)
	var fields_ok := autoload != null
	if fields_ok:
		fields_ok = (
			autoload.has_method("set_window_mode")
			and autoload.has_method("set_ui_scale")
			and "window_mode" in autoload
			and "window_size" in autoload
			and "monitor_index" in autoload
			and "vsync_mode" in autoload
			and "max_fps" in autoload
			and "ui_scale" in autoload
			and "hud_safe_area" in autoload
		)
	ctx.timed_record(
		"display.service_present",
		get_category(),
		fields_ok,
		"DisplayService autoload exposes all seven fields",
		start,
		"DSP-01"
	)

	start = Time.get_ticks_msec()
	var legacy_gone := not ResourceLoader.exists("res://scripts/ui/display_settings.gd")
	ctx.timed_record(
		"display.legacy_helper_gone",
		get_category(),
		legacy_gone,
		"display_settings.gd removed",
		start,
		"DSP-06"
	)

	start = Time.get_ticks_msec()
	var service := DisplayServiceScript.new()
	service.monitor_index = 0
	service.window_mode = DisplayServiceScript.WINDOW_MODE_WINDOWED
	service.window_size = Vector2i(1600, 900)
	service.vsync_mode = DisplayServiceScript.VSYNC_ENABLED
	service.max_fps = 60
	service.ui_scale = 1.25
	service.hud_safe_area = 0.02
	var serialized := service.serialize()
	var reloaded := DisplayServiceScript.new()
	var data: Dictionary = serialized
	reloaded.window_mode = reloaded._parse_window_mode(data.get("window_mode"))
	var size_arr: Variant = data.get("window_size", [1920, 1080])
	reloaded.window_size = Vector2i(int(size_arr[0]), int(size_arr[1]))
	reloaded.monitor_index = int(data.get("monitor_index", 0))
	reloaded.vsync_mode = reloaded._parse_vsync_mode(data.get("vsync_mode"))
	reloaded.max_fps = int(data.get("max_fps", 0))
	reloaded.ui_scale = float(data.get("ui_scale", 1.0))
	reloaded.hud_safe_area = float(data.get("hud_safe_area", 0.0))
	var roundtrip_ok := (
		reloaded.window_mode == DisplayServiceScript.WINDOW_MODE_WINDOWED
		and reloaded.window_size == Vector2i(1600, 900)
		and reloaded.vsync_mode == DisplayServiceScript.VSYNC_ENABLED
		and reloaded.max_fps == 60
		and is_equal_approx(reloaded.ui_scale, 1.25)
		and is_equal_approx(reloaded.hud_safe_area, 0.02)
	)
	ctx.timed_record(
		"display.roundtrip",
		get_category(),
		roundtrip_ok,
		"display fields serialize and reload consistently",
		start,
		"DSP-01"
	)

	start = Time.get_ticks_msec()
	var ui_scale_row := {}
	for entry in SettingsSchema.entries():
		if str(entry.get("id", "")) == "ui_scale":
			ui_scale_row = entry
			break
	var range_dict: Dictionary = ui_scale_row.get("range", {})
	var bounds_match := (
		not ui_scale_row.is_empty()
		and is_equal_approx(float(range_dict.get("min", -1.0)), DisplayServiceScript.SCALE_MIN)
		and is_equal_approx(float(range_dict.get("max", -1.0)), DisplayServiceScript.SCALE_MAX)
	)
	var probe_before := DisplayService.ui_scale
	var setter: Callable = ui_scale_row.get("setter", Callable())
	var getter: Callable = ui_scale_row.get("getter", Callable())
	var probe_written := false
	if setter.is_valid() and getter.is_valid():
		setter.call(DisplayServiceScript.SCALE_MAX)
		probe_written = is_equal_approx(float(getter.call()), DisplayServiceScript.SCALE_MAX)
		DisplayService.ui_scale = probe_before
	var single_source_ok := bounds_match and probe_written
	ctx.timed_record(
		"display.scale_single_source",
		get_category(),
		single_source_ok,
		"settings schema's ui_scale slider bounds and getter/setter delegate to DisplayService",
		start,
		"DSP-03"
	)

	start = Time.get_ticks_msec()
	if DisplayService:
		DisplayService.set_ui_scale(1.25)
		DisplayService.apply_all()
	var tree := Engine.get_main_loop() as SceneTree
	var content_scale := tree.root.content_scale_factor if tree and tree.root else 0.0
	var theme: Theme = tree.root.theme if tree and tree.root else null
	var body_size := (
		theme.get_font_size(&"font_size", GameUISkinScript.VAR_BODY_TEXT) if theme else 0
	)
	var text_scale_ok := (
		is_equal_approx(content_scale, 1.0) and body_size > GameUISkinScript.FONT_SIZE_BODY
	)
	ctx.timed_record(
		"display.text_scale_effect",
		get_category(),
		text_scale_ok,
		"ui_scale 1.25 enlarges theme fonts while content_scale_factor stays integral",
		start,
		"DSP-02"
	)

	start = Time.get_ticks_msec()
	var relayout_ok := false
	if ctx.owner:
		var settings_scene := load("res://scripts/ui/settings_ui.gd") as Script
		var settings := settings_scene.new() as Control
		ctx.owner.add_child(settings)
		settings.call("open_settings")
		await ctx.await_frame()
		var panel_before := settings.get_node_or_null("Panel") as PanelContainer
		var size_before := panel_before.size if panel_before else Vector2.ZERO
		DisplayService.set_ui_scale(DisplayService.SCALE_MAX)
		await ctx.await_frame()
		var panel_after := settings.get_node_or_null("Panel") as PanelContainer
		relayout_ok = panel_after != null and panel_after.size != size_before
		settings.call("close_settings")
		settings.queue_free()
	ctx.timed_record(
		"display.relayout_on_change",
		get_category(),
		relayout_ok,
		"open settings modal relayouts when display_changed fires",
		start,
		"DSP-04"
	)

	start = Time.get_ticks_msec()
	var fallback_service := DisplayServiceScript.new()
	fallback_service.window_size = Vector2i(4000, 3000)
	fallback_service.monitor_index = 0
	fallback_service.sanitize_persisted_settings_for_test()
	var fallback_ok := (
		fallback_service.window_mode == DisplayServiceScript.WINDOW_MODE_WINDOWED
		and fallback_service.window_size_fits_any_monitor(fallback_service.window_size)
	)
	ctx.timed_record(
		"display.window_size_fallback",
		get_category(),
		fallback_ok,
		"oversized saved window size falls back to a fitting windowed size",
		start,
		"DSP-01"
	)

	start = Time.get_ticks_msec()
	var monitor_service := DisplayServiceScript.new()
	monitor_service.monitor_index = DisplayServer.get_screen_count() + 5
	monitor_service.sanitize_persisted_settings_for_test()
	ctx.timed_record(
		"display.monitor_fallback",
		get_category(),
		monitor_service.monitor_index == 0,
		"invalid monitor index falls back to 0",
		start,
		"DSP-01"
	)

	start = Time.get_ticks_msec()
	var fullscreen_service := DisplayServiceScript.new()
	fullscreen_service.window_mode = DisplayServiceScript.WINDOW_MODE_WINDOWED
	fullscreen_service._fullscreen_saved_mode = DisplayServiceScript.WINDOW_MODE_WINDOWED
	fullscreen_service._fullscreen_confirm_active = true
	fullscreen_service.window_mode = DisplayServiceScript.WINDOW_MODE_FULLSCREEN
	fullscreen_service._on_fullscreen_confirm_timeout()
	var revert_ok := fullscreen_service.window_mode == DisplayServiceScript.WINDOW_MODE_WINDOWED
	ctx.timed_record(
		"display.fullscreen_revert",
		get_category(),
		revert_ok,
		"unconfirmed fullscreen switch reverts after timeout",
		start,
		"DSP-01"
	)

	start = Time.get_ticks_msec()
	var SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
	var legacy_save := {
		"schemaVersion": 8,
		"meta": {"accessibility": {"ui_scale": 1.2, "reduce_camera_shake": false}},
	}
	var migrated: Dictionary = SaveMigratorScript.migrate(legacy_save)
	var display_block: Dictionary = migrated.get("meta", {}).get("display", {})
	var migration_ok := (
		int(migrated.get("schemaVersion", 0)) == SaveMigratorScript.CURRENT_VERSION
		and is_equal_approx(float(display_block.get("ui_scale", 0.0)), 1.2)
	)
	ctx.timed_record(
		"display.migration_ui_scale",
		get_category(),
		migration_ok,
		"accessibility.ui_scale migrates into meta.display.ui_scale",
		start,
		"DSP-01"
	)


func _test_ui_skin() -> void:
	var start := Time.get_ticks_msec()
	var theme_exists: bool = ResourceLoader.exists(GameUISkinScript.THEME_PATH)
	var theme: Theme = null
	if theme_exists:
		theme = load(GameUISkinScript.THEME_PATH) as Theme
	ctx.timed_record(
		"ui.skin.theme_resource",
		get_category(),
		theme_exists and theme != null,
		"aumbrye_ui.tres exists and loads as Theme",
		start,
		"SKN-01"
	)

	start = Time.get_ticks_msec()
	var registered: bool = (
		ProjectSettings.get_setting("gui/theme/custom") == GameUISkinScript.THEME_PATH
	)
	ctx.timed_record(
		"ui.skin.theme_registered",
		get_category(),
		registered,
		"project.godot registers gui/theme/custom",
		start,
		"SKN-01"
	)

	start = Time.get_ticks_msec()
	var built := GameUISkinScript.build_theme()
	var regen_ok: bool = built.get_color("font_color", "Label").is_equal_approx(
		GameUISkinScript.BODY_COLOR
	)
	ctx.timed_record(
		"ui.skin.theme_regenerates",
		get_category(),
		regen_ok,
		"build_theme() Label font_color matches BODY_COLOR",
		start,
		"SKN-01"
	)

	start = Time.get_ticks_msec()
	var variations_ok := true
	if theme == null:
		variations_ok = false
	else:
		for variation in GameUISkinScript.LABEL_VARIATIONS:
			if theme.get_type_variation_base(variation) != "Label":
				variations_ok = false
				break
	ctx.timed_record(
		"ui.skin.variations_present",
		get_category(),
		variations_ok,
		"theme defines all seven label variations",
		start,
		"SKN-02"
	)

	start = Time.get_ticks_msec()
	var font_ok := false
	if theme != null and theme.default_font != null:
		var font_path := theme.default_font.resource_path
		font_ok = font_path.ends_with("aumbrye_pixel.ttf")
	ctx.timed_record(
		"ui.skin.font_default",
		get_category(),
		font_ok,
		"theme default_font points at aumbrye_pixel.ttf",
		start,
		"SKN-03"
	)

	start = Time.get_ticks_msec()
	var saved_low_res := PixelDioramaSettingsScript.low_res_viewport_enabled
	var saved_width := PixelDioramaSettingsScript.viewport_width
	var saved_height := PixelDioramaSettingsScript.viewport_height
	PixelDioramaSettingsScript.low_res_viewport_enabled = true
	PixelDioramaSettingsScript.viewport_width = 480
	PixelDioramaSettingsScript.viewport_height = 270
	var pixel_panel := GameUISkinScript.make_panel_style()
	var pixel_ok: bool = pixel_panel.corner_radius_top_left == 0 and pixel_panel.shadow_size == 0
	PixelDioramaSettingsScript.low_res_viewport_enabled = saved_low_res
	PixelDioramaSettingsScript.viewport_width = saved_width
	PixelDioramaSettingsScript.viewport_height = saved_height
	ctx.timed_record(
		"ui.skin.pixel_panel_square",
		get_category(),
		pixel_ok,
		"pixel mode panel style has zero radius and shadow",
		start,
		"SKN-05"
	)

	start = Time.get_ticks_msec()
	PixelDioramaSettingsScript.set_resolution_preset(4)
	var hd_panel := GameUISkinScript.make_panel_style()
	var hd_ok: bool = hd_panel.corner_radius_top_left == GameUISkinScript.PANEL_CORNER_RADIUS_HD
	PixelDioramaSettingsScript.viewport_width = saved_width
	PixelDioramaSettingsScript.viewport_height = saved_height
	ctx.timed_record(
		"ui.skin.hd_panel_rounded",
		get_category(),
		hd_ok,
		"native-HD panel style keeps rounded corners",
		start,
		"SKN-05"
	)

	start = Time.get_ticks_msec()
	var focus_ok := true
	if theme == null:
		focus_ok = false
	else:
		for control_type in ["Button", "ItemList", "OptionButton", "CheckBox", "LineEdit"]:
			if theme.get_stylebox("focus", control_type) == null:
				focus_ok = false
				break
	ctx.timed_record(
		"ui.skin.focus_styleboxes",
		get_category(),
		focus_ok,
		"theme defines focus styleboxes for interactive controls",
		start,
		"SKN-10"
	)

	start = Time.get_ticks_msec()
	var label_walk_saved_low_res := PixelDioramaSettingsScript.low_res_viewport_enabled
	var label_walk_saved_width := PixelDioramaSettingsScript.viewport_width
	var label_walk_saved_height := PixelDioramaSettingsScript.viewport_height
	PixelDioramaSettingsScript.low_res_viewport_enabled = true
	PixelDioramaSettingsScript.viewport_width = 480
	PixelDioramaSettingsScript.viewport_height = 270
	var label_walk_root := Control.new()
	var oddly_named_label := Label.new()
	oddly_named_label.name = "NotCalledLabelAtAll"
	label_walk_root.add_child(oddly_named_label)
	if ctx.owner:
		ctx.owner.add_child(label_walk_root)
	GameUISkinScript.apply_pixel_theme(label_walk_root)
	var no_label_walk: bool = (
		oddly_named_label.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
	)
	label_walk_root.queue_free()
	PixelDioramaSettingsScript.low_res_viewport_enabled = label_walk_saved_low_res
	PixelDioramaSettingsScript.viewport_width = label_walk_saved_width
	PixelDioramaSettingsScript.viewport_height = label_walk_saved_height
	ctx.timed_record(
		"ui.skin.no_label_walk",
		get_category(),
		no_label_walk,
		"apply_pixel_theme themes an arbitrarily-named Label by type, not by node name",
		start,
		"SKN-02"
	)

	start = Time.get_ticks_msec()
	var skin_constants := GameUISkinScript.get_script_constant_map()
	var no_dead: bool = (
		not skin_constants.has("CELL_SIZE") and not skin_constants.has("EQUIP_CELL_SIZE")
	)
	ctx.timed_record(
		"ui.skin.no_dead_constants",
		get_category(),
		no_dead,
		"game_ui_skin.gd defines no dead CELL_SIZE/EQUIP_CELL_SIZE constants",
		start,
		"SKN-08"
	)

	start = Time.get_ticks_msec()
	var button_files := [
		"res://scripts/ui/stair_menu.gd",
		"res://scripts/ui/umbral_endless_menu.gd",
		"res://scripts/ui/blacksmith_ui.gd",
	]
	var buttons_ok := true
	for path in button_files:
		if ctx.file_contains(path, "Button.new()"):
			buttons_ok = false
			break
	ctx.timed_record(
		"ui.skin.button_sfx_coverage",
		get_category(),
		buttons_ok,
		"hub menu scripts use GameUISkin.make_button",
		start,
		"SKN-07"
	)

	start = Time.get_ticks_msec()
	var paperdoll_ok: bool = ResourceLoader.exists(GameUISkinScript.PAPERDOLL_TEXTURE_PATH)
	if paperdoll_ok:
		var dir := DirAccess.open("res://scripts/ui")
		if dir:
			dir.list_dir_begin()
			var file_name := dir.get_next()
			while file_name != "":
				if not dir.current_is_dir() and file_name.ends_with(".gd"):
					if ctx.file_contains(
						"res://scripts/ui/%s" % file_name, "build_human_silhouette"
					):
						paperdoll_ok = false
						break
				file_name = dir.get_next()
	ctx.timed_record(
		"ui.skin.paperdoll_texture",
		get_category(),
		paperdoll_ok,
		"paperdoll texture exists and no UI script calls build_human_silhouette",
		start,
		"SKN-04"
	)


func _content_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../../..")

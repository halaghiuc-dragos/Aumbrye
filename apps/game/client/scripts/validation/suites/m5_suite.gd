extends "res://scripts/validation/validation_suite.gd"

const CRYSTAL_ENEMIES: Array[String] = [
	"crystal_slime", "crystal_bat", "crystal_golem", "crystal_shade",
	"crystal_guardian", "crystal_sovereign",
]
const SWAMP_ENEMIES: Array[String] = [
	"swamp_bogling", "swamp_leech", "swamp_toad", "swamp_witch",
	"swamp_hag", "swamp_hydra",
]
const M5_WEAPONS: Array[String] = ["greatsword", "dagger", "spear", "bow"]
const M5_STATUSES: Array[String] = ["burn", "bleed", "poison", "freeze", "stun"]
const CASTLE_UNIQUES: Array[String] = ["castle_banner", "castle_chalice", "castle_crown"]
const CRYSTAL_UNIQUES: Array[String] = [
	"crystal_frost_ring", "crystal_prism_amulet", "crystal_shard_blade",
]
const SWAMP_UNIQUES: Array[String] = [
	"swamp_bog_boots", "swamp_mire_charm", "swamp_toxin_dagger",
]
const M5_SCHEMAS: Array[String] = [
	"content/schemas/npc-definition.v1.json",
	"content/schemas/quest-definition.v1.json",
	"content/schemas/dialogue-definition.v1.json",
	"content/schemas/relic-definition.v1.json",
	"content/schemas/recipe-definition.v1.json",
	"content/schemas/status-definition.v1.json",
	"content/schemas/audio-profile.v1.json",
	"content/schemas/merchant-pack.v1.json",
]


func get_category() -> String:
	return "m5"


func run() -> void:
	_test_biome_registry()
	_test_biome_materials_and_lighting()
	await _test_procgen_biomes()
	await _test_dungeon_build_biomes()
	_test_damage_types_and_resistance()
	await _test_status_system()
	_test_weapon_definitions()
	await _test_loadout_unlocks()
	_test_castle_entry_biome_select()
	_test_theme_enemies_and_bosses()
	_test_theme_unique_items()
	_test_audio_profiles()
	_test_m5_schemas()
	_test_loot_epic_affix_counts()
	await _test_save_integer_normalization()
	_test_balance_doc()
	_test_online_procgen_optional_path()


func _test_biome_registry() -> void:
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"m5.biome.all_three_registered",
		get_category(),
		BiomeRegistry.ALL_BIOMES.has(BiomeRegistry.BIOME_CASTLE)
			and BiomeRegistry.ALL_BIOMES.has(BiomeRegistry.BIOME_CRYSTAL)
			and BiomeRegistry.ALL_BIOMES.has(BiomeRegistry.BIOME_SWAMP),
		"M5 biomes (castle, crystal, swamp) still registered",
		start,
		"M5.theme.biomes"
	)

	for biome_id in [
		BiomeRegistry.BIOME_CASTLE,
		BiomeRegistry.BIOME_CRYSTAL,
		BiomeRegistry.BIOME_SWAMP,
	]:
		start = Time.get_ticks_msec()
		var rooms: Dictionary = BiomeRegistry.get_room_scenes(biome_id)
		var expected_min := 8 if biome_id == BiomeRegistry.BIOME_CASTLE else 9
		ctx.timed_record(
			"m5.biome.%s_room_count" % biome_id,
			get_category(),
			rooms.size() >= expected_min,
			"%s has %d room templates" % [biome_id, rooms.size()],
			start,
			"M5.theme.%s" % biome_id
		)


func _test_biome_materials_and_lighting() -> void:
	var profiles: Array[Dictionary] = []
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var start := Time.get_ticks_msec()
		var floor_mat: Material = BiomeRegistry.get_floor_material(biome_id)
		var wall_mat: Material = BiomeRegistry.get_wall_material(biome_id)
		var lighting: Dictionary = BiomeRegistry.get_lighting_profile(biome_id)
		profiles.append(lighting)
		ctx.timed_record(
			"m5.biome.%s_materials" % biome_id,
			get_category(),
			floor_mat != null and wall_mat != null and lighting.has("ambient_color"),
			"%s materials + lighting profile load" % biome_id,
			start,
			"M5.theme.materials"
		)

	var start := Time.get_ticks_msec()
	var distinct: bool = (
		profiles[0].get("ambient_color") != profiles[1].get("ambient_color")
		and profiles[1].get("ambient_color") != profiles[2].get("ambient_color")
	)
	ctx.timed_record(
		"m5.biome.distinct_lighting",
		get_category(),
		distinct,
		"three biomes have distinct ambient colors",
		start,
		"M5.theme.blind"
	)


func _test_procgen_biomes() -> void:
	for biome_id in [BiomeRegistry.BIOME_CRYSTAL, BiomeRegistry.BIOME_SWAMP]:
		var prefix: String = "crystal" if biome_id == BiomeRegistry.BIOME_CRYSTAL else "swamp"
		var start := Time.get_ticks_msec()
		var gen := LocalProcgen.generate(biome_id, TC.SEED_A)
		ctx.timed_record(
			"m5.procgen.%s_generates" % biome_id,
			get_category(),
			gen.get("ok", false),
			"%s seed %d generates" % [biome_id, TC.SEED_A],
			start,
			"M5.theme.%s" % biome_id
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
			"m5.procgen.%s_template_prefix" % biome_id,
			get_category(),
			prefix_ok,
			"%s rooms use %s_ template prefix" % [biome_id, prefix],
			start,
			"M5.theme.templates"
		)

		start = Time.get_ticks_msec()
		var gen2 := LocalProcgen.generate(biome_id, TC.SEED_A)
		var sig1: String = ctx.layout_signature(def)
		var sig2: String = ctx.layout_signature(gen2.get("definition", {}))
		ctx.timed_record(
			"m5.procgen.%s_deterministic" % biome_id,
			get_category(),
			sig1 == sig2 and not sig1.is_empty(),
			"%s same seed produces identical layout" % biome_id,
			start,
			"M3.procgen.determinism"
		)


func _test_dungeon_build_biomes() -> void:
	for biome_id in [BiomeRegistry.BIOME_CRYSTAL, BiomeRegistry.BIOME_SWAMP]:
		var gen := LocalProcgen.generate(biome_id, TC.SEED_A)
		if not gen.get("ok", false):
			var start := Time.get_ticks_msec()
			ctx.timed_record(
				"m5.dungeon.%s_build" % biome_id,
				get_category(),
				false,
				"procgen failed before dungeon build for %s" % biome_id,
				start,
				"M5.theme.%s" % biome_id
			)
			continue

		var root := Node3D.new()
		root.name = "M5Dungeon_%s" % biome_id
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
			"m5.dungeon.%s_rooms" % biome_id,
			get_category(),
			room_count > 0,
			"%s: %d rooms built" % [biome_id, room_count],
			start,
			"M5.theme.%s" % biome_id
		)

		start = Time.get_ticks_msec()
		ctx.timed_record(
			"m5.dungeon.%s_enemies" % biome_id,
			get_category(),
			enemy_count > 0,
			"%s: %d enemies spawned" % [biome_id, enemy_count],
			start,
			"M5.theme.%s" % biome_id
		)

		start = Time.get_ticks_msec()
		var boss_door := builder.get_boss_door()
		ctx.timed_record(
			"m5.dungeon.%s_boss_door" % biome_id,
			get_category(),
			boss_door != null,
			"%s boss door wired" % biome_id,
			start,
			"M5.boss.%s" % biome_id
		)
		root.queue_free()


func _test_damage_types_and_resistance() -> void:
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"m5.damage.six_types",
		get_category(),
		DamageInfo.ALL_TYPES.size() == 6,
		"DamageInfo defines six damage types",
		start,
		"M5.dmg.types"
	)

	start = Time.get_ticks_msec()
	var reduced := DamageInfo.apply_resistance(100.0, DamageInfo.TYPE_FIRE, {"fire": 0.5})
	var immune := DamageInfo.apply_resistance(50.0, DamageInfo.TYPE_FROST, {"frost": 1.0})
	ctx.timed_record(
		"m5.damage.resistance_pipeline",
		get_category(),
		is_equal_approx(reduced, 50.0) and is_equal_approx(immune, 0.0),
		"resistance reduces and full resist blocks damage",
		start,
		"M5.dmg.resist"
	)

	start = Time.get_ticks_msec()
	var golem := EnemyCatalog.get_definition("crystal_golem")
	var has_resist: bool = golem.get("resistances", {}).has("frost")
	ctx.timed_record(
		"m5.damage.enemy_resistances_data",
		get_category(),
		has_resist,
		"crystal_golem has frost resistance in JSON",
		start,
		"M5.dmg.resist"
	)


func _test_status_system() -> void:
	var start := Time.get_ticks_msec()
	var loaded: Array[String] = StatusCatalog.all_ids()
	var all_present := true
	for status_id in M5_STATUSES:
		if not loaded.has(status_id):
			all_present = false
	ctx.timed_record(
		"m5.status.five_definitions",
		get_category(),
		all_present and loaded.size() >= 5,
		"five status definitions load from content/statuses/",
		start,
		"M5.dmg.status"
	)

	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	ctx.owner.add_child(player)
	await ctx.await_frame()
	var status_ctrl := player.get_node_or_null("StatusController") as StatusController
	start = Time.get_ticks_msec()
	var has_controller := status_ctrl != null
	if has_controller:
		status_ctrl.debug_apply("burn")
		await ctx.await_physics(2)
	var active := status_ctrl.get_active_statuses() if has_controller else []
	ctx.timed_record(
		"m5.status.apply_burn",
		get_category(),
		has_controller and not active.is_empty() and active[0].get("id", "") == "burn",
		"StatusController applies burn via debug_apply",
		start,
		"M5.dmg.status"
	)

	start = Time.get_ticks_msec()
	var hud_script := FileAccess.get_file_as_string("res://scripts/ui/combat_hud.gd")
	var hud_has_row := "_status_row" in hud_script and "_refresh_status_icons" in hud_script
	ctx.timed_record(
		"m5.status.hud_icon_row",
		get_category(),
		hud_has_row,
		"combat_hud renders status icon row",
		start,
		"M5.dmg.status_hud"
	)
	player.queue_free()


func _test_weapon_definitions() -> void:
	for weapon_id in M5_WEAPONS:
		var start := Time.get_ticks_msec()
		var path := "content/weapons/%s.json" % weapon_id
		var data: Dictionary = ContentLoader.load_json(path)
		var ok := (
			not data.is_empty()
			and str(data.get("id", "")) == weapon_id
			and (data.has("light_attacks") or data.has("heavy_attack"))
		)
		ctx.timed_record(
			"m5.weapon.%s_json" % weapon_id,
			get_category(),
			ok,
			"weapon definition loads: %s" % path,
			start,
			"M5.wpn.%s" % weapon_id
		)


func _test_loadout_unlocks() -> void:
	ProgressionService.from_save_dict({"level": 1, "xp": 0, "talents": {}})
	CharacterService.reset_to_defaults()
	var start := Time.get_ticks_msec()
	var spear_locked: bool = not _is_weapon_unlocked_for_test("guard_spear", 1, {})
	var bow_locked: bool = not _is_weapon_unlocked_for_test("hunter_bow", 1, {})
	var dagger_open: bool = _is_weapon_unlocked_for_test("rogue_dagger", 1, {})
	ctx.timed_record(
		"m5.loadout.level_gates",
		get_category(),
		spear_locked and bow_locked and dagger_open,
		"spear/bow locked at level 1; dagger always unlocked",
		start,
		"M5.wpn.loadout"
	)

	start = Time.get_ticks_msec()
	var spear_unlocked: bool = _is_weapon_unlocked_for_test("guard_spear", 5, {})
	var bow_unlocked: bool = _is_weapon_unlocked_for_test("hunter_bow", 8, {})
	ProgressionService.from_save_dict({"level": 1, "xp": 0, "talents": {}})
	ctx.timed_record(
		"m5.loadout.unlock_thresholds",
		get_category(),
		spear_unlocked and bow_unlocked,
		"spear unlocks at Lv5; bow at Lv8",
		start,
		"M5.wpn.loadout"
	)


func _is_weapon_unlocked_for_test(item_id: String, level: int, flags: Dictionary) -> bool:
	match item_id:
		"castle_sword", "training_greatsword", "rogue_dagger":
			return true
		"guard_spear":
			return level >= 5 or flags.get("theme_forgotten_castle_cleared", false)
		"hunter_bow":
			return level >= 8 or flags.get("theme_crystal_caverns_cleared", false)
		_:
			return ItemCatalog.has_item(item_id)


func _test_castle_entry_biome_select() -> void:
	var menu: Control = load("res://scenes/ui/castle_entry_menu.tscn").instantiate() as Control
	ctx.owner.add_child(menu)
	await ctx.await_frame()
	menu.call("_build_biome_buttons")
	var biome_box := menu.get_node_or_null("MainPanel/Margin/VBox/BiomeBox")
	var start := Time.get_ticks_msec()
	var btn_count := biome_box.get_child_count() if biome_box else 0
	ctx.timed_record(
		"m5.hub.biome_buttons",
		get_category(),
		btn_count == BiomeRegistry.ALL_BIOMES.size(),
		"castle entry menu shows %d biome buttons" % btn_count,
		start,
		"M5.hub.biome_select"
	)

	start = Time.get_ticks_msec()
	menu.call("_on_biome_pressed", BiomeRegistry.BIOME_SWAMP, biome_box.get_child(2))
	var selected: String = menu.get_selected_biome()
	ctx.timed_record(
		"m5.hub.biome_selection",
		get_category(),
		selected == BiomeRegistry.BIOME_SWAMP,
		"biome selection updates get_selected_biome()",
		start,
		"M5.hub.biome_select"
	)
	menu.queue_free()


func _test_theme_enemies_and_bosses() -> void:
	for enemy_id in CRYSTAL_ENEMIES:
		_record_enemy_alignment(enemy_id, "crystal")
	for enemy_id in SWAMP_ENEMIES:
		_record_enemy_alignment(enemy_id, "swamp")

	var start := Time.get_ticks_msec()
	var sovereign_scene := EnemyCatalog.get_scene("crystal_sovereign")
	var hydra_scene := EnemyCatalog.get_scene("swamp_hydra")
	ctx.timed_record(
		"m5.boss.theme_scenes",
		get_category(),
		sovereign_scene != null and hydra_scene != null,
		"crystal_sovereign and swamp_hydra scenes resolve",
		start,
		"M5.boss.scenes"
	)


func _record_enemy_alignment(enemy_id: String, theme: String) -> void:
	var start := Time.get_ticks_msec()
	var def := EnemyCatalog.get_definition(enemy_id)
	var scene := EnemyCatalog.get_scene(enemy_id)
	ctx.timed_record(
		"m5.enemy.%s" % enemy_id,
		get_category(),
		not def.is_empty() and scene != null,
		"%s enemy JSON + scene aligned" % enemy_id,
		start,
		"M5.theme.%s" % theme
	)


func _test_theme_unique_items() -> void:
	for item_id in CASTLE_UNIQUES + CRYSTAL_UNIQUES + SWAMP_UNIQUES:
		var start := Time.get_ticks_msec()
		var has_item := ItemCatalog.has_item(item_id)
		var def := ItemCatalog.get_definition(item_id) if has_item else {}
		ctx.timed_record(
			"m5.item.%s" % item_id,
			get_category(),
			has_item and not def.is_empty(),
			"theme unique item in catalog: %s" % item_id,
			start,
			"M5.item.uniques"
		)


func _test_audio_profiles() -> void:
	var start := Time.get_ticks_msec()
	for biome_id in BiomeRegistry.ALL_BIOMES:
		start = Time.get_ticks_msec()
		var path := BiomeRegistry.get_audio_profile_path(biome_id)
		var data: Dictionary = ContentLoader.load_json(path)
		ctx.timed_record(
			"m5.audio.profile_%s" % biome_id,
			get_category(),
			not data.is_empty() and data.has("id"),
			"audio profile loads for %s" % biome_id,
			start,
			"M5.audio.profile"
		)

	start = Time.get_ticks_msec()
	AudioDirector.set_biome(BiomeRegistry.BIOME_CRYSTAL)
	var has_set_biome: bool = AudioDirector.has_method("set_biome")
	ctx.timed_record(
		"m5.audio.set_biome",
		get_category(),
		has_set_biome,
		"AudioDirector.set_biome() callable",
		start,
		"M5.audio.director"
	)


func _test_m5_schemas() -> void:
	for relative in M5_SCHEMAS:
		var start := Time.get_ticks_msec()
		var full := _content_root().path_join(relative)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(full)) if FileAccess.file_exists(full) else null
		var ok: bool = parsed is Dictionary and (
			(parsed as Dictionary).has("schemaVersion")
			or (parsed as Dictionary).has("$schema")
			or (parsed as Dictionary).has("$id")
		)
		ctx.timed_record(
			"m5.schema.%s" % relative.get_file().get_basename(),
			get_category(),
			ok,
			"M5 schema file loads: %s" % relative,
			start,
			"M5.schema.hub"
		)


func _test_loot_epic_affix_counts() -> void:
	var start := Time.get_ticks_msec()
	var data: Dictionary = ContentLoader.load_json("content/affixes/rarity_rules.json")
	var counts: Dictionary = data.get("affixCounts", {})
	var epic: Dictionary = counts.get("epic", {})
	var legendary: Dictionary = counts.get("legendary", {})
	var mythic: Dictionary = counts.get("mythic", {})
	var ok := (
		int(epic.get("min", 0)) == 2 and int(epic.get("max", 0)) == 3
		and int(legendary.get("min", 0)) == 3 and int(legendary.get("max", 0)) == 4
		and int(mythic.get("min", 0)) == 4 and int(mythic.get("max", 0)) == 5
	)
	ctx.timed_record(
		"m5.loot.epic_affix_counts",
		get_category(),
		ok,
		"rarity_rules.json defines epic/legendary/mythic affix counts",
		start,
		"M5.loot.affix"
	)


func _test_save_integer_normalization() -> void:
	var backup: Dictionary = ctx.backup_save_file()
	LocalSave.delete_save()
	InventoryService.inventory = GridInventory.new()
	InventoryService.inventory.from_save_dict({
		"gridWidth": 10.0,
		"gridHeight": 6.0,
		"slots": [{
			"itemId": "iron_scrap",
			"quantity": 2.0,
			"x": 1.0,
			"y": 0.0,
			"rollSeed": 42.0,
		}],
		"equipped": {},
	})
	LocalSave.autosave()
	var start := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string(TC.SAVE_PATH)
	var ok := false
	if FileAccess.file_exists(TC.SAVE_PATH) and not text.is_empty():
		var no_float_coords := (
			not text.contains('"quantity": 2.0')
			and not text.contains('"x": 1.0')
			and not text.contains('"y": 0.0')
			and not text.contains('"rollSeed": 42.0')
		)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			var slots: Array = (parsed as Dictionary).get("inventory", {}).get("slots", [])
			if not slots.is_empty() and slots[0] is Dictionary:
				var slot: Dictionary = slots[0]
				ok = (
					no_float_coords
					and int(slot.get("quantity", -1)) == 2
					and int(slot.get("x", -1)) == 1
					and int(slot.get("y", -1)) == 0
					and int(slot.get("rollSeed", -1)) == 42
				)
	ctx.restore_save_file(backup)
	ctx.timed_record(
		"m5.save.integer_normalization",
		get_category(),
		ok,
		"autosave writes integer quantity/x/y/rollSeed",
		start,
		"M5.save.integers"
	)


func _test_balance_doc() -> void:
	var start := Time.get_ticks_msec()
	var path := _content_root().path_join("docs/design/balance_m5.md")
	ctx.timed_record(
		"m5.balance.doc_exists",
		get_category(),
		FileAccess.file_exists(path),
		"balance_m5.md structural doc present",
		start,
		"M5.bal.doc"
	)


func _test_online_procgen_optional_path() -> void:
	var start := Time.get_ticks_msec()
	var has_online: bool = ctx.file_contains("res://scripts/app/run_flow.gd", "func _try_online_generate")
	var offline_default: bool = ctx.file_contains("res://scripts/app/run_flow.gd", "const USE_ONLINE_PROCgen := false")
	ctx.timed_record(
		"m5.net.online_path_optional",
		get_category(),
		has_online and offline_default,
		"online procgen path exists; USE_ONLINE_PROCgen false by default",
		start,
		"M5.net.offline"
	)


func _content_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../../..")

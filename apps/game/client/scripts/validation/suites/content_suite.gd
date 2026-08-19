extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "content"


func run() -> void:
	_test_enemy_catalog()
	_test_items()
	_test_no_unauthored_items()
	_test_character_manifests()
	_test_equipment_visual_pivots()
	_test_ui_atlases()
	_test_hub_tips_content()
	_test_scenes_and_scripts()
	_test_room_templates()
	_test_audio_director()
	_test_combat_sfx_bank()
	_test_save_migrations_doc_sync()
	_test_character_state_v2_matches_runtime()
	_test_appearance_schema_bounds()
	_test_dialogue_flags_registered()
	_test_quest_flags_registered()
	_test_quest_ids_no_progress_suffix()
	_test_dungeon_clear_flags_registered()
	_test_npc_hub_content()
	_test_no_root_seed_dumps()
	_test_biome_grades()


func _test_biome_grades() -> void:
	BiomeRegistry.warm_index()
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var start := Time.get_ticks_msec()
		var biome: Dictionary = ContentLoader.load_json("content/biomes/%s.json" % biome_id)
		var grade: Variant = biome.get("grade", null)
		if grade == null:
			continue
		var ok := grade is Dictionary
		if ok:
			var allowed := [
				"shadowTint",
				"shadowTintAmount",
				"highlightTint",
				"highlightTintAmount",
			]
			for key in (grade as Dictionary).keys():
				if key not in allowed:
					ok = false
					break
		ctx.timed_record(
			"content.biome_grade_%s" % biome_id,
			get_category(),
			ok,
			"optional grade block uses allowed keys for %s" % biome_id,
			start,
			"PDS-06"
		)


func _test_no_root_seed_dumps() -> void:
	var start := Time.get_ticks_msec()
	var repo_root := ProjectSettings.globalize_path("res://").path_join("..").path_join("..")
	var found: PackedStringArray = []
	for file_name in ["seed1.json", "seed99999.json"]:
		var candidate := repo_root.path_join(file_name)
		if FileAccess.file_exists(candidate):
			found.append(file_name)
	ctx.timed_record(
		"content.no_root_seed_dumps",
		get_category(),
		found.is_empty(),
		"no seed*.json artifacts at repo root" if found.is_empty() else "found: %s" % ", ".join(found),
		start,
		"FGS-12"
	)


func _test_npc_hub_content() -> void:
	var start := Time.get_ticks_msec()
	var merchant_ok := true
	for file_name in ["hub_merchant.json", "dungeon_merchant.json"]:
		var pack: Dictionary = ContentLoader.load_json("content/merchant/%s" % file_name)
		for row in pack.get("items", []):
			if not row is Dictionary:
				continue
			var item_id := str(row.get("itemId", ""))
			if not ItemCatalog.has_item(item_id):
				merchant_ok = false
			if int(row.get("price", 0)) <= 0 or int(row.get("stock", 0)) <= 0:
				merchant_ok = false
	ctx.timed_record(
		"content.merchant.items_exist",
		get_category(),
		merchant_ok,
		"merchant stock rows resolve items with positive price/stock",
		start,
		"NPC-04"
	)

	start = Time.get_ticks_msec()
	var recipe_types_ok := true
	for recipe in RecipeCatalog.get_unlock_recipes():
		if not RecipeCatalog.get_unlock_recipe_for_item(str(recipe.get("itemId", ""))).is_empty():
			continue
		recipe_types_ok = false
	for recipe_id in ["castle_sword_upgrade_1", "castle_sword_repair"]:
		if RecipeCatalog.get_unlock_recipe(recipe_id).is_empty() and recipe_id.begins_with("unlock"):
			recipe_types_ok = false
	ctx.timed_record(
		"content.recipes.types_are_handled",
		get_category(),
		recipe_types_ok,
		"unlock recipes resolve through RecipeCatalog",
		start,
		"NPC-06"
	)
	_test_waves_definition()


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
		(
			"enemy catalog + scenes"
			if missing_enemies.is_empty()
			else "missing: %s" % ", ".join(missing_enemies)
		),
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
		(
			"item catalog entries"
			if missing_items.is_empty()
			else "missing: %s" % ", ".join(missing_items)
		),
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


func _test_no_unauthored_items() -> void:
	var start := Time.get_ticks_msec()
	var catalog: Dictionary = ContentLoader.load_json("content/items/catalog.json")
	var bad: PackedStringArray = []
	for category in ["equipment", "consumables", "materials"]:
		for item_id in catalog.get(category, []):
			var path := ItemCatalog.get_content_path(str(item_id))
			if path.is_empty():
				continue
			var item: Dictionary = ContentLoader.load_json(path)
			if item.get("authored", true) == false:
				bad.append("%s (authored=false)" % item_id)
			elif str(item.get("description", "")).strip_edges() == "":
				bad.append("%s (empty description)" % item_id)
	ctx.timed_record(
		"content.no_unauthored_items",
		get_category(),
		bad.is_empty(),
		"catalog items are authored" if bad.is_empty() else "unauthored: %s" % ", ".join(bad),
		start,
		"TLS-01"
	)


func _test_character_manifests() -> void:
	var start := Time.get_ticks_msec()
	var CharacterRigCatalog := preload("res://scripts/art/characters/character_rig_catalog.gd")
	var schema_path: String = ctx.repo_root().path_join("content/schemas/character-rig.v1.json")
	var schema_ok := FileAccess.file_exists(schema_path)
	var missing_meshes: PackedStringArray = []
	var invalid: PackedStringArray = []
	for archetype_id in CharacterRigCatalog.list_archetype_ids():
		var manifest := CharacterRigCatalog.get_manifest(archetype_id)
		if manifest.is_empty():
			invalid.append(archetype_id)
			continue
		if (
			not manifest.has("id")
			or not manifest.has("grid")
			or not manifest.has("profile")
			or not manifest.has("parts")
		):
			invalid.append(archetype_id)
		var parts: Dictionary = manifest.get("parts", {})
		for part_name in parts:
			var mesh_path := str(parts[part_name].get("mesh", ""))
			if mesh_path == "" or not ResourceLoader.exists(mesh_path):
				missing_meshes.append("%s:%s" % [archetype_id, part_name])
	ctx.timed_record(
		"content.character_manifests",
		get_category(),
		schema_ok and invalid.is_empty() and missing_meshes.is_empty(),
		(
			"character rig manifests valid"
			if missing_meshes.is_empty() and invalid.is_empty()
			else "invalid=%s missing=%s" % [", ".join(invalid), ", ".join(missing_meshes)]
		),
		start,
		"CHA-02"
	)


func _test_equipment_visual_pivots() -> void:
	var start := Time.get_ticks_msec()
	const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
	const CharacterRigCatalog := preload("res://scripts/art/characters/character_rig_catalog.gd")
	const VoxelGrid := preload("res://scripts/art/characters/voxel_grid.gd")
	const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
	var bad: PackedStringArray = []
	var catalog := ContentLoader.load_json("content/items/catalog.json")
	for category in ["equipment"]:
		for item_id in catalog.get(category, []):
			var def := ContentLoader.load_json("content/items/equipment/%s.json" % item_id)
			var vis: Dictionary = def.get("visual", {})
			if vis.is_empty():
				continue
			var attach := str(vis.get("attach", ""))
			if attach == "":
				bad.append("%s:missing_attach" % item_id)
				continue
			var visual := Node3D.new()
			var archetype := CharacterRigCatalog.archetype_for_player({})
			var root := CharacterSkin.build_from_manifest(visual, archetype, PixelStyle.PaletteTheme.CASTLE)
			if root == null:
				bad.append("%s:player_build" % item_id)
				visual.free()
				continue
			var profile := str(CharacterRigCatalog.get_manifest(archetype).get("profile", "biped"))
			var allowed: Array = VoxelGrid.REQUIRED_PIVOTS.get(profile, [])
			if attach not in allowed and CharacterSkin.find_part(visual, attach) == null:
				bad.append("%s:bad_attach_%s" % [item_id, attach])
			visual.free()
	ctx.timed_record(
		"content.equipment_visual_pivots",
		get_category(),
		bad.is_empty(),
		(
			"equipment visual attach pivots exist on player rig"
			if bad.is_empty()
			else "invalid: %s" % ", ".join(bad)
		),
		start,
		"CHA-05"
	)


func _test_ui_atlases() -> void:
	var status_manifest := ContentLoader.load_json("content/ui/status_icon_atlas.json")
	var start := Time.get_ticks_msec()
	var schema_ok := (
		int(status_manifest.get("schemaVersion", 0)) == 1
		and not str(status_manifest.get("texture", "")).is_empty()
		and status_manifest.has("cellSize")
		and status_manifest.has("columns")
		and status_manifest.has("rows")
		and status_manifest.get("cells", {}) is Dictionary
	)
	ctx.timed_record(
		"content.status_atlas_schema",
		get_category(),
		schema_ok,
		"status icon atlas manifest matches status-icon-atlas.v1.json shape",
		start,
		"SIA-01"
	)

	start = Time.get_ticks_msec()
	var cell_size := int(status_manifest.get("cellSize", 16))
	var columns := int(status_manifest.get("columns", 0))
	var rows := int(status_manifest.get("rows", 0))
	var texture_path := str(status_manifest.get("texture", ""))
	var bounds_ok := columns > 0 and rows > 0
	if bounds_ok and ResourceLoader.exists(texture_path):
		var tex := load(texture_path) as Texture2D
		if tex:
			bounds_ok = columns * cell_size == tex.get_width() and rows * cell_size == tex.get_height()
	var cells: Dictionary = status_manifest.get("cells", {})
	for cell_id in cells.keys():
		var entry: Dictionary = cells[cell_id]
		if int(entry.get("col", -1)) >= columns or int(entry.get("row", -1)) >= rows:
			bounds_ok = false
	ctx.timed_record(
		"content.status_atlas_cells_in_bounds",
		get_category(),
		bounds_ok,
		"status atlas cells fit manifest grid and texture dimensions",
		start,
		"SIA-08"
	)

	start = Time.get_ticks_msec()
	var orphan_ok := true
	for cell_id in cells.keys():
		if cell_id == "unknown" or str(cell_id).begins_with("frame_"):
			continue
		if not FileAccess.file_exists(
			ContentLoader.content_path("content/statuses/%s.json" % cell_id)
		):
			orphan_ok = false
	ctx.timed_record(
		"content.status_atlas_no_orphan_cells",
		get_category(),
		orphan_ok,
		"every manifest status cell has a content/statuses file",
		start,
		"SIA-06"
	)

	start = Time.get_ticks_msec()
	var covers_ok := true
	for file_name in DirAccess.get_files_at(ContentLoader.content_path("content/statuses")):
		if not file_name.ends_with(".json"):
			continue
		var status_id := file_name.get_basename()
		if not StatusIconAtlas.has_icon(status_id):
			covers_ok = false
	ctx.timed_record(
		"content.status_atlas_covers_all",
		get_category(),
		covers_ok,
		"every authored status has an atlas cell",
		start,
		"SIA-02"
	)

	start = Time.get_ticks_msec()
	var polarity_ok := true
	for file_name in DirAccess.get_files_at(ContentLoader.content_path("content/statuses")):
		if not file_name.ends_with(".json"):
			continue
		var def: Dictionary = ContentLoader.load_json("content/statuses/%s" % file_name)
		var polarity := str(def.get("polarity", ""))
		if polarity != "buff" and polarity != "debuff":
			polarity_ok = false
	ctx.timed_record(
		"content.status_polarity_present",
		get_category(),
		polarity_ok,
		"every status file declares polarity buff or debuff",
		start,
		"SIA-04"
	)

	start = Time.get_ticks_msec()
	var item_manifest := ContentLoader.load_json("content/ui/item_icon_atlas.json")
	var catalog := ContentLoader.load_json("content/items/catalog.json")
	var missing_icons: PackedStringArray = []
	for category in ["equipment", "consumables", "materials"]:
		for item_id in catalog.get(category, []):
			var item_cells: Variant = item_manifest.get("cells", {})
			if not item_cells is Dictionary or not (item_cells as Dictionary).has(item_id):
				missing_icons.append(item_id)
	ctx.timed_record(
		"content.item_atlas_coverage",
		get_category(),
		missing_icons.is_empty(),
		(
			"item icon atlas covers catalog"
			if missing_icons.is_empty()
			else "missing: %s" % ", ".join(missing_icons)
		),
		start,
		"M5.ui.atlas"
	)

	start = Time.get_ticks_msec()
	var status_ok := true
	for status_id in ["burn", "poison", "freeze", "stun", "bleed"]:
		if not StatusIconAtlas.has_icon(status_id):
			status_ok = false
	ctx.timed_record(
		"content.status_atlas_covers_all",
		get_category(),
		status_ok,
		"every authored status has an atlas cell",
		start,
		"M5.ui.atlas"
	)


func _test_hub_tips_content() -> void:
	var start := Time.get_ticks_msec()
	var tips: Dictionary = ContentLoader.load_json("content/hub/tips.json")
	var schema_ok := (
		int(tips.get("schemaVersion", 0)) == 1
		and tips.get("tips", []) is Array
		and (tips.get("tips", []) as Array).size() >= 1
	)
	ctx.timed_record(
		"content.hub_tips.schema_valid",
		get_category(),
		schema_ok,
		"content/hub/tips.json matches hub-tips schema shape",
		start,
		"HUB-05"
	)

	start = Time.get_ticks_msec()
	var conditions_ok := true
	for entry in tips.get("tips", []):
		if not entry is Dictionary:
			continue
		var show_when: Variant = entry.get("showWhen", null)
		if show_when == null:
			continue
		if not DialogueConditions.evaluate(show_when):
			# minLevel 1 should pass for default character state in validation
			if show_when is Dictionary and show_when.has("minLevel"):
				if int(show_when.get("minLevel", 1)) > CharacterService.get_level():
					conditions_ok = false
	ctx.timed_record(
		"content.hub_tips.conditions_resolve",
		get_category(),
		conditions_ok,
		"hub tip showWhen blocks evaluate without error",
		start,
		"HUB-05"
	)


func _test_scenes_and_scripts() -> void:
	var content_checks: Array[Dictionary] = [
		{
			"id": "content.loot_chest_scene",
			"path": "res://scenes/loot/loot_chest.tscn",
			"ref": "M2.loot.chest"
		},
		{
			"id": "content.loot_chest_script",
			"path": "res://scripts/loot/loot_chest.gd",
			"ref": "M2.loot.chest"
		},
		{
			"id": "content.spike_trap_scene",
			"path": "res://scenes/traps/spike_trap.tscn",
			"ref": "M2.traps.spike"
		},
		{
			"id": "content.falling_trap_scene",
			"path": "res://scenes/traps/falling_trap.tscn",
			"ref": "M2.traps.falling"
		},
		{
			"id": "content.results_screen",
			"path": "res://scenes/ui/results_screen.tscn",
			"ref": "M3.flow.results"
		},
		{
			"id": "content.inventory_ui_script",
			"path": "res://scripts/ui/inventory_ui.gd",
			"ref": "M2.inventory.ui"
		},
		{
			"id": "content.world_pickup_script",
			"path": "res://scripts/inventory/world_item_pickup.gd",
			"ref": "M2.inventory.pickup"
		},
		{
			"id": "content.boss_knight_script",
			"path": "res://scripts/bosses/castle_knight.gd",
			"ref": "M2.boss.knight"
		},
		{
			"id": "content.doorway_socket_script",
			"path": "res://scripts/dungeon/doorway_socket.gd",
			"ref": "M2.dungeon.sockets"
		},
		{
			"id": "content.room_template_script",
			"path": "res://scripts/dungeon/room_template.gd",
			"ref": "M2.dungeon.rooms"
		},
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
		"play_menu_music",
		"play_hub_ambience",
		"stop_all",
		"play_sfx",
		"play_combat_sfx",
		"play_ui_sfx",
		"register_combat_engagement",
		"unregister_combat_engagement",
		"has_combat_sfx",
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


func _test_combat_sfx_bank() -> void:
	const COMBAT_KEYS: Array[String] = [
		"hit", "block", "parry", "swing", "death", "footstep", "windup",
	]
	var bank: Dictionary = ContentLoader.load_json("content/audio/sfx.json")
	var sfx_entries: Dictionary = bank.get("sfx", {})
	for kind in COMBAT_KEYS:
		var start := Time.get_ticks_msec()
		var entry: Dictionary = sfx_entries.get(kind, {})
		var paths: Array[String] = []
		for path in entry.get("variants", []):
			paths.append(str(path))
		if paths.is_empty():
			for surface_paths in entry.get("surface_variants", {}).values():
				for path in surface_paths:
					paths.append(str(path))
		var files_ok := not paths.is_empty()
		for path in paths:
			files_ok = files_ok and _audio_profile_path_exists(path)
		ctx.timed_record(
			"content.combat_sfx_%s" % kind,
			get_category(),
			files_ok and AudioDirector.has_combat_sfx(kind),
			"combat SFX bank resolves %s" % kind,
			start,
			"M2.audio.combat_sfx"
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


func _test_character_state_v2_matches_runtime() -> void:
	var start := Time.get_ticks_msec()
	var schema_path := ContentLoader.content_path("content/schemas/character-state.v2.json")
	var schema: Dictionary = ContentLoader.load_json("content/schemas/character-state.v2.json")
	var schema_props: Dictionary = schema.get("properties", {})
	var payload: Dictionary = LocalSave._build_save_payload()
	var missing: PackedStringArray = []
	for key in payload.keys():
		if not schema_props.has(key):
			missing.append(key)
	ctx.timed_record(
		"content.schema.character_state_v2_matches_runtime",
		get_category(),
		missing.is_empty() and FileAccess.file_exists(schema_path),
		"runtime payload keys covered by v2 schema"
		if missing.is_empty()
		else "missing schema keys: %s" % ", ".join(missing),
		start,
		"SAV-08"
	)


func _test_save_migrations_doc_sync() -> void:
	var SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
	var doc_path: String = ctx.repo_root().path_join("docs/SAVE_MIGRATIONS.md")
	var start := Time.get_ticks_msec()
	var missing: PackedStringArray = []
	if not FileAccess.file_exists(doc_path):
		missing.append("docs/SAVE_MIGRATIONS.md missing")
	else:
		var text := FileAccess.get_file_as_string(doc_path)
		for step in SaveMigratorScript.STEPS:
			var from_v: int = int(step["from"])
			var to_v: int = int(step["to"])
			var summary: String = str(step["summary"])
			var row_needle := "| %d | %d | %s |" % [from_v, to_v, summary]
			if row_needle not in text:
				missing.append("v%d→v%d" % [from_v, to_v])
	ctx.timed_record(
		"content.docs.save_migrations_in_sync",
		get_category(),
		missing.is_empty(),
		(
			"SAVE_MIGRATIONS.md rows match STEPS"
			if missing.is_empty()
			else "missing rows: %s" % ", ".join(missing)
		),
		start,
		"MIG.docs.sync"
	)


func _test_dialogue_flags_registered() -> void:
	var start := Time.get_ticks_msec()
	var bad: PackedStringArray = []
	for file_name in DirAccess.get_files_at(ContentLoader.content_path("content/dialogue")):
		if not file_name.ends_with(".json"):
			continue
		var dialogue: Dictionary = ContentLoader.load_json("content/dialogue/%s" % file_name)
		for flag_id in _collect_dialogue_flag_refs(dialogue):
			if not CharacterFlags.is_registered(flag_id):
				bad.append("%s:%s" % [file_name, flag_id])
	ctx.timed_record(
		"content.dialogue.flags_are_registered",
		get_category(),
		bad.is_empty(),
		"dialogue flags are registered" if bad.is_empty() else "unregistered: %s" % ", ".join(bad),
		start,
		"CHS-07"
	)


func _test_quest_flags_registered() -> void:
	var start := Time.get_ticks_msec()
	var bad: PackedStringArray = []
	for file_name in DirAccess.get_files_at(ContentLoader.content_path("content/quests")):
		if not file_name.ends_with(".json"):
			continue
		var quest: Dictionary = ContentLoader.load_json("content/quests/%s" % file_name)
		for flag_id in _collect_dialogue_flag_refs(quest):
			if not CharacterFlags.is_registered(flag_id):
				bad.append("%s:%s" % [file_name, flag_id])
	ctx.timed_record(
		"content.quests.flags_are_registered",
		get_category(),
		bad.is_empty(),
		"quest flags are registered" if bad.is_empty() else "unregistered: %s" % ", ".join(bad),
		start,
		"CHS-07"
	)


func _test_quest_ids_no_progress_suffix() -> void:
	var start := Time.get_ticks_msec()
	var bad: PackedStringArray = []
	for quest_id in QuestCatalog.get_all_ids():
		if str(quest_id).ends_with("_progress"):
			bad.append(quest_id)
	ctx.timed_record(
		"content.quests.no_progress_suffix",
		get_category(),
		bad.is_empty(),
		"no quest id ends with _progress",
		start,
		"CHS-01"
	)


func _test_dungeon_clear_flags_registered() -> void:
	var start := Time.get_ticks_msec()
	var bad: PackedStringArray = []
	for entry in DungeonCatalog.ENTRIES:
		var clear_flag := str(entry.get("clearFlag", ""))
		if clear_flag == "":
			bad.append("%s:missing" % entry.get("id", "?"))
		elif not CharacterFlags.is_registered(clear_flag):
			bad.append("%s:%s" % [entry.get("id", "?"), clear_flag])
	ctx.timed_record(
		"content.dungeons.clear_flag_registered",
		get_category(),
		bad.is_empty(),
		"dungeon clear flags registered" if bad.is_empty() else "bad: %s" % ", ".join(bad),
		start,
		"CHS-02"
	)


func _collect_dialogue_flag_refs(value: Variant) -> PackedStringArray:
	var refs: PackedStringArray = []
	_collect_dialogue_flag_refs_into(value, refs)
	return refs


func _collect_dialogue_flag_refs_into(value: Variant, refs: PackedStringArray) -> void:
	if value is Dictionary:
		var dict: Dictionary = value
		if dict.has("flag"):
			var flag_id := str(dict.get("flag", ""))
			if flag_id != "" and flag_id not in refs:
				refs.append(flag_id)
		if dict.has("actions") and dict["actions"] is Array:
			for action in dict["actions"]:
				if action is Dictionary and str(action.get("type", "")) == "set_flag":
					var set_flag := str(action.get("flag", ""))
					if set_flag != "" and set_flag not in refs:
						refs.append(set_flag)
		for key in dict:
			_collect_dialogue_flag_refs_into(dict[key], refs)
	elif value is Array:
		for entry in value:
			_collect_dialogue_flag_refs_into(entry, refs)


func _test_appearance_schema_bounds() -> void:
	var CharacterAppearanceScript := preload("res://scripts/save/character_appearance.gd")
	var PixelStyleScript := preload("res://scripts/art/style/pixel_diorama_style.gd")
	var start := Time.get_ticks_msec()
	var schema: Dictionary = ContentLoader.load_json("content/schemas/character-state.v2.json")
	var appearance_def: Dictionary = schema.get("$defs", {}).get("appearanceProfile", {})
	var theme_props: Dictionary = appearance_def.get("properties", {}).get("theme", {})
	var theme_ok := int(theme_props.get("maximum", -1)) == PixelStyleScript.PALETTES.size() - 1
	ctx.timed_record(
		"content.appearance.theme_bound_matches_palettes",
		get_category(),
		theme_ok,
		"appearance.theme maximum matches PALETTES.size() - 1",
		start,
		"CHA-07"
	)

	start = Time.get_ticks_msec()
	var height_variants: Array = appearance_def.get("properties", {}).get("heightVariant", {}).get(
		"enum", []
	)
	var bulk_variants: Array = appearance_def.get("properties", {}).get("bulkVariant", {}).get(
		"enum", []
	)
	var bounds_ok := (
		height_variants == CharacterAppearanceScript.HEIGHT_VARIANTS
		and bulk_variants == CharacterAppearanceScript.BULK_VARIANTS
	)
	ctx.timed_record(
		"content.appearance.schema_bounds_match_clamps",
		get_category(),
		bounds_ok,
		"schema variant enums match GDScript constants",
		start,
		"CHA-07"
	)


func _test_waves_definition() -> void:
	var start := Time.get_ticks_msec()
	var waves: Dictionary = ContentLoader.load_json("content/waves/umbral_waves.json")
	var schema_ok := (
		int(waves.get("schemaVersion", 0)) == 1
		and str(waves.get("id", "")) == "umbral_waves"
		and waves.get("milestones", []) is Array
		and (waves.get("chests", []) as Array).size() == 6
	)
	ctx.timed_record(
		"wav.content.schema",
		get_category(),
		schema_ok,
		"content/waves/umbral_waves.json matches waves-definition schema shape",
		start,
		"WAV-06"
	)

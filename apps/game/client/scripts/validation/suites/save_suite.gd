extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "save"


func _init(context) -> void:
	super._init(context)
	manage_save_file = false


func run() -> void:
	var backup: Dictionary = ctx.backup_save_file()
	_try_localsave_tests()
	_test_save_migration_roundtrip()
	ctx.restore_save_file(backup)
	_test_continuable_rules()
	_test_death_snapshot_guard()
	_test_player_dead_flag()
	_test_backup_rotation()
	_test_storage_roundtrip()
	_test_world_flags_restore()
	_test_world_flags_migration()
	_test_checkpoint_migration()
	_test_v4_to_v5_playerdead_migration()
	_test_save_migrator_suite()
	_test_camera_settings_migration()
	_test_per_character_backup_rotation()
	_test_atomic_write_rejects_bad_payload()
	_test_character_corruption_recovery()
	_test_warm_load_migration()
	_test_save_validator_problems()
	_test_item_instances_round_trip()
	_test_autosave_coalescing()
	_test_cloud_conflict_backup()
	_test_migrate_v4_to_v5_account_id_reset()
	_test_migrate_quests_split_v4_to_v5()
	_test_migrate_coins_folded_into_gold()
	await _test_character_currency_autosave_deferred()
	_test_character_id_uniqueness()
	_test_appearance_profile()


func _test_backup_rotation() -> void:
	var start := Time.get_ticks_msec()
	var has_list := LocalSave.has_method("list_backups")
	var has_restore := LocalSave.has_method("restore_backup")
	ctx.timed_record(
		"save.backup_api",
		get_category(),
		has_list and has_restore,
		"LocalSave exposes list_backups and restore_backup",
		start,
		"M4.save.backup"
	)

	start = Time.get_ticks_msec()
	LocalSave.autosave()
	var backups := LocalSave.list_backups()
	ctx.timed_record(
		"save.backup_after_autosave",
		get_category(),
		backups.size() >= 0,
		"list_backups callable after autosave",
		start,
		"M4.save.backup"
	)


func _try_localsave_tests() -> void:
	var start := Time.get_ticks_msec()
	(
		LocalSave
		. set_active_run(
			{
				"schemaVersion": 2,
				"runId": "validation-test",
				"seed": TC.SEED_A,
				"snapshot": {"player": {"health": 75.0}},
			}
		)
	)
	var can_continue := LocalSave.has_continuable_run()
	ctx.timed_record(
		"save.localsave_continuable_midrun",
		get_category(),
		can_continue,
		"LocalSave.has_continuable_run() true for valid snapshot",
		start,
		"M3.save.continue"
	)

	start = Time.get_ticks_msec()
	LocalSave.clear_active_run()
	ctx.timed_record(
		"save.localsave_cleared",
		get_category(),
		not LocalSave.has_continuable_run(),
		"LocalSave.has_continuable_run() false after clear",
		start,
		"M3.save.clear"
	)


func _test_continuable_rules() -> void:
	var start := Time.get_ticks_msec()
	(
		ctx
		. timed_record(
			"save.zero_hp_not_continuable",
			get_category(),
			not (
				LocalSave
				. run_is_continuable(
					{
						"snapshot": {"player": {"health": 0.0}},
					}
				)
			),
			"0 HP snapshot is not continuable",
			start,
			"M3.save.zero_hp"
		)
	)

	start = Time.get_ticks_msec()
	ctx.timed_record(
		"save.empty_snapshot_not_continuable",
		get_category(),
		not LocalSave.run_is_continuable({"snapshot": {}}),
		"empty snapshot is not continuable",
		start,
		"M3.save.empty_snapshot"
	)

	start = Time.get_ticks_msec()
	ctx.timed_record(
		"save.legacy_no_snapshot_key",
		get_category(),
		not LocalSave.run_is_continuable({}),
		"run without snapshot is not continuable",
		start,
		"M3.save.no_snapshot"
	)

	start = Time.get_ticks_msec()
	(
		ctx
		. timed_record(
			"save.valid_midrun_continuable",
			get_category(),
			(
				LocalSave
				. run_is_continuable(
					{
						"snapshot":
						{
							"player": {"health": 50.0},
							"enemies": {},
						},
					}
				)
			),
			"valid mid-run snapshot is continuable",
			start,
			"M3.save.midrun"
		)
	)


func _test_death_snapshot_guard() -> void:
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"save.death_snapshot_skipped",
		get_category(),
		not CastleRun.should_persist_player_state(0.0, true),
		"castle_run would skip persisting dead player snapshot",
		start,
		"M3.save.death_guard"
	)


func _test_player_dead_flag() -> void:
	var start := Time.get_ticks_msec()
	(
		ctx
		. timed_record(
			"save.player_dead_not_continuable",
			get_category(),
			not (
				LocalSave
				. run_is_continuable(
					{
						"playerDead": true,
						"snapshot": {"player": {"health": 50.0}},
					}
				)
			),
			"playerDead flag blocks continue",
			start,
			"M3.save.player_dead"
		)
	)


func _test_save_migration_roundtrip() -> void:
	var SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
	var v1 := {
		"schemaVersion": 1,
		"activeRun":
		{
			"runId": "migrate-test",
			"seed": TC.SEED_A,
			"snapshot": {"player": {"health": 80.0}},
		},
	}
	var start := Time.get_ticks_msec()
	var migrated: Dictionary = SaveMigratorScript.migrate(v1.duplicate(true))
	var v1_ok: bool = (
		not migrated.get("migrationFailed", false)
		and int(migrated.get("schemaVersion", 0)) == SaveMigratorScript.CURRENT_VERSION
		and int(migrated.get("activeRun", {}).get("currentFloor", 0)) == 1
		and migrated.get("activeRun", {}).has("lastCheckpoint")
	)
	ctx.timed_record(
		"save.migrate_v1_to_v2",
		get_category(),
		v1_ok,
		"v1 save migrates to current schema with currentFloor=1",
		start,
		"M9.save.migrate_v2"
	)

	var v2_manual := {
		"schemaVersion": 2,
		"activeRun":
		{
			"runId": "migrate-test",
			"seed": TC.SEED_A,
			"currentFloor": 1,
			"maxFloors": RunFloorConfig.MAX_FLOORS,
			"floorDefinitions": {},
			"snapshot": {"player": {"health": 80.0}},
		},
	}
	start = Time.get_ticks_msec()
	var from_v2: Dictionary = SaveMigratorScript.migrate(v2_manual.duplicate(true))
	var v2_ok: bool = (
		not from_v2.get("migrationFailed", false)
		and int(from_v2.get("schemaVersion", 0)) == SaveMigratorScript.CURRENT_VERSION
		and str(from_v2.get("activeRun", {}).get("runMode", "")) == "castle"
		and not from_v2.get("activeRun", {}).has("floorDefinitions")
	)
	ctx.timed_record(
		"save.migrate_v2_to_v3",
		get_category(),
		v2_ok,
		"v2→current adds runMode and strips floorDefinitions",
		start,
		"M9.save.migrate_v3"
	)

	start = Time.get_ticks_msec()
	var roundtrip: Dictionary = SaveMigratorScript.migrate(from_v2.duplicate(true))
	ctx.timed_record(
		"save.migrate_idempotent_v3",
		get_category(),
		int(roundtrip.get("schemaVersion", 0)) == SaveMigratorScript.CURRENT_VERSION,
		"v4 save is idempotent under migrate()",
		start,
		"M9.save.migrate_idempotent"
	)


func _test_storage_roundtrip() -> void:
	var start := Time.get_ticks_msec()
	StorageService.storage.clear()
	StorageService.storage.add_item("castle_sword", 1)
	var saved := StorageService.get_save_storage()
	StorageService.storage.clear()
	StorageService.apply_save_storage(saved)
	var ok := false
	for slot in StorageService.storage.slots:
		if slot.get("itemId", "") == "castle_sword":
			ok = true
			break
	ctx.timed_record(
		"save.storage_payload",
		get_category(),
		ok,
		"hub storage round-trip via StorageService",
		start,
		"B05.save.storage"
	)


func _test_world_flags_restore() -> void:
	var start := Time.get_ticks_msec()
	var door_flag := WorldFlags.lock_opened("suite_test_door")
	var other_flag := WorldFlags.lock_opened("suite_other")
	WorldState.set_flag(door_flag, true)
	WorldState.restore_flags({door_flag: true, other_flag: 2})
	var ok := WorldState.has_flag(door_flag) and int(WorldState.get_flag(other_flag, 0)) == 2
	WorldState.reset()
	ctx.timed_record(
		"save.world_flags_restore",
		get_category(),
		ok,
		"WorldState.restore_flags round-trip",
		start,
		"B05.save.world_flags"
	)


func _test_world_flags_migration() -> void:
	var SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
	var start := Time.get_ticks_msec()
	var v4 := {
		"schemaVersion": 4,
		"activeRun":
		{
			"snapshot":
			{
				"worldFlags":
				{
					"key_entrance_hall": true,
					"quest_stranded_active": true,
					"orphan_flag": 1,
				}
			},
			"lastCheckpoint":
			{
				"worldFlags":
				{
					"key_start_boss": true,
				}
			},
		},
	}
	var migrated: Dictionary = SaveMigratorScript.migrate(v4.duplicate(true))
	var snapshot: Dictionary = migrated.get("activeRun", {}).get("snapshot", {})
	var flags: Dictionary = snapshot.get("worldFlags", {})
	var checkpoint_flags: Dictionary = migrated.get("activeRun", {}).get("lastCheckpoint", {}).get(
		"worldFlags", {}
	)
	var ok := (
		int(migrated.get("schemaVersion", 0)) == SaveMigratorScript.CURRENT_VERSION
		and flags.get(WorldFlags.lock_opened("lock_entrance_hall"), false) == true
		and flags.get(WorldFlags.secret_opened("stranded"), false) == true
		and not flags.has("orphan_flag")
		and checkpoint_flags.get(WorldFlags.lock_opened("lock_start_boss"), false) == true
	)
	ctx.timed_record(
		"save.migrate.world_flags_namespaced",
		get_category(),
		ok,
		"v4 worldFlags migrate to namespaced ids",
		start,
		"WST-05.save.migrate_world_flags"
	)


func _test_checkpoint_migration() -> void:
	var SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
	var start := Time.get_ticks_msec()
	var v3 := {"schemaVersion": 3, "activeRun": {"snapshot": {"player": {"health": 1.0}}}}
	var migrated: Dictionary = SaveMigratorScript.migrate(v3.duplicate(true))
	var run: Dictionary = migrated.get("activeRun", {})
	var ok := (
		int(migrated.get("schemaVersion", 0)) == SaveMigratorScript.CURRENT_VERSION
		and run.has("lastCheckpoint")
	)
	ctx.timed_record(
		"save.migrate_v4_checkpoint",
		get_category(),
		ok,
		"v3→current adds lastCheckpoint and worldFlags defaults",
		start,
		"S09.save.migrate_v4"
	)


func _test_v4_to_v5_playerdead_migration() -> void:
	var SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
	var checkpoint := {
		"player": {"health": 50.0, "x": 1.0, "y": 0.0, "z": 2.0},
		"killCount": 3,
	}
	var v4_recover := {
		"schemaVersion": 4,
		"character": {"name": "Tester", "classId": "warden", "level": 1, "xp": 0},
		"inventory": {"schemaVersion": 1, "gridWidth": 8, "gridHeight": 6, "slots": [], "equipped": {}},
		"activeRun": {
			"schemaVersion": 4,
			"playerDead": true,
			"lastCheckpoint": checkpoint,
			"snapshot": {"player": {"health": 0.0}},
		},
	}
	var start := Time.get_ticks_msec()
	var recovered: Dictionary = SaveMigratorScript.migrate(v4_recover.duplicate(true))
	var run: Dictionary = recovered.get("activeRun", {})
	var snap: Dictionary = run.get("snapshot", {})
	var recovered_ok: bool = (
		not recovered.get("migrationFailed", false)
		and int(recovered.get("schemaVersion", 0)) == SaveMigratorScript.CURRENT_VERSION
		and not run.has("playerDead")
		and int(snap.get("killCount", -1)) == 3
	)
	ctx.timed_record(
		"save.migrate.v4_to_v5_playerdead_recovered",
		get_category(),
		recovered_ok,
		"playerDead with checkpoint restores snapshot on v5 migration",
		start,
		"RFL.save"
	)

	var v4_drop := {
		"schemaVersion": 4,
		"character": {"name": "Tester", "classId": "warden", "level": 1, "xp": 0},
		"inventory": {"schemaVersion": 1, "gridWidth": 8, "gridHeight": 6, "slots": [], "equipped": {}},
		"activeRun": {
			"schemaVersion": 4,
			"playerDead": true,
			"lastCheckpoint": {},
		},
	}
	start = Time.get_ticks_msec()
	var dropped: Dictionary = SaveMigratorScript.migrate(v4_drop.duplicate(true))
	var drop_ok: bool = (
		not dropped.get("migrationFailed", false)
		and int(dropped.get("schemaVersion", 0)) == SaveMigratorScript.CURRENT_VERSION
		and not dropped.has("activeRun")
		and dropped.has("character")
		and dropped.has("inventory")
	)
	ctx.timed_record(
		"save.migrate.v4_to_v5_playerdead_no_checkpoint",
		get_category(),
		drop_ok,
		"playerDead without checkpoint drops activeRun only",
		start,
		"RFL.save"
	)


func _test_save_migrator_suite() -> void:
	var SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
	_test_migrate_chain_v1_to_v5(SaveMigratorScript)
	_test_migrate_step_table(SaveMigratorScript)
	_test_migrate_too_new(SaveMigratorScript)
	_test_migrate_failure_preserves_payload(SaveMigratorScript)
	_test_migrate_normalizes_equipped_legacy_string(SaveMigratorScript)
	_test_migrate_normalizes_float_talents(SaveMigratorScript)
	_test_migrate_clamps_overspent_talent_points(SaveMigratorScript)
	_test_migrate_normalizes_affix_arrays(SaveMigratorScript)
	_test_migrate_dry_run_applies_nothing(SaveMigratorScript)
	_test_migrate_current_version_is_deep_copied(SaveMigratorScript)
	_test_migrate_premigrate_artefact_written(SaveMigratorScript)


func _test_camera_settings_migration() -> void:
	var SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
	var start := Time.get_ticks_msec()
	var legacy := _minimal_v1_save(
		{
			"schemaVersion": 7,
			"meta": {"accessibility": {"ui_scale": 1.0, "reduce_camera_shake": false}},
		}
	)
	var migrated: Dictionary = SaveMigratorScript.migrate(legacy)
	var a11y: Dictionary = migrated.get("meta", {}).get("accessibility", {})
	var defaults := AccessibilitySettings.camera_settings_defaults()
	var ok := int(migrated.get("schemaVersion", 0)) == SaveMigratorScript.CURRENT_VERSION
	for key in defaults:
		if not a11y.has(key):
			ok = false
		elif key.contains("Sensitivity") or key == "cameraFov" or key.contains("Curve") or key.contains("Deadzone"):
			if float(a11y.get(key, 0.0)) == 0.0:
				ok = false
	ctx.timed_record(
		"save.camera_settings_migration",
		get_category(),
		ok,
		"v7 save gains six camera accessibility keys with defaults",
		start,
		"M3.save.camera_settings"
	)


func _minimal_v1_save(extra: Dictionary = {}) -> Dictionary:
	var base := {
		"schemaVersion": 1,
		"accountId": "00000000-0000-4000-8000-000000000000",
		"character": {"name": "Tester", "classId": "warden", "level": 1, "xp": 0},
		"currencies": {"gold": 10},
		"inventory":
		{
			"schemaVersion": 1,
			"gridWidth": 8,
			"gridHeight": 6,
			"slots": [],
			"equipped": Equipment.empty_equipped(),
		},
		"itemInstances": {},
		"talents": {},
		"talentPointsSpent": 0,
		"flags": {},
		"recipes": [],
	}
	for key in extra:
		base[key] = extra[key]
	return base


func _test_migrate_chain_v1_to_v5(SaveMigratorScript: Script) -> void:
	var start := Time.get_ticks_msec()
	var migrated: Dictionary = SaveMigratorScript.migrate(_minimal_v1_save())
	var inv: Dictionary = migrated.get("inventory", {})
	var equipped: Dictionary = inv.get("equipped", {})
	var ok := (
		not migrated.get("migrationFailed", false)
		and int(migrated.get("schemaVersion", 0)) == SaveMigratorScript.CURRENT_VERSION
		and migrated.has("character")
		and inv.get("schemaVersion", 0) == 1
		and equipped.has("weapon")
		and equipped.has("helmet")
		and migrated.get("currencies", {}).has("coins")
	)
	ctx.timed_record(
		"save.migrate.chain_v1_to_v5",
		get_category(),
		ok,
		"minimal v1 document reaches current schema with v5 guarantees",
		start,
		"MIG.save.chain"
	)


func _test_migrate_step_table(SaveMigratorScript: Script) -> void:
	var start := Time.get_ticks_msec()
	var steps: Array = SaveMigratorScript.STEPS
	var ok := false
	if not steps.is_empty():
		ok = int(steps.back()["to"]) == SaveMigratorScript.CURRENT_VERSION
		var expected_from := 1
		for step in steps:
			ok = ok and int(step["from"]) == expected_from
			expected_from = int(step["to"])
	ctx.timed_record(
		"save.migrate.step_table_matches_current_version",
		get_category(),
		ok,
		"STEPS contiguous and ends at CURRENT_VERSION",
		start,
		"MIG.save.steps"
	)


func _test_migrate_too_new(SaveMigratorScript: Script) -> void:
	var start := Time.get_ticks_msec()
	var result: Dictionary = SaveMigratorScript.migrate(
		{"schemaVersion": 6, "character": {"name": "X"}}
	)
	var ok := (
		result.get("migrationFailed", false)
		and str(result.get("migrationKind", "")) == "too_new"
		and result.has("character")
	)
	ctx.timed_record(
		"save.migrate.too_new_is_not_corruption",
		get_category(),
		ok,
		"schemaVersion 6 yields migrationKind too_new with payload preserved",
		start,
		"MIG.save.too_new"
	)


func _test_migrate_failure_preserves_payload(SaveMigratorScript: Script) -> void:
	var start := Time.get_ticks_msec()
	var source := {
		"schemaVersion": 0,
		"character": {"name": "KeepMe", "level": 3, "xp": 0},
		"inventory":
		{"schemaVersion": 1, "gridWidth": 8, "gridHeight": 6, "slots": [], "equipped": {}},
	}
	var result: Dictionary = SaveMigratorScript.migrate(source)
	var character: Dictionary = result.get("character", {})
	var ok := (
		result.get("migrationFailed", false)
		and character.get("name", "") == "KeepMe"
		and int(character.get("level", 0)) == 3
	)
	ctx.timed_record(
		"save.migrate.failure_preserves_payload",
		get_category(),
		ok,
		"version-0 document keeps original character section",
		start,
		"MIG.save.payload"
	)


func _test_migrate_normalizes_equipped_legacy_string(SaveMigratorScript: Script) -> void:
	var start := Time.get_ticks_msec()
	var source := _minimal_v1_save(
		{
			"inventory":
			{
				"schemaVersion": 1,
				"gridWidth": 8,
				"gridHeight": 6,
				"slots": [],
				"equipped": {"weapon": "castle_sword"},
			},
		}
	)
	var migrated: Dictionary = SaveMigratorScript.migrate(source)
	var weapon: Dictionary = migrated.get("inventory", {}).get("equipped", {}).get("weapon", {})
	var ok := weapon.get("itemId", "") == "castle_sword" and int(weapon.get("quantity", 0)) == 1
	ctx.timed_record(
		"save.migrate.normalizes_equipped_legacy_string",
		get_category(),
		ok,
		"equipped.weapon String becomes itemId/quantity dict",
		start,
		"MIG.save.equipped"
	)


func _test_migrate_normalizes_float_talents(SaveMigratorScript: Script) -> void:
	var start := Time.get_ticks_msec()
	var source := _minimal_v1_save({"talents": {"arms_1": 2.0}})
	var migrated: Dictionary = SaveMigratorScript.migrate(source)
	var ok := int(migrated.get("talents", {}).get("arms_1", -1)) == 2
	ctx.timed_record(
		"save.migrate.normalizes_float_talents",
		get_category(),
		ok,
		"float talent ranks coerce to int",
		start,
		"MIG.save.talents"
	)


func _test_migrate_clamps_overspent_talent_points(SaveMigratorScript: Script) -> void:
	var start := Time.get_ticks_msec()
	var source := _minimal_v1_save(
		{
			"talents": {"arms_1": 1, "arms_2": 1},
			"talentPointsSpent": 999,
		}
	)
	var migrated: Dictionary = SaveMigratorScript.migrate(source)
	var spent: int = int(migrated.get("talentPointsSpent", -1))
	if ProgressionService:
		ProgressionService.from_save_dict(migrated)
		var available := ProgressionService.get_available_talent_points()
		ctx.timed_record(
			"save.migrate.clamps_overspent_talent_points",
			get_category(),
			spent == 2 and available >= 0,
			"talentPointsSpent clamped to reachable total",
			start,
			"MIG.save.talent_clamp"
		)
	else:
		ctx.timed_record(
			"save.migrate.clamps_overspent_talent_points",
			get_category(),
			spent == 2,
			"talentPointsSpent clamped to reachable total",
			start,
			"MIG.save.talent_clamp"
		)


func _test_migrate_normalizes_affix_arrays(SaveMigratorScript: Script) -> void:
	var start := Time.get_ticks_msec()
	var source := _minimal_v1_save(
		{
			"inventory":
			{
				"schemaVersion": 1,
				"gridWidth": 8,
				"gridHeight": 6,
				"slots":
				[
					{
						"itemId": "castle_sword",
						"quantity": 1,
						"x": 0,
						"y": 0,
						"affixes":
						[
							{"affixId": "sharp", "value": 1.0},
							"bad",
							{"value": 2.0},
						],
					},
				],
				"equipped": Equipment.empty_equipped(),
			},
		}
	)
	var migrated: Dictionary = SaveMigratorScript.migrate(source)
	var affixes: Array = migrated.get("inventory", {}).get("slots", [{}])[0].get("affixes", [])
	var ok := affixes.size() == 1 and affixes[0].get("affixId", "") == "sharp"
	ctx.timed_record(
		"save.migrate.normalizes_affix_arrays",
		get_category(),
		ok,
		"malformed affix entries dropped, valid ones kept",
		start,
		"MIG.save.affixes"
	)


func _test_migrate_dry_run_applies_nothing(SaveMigratorScript: Script) -> void:
	var start := Time.get_ticks_msec()
	var source := _minimal_v1_save()
	var before := JSON.stringify(source)
	var steps: Array = SaveMigratorScript.plan(1)
	var ok := steps.size() == 4 and before == JSON.stringify(source)
	ctx.timed_record(
		"save.migrate.dry_run_applies_nothing",
		get_category(),
		ok,
		"plan(1) returns four steps and mutates nothing",
		start,
		"MIG.save.plan"
	)


func _test_migrate_current_version_is_deep_copied(SaveMigratorScript: Script) -> void:
	var start := Time.get_ticks_msec()
	var source := _minimal_v1_save()
	source["schemaVersion"] = SaveMigratorScript.CURRENT_VERSION
	var migrated: Dictionary = SaveMigratorScript.migrate(source)
	migrated["character"]["name"] = "Mutated"
	var ok := str(source["character"]["name"]) != "Mutated"
	ctx.timed_record(
		"save.migrate.current_version_is_deep_copied",
		get_category(),
		ok,
		"current-version migrate() does not alias input",
		start,
		"MIG.save.deepcopy"
	)


func _test_migrate_premigrate_artefact_written(SaveMigratorScript: Script) -> void:
	var start := Time.get_ticks_msec()
	var char_id := "mig_test_%d" % (Time.get_ticks_usec() % 1000000)
	var path := "%s%s.json" % [LocalSave.CHARACTERS_DIR, char_id]
	DirAccess.make_dir_recursive_absolute(LocalSave.CHARACTERS_DIR)
	var v4 := _minimal_v1_save({"schemaVersion": 4})
	var file := FileAccess.open(path, FileAccess.WRITE)
	var ok := false
	if file:
		file.store_string(JSON.stringify(v4, "\t"))
		file.close()
		var before_count := _count_premigrate_artefacts(char_id)
		LocalSave.load_character(char_id)
		LocalSave.autosave()
		var after_first := _count_premigrate_artefacts(char_id)
		LocalSave.load_character(char_id)
		var after_second := _count_premigrate_artefacts(char_id)
		ok = after_first == before_count + 1 and after_second == after_first
		_cleanup_premigrate_artefacts(char_id)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	ctx.timed_record(
		"save.migrate.premigrate_artefact_written",
		get_category(),
		ok,
		"v4 load writes one premigrate artefact; v5 reload writes none",
		start,
		"MIG.save.premigrate"
	)


func _count_premigrate_artefacts(character_id: String) -> int:
	var count := 0
	var dir := DirAccess.open(LocalSave.BACKUP_DIR)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("%s.premigrate_v" % character_id):
			count += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return count


func _cleanup_premigrate_artefacts(character_id: String) -> void:
	var dir := DirAccess.open(LocalSave.BACKUP_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("%s.premigrate_v" % character_id):
			DirAccess.remove_absolute("%s%s" % [LocalSave.BACKUP_DIR, entry])
		entry = dir.get_next()
	dir.list_dir_end()


func _test_per_character_backup_rotation() -> void:
	var start := Time.get_ticks_msec()
	var char_id := "save_rot_%d" % (Time.get_ticks_usec() % 1000000)
	LocalSave._active_character_id = char_id
	DirAccess.make_dir_recursive_absolute(LocalSave.CHARACTERS_DIR)
	for i in LocalSave.BACKUP_COUNT:
		var backup_path := "%s%s_%d.json" % [LocalSave.BACKUP_DIR, char_id, i]
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_path)
	for _i in LocalSave.BACKUP_COUNT:
		LocalSave.autosave()
	var found := 0
	for i in LocalSave.BACKUP_COUNT:
		if FileAccess.file_exists("%s%s_%d.json" % [LocalSave.BACKUP_DIR, char_id, i]):
			found += 1
	LocalSave._active_character_id = ""
	ctx.timed_record(
		"save.backup.per_character_rotation",
		get_category(),
		found == LocalSave.BACKUP_COUNT,
		"five roster saves produce indexed backups 0..4",
		start,
		"SAV-01"
	)


func _test_atomic_write_rejects_bad_payload() -> void:
	var start := Time.get_ticks_msec()
	var char_id := "save_atomic_%d" % (Time.get_ticks_usec() % 1000000)
	var path := "%s%s.json" % [LocalSave.CHARACTERS_DIR, char_id]
	DirAccess.make_dir_recursive_absolute(LocalSave.CHARACTERS_DIR)
	var good := LocalSave._build_save_payload()
	var good_text := JSON.stringify(good, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(good_text)
		file.close()
	LocalSave._active_character_id = char_id
	var bad := good.duplicate(true)
	bad.erase("character")
	var ok := not LocalSave._write_save(bad, false)
	ok = ok and FileAccess.get_file_as_string(path) == good_text
	ok = ok and not FileAccess.file_exists("%s.tmp" % path)
	LocalSave._active_character_id = ""
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	ctx.timed_record(
		"save.backup.atomic_write_survives_bad_payload",
		get_category(),
		ok,
		"invalid payload leaves prior file and no .tmp residue",
		start,
		"SAV-01"
	)


func _test_character_corruption_recovery() -> void:
	var start := Time.get_ticks_msec()
	var char_id := "save_corr_%d" % (Time.get_ticks_usec() % 1000000)
	var path := "%s%s.json" % [LocalSave.CHARACTERS_DIR, char_id]
	DirAccess.make_dir_recursive_absolute(LocalSave.CHARACTERS_DIR)
	LocalSave._active_character_id = char_id
	LocalSave.autosave()
	var failed_reason := ""
	var restored_index := -1
	var on_failed := func(reason: String) -> void:
		failed_reason = reason
	var on_restored := func(index: int) -> void:
		restored_index = index
	if not LocalSave.save_failed.is_connected(on_failed):
		LocalSave.save_failed.connect(on_failed)
	if not LocalSave.backup_restored.is_connected(on_restored):
		LocalSave.backup_restored.connect(on_restored)
	var corrupt_file := FileAccess.open(path, FileAccess.WRITE)
	if corrupt_file:
		corrupt_file.store_string("{")
		corrupt_file.close()
	var loaded := LocalSave.load_character(char_id)
	var quarantine_exists := false
	var dir := DirAccess.open(LocalSave.CHARACTERS_DIR)
	if dir:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry.begins_with("%s.corrupt_" % char_id):
				quarantine_exists = true
			entry = dir.get_next()
		dir.list_dir_end()
	LocalSave._active_character_id = ""
	ctx.timed_record(
		"save.load.character_corruption_recovers",
		get_category(),
		loaded and quarantine_exists and failed_reason != "" and restored_index == 0,
		"corrupt character file quarantined and backup 0 restored",
		start,
		"SAV-02"
	)


func _test_warm_load_migration() -> void:
	var start := Time.get_ticks_msec()
	var char_id := "save_warm_%d" % (Time.get_ticks_usec() % 1000000)
	var path := "%s%s.json" % [LocalSave.CHARACTERS_DIR, char_id]
	DirAccess.make_dir_recursive_absolute(LocalSave.CHARACTERS_DIR)
	var v1 := _minimal_v1_save({"character": {"name": "Warm", "classId": "knight", "level": 7, "xp": 0}})
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(v1, "\t"))
		file.close()
	LocalSave._active_character_id = char_id
	LocalSave._roster["activeId"] = char_id
	LocalSave._warm_load_path(path)
	var schema_version := int(LocalSave._cached_state.get("schemaVersion", 0))
	LocalSave._active_character_id = ""
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	ctx.timed_record(
		"save.load.warm_load_is_migrated",
		get_category(),
		schema_version == SaveMigrator.CURRENT_VERSION,
		"warm load migrates v1 before getters read cached state",
		start,
		"SAV-03"
	)


func _test_save_validator_problems() -> void:
	var SaveValidatorScript := preload("res://scripts/save/save_validator.gd")
	var start := Time.get_ticks_msec()
	var missing_character: Array = SaveValidatorScript.validate({"schemaVersion": 5, "currencies": {}, "inventory": {"schemaVersion": 1, "gridWidth": 1, "gridHeight": 1, "slots": [], "equipped": Equipment.empty_equipped()}, "talents": {}, "flags": {}})
	var bad_equipped: Dictionary = _minimal_v1_save()["inventory"]
	bad_equipped["equipped"] = []
	var equipped_array: Array = SaveValidatorScript.validate({"schemaVersion": 5, "character": {"name": "X", "level": 1, "xp": 0}, "currencies": {"gold": 0}, "inventory": bad_equipped, "talents": {}, "flags": {}})
	var bad_level: Array = SaveValidatorScript.validate(_minimal_v1_save({"character": {"name": "X", "level": -1, "xp": 0}, "schemaVersion": 5}))
	var ok := (
		"character" in missing_character
		and "inventory.equipped" in equipped_array
		and "character.level" in bad_level
	)
	ctx.timed_record(
		"save.validate.reports_named_problems",
		get_category(),
		ok,
		"SaveValidator names missing character, bad equipped, negative level",
		start,
		"SAV-06"
	)


func _test_item_instances_round_trip() -> void:
	var start := Time.get_ticks_msec()
	var grid_slot := {
		"itemId": "castle_sword",
		"instanceId": "castle_sword_11",
		"quantity": 1,
		"x": 0,
		"y": 0,
		"rarity": "magic",
		"rollSeed": 11,
		"affixes": [{"affixId": "sharp", "value": 2.0}],
	}
	var equipped_slot := {
		"itemId": "castle_sword",
		"instanceId": "castle_sword_22",
		"quantity": 1,
		"rarity": "rare",
		"rollSeed": 22,
		"affixes": [{"affixId": "keen", "value": 3.0}],
	}
	InventoryService.inventory.slots = [grid_slot.duplicate(true)]
	InventoryService.inventory.equipped["weapon"] = equipped_slot.duplicate(true)
	var payload := LocalSave._build_save_payload()
	var instances: Dictionary = payload.get("itemInstances", {})
	var ok := instances.size() == 2
	var stripped := payload.duplicate(true)
	(stripped["inventory"] as Dictionary)["slots"][0].erase("affixes")
	(stripped["inventory"] as Dictionary)["equipped"]["weapon"].erase("affixes")
	LocalSave._apply_save_data(stripped)
	var restored_grid: Array = InventoryService.inventory.slots
	var restored_weapon: Dictionary = InventoryService.inventory.equipped.get("weapon", {})
	ok = ok and restored_grid[0].has("affixes") and restored_weapon.has("affixes")
	ctx.timed_record(
		"save.instances.round_trip",
		get_category(),
		ok,
		"itemInstances built from slots and repairs missing affixes on load",
		start,
		"SAV-04"
	)


func _test_autosave_coalescing() -> void:
	var start := Time.get_ticks_msec()
	var char_id := "save_coalesce_%d" % (Time.get_ticks_usec() % 1000000)
	var path := "%s%s.json" % [LocalSave.CHARACTERS_DIR, char_id]
	DirAccess.make_dir_recursive_absolute(LocalSave.CHARACTERS_DIR)
	LocalSave._active_character_id = char_id
	for _i in 10:
		LocalSave.request_autosave()
	await Engine.get_main_loop().create_timer(LocalSave.AUTOSAVE_MIN_INTERVAL + 0.1).timeout
	var mtime := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
	await Engine.get_main_loop().create_timer(0.05).timeout
	LocalSave.request_autosave()
	await Engine.get_main_loop().create_timer(LocalSave.AUTOSAVE_MIN_INTERVAL + 0.1).timeout
	var mtime2 := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
	LocalSave._active_character_id = ""
	ctx.timed_record(
		"save.autosave.coalesces",
		get_category(),
		FileAccess.file_exists(path) and mtime > 0 and mtime == mtime2,
		"ten request_autosave calls inside interval produce one write",
		start,
		"SAV-07"
	)


func _test_cloud_conflict_backup() -> void:
	var start := Time.get_ticks_msec()
	var char_id := "save_cloud_%d" % (Time.get_ticks_usec() % 1000000)
	DirAccess.make_dir_recursive_absolute(LocalSave.CHARACTERS_DIR)
	LocalSave._active_character_id = char_id
	LocalSave.autosave()
	var backup_path := LocalSave._backup_local_save()
	var ok := backup_path != "" and FileAccess.file_exists(backup_path)
	ok = ok and backup_path.find(char_id) >= 0
	LocalSave._active_character_id = ""
	ctx.timed_record(
		"save.cloud.conflict_backup_named",
		get_category(),
		ok,
		"conflict backup uses character prefix and returns path",
		start,
		"SAV-05"
	)


func _test_migrate_v4_to_v5_account_id_reset() -> void:
	var SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
	var start := Time.get_ticks_msec()
	var source := _minimal_v1_save(
		{
			"schemaVersion": 4,
			"accountId": SaveMigratorScript.NIL_ACCOUNT_ID,
		}
	)
	var migrated: Dictionary = SaveMigratorScript.migrate(source)
	LocalSave._cached_state = migrated.duplicate(true)
	var resolved := LocalSave._resolve_account_id()
	var ok := str(migrated.get("accountId", "x")) == "" and resolved != "" and resolved != SaveMigratorScript.NIL_ACCOUNT_ID
	ctx.timed_record(
		"save.migrate.v4_to_v5_account_id_reset",
		get_category(),
		ok,
		"nil accountId cleared and regenerated on write",
		start,
		"SAV-09"
	)


func _test_migrate_quests_split_v4_to_v5() -> void:
	var SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
	var start := Time.get_ticks_msec()
	var source := _minimal_v1_save(
		{
			"schemaVersion": 4,
			"quests": {
				"kill_grunts": "active",
				"kill_grunts_progress": {"count": 2},
				"relic_progress": "active",
				"relic": "completed",
			},
		}
	)
	var migrated: Dictionary = SaveMigratorScript.migrate(source)
	var quests: Variant = migrated.get("quests", {})
	var ok := false
	if quests is Dictionary:
		var states: Dictionary = quests.get("states", {})
		var progress: Dictionary = quests.get("progress", {})
		ok = (
			str(states.get("kill_grunts", "")) == "active"
			and str(states.get("relic_progress", "")) == "active"
			and str(states.get("relic", "")) == "completed"
			and int(progress.get("kill_grunts", {}).get("count", 0)) == 2
		)
	ctx.timed_record(
		"save.migrate.quests_split_v4_to_v5",
		get_category(),
		ok,
		"legacy quest rows split into states and progress",
		start,
		"CHS-01"
	)


func _test_migrate_coins_folded_into_gold() -> void:
	var SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
	var start := Time.get_ticks_msec()
	var source := _minimal_v1_save(
		{
			"schemaVersion": 4,
			"currencies": {"gold": 40, "coins": 90},
		}
	)
	var migrated: Dictionary = SaveMigratorScript.migrate(source)
	var currencies: Variant = migrated.get("currencies", {})
	var ok := false
	if currencies is Dictionary:
		ok = int(currencies.get("gold", 0)) == 90 and not currencies.has("coins")
	ctx.timed_record(
		"save.migrate.coins_folded_into_gold",
		get_category(),
		ok,
		"v4 coins folded into gold without loss",
		start,
		"CHS-08"
	)


func _test_character_currency_autosave_deferred() -> void:
	var start := Time.get_ticks_msec()
	var char_id := "save_char_currency_%d" % (Time.get_ticks_usec() % 1000000)
	var path := "%s%s.json" % [LocalSave.CHARACTERS_DIR, char_id]
	DirAccess.make_dir_recursive_absolute(LocalSave.CHARACTERS_DIR)
	LocalSave._active_character_id = char_id
	CharacterService.reset_to_defaults()
	for _i in 30:
		CharacterService.add_coins(1)
	await Engine.get_main_loop().create_timer(LocalSave.AUTOSAVE_MIN_INTERVAL + 0.1).timeout
	var deferred_mtime := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
	CharacterService.spend_gold(1)
	await Engine.get_main_loop().create_timer(0.1).timeout
	var immediate_mtime := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
	LocalSave._active_character_id = ""
	ctx.timed_record(
		"character.currency.autosave_is_deferred",
		get_category(),
		deferred_mtime > 0 and immediate_mtime > deferred_mtime,
		"30 add_coins coalesce; spend_gold writes immediately",
		start,
		"CHS-04"
	)


func _test_character_id_uniqueness() -> void:
	var start := Time.get_ticks_msec()
	LocalSave._roster["characters"] = [{"id": "warden_1", "name": "A", "classId": "knight", "level": 1}]
	var first := LocalSave._generate_character_id()
	var second := LocalSave._generate_character_id()
	ctx.timed_record(
		"save.identity.character_id_unique",
		get_category(),
		first != "" and second != "" and first != second,
		"back-to-back character id generation avoids collisions",
		start,
		"SAV-10"
	)


func _test_appearance_profile() -> void:
	var CharacterAppearanceScript := preload("res://scripts/save/character_appearance.gd")
	var PixelStyleScript := preload("res://scripts/art/style/pixel_diorama_style.gd")
	var SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
	var start := Time.get_ticks_msec()
	var clamped: Dictionary = CharacterAppearanceScript.sanitize({"theme": 42})
	var theme_ok := (
		int(clamped.get("theme", -1)) >= 0
		and int(clamped.get("theme", -1)) <= PixelStyleScript.PALETTES.size() - 1
	)
	ctx.timed_record(
		"appearance.sanitize_clamps_theme",
		get_category(),
		theme_ok,
		"sanitize clamps theme into palette range",
		start,
		"CHA-01"
	)

	start = Time.get_ticks_msec()
	var legacy: Dictionary = CharacterAppearanceScript.sanitize({"height": 5.0, "bulk": -1.0})
	var legacy_ok := (
		str(legacy.get("heightVariant", "")) in CharacterAppearanceScript.HEIGHT_VARIANTS
		and str(legacy.get("bulkVariant", "")) in CharacterAppearanceScript.BULK_VARIANTS
	)
	ctx.timed_record(
		"appearance.sanitize_clamps_height_and_bulk",
		get_category(),
		legacy_ok,
		"legacy height/bulk migrate into variant clamps",
		start,
		"CHA-04"
	)

	start = Time.get_ticks_msec()
	var versioned: Dictionary = CharacterAppearanceScript.sanitize({})
	ctx.timed_record(
		"appearance.sanitize_stamps_profile_version",
		get_category(),
		int(versioned.get("profileVersion", 0)) == CharacterAppearanceScript.PROFILE_VERSION,
		"sanitize stamps profileVersion",
		start,
		"CHA-07"
	)

	start = Time.get_ticks_msec()
	var invalid := not CharacterAppearanceScript.is_valid({"theme": 42, "profileVersion": 1})
	var repaired: Dictionary = CharacterAppearanceScript.sanitize({"theme": 42})
	var repaired_ok := CharacterAppearanceScript.is_valid(repaired)
	ctx.timed_record(
		"appearance.is_valid_rejects_out_of_range",
		get_category(),
		invalid and repaired_ok,
		"is_valid rejects out-of-range theme; sanitize repairs",
		start,
		"CHA-01"
	)

	start = Time.get_ticks_msec()
	var presets_ok := true
	for height in CharacterAppearanceScript.HEIGHT_PRESETS:
		if height < CharacterAppearanceScript.HEIGHT_MIN or height > CharacterAppearanceScript.HEIGHT_MAX:
			presets_ok = false
	for bulk in CharacterAppearanceScript.BULK_PRESETS:
		if bulk < CharacterAppearanceScript.BULK_MIN or bulk > CharacterAppearanceScript.BULK_MAX:
			presets_ok = false
	ctx.timed_record(
		"appearance.presets_inside_clamps",
		get_category(),
		presets_ok,
		"legacy presets stay inside clamp ranges",
		start,
		"CHA-04"
	)

	start = Time.get_ticks_msec()
	var profile := CharacterAppearanceScript.profile_from_indices(2, 2, 2, 2, 2, 2, 2, 2)
	var character := {
		"appearanceTheme": int(profile.get("theme", 0)),
		"appearance": profile.duplicate(),
	}
	var roundtrip := CharacterAppearanceScript.from_character_dict(character)
	var roundtrip_ok := true
	for key in ["theme", "heightVariant", "bulkVariant", "head", "trim"]:
		if roundtrip.get(key) != profile.get(key):
			roundtrip_ok = false
	ctx.timed_record(
		"appearance.round_trip_through_save",
		get_category(),
		roundtrip_ok,
		"profile keys survive save round-trip",
		start,
		"CHA-07"
	)

	start = Time.get_ticks_msec()
	var source := _minimal_v1_save(
		{
			"schemaVersion": 4,
			"character": {
				"appearanceTheme": 42,
				"appearance": {"theme": 42, "height": 1.18, "bulk": 1.22, "head": "hood", "trim": 2},
			},
		}
	)
	var migrated: Dictionary = SaveMigratorScript.migrate(source)
	var migrated_char: Dictionary = migrated.get("character", {})
	var migrated_profile: Dictionary = migrated_char.get("appearance", {})
	var migrate_ok := (
		int(migrated_profile.get("theme", -1)) <= CharacterAppearanceScript.theme_max()
		and str(migrated_profile.get("heightVariant", "")) in CharacterAppearanceScript.HEIGHT_VARIANTS
	)
	ctx.timed_record(
		"appearance.migrate_v4_clamps_profile",
		get_category(),
		migrate_ok,
		"v4 appearance migrates into clamped profile",
		start,
		"CHA-01"
	)

	start = Time.get_ticks_msec()
	var palette_low := PixelStyleScript.get_palette(-3)
	var palette_high := PixelStyleScript.get_palette(99)
	var palette_ok := (
		palette_low.size() == PixelStyleScript.PALETTES[0].size()
		and palette_high.size() == PixelStyleScript.PALETTES[0].size()
	)
	ctx.timed_record(
		"appearance.palette_lookup_never_throws",
		get_category(),
		palette_ok,
		"get_palette clamps out-of-range themes without throwing",
		start,
		"CHA-01"
	)

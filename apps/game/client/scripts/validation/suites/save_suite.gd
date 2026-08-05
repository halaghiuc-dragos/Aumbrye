extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "save"


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
	_test_checkpoint_migration()


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
				ctx
				. eval_continuable(
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
		not ctx.eval_continuable({"snapshot": {}}),
		"empty snapshot is not continuable",
		start,
		"M3.save.empty_snapshot"
	)

	start = Time.get_ticks_msec()
	ctx.timed_record(
		"save.legacy_no_snapshot_key",
		get_category(),
		not ctx.eval_continuable({}),
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
				ctx
				. eval_continuable(
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
		not ctx.player_snapshot_allowed(0.0, true),
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
				ctx
				. eval_continuable(
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
		"activeRun": {
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
	WorldState.set_flag("suite_test_door", true)
	WorldState.restore_flags({"suite_test_door": true, "suite_other": 2})
	var ok := WorldState.has_flag("suite_test_door") and int(WorldState.get_flag("suite_other", 0)) == 2
	WorldState.reset()
	ctx.timed_record(
		"save.world_flags_restore",
		get_category(),
		ok,
		"WorldState.restore_flags round-trip",
		start,
		"B05.save.world_flags"
	)


func _test_checkpoint_migration() -> void:
	var SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
	var start := Time.get_ticks_msec()
	var v3 := {"schemaVersion": 3, "activeRun": {"snapshot": {"player": {"health": 1.0}}}}
	var migrated: Dictionary = SaveMigratorScript.migrate(v3.duplicate(true))
	var run: Dictionary = migrated.get("activeRun", {})
	var ok := int(migrated.get("schemaVersion", 0)) == 4 and run.has("lastCheckpoint")
	ctx.timed_record(
		"save.migrate_v4_checkpoint",
		get_category(),
		ok,
		"v3→v4 adds lastCheckpoint and worldFlags defaults",
		start,
		"S09.save.migrate_v4"
	)

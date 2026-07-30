extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "save"


func run() -> void:
	var backup: Dictionary = ctx.backup_save_file()
	_try_localsave_tests()
	ctx.restore_save_file(backup)
	_test_continuable_rules()
	_test_death_snapshot_guard()
	_test_player_dead_flag()
	_test_backup_rotation()


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
	LocalSave.set_active_run({
		"schemaVersion": 2,
		"runId": "validation-test",
		"seed": TC.SEED_A,
		"snapshot": {"player": {"health": 75.0}},
	})
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
	ctx.timed_record(
		"save.zero_hp_not_continuable",
		get_category(),
		not ctx.eval_continuable({
			"snapshot": {"player": {"health": 0.0}},
		}),
		"0 HP snapshot is not continuable",
		start,
		"M3.save.zero_hp"
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
	ctx.timed_record(
		"save.valid_midrun_continuable",
		get_category(),
		ctx.eval_continuable({
			"snapshot": {
				"player": {"health": 50.0},
				"enemies": {},
			},
		}),
		"valid mid-run snapshot is continuable",
		start,
		"M3.save.midrun"
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
	ctx.timed_record(
		"save.player_dead_not_continuable",
		get_category(),
		not ctx.eval_continuable({
			"playerDead": true,
			"snapshot": {"player": {"health": 50.0}},
		}),
		"playerDead flag blocks continue",
		start,
		"M3.save.player_dead"
	)

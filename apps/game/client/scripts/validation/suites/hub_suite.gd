extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "hub"


func run() -> void:
	await _test_menu_wiring()
	await _test_continue_button_states()
	_test_seed_validation()


func _test_menu_wiring() -> void:
	var start := Time.get_ticks_msec()
	var menu: Control = load("res://scenes/ui/castle_entry_menu.tscn").instantiate() as Control
	ctx.owner.add_child(menu)
	await ctx.await_frame()
	var has_buttons := (
		menu.get_node_or_null("MainPanel/Margin/VBox/NewButton") != null
		and menu.get_node_or_null("MainPanel/Margin/VBox/ContinueButton") != null
		and menu.get_node_or_null("MainPanel/Margin/VBox/SeedButton") != null
	)
	ctx.timed_record(
		"hub.menu_buttons",
		get_category(),
		has_buttons,
		"castle entry menu has New/Continue/Seed buttons",
		start,
		"M3.hub.menu"
	)
	menu.queue_free()

	start = Time.get_ticks_msec()
	var hub: Node3D = load("res://scenes/hub/hub_stub.tscn").instantiate() as Node3D
	ctx.timed_record(
		"hub.portal_and_arena",
		get_category(),
		hub.get_node_or_null("CastlePortal") != null and hub.get_node_or_null("ArenaDoor") != null,
		"hub has castle portal and arena door",
		start,
		"M3.hub.portal"
	)
	hub.free()


func _test_continue_button_states() -> void:
	var backup: Dictionary = ctx.backup_save_file()
	LocalSave.clear_active_run()

	var start := Time.get_ticks_msec()
	var menu: Control = load("res://scenes/ui/castle_entry_menu.tscn").instantiate() as Control
	ctx.owner.add_child(menu)
	await ctx.await_frame()
	menu.call("open_menu")
	await ctx.await_frame()
	var continue_btn: Button = menu.get_node("MainPanel/Margin/VBox/ContinueButton") as Button
	var disabled_no_save := continue_btn.disabled
	ctx.timed_record(
		"hub.continue_disabled_no_save",
		get_category(),
		disabled_no_save,
		"Continue button disabled with no save",
		start,
		"M3.hub.continue_disabled"
	)
	menu.queue_free()

	start = Time.get_ticks_msec()
	LocalSave.set_active_run({
		"schemaVersion": 2,
		"runId": "validation-continue",
		"seed": TC.SEED_A,
		"snapshot": {"player": {"health": 80.0}, "enemies": {}},
	})
	menu = load("res://scenes/ui/castle_entry_menu.tscn").instantiate() as Control
	ctx.owner.add_child(menu)
	await ctx.await_frame()
	menu.call("open_menu")
	await ctx.await_frame()
	continue_btn = menu.get_node("MainPanel/Margin/VBox/ContinueButton") as Button
	var enabled_with_save := not continue_btn.disabled and LocalSave.has_continuable_run()
	ctx.timed_record(
		"hub.continue_enabled_with_save",
		get_category(),
		enabled_with_save,
		"Continue button enabled with continuable save",
		start,
		"M3.hub.continue_enabled"
	)
	menu.queue_free()
	LocalSave.clear_active_run()
	ctx.restore_save_file(backup)


func _test_seed_validation() -> void:
	var start := Time.get_ticks_msec()
	var invalid := (
		ctx.parse_castle_seed("abc") == null
		and ctx.parse_castle_seed("0") == null
		and ctx.parse_castle_seed("") == null
	)
	ctx.timed_record(
		"seed.invalid_rejected",
		get_category(),
		invalid,
		"invalid seed text rejected (letters, zero, empty)",
		start,
		"M3.hub.seed_invalid"
	)

	start = Time.get_ticks_msec()
	ctx.timed_record(
		"seed.valid_accepted",
		get_category(),
		ctx.parse_castle_seed("42001") == 42001,
		"valid numeric seed accepted",
		start,
		"M3.hub.seed_valid"
	)

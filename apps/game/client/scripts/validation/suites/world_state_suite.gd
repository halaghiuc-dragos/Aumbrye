extends "res://scripts/validation/validation_suite.gd"

const WorldFlagsScript := preload("res://scripts/app/world_flags.gd")


func get_category() -> String:
	return "world_state"


func run() -> void:
	_test_rejects_unnamespaced()
	_test_accepts_builder_output()
	_test_deep_copy()
	_test_presence_vs_truthiness()
	_test_erase_emits_null()
	_test_restore_rejects_invalid()
	_test_lifecycle_cleared_on_return_to_hub()


func _test_rejects_unnamespaced() -> void:
	var start := Time.get_ticks_msec()
	WorldState.reset()
	WorldState.set_flag("foo", true)
	var ok := WorldState.all_flags().is_empty()
	WorldState.reset()
	ctx.timed_record(
		"world_state.id.rejects_unnamespaced",
		get_category(),
		ok,
		"set_flag rejects unnamespaced ids",
		start,
		"WST-05.world_state.id"
	)


func _test_accepts_builder_output() -> void:
	var start := Time.get_ticks_msec()
	WorldState.reset()
	var flag_id := WorldFlagsScript.lock_opened("gate_a")
	WorldState.set_flag(flag_id, true)
	var ok := WorldState.is_flag_true(flag_id)
	WorldState.reset()
	ctx.timed_record(
		"world_state.id.accepts_builder_output",
		get_category(),
		ok,
		"WorldFlags.lock_opened output is accepted",
		start,
		"WST-05.world_state.builder"
	)


func _test_deep_copy() -> void:
	var start := Time.get_ticks_msec()
	WorldState.reset()
	var flag_id := WorldFlagsScript.room_cleared("r1")
	var payload := {"enemies": []}
	WorldState.set_flag(flag_id, payload)
	payload["enemies"].append("grunt")
	var snapshot := WorldState.all_flags()
	var ok: bool = snapshot[flag_id]["enemies"].is_empty()
	WorldState.reset()
	ctx.timed_record(
		"world_state.copy.deep",
		get_category(),
		ok,
		"all_flags deep copy isolates nested containers",
		start,
		"WST-01.world_state.copy"
	)


func _test_presence_vs_truthiness() -> void:
	var start := Time.get_ticks_msec()
	WorldState.reset()
	var flag_id := WorldFlagsScript.chest_opened("c1")
	WorldState.set_flag(flag_id, 0)
	var ok := WorldState.has_flag(flag_id) and not WorldState.is_flag_true(flag_id)
	WorldState.reset()
	ctx.timed_record(
		"world_state.presence.vs_truthiness",
		get_category(),
		ok,
		"has_flag and is_flag_true disagree for zero",
		start,
		"WST-02.world_state.presence"
	)


func _test_erase_emits_null() -> void:
	var start := Time.get_ticks_msec()
	WorldState.reset()
	var flag_id := WorldFlagsScript.lock_opened("erase_test")
	var emitted_id := ""
	var emitted_value: Variant = false
	var handler := func(id: String, value: Variant) -> void:
		emitted_id = id
		emitted_value = value
	WorldState.flag_changed.connect(handler)
	WorldState.set_flag(flag_id, true)
	WorldState.erase_flag(flag_id)
	var ok := not WorldState.has_flag(flag_id) and emitted_id == flag_id and emitted_value == null
	WorldState.flag_changed.disconnect(handler)
	WorldState.reset()
	ctx.timed_record(
		"world_state.erase.emits_null",
		get_category(),
		ok,
		"erase_flag removes key and emits flag_changed(id, null)",
		start,
		"WST-07.world_state.erase"
	)


func _test_restore_rejects_invalid() -> void:
	var start := Time.get_ticks_msec()
	WorldState.reset()
	var rejected := WorldState.restore_flags(
		{WorldFlagsScript.lock_opened("a"): true, "garbage": Callable()}
	)
	var ok := (
		rejected == 1
		and WorldState.is_flag_true(WorldFlagsScript.lock_opened("a"))
		and WorldState.all_flags().size() == 1
	)
	WorldState.reset()
	ctx.timed_record(
		"world_state.restore.rejects_invalid",
		get_category(),
		ok,
		"restore_flags rejects invalid keys and values",
		start,
		"WST-06.world_state.restore"
	)


func _test_lifecycle_cleared_on_return_to_hub() -> void:
	var start := Time.get_ticks_msec()
	WorldState.reset()
	WorldState.set_flag(WorldFlagsScript.lock_opened("hub_test"), true)
	RunFlow.returned_to_hub.emit("test")
	var ok := WorldState.all_flags().is_empty()
	WorldState.reset()
	ctx.timed_record(
		"world_state.lifecycle.cleared_on_return_to_hub",
		get_category(),
		ok,
		"returned_to_hub clears world flags",
		start,
		"WST-03.world_state.lifecycle"
	)

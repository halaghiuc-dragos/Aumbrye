extends Node

const Resources := preload("res://scripts/player/player_run_state.gd")
var _failures := 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error(label)


func _ready() -> void:
	var player := Node.new()
	var health := Health.new()
	var stamina := Stamina.new()
	var mana := Mana.new()
	var heal := PlayerHeal.new()
	var arrows := PlayerArrows.new()
	var names := ["Health", "Stamina", "Mana", "PlayerHeal", "PlayerArrows"]
	var nodes := [health, stamina, mana, heal, arrows]
	for index in nodes.size():
		nodes[index].name = names[index]
		player.add_child(nodes[index])
	health.current = 41.0
	stamina.current = 0.0
	mana.current = 12.0
	heal.current_charges = 2
	heal.is_drinking = true
	arrows.current_arrows = 4
	var saved := Resources.capture(player)
	_check(int(saved["flaskCharges"]) == 1, "Saving during a drink reserves its flask")
	heal.is_drinking = false
	health.reset_health()
	stamina.reset_stamina()
	mana.reset_mana()
	heal.current_charges = 3
	arrows.current_arrows = 12
	Resources.restore(player, saved)
	_check(health.current == 41.0 and mana.current == 12.0, "Resource save round trip")
	_check(stamina.current == 0.0 and stamina.is_exhausted(), "Reload cannot bypass exhaustion")
	_check(heal.current_charges == 1 and arrows.current_arrows == 4, "Resource save round trip retains supplies")
	Resources.restore(player, {"health": NAN, "mana": "bad", "flaskCharges": -9, "arrows": 999})
	_check(health.current == 41.0 and mana.current == 12.0, "Invalid saved numbers do not poison resources")
	_check(heal.current_charges == 0 and arrows.current_arrows == arrows.max_arrows, "Saved supplies clamp to capacity")
	Resources.restore(player, {"health": 32.0})
	_check(health.current == 32.0 and arrows.current_arrows == arrows.max_arrows, "Old health-only saves remain compatible")
	player.free()

	RunFlow.run_mode = "castle"
	RunFlow.max_floors = 20
	RunFlow.current_floor = 10
	_check(not RunFlow.is_final_floor(), "A twenty-floor run cannot finish at ten")
	RunFlow.current_floor = 20
	_check(RunFlow.is_final_floor(), "A twenty-floor run finishes at twenty")
	RunFlow.max_floors = 3
	RunFlow.current_floor = 3
	_check(RunFlow.is_final_floor(), "A short run finishes at its configured length")
	var final_floor := LocalProcgen.generate("forgotten_castle", 1123, 3, "castle", 1, 1, false, false, true, 3)
	_check(bool(final_floor.get("ok", false)) and bool(final_floor.get("definition", {}).get("isFinalFloor", false)), "Short-run generator creates an extraction floor")
	RunFlow._restore_run_rules({"alternateMode": "ironman", "baseModifiers": ["starved_hearth"]})
	_check(RunFlow._is_permadeath_run(), "Continue preserves permadeath rules")
	_check(RunModifierService.has_modifier("starved_hearth"), "Continue restores modifiers")
	RunFlow._restore_run_rules({"alternateMode": "", "baseModifiers": []})

	RunFlow.current_floor = 1
	RunFlow.max_floors = 3
	RunFlow.current_dungeon_definition = {"floorIndex": 1}
	RunFlow.current_biome_id = "forgotten_castle"
	RunFlow._run_active = true
	RunFlow._boss_defeated = true
	RunFlow._cleared_floors.assign([1])
	RunFlow._test_resolve_floor_override = {}
	FloorKeyring.take("regression_red")
	await RunFlow.ascend_floor()
	_check(RunFlow.current_floor == 1 and RunFlow._boss_defeated, "Failed generation restores floor progression")
	_check(FloorKeyring.is_held("regression_red"), "Failed stairs do not consume the keyring")
	_check(not RunFlow._floor_transitioning, "Failed stairs can be retried")
	_check(int(RunFlow.current_dungeon_definition["floorIndex"]) == 1, "Failed stairs preserve the existing map")
	print("RUN STATE RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

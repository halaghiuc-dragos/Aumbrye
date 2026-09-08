extends Node

var _failures := 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _ready() -> void:
	var body := CharacterBody3D.new()
	var health := Health.new()
	health.name = "Health"
	var stamina := Stamina.new()
	stamina.name = "Stamina"
	var dodge := Dodge.new()
	dodge.name = "Dodge"
	var heal := PlayerHeal.new()
	heal.name = "PlayerHeal"
	var weapon := WeaponController.new()
	weapon.name = "WeaponController"
	var guard := Guard.new()
	guard.name = "Guard"
	for component in [health, stamina, dodge, heal, weapon, guard]:
		body.add_child(component)
	add_child(body)
	body.process_mode = Node.PROCESS_MODE_DISABLED

	heal._try_drink()
	_check(not heal.is_drinking, "Full health must not spend a flask")
	health.take_damage(80.0)
	weapon.is_attacking = true
	heal._try_drink()
	_check(not heal.is_drinking, "Flask must not overlap an attack")
	weapon.is_attacking = false
	dodge.is_dodging = true
	heal._try_drink()
	_check(not heal.is_drinking, "Flask must not overlap a dodge")
	dodge.is_dodging = false
	guard._enter_guard()
	heal._try_drink()
	_check(not heal.is_drinking, "Flask must not overlap guarding")
	guard._end_guard()
	heal._try_drink()
	_check(heal.is_drinking, "An injured idle player can drink")
	_check(weapon._is_action_blocked(), "Drinking must block attacks")
	_check(not dodge._can_dash(), "Drinking must block dodges")
	heal._physics_process(PlayerHeal.DRINK_DURATION * 0.63)
	_check(is_equal_approx(health.current, 65.0), "Flask commits at its timed gulp without an animator")
	heal._on_heal_commit()
	_check(is_equal_approx(health.current, 65.0), "Animation cannot commit a flask twice")
	heal._interrupt_drink()
	_check(heal.current_charges == 2, "Interrupted committed drink spends exactly one flask")
	_check(is_equal_approx(health.current, 65.0), "Interrupt does not heal again")
	heal._try_drink()
	heal._physics_process(0.1)
	heal._interrupt_drink()
	_check(is_equal_approx(health.current, 65.0), "Early interruption grants no healing")
	_check(heal.current_charges == 1, "Early interruption spends one flask")

	dodge.configure({}, "medium")
	dodge.is_dodging = true
	dodge._active_duration = 0.55
	dodge._dodge_timer = 0.35
	dodge.grant_external_iframes(true)
	dodge.grant_external_iframes(false)
	_check(dodge.iframes_active, "Ending external protection preserves active roll protection")
	dodge._dodge_timer = 0.02
	dodge.grant_external_iframes(true)
	dodge._refresh_iframes()
	_check(dodge.iframes_active, "External protection survives roll recovery")
	dodge.cancel_dodge()
	_check(not dodge.is_dodging and dodge.iframes_active, "Cancel ends the roll but preserves external protection")
	dodge.reset_after_revive()
	_check(not dodge.iframes_active and dodge._recovery_timer == 0.0, "Revive clears roll state")
	dodge._weight_override = ""
	body.set_meta("combat_defense", 80.0)
	stamina.current = 35.0
	_check(not dodge._can_dash(), "New heavy equipment cost applies before affordability check")
	body.set_meta("combat_defense", 0.0)
	stamina.current = 28.0
	_check(dodge._can_dash(), "New light equipment cost applies before affordability check")
	guard._enter_guard()
	dodge.is_dodging = true
	guard._physics_process(0.01)
	_check(not guard.is_guard_active, "Rolling releases an existing guard")
	_check(stamina._regen_state == Stamina.RegenState.SUPPRESSED, "Releasing guard cannot enable regen during roll")
	dodge.reset_after_revive()

	var floor_result := LocalProcgen.generate("forgotten_castle", 7919, 10, "castle", 1, 1, false, false, true)
	_check(bool(floor_result.get("ok", false)), "Final floor generates")
	_check(int(floor_result.get("attempts", 0)) == 1, "Final floor must not reroll looking for unused locks")
	print("COMBAT STATE RESULT %d failures" % _failures)
	body.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)

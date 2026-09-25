extends Node

var _failures := 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _ready() -> void:
	WavesRunService.begin_new_run(8712)
	var options := WavesRunService.starter_choice_options()
	var verbs: Dictionary = {}
	for option in options:
		verbs[str((option as Dictionary).get("weaponId", ""))] = true
	_check(options.size() == 4, "Starter offer supplies four deliberate choices")
	_check(verbs.has("sword_basic") and verbs.has("dagger") and verbs.has("bow") and verbs.has("staff"), "Starter offer covers melee, agile, ranged, and caster verbs")
	WavesRunService.lobby_ready = true
	WavesRunService.start_waves()
	_check(WavesRunService.current_wave == 0, "Waves cannot start before an explicit starter choice")
	var staff_option: Dictionary = {}
	for option in options:
		if str((option as Dictionary).get("weaponId", "")) == "staff":
			staff_option = option as Dictionary
	_check(WavesRunService.choose_starter_weapon(str(staff_option.get("instanceId", ""))), "Player can select the caster starter")
	WavesRunService.start_waves()
	_check(WavesRunService.current_wave == 1 and WavesRunService.waves_inventory.get_equipped_weapon_id() == "sage_staff", "Selected starter is equipped and permits the run")
	print("WAVES STARTER CHOICE RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

extends Node

var _failures := 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _ready() -> void:
	var quiet_empty := DescentPactService.resolve("quiet_halls", [])
	_check(not bool(quiet_empty.get("valid", true)), "Quiet Halls is suppressed when it removes nothing")
	var starved := DescentPactService.resolve("starved_road", [RunModifierService.MODIFIER_STARVED_HEARTH])
	var after: Array = starved.get("after", [])
	_check(RunModifierService.MODIFIER_NO_REST in after and RunModifierService.MODIFIER_STARVED_HEARTH not in after, "Pact additions replace incompatible base modifiers")
	_check(RunModifierService.MODIFIER_BOSS_HOARD in starved.get("rewards", []), "Resolved pact states its actual boss reward opportunity")
	var hunted := DescentPactService.resolve("hunted", [RunModifierService.MODIFIER_NO_REST])
	_check(RunModifierService.MODIFIER_NO_REST not in hunted.get("after", []), "Hunted removes the current no-rest conflict")
	var offers := DescentPactService.offers_for_descent(417, 3, [])
	for offer in offers:
		_check(bool((offer as Dictionary).get("resolution", {}).get("valid", false)), "Every offered pact has a meaningful resolved delta")
	print("DESCENT PACT RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

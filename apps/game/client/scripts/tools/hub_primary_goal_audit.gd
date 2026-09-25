extends Node

const ResultsScreenScript := preload("res://scripts/ui/results_screen.gd")

var _failures := 0


func _ready() -> void:
	var rows: Array[Dictionary] = [
		{"id": "far", "unlocked": false, "requirement": "4 runs", "goal_gap_ratio": 0.8},
		{"id": "already_done", "unlocked": true, "requirement": "", "goal_gap_ratio": 0.0},
		{"id": "near", "unlocked": false, "requirement": "1 study", "goal_gap_ratio": 0.25},
		{"id": "tied", "unlocked": false, "requirement": "1 clear", "goal_gap_ratio": 0.25},
	]
	var goal := HubGrowthService.choose_next_goal(rows)
	_check(str(goal.get("id", "")) == "near", "nearest locked character milestone is selected deterministically")
	var empty_rows: Array[Dictionary] = [
		{"id": "complete", "unlocked": true, "requirement": "", "goal_gap_ratio": 0.0}
	]
	_check(HubGrowthService.choose_next_goal(empty_rows).is_empty(), "no primary goal is proposed after every milestone is done")
	_check(
		ResultsScreenScript.vault_impact_translation_key(VaultService.TYPE_RELIC) == "RESULTS_VAULT_IMPACT_RELIC"
			and ResultsScreenScript.vault_impact_translation_key(VaultService.TYPE_ITEM) == "RESULTS_VAULT_IMPACT_ITEM"
			and ResultsScreenScript.vault_impact_translation_key(VaultService.TYPE_PACT) == "RESULTS_VAULT_IMPACT_PACT",
		"vault results explain how each unlock changes future run pools"
	)
	print("HUB PRIMARY GOAL RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)

extends Node

var _failures := 0
const SEEDS: Array[int] = [7, 91, 713, 2207, 9811, 44177, 901223, 1900111]


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _ready() -> void:
	RunBuffs.clear_all()
	var future := RunBuffs.offer_relevance("the_open_wound")
	_check(not bool(future.get("immediatelyUseful", true)), "Bleed-dependent relic is marked as a future build without a bleed source")
	_check("bleed" in future.get("missingStatuses", []), "Future-build explanation names the missing bleed source")
	_check(RunBuffs.add_relic("the_bleeding_edge"), "A bleed-enabling relic can be acquired")
	var ready_result := RunBuffs.offer_relevance("the_open_wound")
	_check(bool(ready_result.get("immediatelyUseful", false)), "Bleed-dependent relic becomes immediately useful with a compatible capability")
	RunBuffs.clear_all()
	var useful_choices := 0
	var offered_choices := 0
	var distinct_tags: Dictionary = {}
	for seed_value in SEEDS:
		RunBuffs.offer_state_from_save({})
		RunFlow.current_seed = seed_value
		var offer := RunBuffs.roll_offer("rl05_audit_%d" % seed_value)
		_check(offer.size() == 3, "Seed %d produces a complete relic offer" % seed_value)
		var has_useful := false
		for relic_id in offer:
			offered_choices += 1
			if bool(RunBuffs.offer_relevance(relic_id).get("immediatelyUseful", false)):
				has_useful = true
				useful_choices += 1
			for tag in RelicCatalog.get_definition(relic_id).get("tags", []):
				distinct_tags[str(tag)] = true
		_check(has_useful, "Seed %d offer contains an immediately useful relic" % seed_value)
	print("RL05 OFFER METRICS useful=%d/%d tags=%d seeds=%d" % [useful_choices, offered_choices, distinct_tags.size(), SEEDS.size()])
	_check(distinct_tags.size() >= 4, "Seed corpus offers more than a single relic-theme lane")
	RunBuffs.offer_state_from_save({})
	print("RELIC OFFER RELEVANCE RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

class_name EnemyAttackScheduler
extends RefCounted


## Owns only authored-attack selection.  Enemy state machines retain responsibility for tokens,
## windups, animation and recovery; this contract makes a deterministic pattern or weighted choice
## independently reusable and prevents selection policy from being buried in a 2,000-line actor.
static func choose(
	attacks: Array,
	ordered: bool,
	ordered_index: int,
	distance: float,
	max_range: float,
	rng: RandomNumberGenerator,
	fallback: Dictionary
) -> Dictionary:
	if attacks.is_empty():
		return {"found": true, "attack": fallback, "next_index": ordered_index}
	if ordered:
		return _choose_ordered(attacks, ordered_index, distance, max_range)
	return _choose_weighted(attacks, ordered_index, distance, max_range, rng)


static func _choose_ordered(
	attacks: Array, ordered_index: int, distance: float, max_range: float
) -> Dictionary:
	var next_index := ordered_index
	var attempts := 0
	while attempts < attacks.size():
		var entry: Variant = attacks[next_index % attacks.size()]
		next_index = (next_index + 1) % attacks.size()
		attempts += 1
		if not (entry is Dictionary):
			continue
		var attack := entry as Dictionary
		if _in_range(attack, distance, max_range):
			return {"found": true, "attack": attack, "next_index": next_index}
	return {"found": false, "attack": {}, "next_index": next_index}


static func _choose_weighted(
	attacks: Array,
	ordered_index: int,
	distance: float,
	max_range: float,
	rng: RandomNumberGenerator
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var weights: Array[float] = []
	var total := 0.0
	for entry in attacks:
		if not (entry is Dictionary):
			continue
		var attack := entry as Dictionary
		if not _in_range(attack, distance, max_range):
			continue
		var weight := maxf(0.01, float(attack.get("weight", 1.0)))
		candidates.append(attack)
		weights.append(weight)
		total += weight
	if candidates.is_empty():
		return {"found": false, "attack": {}, "next_index": ordered_index}
	var roll := rng.randf() * total
	for i in candidates.size():
		roll -= weights[i]
		if roll <= 0.0:
			return {"found": true, "attack": candidates[i], "next_index": ordered_index}
	return {"found": true, "attack": candidates[candidates.size() - 1], "next_index": ordered_index}


static func _in_range(attack: Dictionary, distance: float, max_range: float) -> bool:
	return (
		distance >= float(attack.get("min_range", 0.0))
		and distance <= float(attack.get("max_range", max_range))
	)

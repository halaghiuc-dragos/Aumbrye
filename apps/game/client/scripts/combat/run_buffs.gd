extends Node

## In-run relics and buffs — cleared on run end (PROG-4.3). Relics contribute flat
## stats and, where they carry `rules`, register against the shared CombatEvents
## dispatcher so a relic can change a rule rather than only a number.

signal buffs_changed
signal offer_taken(relic_id: String)

const RULE_SOURCE_PREFIX := "relic/"
const SYNERGY_MULTIPLIER := 1.75
const SYNERGY_CAP := 4.0

var _active: Array[Dictionary] = []
var _registered_sources: Array = []
var _procs: Dictionary = {}
var _trap_catches := 0

## C-124: `Hurtbox.hit_resolved` carries `DamageResolution` — incoming/outgoing damage, poise on both
## sides, crit, backstab, blocked, parried, dodged, absorbed_by_poise, damage type, region and a
## per-stage `stages` array — and is emitted on five paths with **no connection anywhere**. The
## damage-breakdown the results screen wanted did not need building; it needed a listener. This is
## it: the run's single biggest landed hit, with the flags that explain it.
var _best_hit: Dictionary = {}
var _offers_taken := 0
var _hooked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_event_hookup()


func get_active_buffs() -> Array[Dictionary]:
	return _active.duplicate(true)


func has_relic(relic_id: String) -> bool:
	for entry in _active:
		if entry.get("relicId", "") == relic_id:
			return true
	return false


func add_relic(relic_id: String) -> bool:
	var def := RelicCatalog.get_definition(relic_id)
	if def.is_empty():
		return false
	var max_stacks: int = int(def.get("maxStacks", 1))
	var current_stacks := 0
	for entry in _active:
		if entry.get("relicId", "") == relic_id:
			current_stacks = int(entry.get("stacks", 1))
			break
	if current_stacks >= max_stacks:
		return false
	if current_stacks == 0:
		_active.append({"relicId": relic_id, "stacks": 1})
	else:
		for entry in _active:
			if entry.get("relicId", "") == relic_id:
				entry["stacks"] = current_stacks + 1
				break
	_ensure_event_hookup()
	_sync_relic_rules()
	buffs_changed.emit()
	return true


func remove_relic(relic_id: String) -> bool:
	for i in range(_active.size() - 1, -1, -1):
		if str(_active[i].get("relicId", "")) != relic_id:
			continue
		_active.remove_at(i)
		_sync_relic_rules()
		buffs_changed.emit()
		return true
	return false


func get_stat_totals() -> Dictionary:
	var totals: Dictionary = {}
	for entry in _active:
		var def: Dictionary = RelicCatalog.get_definition(str(entry.get("relicId", "")))
		var stacks: int = int(entry.get("stacks", 1))
		var stats: Dictionary = def.get("stats", {})
		for stat in stats:
			totals[stat] = totals.get(stat, 0.0) + float(stats[stat]) * stacks
	return totals


## Seeded relic choice for a decision point. `offer_key` identifies the point —
## one seed and one key always produce the same three relics. Candidates are
## weighted toward tags the run already carries so a build compounds.
func roll_offer(offer_key: String, count: int = 3) -> Array[String]:
	var candidates := _offer_candidates()
	var offer: Array[String] = []
	if candidates.is_empty() or count <= 0:
		return offer
	var carried := _carried_tags()
	var weights: Array[float] = []
	var total := 0.0
	for relic_id in candidates:
		var weight := _offer_weight(relic_id, carried)
		weights.append(weight)
		total += weight
	var rng := RandomNumberGenerator.new()
	var run_seed: int = RunFlow.current_seed if RunFlow else 0
	rng.seed = FloorSeedMix.mix(run_seed, hash(offer_key))
	while offer.size() < count and total > 0.0:
		var roll := rng.randf() * total
		var picked := -1
		for i in candidates.size():
			if weights[i] <= 0.0:
				continue
			roll -= weights[i]
			if roll <= 0.0:
				picked = i
				break
		if picked < 0:
			break
		offer.append(candidates[picked])
		total -= weights[picked]
		weights[picked] = 0.0
	return offer


## Accepts one relic from an offer and reports it as a run highlight.
func take_offer(relic_id: String) -> bool:
	if not add_relic(relic_id):
		return false
	_offers_taken += 1
	offer_taken.emit(relic_id)
	return true


## C-124: called by `Hurtbox` when the player resolves a hit against something.
func note_player_hit(resolution: Variant) -> void:
	if resolution == null:
		return
	var amount := float(resolution.get("outgoing"))
	if amount <= float(_best_hit.get("amount", 0.0)):
		return
	_best_hit = {
		"amount": amount,
		"crit": bool(resolution.get("crit")),
		"backstab": bool(resolution.get("backstab")),
		"damageType": str(resolution.get("damage_type")),
	}


func note_trap_catch(count: int = 1) -> void:
	if count > 0:
		_trap_catches += count


## Per-run figures the results screen can turn into something worth repeating:
## which relic actually did the work, how often, and how much of the room the
## player turned against its own occupants.
func get_run_highlights() -> Dictionary:
	var relics: Array[Dictionary] = []
	var top_id := ""
	var top_procs := 0
	for entry in _active:
		var relic_id := str(entry.get("relicId", ""))
		var def := RelicCatalog.get_definition(relic_id)
		var procs := int(_procs.get(relic_id, 0))
		(
			relics
			. append(
				{
					"id": relic_id,
					"name": str(def.get("name", relic_id)),
					"stacks": int(entry.get("stacks", 1)),
					"procs": procs,
				}
			)
		)
		if procs > top_procs:
			top_procs = procs
			top_id = relic_id
	return {
		"relics": relics,
		"topRelic": top_id,
		"topRelicProcs": top_procs,
		"offersTaken": _offers_taken,
		"trapCatches": _trap_catches,
		"bestHit": _best_hit,
	}


func clear_all() -> void:
	var had_entries := not _active.is_empty()
	_active.clear()
	_procs.clear()
	_trap_catches = 0
	_offers_taken = 0
	_best_hit = {}
	_unregister_all()
	if had_entries:
		buffs_changed.emit()


func to_save_array() -> Array:
	return _active.duplicate(true)


func from_save_array(data: Variant) -> void:
	_active.clear()
	if data is Array:
		for entry in data:
			if entry is Dictionary:
				_active.append(entry.duplicate())
	_ensure_event_hookup()
	_sync_relic_rules()
	buffs_changed.emit()


func _offer_candidates() -> Array[String]:
	var ids := RelicCatalog.get_all_ids()
	ids.sort()
	var out: Array[String] = []
	for relic_id in ids:
		var def := RelicCatalog.get_definition(relic_id)
		if def.is_empty() or not bool(def.get("offerable", true)):
			continue
		if _stacks_of(relic_id) >= int(def.get("maxStacks", 1)):
			continue
		out.append(relic_id)
	return out


func _carried_tags() -> Dictionary:
	var tags: Dictionary = {}
	for entry in _active:
		var def := RelicCatalog.get_definition(str(entry.get("relicId", "")))
		for tag in def.get("tags", []):
			tags[str(tag)] = true
	return tags


func _offer_weight(relic_id: String, carried: Dictionary) -> float:
	var def := RelicCatalog.get_definition(relic_id)
	var weight := maxf(0.01, float(def.get("weight", 1.0)))
	if carried.is_empty():
		return weight
	var synergy := 1.0
	for tag in def.get("tags", []):
		if carried.has(str(tag)):
			synergy = minf(SYNERGY_CAP, synergy * SYNERGY_MULTIPLIER)
	return weight * synergy


func _stacks_of(relic_id: String) -> int:
	for entry in _active:
		if str(entry.get("relicId", "")) == relic_id:
			return int(entry.get("stacks", 1))
	return 0


## C-32: one source id per *stack*. `add_relic` increments `stacks` and then calls
## `_sync_relic_rules`, which used to see the single source already registered and do nothing — so
## stacks scaled `stats` only and a 2-stack relic's rule still fired once, despite `maxStacks`
## being authored per relic. A distinct id per stack makes the rule fire once per stack and gives
## each stack its own cooldown, which is the natural reading of stacking a triggered effect.
func _rule_source_id(relic_id: String, stack_index: int = 0) -> String:
	if stack_index <= 0:
		return "%s%s" % [RULE_SOURCE_PREFIX, relic_id]
	return "%s%s#%d" % [RULE_SOURCE_PREFIX, relic_id, stack_index]


func _sync_relic_rules() -> void:
	if not CombatEvents:
		return
	var wanted: Dictionary = {}
	for entry in _active:
		var relic_id := str(entry.get("relicId", ""))
		if relic_id == "":
			continue
		var def := RelicCatalog.get_definition(relic_id)
		var rules: Variant = def.get("rules", [])
		if not rules is Array or (rules as Array).is_empty():
			continue
		var stacks: int = maxi(1, int(entry.get("stacks", 1)))
		for stack_index in stacks:
			wanted[_rule_source_id(relic_id, stack_index)] = rules
	for source_id in _registered_sources:
		if not wanted.has(source_id):
			CombatEvents.unregister(str(source_id))
	for source_id in wanted:
		if not CombatEvents.is_registered(str(source_id)):
			CombatEvents.register(str(source_id), wanted[source_id])
	_registered_sources = wanted.keys()


func _unregister_all() -> void:
	if not CombatEvents:
		_registered_sources = []
		return
	for source_id in _registered_sources:
		CombatEvents.unregister(str(source_id))
	_registered_sources = []


func _ensure_event_hookup() -> void:
	if _hooked or not CombatEvents:
		return
	CombatEvents.rule_triggered.connect(_on_rule_triggered)
	_hooked = true


func _on_rule_triggered(source_id: String, _effect: String) -> void:
	if not source_id.begins_with(RULE_SOURCE_PREFIX):
		return
	# C-32: stacked relics register one source per stack (`relic/<id>#<n>`), so the stack suffix is
	# stripped before attribution — the results screen counts procs per relic, not per stack.
	var relic_id := source_id.substr(RULE_SOURCE_PREFIX.length())
	var hash_at := relic_id.find("#")
	if hash_at > 0:
		relic_id = relic_id.substr(0, hash_at)
	_procs[relic_id] = int(_procs.get(relic_id, 0)) + 1

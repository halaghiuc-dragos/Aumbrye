extends Node


signal buffs_changed
signal offer_taken(relic_id: String)

const RULE_SOURCE_PREFIX := "relic/"
const SYNERGY_MULTIPLIER := 1.75
const SYNERGY_CAP := 4.0

var _active: Array[Dictionary] = []
var _temporary_effects: Array[Dictionary] = []
var _registered_sources: Array = []
var _procs: Dictionary = {}
var _contributions: Dictionary = {}
var _trap_catches := 0

var _best_hit: Dictionary = {}
var _offers_taken := 0
var _pending_offer_ids: Array[String] = []
var _offer_tag_history: Array[String] = []
var _hooked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_event_hookup()


func get_active_buffs() -> Array[Dictionary]:
	return _active.duplicate(true)


func add_temporary_effect(effect_id: String, stat: String, amount: float, duration: float) -> bool:
	if effect_id == "" or stat == "" or duration <= 0.0:
		return false
	for entry in _temporary_effects:
		if str(entry.get("id", "")) == effect_id:
			entry["remaining"] = maxf(float(entry.get("remaining", 0.0)), duration)
			entry["amount"] = amount
			buffs_changed.emit()
			return true
	_temporary_effects.append({"id": effect_id, "stat": stat, "amount": amount, "remaining": duration})
	buffs_changed.emit()
	return true


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
	if CombatEvents:
		CombatEvents.dispatch(
			CombatEvents.ON_ACQUIRED,
			{
				"actor": get_tree().get_first_node_in_group("player"),
				"acquiredRelicId": relic_id,
			}
		)
	return true


func get_stat_totals() -> Dictionary:
	var totals: Dictionary = {}
	for entry in _active:
		var def: Dictionary = RelicCatalog.get_definition(str(entry.get("relicId", "")))
		var stacks: int = int(entry.get("stacks", 1))
		var stats: Dictionary = def.get("stats", {})
		for stat in stats:
			totals[stat] = totals.get(stat, 0.0) + float(stats[stat]) * stacks
	for entry in _temporary_effects:
		var stat := str(entry.get("stat", ""))
		if stat != "":
			totals[stat] = totals.get(stat, 0.0) + float(entry.get("amount", 0.0))
	return totals


func _physics_process(delta: float) -> void:
	if get_tree().paused or _temporary_effects.is_empty():
		return
	var changed := false
	for index in range(_temporary_effects.size() - 1, -1, -1):
		var entry: Dictionary = _temporary_effects[index]
		entry["remaining"] = float(entry.get("remaining", 0.0)) - delta
		if float(entry["remaining"]) <= 0.0:
			_temporary_effects.remove_at(index)
			changed = true
	if changed:
		buffs_changed.emit()


func roll_offer(offer_key: String, count: int = 3) -> Array[String]:
	if not _pending_offer_ids.is_empty():
		return _pending_offer_ids.duplicate()
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
		var picked_tags: Array = RelicCatalog.get_definition(candidates[picked]).get("tags", [])
		var picked_role := _offer_role(candidates[picked])
		for i in candidates.size():
			if weights[i] <= 0.0:
				continue
			var factor := 1.0
			if _shares_tag(candidates[i], picked_tags):
				factor *= 0.35
			if _offer_role(candidates[i]) == picked_role:
				factor *= 0.5
			if is_equal_approx(factor, 1.0):
				continue
			var reduced := weights[i] * factor
			total -= weights[i] - reduced
			weights[i] = reduced
	_ensure_immediately_useful_offer(offer, candidates)
	_pending_offer_ids = offer.duplicate()
	return offer


func take_offer(relic_id: String) -> bool:
	if relic_id not in _pending_offer_ids:
		return false
	if not add_relic(relic_id):
		return false
	_pending_offer_ids.clear()
	_offers_taken += 1
	for tag in RelicCatalog.get_definition(relic_id).get("tags", []):
		_offer_tag_history.append(str(tag))
	while _offer_tag_history.size() > 12:
		_offer_tag_history.pop_front()
	offer_taken.emit(relic_id)
	return true


func note_player_hit(resolution: Variant) -> void:
	if not resolution is DamageResolution:
		return
	var hit_resolution := resolution as DamageResolution
	var amount := hit_resolution.outgoing
	if amount <= float(_best_hit.get("amount", 0.0)):
		return
	_best_hit = {
		"amount": amount,
		"crit": hit_resolution.crit,
		"backstab": hit_resolution.backstab,
		"damageType": hit_resolution.damage_type,
	}


func note_trap_catch(count: int = 1) -> void:
	if count > 0:
		_trap_catches += count


func get_run_highlights() -> Dictionary:
	var relics: Array[Dictionary] = []
	var top_id := ""
	var top_procs := 0
	for entry in _active:
		var relic_id := str(entry.get("relicId", ""))
		var def := RelicCatalog.get_definition(relic_id)
		var procs := int(_procs.get(relic_id, 0))
		var contribution: Dictionary = _contributions.get(relic_id, {})
		(
			relics
			. append(
				{
					"id": relic_id,
					"name": str(def.get("name", relic_id)),
					"stacks": int(entry.get("stacks", 1)),
					"procs": procs,
					"contribution": contribution.duplicate(true),
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
		"relicContributions": _contributions.duplicate(true),
		"offersTaken": _offers_taken,
		"pendingOffer": _pending_offer_ids.duplicate(),
		"offerTagHistory": _offer_tag_history.duplicate(),
		"trapCatches": _trap_catches,
		"bestHit": _best_hit,
	}


func clear_all() -> void:
	var had_entries := not _active.is_empty()
	_active.clear()
	_temporary_effects.clear()
	_procs.clear()
	_contributions.clear()
	_trap_catches = 0
	_offers_taken = 0
	_pending_offer_ids.clear()
	_offer_tag_history.clear()
	_best_hit = {}
	_unregister_all()
	if had_entries:
		buffs_changed.emit()


func to_save_array() -> Array:
	return _active.duplicate(true)


func temporary_effects_to_save_array() -> Array:
	return _temporary_effects.duplicate(true)


func offer_state_to_save() -> Dictionary:
	return {
		"pending": _pending_offer_ids.duplicate(),
		"taken": _offers_taken,
		"tagHistory": _offer_tag_history.duplicate(),
		"contributions": _contributions.duplicate(true),
		"procs": _procs.duplicate(true),
		"trapCatches": _trap_catches,
		"bestHit": _best_hit.duplicate(true),
	}


func offer_state_from_save(data: Variant) -> void:
	_pending_offer_ids.clear()
	_offers_taken = 0
	_offer_tag_history.clear()
	_contributions.clear()
	_procs.clear()
	_trap_catches = 0
	_best_hit = {}
	if not data is Dictionary:
		return
	for relic_id in data.get("pending", []):
		var id := str(relic_id)
		if not RelicCatalog.get_definition(id).is_empty() and id not in _pending_offer_ids:
			_pending_offer_ids.append(id)
	_offers_taken = maxi(0, int(data.get("taken", 0)))
	var history: Variant = data.get("tagHistory", [])
	if history is Array:
		for tag in history:
			_offer_tag_history.append(str(tag))
	while _offer_tag_history.size() > 12:
		_offer_tag_history.pop_front()
	var saved_contributions: Variant = data.get("contributions", {})
	if saved_contributions is Dictionary:
		for raw_id in saved_contributions:
			var relic_id := str(raw_id)
			var raw_metrics: Variant = saved_contributions[raw_id]
			if RelicCatalog.get_definition(relic_id).is_empty() or not raw_metrics is Dictionary:
				continue
			var metrics: Dictionary = {}
			for metric in raw_metrics:
				metrics[str(metric)] = clampf(float(raw_metrics[metric]), 0.0, 1000000.0)
			_contributions[relic_id] = metrics
	var saved_procs: Variant = data.get("procs", {})
	if saved_procs is Dictionary:
		for raw_id in saved_procs:
			var relic_id := str(raw_id)
			if not RelicCatalog.get_definition(relic_id).is_empty():
				_procs[relic_id] = clampi(int(saved_procs[raw_id]), 0, 100000)
	_trap_catches = clampi(int(data.get("trapCatches", 0)), 0, 100000)
	var saved_best: Variant = data.get("bestHit", {})
	if saved_best is Dictionary and float(saved_best.get("amount", 0.0)) > 0.0:
		_best_hit = {
			"amount": maxf(0.0, float(saved_best.get("amount", 0.0))),
			"crit": bool(saved_best.get("crit", false)),
			"backstab": bool(saved_best.get("backstab", false)),
			"damageType": str(saved_best.get("damageType", "physical")),
		}


func temporary_effects_from_save_array(data: Variant) -> void:
	_temporary_effects.clear()
	if data is Array:
		for raw in data:
			if not raw is Dictionary:
				continue
			var entry: Dictionary = raw
			var effect_id := str(entry.get("id", ""))
			var stat := str(entry.get("stat", ""))
			var remaining := float(entry.get("remaining", 0.0))
			if effect_id != "" and stat != "" and remaining > 0.0:
				_temporary_effects.append({"id": effect_id, "stat": stat, "amount": float(entry.get("amount", 0.0)), "remaining": remaining})
	buffs_changed.emit()


func from_save_array(data: Variant) -> void:
	_active.clear()
	if data is Array:
		for entry in data:
			if not entry is Dictionary:
				continue
			var relic_id := str((entry as Dictionary).get("relicId", ""))
			var definition := RelicCatalog.get_definition(relic_id)
			if definition.is_empty():
				continue
			var max_stacks := maxi(1, int(definition.get("maxStacks", 1)))
			var stacks := clampi(int((entry as Dictionary).get("stacks", 1)), 1, max_stacks)
			var existing := _stacks_of(relic_id)
			if existing >= max_stacks:
				continue
			for current in _active:
				if str(current.get("relicId", "")) == relic_id:
					current["stacks"] = mini(max_stacks, existing + stacks)
					stacks = 0
					break
			if stacks > 0:
				_active.append({"relicId": relic_id, "stacks": mini(max_stacks, stacks)})
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
		if VaultService and not VaultService.is_relic_available(relic_id):
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
	var synergy := 1.0
	for tag in def.get("tags", []):
		if carried.has(str(tag)):
			synergy = minf(SYNERGY_CAP, synergy * SYNERGY_MULTIPLIER)
	var recent_matches := 0
	for tag in def.get("tags", []):
		for previous in _offer_tag_history:
			if str(tag) == previous:
				recent_matches += 1
	return weight * synergy / (1.0 + float(recent_matches) * 0.25)


## RL05: an on-hit conditional is not a useful synergy unless the current loadout can actually
## produce its required status.  This stays data-driven: a relic or equipped item that applies a
## status becomes a capability source without a hard-coded weapon list.
func offer_relevance(relic_id: String) -> Dictionary:
	var def := RelicCatalog.get_definition(relic_id)
	var required := _required_statuses(def)
	var capabilities := _current_capabilities()
	var missing: Array[String] = []
	for status_id in required:
		if not capabilities.has(status_id):
			missing.append(status_id)
	return {
		"immediatelyUseful": missing.is_empty(),
		"requiredStatuses": required,
		"missingStatuses": missing,
	}


func _ensure_immediately_useful_offer(offer: Array[String], candidates: Array[String]) -> void:
	if offer.is_empty():
		return
	for relic_id in offer:
		if bool(offer_relevance(relic_id).get("immediatelyUseful", false)):
			return
	for relic_id in candidates:
		if relic_id not in offer and bool(offer_relevance(relic_id).get("immediatelyUseful", false)):
			offer[offer.size() - 1] = relic_id
			return


func _required_statuses(definition: Dictionary) -> Array[String]:
	var required: Array[String] = []
	for rule in definition.get("rules", []):
		if not rule is Dictionary:
			continue
		var status_id := str((rule as Dictionary).get("ifTargetHasStatus", ""))
		if status_id != "" and status_id not in required:
			required.append(status_id)
	return required


func _current_capabilities() -> Dictionary:
	var capabilities: Dictionary = {}
	for entry in _active:
		_add_rule_capabilities(capabilities, RelicCatalog.get_definition(str(entry.get("relicId", ""))))
	if InventoryService == null:
		return capabilities
	var inventory := InventoryService.active_inventory()
	if inventory == null:
		return capabilities
	for slot_name in inventory.equipped:
		var instance: Variant = inventory.equipped.get(slot_name, {})
		if instance is Dictionary:
			_add_rule_capabilities(capabilities, InventoryService.get_item_def(str((instance as Dictionary).get("itemId", ""))))
	return capabilities


func _add_rule_capabilities(capabilities: Dictionary, definition: Dictionary) -> void:
	for rule in definition.get("rules", []):
		if rule is Dictionary and str((rule as Dictionary).get("effect", "")) == "apply_status":
			var status_id := str((rule as Dictionary).get("statusId", ""))
			if status_id != "":
				capabilities[status_id] = true


func _shares_tag(relic_id: String, tags: Array) -> bool:
	for tag in RelicCatalog.get_definition(relic_id).get("tags", []):
		if tag in tags:
			return true
	return false


func _offer_role(relic_id: String) -> String:
	var def := RelicCatalog.get_definition(relic_id)
	var stats: Dictionary = def.get("stats", {}) as Dictionary
	if (
		float(stats.get("maxHealth", 0.0)) > 0.0
		or float(stats.get("armor", 0.0)) > 0.0
		or float(stats.get("resistance", 0.0)) > 0.0
	):
		return "defense"
	for rule in def.get("rules", []):
		if not rule is Dictionary:
			continue
		var effect := str((rule as Dictionary).get("effect", ""))
		if effect in ["restore_health", "restore_stamina", "restore_mana", "cleanse", "shield"]:
			return "utility"
	return "pivot"


func _stacks_of(relic_id: String) -> int:
	for entry in _active:
		if str(entry.get("relicId", "")) == relic_id:
			return int(entry.get("stacks", 1))
	return 0


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


func _on_rule_triggered(source_id: String, _effect: String, contribution: Dictionary) -> void:
	if not source_id.begins_with(RULE_SOURCE_PREFIX):
		return
	var relic_id := source_id.substr(RULE_SOURCE_PREFIX.length())
	var hash_at := relic_id.find("#")
	if hash_at > 0:
		relic_id = relic_id.substr(0, hash_at)
	_procs[relic_id] = int(_procs.get(relic_id, 0)) + 1
	if contribution.is_empty():
		return
	var totals: Dictionary = _contributions.get(relic_id, {})
	for metric in contribution:
		totals[str(metric)] = clampf(
			float(totals.get(str(metric), 0.0)) + maxf(0.0, float(contribution[metric])),
			0.0,
			1000000.0
		)
	_contributions[relic_id] = totals

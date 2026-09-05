extends Node


signal progression_changed
signal xp_granted(amount: int, reason: String)
## UX-02: fired when the queued-but-not-yet-spent talent plan changes (plan/unplan/clear/commit),
## separate from `progression_changed` so the talents screen can redraw the plan overlay without
## the rest of the game reacting as if talents actually changed.
signal talent_plan_changed

const XP_CURVE_PATH := "content/progression/xp_curve.json"
const TALENT_TREE_PATH := "content/talents/tree.json"
const ENDLESS_DEPTH_PATH := "content/progression/endless_depth.json"
const MAX_FAILURE_POINTS := 50
const KEYSTONE_RULE_PREFIX := "talent/"

signal endless_depth_record(previous_best: int, new_best: int, tokens_awarded: int)
signal endless_milestone_reached(milestone: Dictionary)

var level := 1
var xp := 0
var talent_points_spent := 0
var talents: Dictionary = {}
var endless_best_floor := 0
var descent_tokens := 0
var endless_milestones: Dictionary = {}
var failure_points: Array = []

## UX-02: nodes queued for the plan-ahead workflow, in the order they'll be spent on commit.
## Never persisted -- a plan is a scratchpad for the current session, not a save-file commitment.
var _planned_talents: Array[String] = []
## UX-02: the level at which the most recent talent was actually unlocked (committed, not just
## planned). Drives the free-respec grace window.
var _last_talent_unlock_level := 0
const TALENT_RESPEC_GRACE_LEVELS := 3

var _curve: Dictionary = {}
var _talent_tree: Dictionary = {}
var _levels: Array = []
var _endless_depth: Dictionary = {}
var _registered_keystone_sources: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_curve()
	_load_talent_tree()
	_sync_keystone_rules()


func get_available_talent_points() -> int:
	return maxi(0, _talent_points_from_level() - talent_points_spent)


func xp_progress_ratio() -> float:
	var current_req := _xp_required_for_level(level)
	var next_req := _xp_required_for_level(level + 1)
	if next_req < 0 or next_req == current_req:
		return 1.0
	return clampf(float(xp - current_req) / float(next_req - current_req), 0.0, 1.0)


func grant_xp(amount: int, reason: String = "") -> Dictionary:
	if amount <= 0:
		return {"gained": 0, "levels_gained": 0}
	var xp_gain_bonus: float = float(get_talent_stat_totals().get("xpGain", 0.0))
	var adjusted := int(float(amount) * (1.0 + xp_gain_bonus))
	if adjusted <= 0:
		return {"gained": 0, "levels_gained": 0}
	var before_level := level
	xp += adjusted
	_recalc_level()
	var result := {
		"gained": adjusted,
		"levels_gained": level - before_level,
		"level": level,
		"xp": xp,
	}
	progression_changed.emit()
	if reason != "":
		xp_granted.emit(adjusted, reason)
	return result


func calculate_run_xp(kills: int, boss_defeated: bool, escaped: bool) -> int:
	var base_per_kill: int = int(_curve.get("baseXpPerKill", 25))
	var total := kills * base_per_kill
	if boss_defeated:
		total += int(_curve.get("bossBonusXp", 150))
	if escaped:
		total += int(_curve.get("escapeBonusXp", 50))
	return total


func apply_death_xp_fraction(full_xp: int) -> int:
	var fraction: float = float(_curve.get("deathXpFraction", 0.5))
	return int(full_xp * fraction)


func apply_abandon_xp_fraction(full_xp: int) -> int:
	var fraction: float = float(_curve.get("abandonedXpFraction", 0.0))
	return int(full_xp * fraction)


func is_branch_available(branch: Dictionary) -> bool:
	var required := str(branch.get("classId", ""))
	if required == "":
		return true
	if not is_instance_valid(CharacterService):
		return false
	return CharacterService.class_id == required


func get_available_talent_tree() -> Dictionary:
	var branches: Array = []
	for branch in _talent_tree.get("branches", []):
		if branch is Dictionary and is_branch_available(branch):
			branches.append((branch as Dictionary).duplicate(true))
	return {"schemaVersion": _talent_tree.get("schemaVersion", 1), "branches": branches}


func get_talent_rank(node_id: String) -> int:
	return int(talents.get(node_id, 0))


func can_unlock_talent(node_id: String) -> bool:
	var node := _find_talent_node(node_id)
	if node.is_empty():
		return false
	if not is_branch_available(_find_talent_branch(node_id)):
		return false
	var rank: int = get_talent_rank(node_id)
	if rank >= int(node.get("maxRank", 1)):
		return false
	if get_available_talent_points() < int(node.get("costPerRank", 1)):
		return false
	for req in node.get("requires", []):
		if get_talent_rank(str(req)) <= 0:
			return false
	# Paired keystones exclude each other: taking one closes the other for the rest of the build.
	# Respec reopens both, so the choice is committing rather than permanent.
	for excluded in node.get("excludes", []):
		if get_talent_rank(str(excluded)) > 0:
			return false
	return true


## The node this one is locked out by, if the player has already committed to its opposite.
func blocked_by(node_id: String) -> String:
	for excluded in _find_talent_node(node_id).get("excludes", []):
		if get_talent_rank(str(excluded)) > 0:
			return str(excluded)
	return ""


func unlock_talent(node_id: String) -> bool:
	if not can_unlock_talent(node_id):
		return false
	var node := _find_talent_node(node_id)
	var cost: int = int(node.get("costPerRank", 1))
	talents[node_id] = get_talent_rank(node_id) + 1
	talent_points_spent += cost
	_last_talent_unlock_level = level
	_sync_keystone_rules()
	progression_changed.emit()
	LocalSave.autosave()
	if AchievementService:
		AchievementService.notify("talent_points_spent", {"cost": cost})
	return true


## UX-02: the marginal stat change from taking the *next* rank of this node, diffed against the
## currently-active build. Talent totals are a straight sum of `effects.valuePerRank * rank`
## (see `get_talent_stat_totals`), so the delta a node would add is exactly its own per-rank
## effect values -- no need to recompute the whole build twice. Returns {} once the node is
## already at (or the tree has no room to plan) its max rank.
func preview_talent_delta(node_id: String) -> Dictionary:
	var node := _find_talent_node(node_id)
	if node.is_empty():
		return {}
	if get_effective_talent_rank(node_id) >= int(node.get("maxRank", 1)):
		return {}
	var deltas: Dictionary = {}
	for effect in node.get("effects", []):
		if not effect is Dictionary:
			continue
		var stat: String = str((effect as Dictionary).get("stat", ""))
		if stat == "":
			continue
		var per_rank: float = float((effect as Dictionary).get("valuePerRank", 0.0))
		deltas[stat] = float(deltas.get(stat, 0.0)) + per_rank
	return deltas


## UX-02 plan-ahead: nodes queued but not yet spent, in commit order. Multiple entries of the
## same id represent multiple queued ranks.
func get_planned_talents() -> Array[String]:
	return _planned_talents.duplicate()


func get_planned_rank(node_id: String) -> int:
	return int(_planned_counts().get(node_id, 0))


## Committed rank plus anything already queued -- what the node's rank would read as if the plan
## were spent right now.
func get_effective_talent_rank(node_id: String) -> int:
	return get_talent_rank(node_id) + get_planned_rank(node_id)


func _planned_counts() -> Dictionary:
	var counts: Dictionary = {}
	for node_id in _planned_talents:
		counts[node_id] = int(counts.get(node_id, 0)) + 1
	return counts


func _planned_total_cost() -> int:
	var total := 0
	for node_id in _planned_counts():
		var node := _find_talent_node(str(node_id))
		if node.is_empty():
			continue
		total += int(node.get("costPerRank", 1)) * int(_planned_counts()[node_id])
	return total


func get_talent_points_available_after_plan() -> int:
	return maxi(0, get_available_talent_points() - _planned_total_cost())


## Same shape as `can_unlock_talent`, but checks against the plan-ahead virtual state (committed
## ranks plus queued ones) instead of only what's actually been spent, so a player can queue a
## node whose prerequisite is itself still only queued.
func can_plan_talent(node_id: String) -> bool:
	var node := _find_talent_node(node_id)
	if node.is_empty():
		return false
	if not is_branch_available(_find_talent_branch(node_id)):
		return false
	if get_effective_talent_rank(node_id) >= int(node.get("maxRank", 1)):
		return false
	if get_talent_points_available_after_plan() < int(node.get("costPerRank", 1)):
		return false
	for req in node.get("requires", []):
		if get_effective_talent_rank(str(req)) <= 0:
			return false
	for excluded in node.get("excludes", []):
		if get_effective_talent_rank(str(excluded)) > 0:
			return false
	return true


func plan_talent(node_id: String) -> bool:
	if not can_plan_talent(node_id):
		return false
	_planned_talents.append(node_id)
	talent_plan_changed.emit()
	return true


func unplan_talent(node_id: String) -> bool:
	var idx := _planned_talents.rfind(node_id)
	if idx < 0:
		return false
	_planned_talents.remove_at(idx)
	talent_plan_changed.emit()
	return true


func clear_planned_talents() -> void:
	if _planned_talents.is_empty():
		return
	_planned_talents.clear()
	talent_plan_changed.emit()


## Spends the queue for real, one node at a time in queue order (so a node that only became legal
## because an earlier queued node just unlocked resolves correctly). Points are never touched
## until this is called -- planning is free right up to commit.
func commit_planned_talents() -> Dictionary:
	var order := _planned_talents.duplicate()
	_planned_talents.clear()
	var committed := 0
	for node_id in order:
		if unlock_talent(node_id):
			committed += 1
	talent_plan_changed.emit()
	return {"committed": committed, "attempted": order.size()}


## UX-02: a respec taken within a few levels of the talent that prompted it is free -- the point
## of the grace window is that trying a node right after a level-up shouldn't be a 250-gold bet.
func is_talent_respec_free() -> bool:
	if _last_talent_unlock_level <= 0:
		return false
	return (level - _last_talent_unlock_level) <= TALENT_RESPEC_GRACE_LEVELS


## Respecs for free when inside the grace window; refuses (does nothing, returns false) otherwise
## so a caller falls back to the paid respec path. Deliberately bypasses any gold check -- the
## whole point of the window is that this specific respec doesn't cost anything.
func free_respec_talents() -> bool:
	if not is_talent_respec_free():
		return false
	respec_talents()
	return true


func get_talent_stat_totals() -> Dictionary:
	var totals: Dictionary = {}
	for branch in _talent_tree.get("branches", []):
		if not branch is Dictionary:
			continue
		if not is_branch_available(branch):
			continue
		for node in branch.get("nodes", []):
			if not node is Dictionary:
				continue
			var node_id: String = node.get("id", "")
			var rank: int = get_talent_rank(node_id)
			if rank <= 0:
				continue
			for effect in node.get("effects", []):
				if not effect is Dictionary:
					continue
				var stat: String = str(effect.get("stat", ""))
				if stat == "":
					continue
				var per_rank: float = float(effect.get("valuePerRank", 0.0))
				totals[stat] = totals.get(stat, 0.0) + per_rank * rank
	return totals


## Drops any saved talent whose node no longer exists in the tree and recomputes the spend from
## what survived, so retuning the tree refunds the difference instead of stranding points.
func _prune_unknown_talents() -> void:
	_load_talent_tree()
	var kept: Dictionary = {}
	var spent := 0
	for node_id in talents:
		var node := _find_talent_node(str(node_id))
		if node.is_empty():
			continue
		var rank := mini(int(talents[node_id]), int(node.get("maxRank", 1)))
		if rank <= 0:
			continue
		kept[node_id] = rank
		spent += rank * int(node.get("costPerRank", 1))
	talents = kept
	talent_points_spent = spent


func respec_talents() -> void:
	talents.clear()
	talent_points_spent = 0
	_planned_talents.clear()
	# Nothing is "just unlocked" any more once the whole build is cleared, so the grace window
	# closes with it -- the next free respec has to be earned by unlocking something again.
	_last_talent_unlock_level = 0
	_sync_keystone_rules()
	progression_changed.emit()
	talent_plan_changed.emit()
	LocalSave.autosave()


func refresh_talent_rules() -> void:
	_sync_keystone_rules()


func _sync_keystone_rules() -> void:
	if not is_instance_valid(CombatEvents):
		return
	var wanted: Dictionary = {}
	for branch in _talent_tree.get("branches", []):
		if not branch is Dictionary:
			continue
		if not is_branch_available(branch):
			continue
		for node in branch.get("nodes", []):
			if not node is Dictionary:
				continue
			var node_id := str((node as Dictionary).get("id", ""))
			if node_id == "" or get_talent_rank(node_id) <= 0:
				continue
			var rules: Variant = (node as Dictionary).get("rules", [])
			if not rules is Array or (rules as Array).is_empty():
				continue
			wanted[KEYSTONE_RULE_PREFIX + node_id] = rules
	for source_id in _registered_keystone_sources:
		if not wanted.has(source_id):
			CombatEvents.unregister(str(source_id))
	for source_id in wanted:
		if not CombatEvents.is_registered(str(source_id)):
			CombatEvents.register(str(source_id), wanted[source_id])
	_registered_keystone_sources = wanted.keys()


func to_save_dict() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"talentPointsSpent": talent_points_spent,
		"talents": talents.duplicate(),
		"endlessBestFloor": endless_best_floor,
		"descentTokens": descent_tokens,
		"endlessMilestones": endless_milestones.duplicate(),
		"failurePoints": failure_points.duplicate(true),
		"lastTalentUnlockLevel": _last_talent_unlock_level,
	}


func from_save_dict(data: Dictionary) -> void:
	level = maxi(1, int(data.get("level", 1)))
	xp = maxi(0, int(data.get("xp", 0)))
	talent_points_spent = maxi(0, int(data.get("talentPointsSpent", 0)))
	talents = {}
	var saved_talents: Variant = data.get("talents", {})
	if saved_talents is Dictionary:
		talents = saved_talents.duplicate()
	_prune_unknown_talents()
	_planned_talents.clear()
	_last_talent_unlock_level = maxi(0, int(data.get("lastTalentUnlockLevel", 0)))
	endless_best_floor = maxi(0, int(data.get("endlessBestFloor", 0)))
	descent_tokens = maxi(0, int(data.get("descentTokens", 0)))
	endless_milestones = {}
	var saved_milestones: Variant = data.get("endlessMilestones", {})
	if saved_milestones is Dictionary:
		endless_milestones = saved_milestones.duplicate()
	failure_points = []
	var saved_failures: Variant = data.get("failurePoints", [])
	if saved_failures is Array:
		failure_points = (saved_failures as Array).duplicate(true)
	_trim_failure_points()
	_recalc_level()
	_sync_keystone_rules()
	progression_changed.emit()


func get_endless_best_floor() -> int:
	return endless_best_floor


func get_descent_tokens() -> int:
	return descent_tokens


func register_endless_depth(floor_reached: int) -> Dictionary:
	var reached := maxi(0, floor_reached)
	var previous := endless_best_floor
	var result := {
		"previousBest": previous,
		"newBest": previous,
		"tokens": 0,
		"milestones": [],
	}
	if reached <= previous:
		return result
	var depth_data := _load_endless_depth()
	var per_floor := int(depth_data.get("tokensPerNewFloor", 1))
	var tokens := maxi(0, (reached - previous) * per_floor)
	var reached_milestones: Array = []
	for milestone in depth_data.get("milestones", []):
		if not milestone is Dictionary:
			continue
		var floor_needed := int((milestone as Dictionary).get("floor", 0))
		if floor_needed <= 0 or reached < floor_needed:
			continue
		var flag := str((milestone as Dictionary).get("flag", ""))
		if flag == "" or bool(endless_milestones.get(flag, false)):
			continue
		endless_milestones[flag] = true
		var reward: Dictionary = (milestone as Dictionary).get("reward", {})
		tokens += int(reward.get("tokens", 0))
		reached_milestones.append(milestone)
		endless_milestone_reached.emit(milestone)
	endless_best_floor = reached
	descent_tokens += tokens
	result["newBest"] = endless_best_floor
	result["tokens"] = tokens
	result["milestones"] = reached_milestones
	progression_changed.emit()
	endless_depth_record.emit(previous, endless_best_floor, tokens)
	return result


func record_failure_point(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	failure_points.append(entry.duplicate(true))
	_trim_failure_points()
	progression_changed.emit()


func get_failure_hotspots(limit: int = 3) -> Array[Dictionary]:
	var counts := {}
	for entry in failure_points:
		if not entry is Dictionary:
			continue
		var key := str((entry as Dictionary).get("label", ""))
		if key == "":
			continue
		counts[key] = int(counts.get(key, 0)) + 1
	var rows: Array[Dictionary] = []
	for key in counts:
		rows.append({"label": str(key), "count": int(counts[key])})
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.get("count", 0)) == int(b.get("count", 0)):
				return str(a.get("label", "")) < str(b.get("label", ""))
			return int(a.get("count", 0)) > int(b.get("count", 0))
	)
	return rows.slice(0, maxi(1, limit))


func _trim_failure_points() -> void:
	while failure_points.size() > MAX_FAILURE_POINTS:
		failure_points.pop_front()


func get_endless_depth_data() -> Dictionary:
	return _load_endless_depth().duplicate(true)


func _load_endless_depth() -> Dictionary:
	if _endless_depth.is_empty():
		var data := ContentLoader.load_json(ENDLESS_DEPTH_PATH)
		if data is Dictionary:
			_endless_depth = data
	return _endless_depth


func _load_curve() -> void:
	_curve = ContentLoader.load_json(XP_CURVE_PATH)
	_levels = _curve.get("levels", [])


func _load_talent_tree() -> void:
	_talent_tree = ContentLoader.load_json(TALENT_TREE_PATH)


func _xp_required_for_level(target_level: int) -> int:
	for entry in _levels:
		if int(entry.get("level", 0)) == target_level:
			return int(entry.get("xpRequired", 0))
	return -1


func _recalc_level() -> void:
	var new_level := 1
	for entry in _levels:
		var req_level: int = int(entry.get("level", 1))
		var req_xp: int = int(entry.get("xpRequired", 0))
		if xp >= req_xp and req_level > new_level:
			new_level = req_level
	level = new_level


func _talent_points_from_level() -> int:
	var per_level: int = int(_curve.get("talentPointsPerLevel", 1))
	return maxi(0, (level - 1) * per_level)


func _find_talent_node(node_id: String) -> Dictionary:
	for branch in _talent_tree.get("branches", []):
		if not branch is Dictionary:
			continue
		for node in branch.get("nodes", []):
			if node is Dictionary and node.get("id", "") == node_id:
				return node
	return {}


func _find_talent_branch(node_id: String) -> Dictionary:
	for branch in _talent_tree.get("branches", []):
		if not branch is Dictionary:
			continue
		for node in branch.get("nodes", []):
			if node is Dictionary and node.get("id", "") == node_id:
				return branch
	return {}

extends Node

## Permanent XP, level, and talent points (PROG-4.1 / PROG-4.2 client).

signal progression_changed

const XP_CURVE_PATH := "content/progression/xp_curve.json"
const TALENT_TREE_PATH := "content/talents/tree.json"

var level := 1
var xp := 0
var talent_points_spent := 0
var talents: Dictionary = {}

var _curve: Dictionary = {}
var _talent_tree: Dictionary = {}
var _levels: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_curve()
	_load_talent_tree()


func get_available_talent_points() -> int:
	return maxi(0, _talent_points_from_level() - talent_points_spent)


func xp_to_next_level() -> int:
	var next := _xp_required_for_level(level + 1)
	if next < 0:
		return 0
	return maxi(0, next - xp)


func xp_progress_ratio() -> float:
	var current_req := _xp_required_for_level(level)
	var next_req := _xp_required_for_level(level + 1)
	if next_req < 0 or next_req == current_req:
		return 1.0
	return clampf(float(xp - current_req) / float(next_req - current_req), 0.0, 1.0)


func grant_xp(amount: int, _reason: String = "") -> Dictionary:
	if amount <= 0:
		return { "gained": 0, "levels_gained": 0 }
	var before_level := level
	xp += amount
	_recalc_level()
	var result := {
		"gained": amount,
		"levels_gained": level - before_level,
		"level": level,
		"xp": xp,
	}
	progression_changed.emit()
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


func get_talent_tree() -> Dictionary:
	return _talent_tree.duplicate(true)


func get_talent_rank(node_id: String) -> int:
	return int(talents.get(node_id, 0))


func can_unlock_talent(node_id: String) -> bool:
	var node := _find_talent_node(node_id)
	if node.is_empty():
		return false
	var rank: int = get_talent_rank(node_id)
	if rank >= int(node.get("maxRank", 1)):
		return false
	if get_available_talent_points() < int(node.get("costPerRank", 1)):
		return false
	for req in node.get("requires", []):
		if get_talent_rank(str(req)) <= 0:
			return false
	return true


func unlock_talent(node_id: String) -> bool:
	if not can_unlock_talent(node_id):
		return false
	var node := _find_talent_node(node_id)
	var cost: int = int(node.get("costPerRank", 1))
	talents[node_id] = get_talent_rank(node_id) + 1
	talent_points_spent += cost
	progression_changed.emit()
	LocalSave.autosave()
	return true


func get_talent_stat_totals() -> Dictionary:
	var totals: Dictionary = {}
	for branch in _talent_tree.get("branches", []):
		if not branch is Dictionary:
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


func respec_talents() -> void:
	talents.clear()
	talent_points_spent = 0
	progression_changed.emit()


func to_save_dict() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"talentPointsSpent": talent_points_spent,
		"talents": talents.duplicate(),
	}


func from_save_dict(data: Dictionary) -> void:
	level = maxi(1, int(data.get("level", 1)))
	xp = maxi(0, int(data.get("xp", 0)))
	talent_points_spent = maxi(0, int(data.get("talentPointsSpent", 0)))
	talents = {}
	var saved_talents: Variant = data.get("talents", {})
	if saved_talents is Dictionary:
		talents = saved_talents.duplicate()
	_recalc_level()
	progression_changed.emit()


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

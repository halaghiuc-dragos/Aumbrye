class_name ProgressCounters
extends RefCounted

## Read-only account/character progress totals that gate hub dressing and alternate modes.

const KEY_DUNGEONS_CLEARED := "dungeonsCleared"
const KEY_MAX_TIER := "maxUnlockedTier"
const KEY_BESTIARY_STUDIED := "bestiaryStudied"
const KEY_BESTIARY_MASTERED := "bestiaryMastered"
const KEY_ENDLESS_BEST := "endlessBestFloor"
const KEY_BOUNTY_TOKENS := "bountyTokens"
const KEY_DESCENT_TOKENS := "descentTokens"
const KEY_RUNS_RECORDED := "runsRecorded"

const ALL_KEYS: Array[String] = [
	KEY_DUNGEONS_CLEARED,
	KEY_MAX_TIER,
	KEY_BESTIARY_STUDIED,
	KEY_BESTIARY_MASTERED,
	KEY_ENDLESS_BEST,
	KEY_BOUNTY_TOKENS,
	KEY_DESCENT_TOKENS,
	KEY_RUNS_RECORDED,
]


static func dungeons_cleared() -> int:
	if DungeonTierService == null:
		return 0
	var total := 0
	for entry in DungeonCatalog.ENTRIES:
		if not entry is Dictionary:
			continue
		var dungeon_id := str((entry as Dictionary).get("id", ""))
		if dungeon_id == "":
			continue
		if DungeonTierService.is_difficulty_tier_cleared(dungeon_id, 1):
			total += 1
	return total


static func snapshot() -> Dictionary:
	var counters := {}
	for key in ALL_KEYS:
		counters[key] = 0
	counters[KEY_DUNGEONS_CLEARED] = dungeons_cleared()
	if DungeonTierService != null:
		counters[KEY_MAX_TIER] = DungeonTierService.get_max_unlocked_tier()
	counters[KEY_BESTIARY_STUDIED] = BestiaryService.studied_count()
	counters[KEY_BESTIARY_MASTERED] = BestiaryService.mastered_count()
	if ProgressionService != null:
		counters[KEY_ENDLESS_BEST] = ProgressionService.get_endless_best_floor()
		counters[KEY_DESCENT_TOKENS] = ProgressionService.get_descent_tokens()
	if QuestService != null:
		counters[KEY_BOUNTY_TOKENS] = QuestService.get_bounty_tokens()
	counters[KEY_RUNS_RECORDED] = RunHistoryService.run_count()
	return counters


static func meets(condition: Dictionary, counters: Dictionary = {}) -> bool:
	if condition.is_empty():
		return true
	var totals := counters if not counters.is_empty() else snapshot()
	for key in condition:
		if int(totals.get(key, 0)) < int(condition[key]):
			return false
	return true


## The single requirement furthest from being met, for "what is still missing" copy.
static func shortfall(condition: Dictionary, counters: Dictionary = {}) -> Dictionary:
	if condition.is_empty():
		return {}
	var totals := counters if not counters.is_empty() else snapshot()
	var worst := {}
	var worst_gap := 0
	for key in condition:
		var need := int(condition[key])
		var have := int(totals.get(key, 0))
		if have >= need:
			continue
		var gap := need - have
		if gap > worst_gap:
			worst_gap = gap
			worst = {"key": str(key), "need": need, "have": have}
	return worst


static func describe(key: String) -> String:
	match key:
		KEY_DUNGEONS_CLEARED:
			return "halls cleared"
		KEY_MAX_TIER:
			return "depth unlocked"
		KEY_BESTIARY_STUDIED:
			return "quarry studied"
		KEY_BESTIARY_MASTERED:
			return "quarry mastered"
		KEY_ENDLESS_BEST:
			return "deepest descent"
		KEY_BOUNTY_TOKENS:
			return "bounty tokens"
		KEY_DESCENT_TOKENS:
			return "descent tokens"
		KEY_RUNS_RECORDED:
			return "runs recorded"
		_:
			return key

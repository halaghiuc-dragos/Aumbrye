class_name BountyService
extends RefCounted


const KIND_DAILY := "daily"
const KIND_WEEKLY := "weekly"

const DAILY_COUNT := 3
const WEEKLY_COUNT := 1

const STATE_FLAG := "bounty_state"
const TOKENS_FLAG := "bounty_tokens"
const CLAIMED_TOTAL_FLAG := "bounty_claimed_total"
const SEED_FLAG := "account_seed"

const SECONDS_PER_DAY := 86400
const DAYS_PER_WEEK := 7


static func current_index(kind: String) -> int:
	var day := int(floor(Time.get_unix_time_from_system() / float(SECONDS_PER_DAY)))
	if kind == KIND_WEEKLY:
		return int(floor(float(day) / float(DAYS_PER_WEEK)))
	return day


static func reset_time_unix(kind: String) -> int:
	var span := SECONDS_PER_DAY * DAYS_PER_WEEK if kind == KIND_WEEKLY else SECONDS_PER_DAY
	return (current_index(kind) + 1) * span


static func reset_time_label(kind: String) -> String:
	var date := Time.get_datetime_dict_from_unix_time(reset_time_unix(kind))
	return "%04d-%02d-%02d %02d:%02d UTC" % [
		int(date.get("year", 0)),
		int(date.get("month", 0)),
		int(date.get("day", 0)),
		int(date.get("hour", 0)),
		int(date.get("minute", 0)),
	]


static func pool_for(kind: String) -> Array[String]:
	var ids: Array[String] = []
	for quest_id in QuestCatalog.get_all_ids():
		var def := QuestCatalog.get_definition(quest_id)
		if str(def.get("bounty", "")) != kind:
			continue
		ids.append(str(quest_id))
	ids.sort()
	return ids


static func slot_count(kind: String) -> int:
	return WEEKLY_COUNT if kind == KIND_WEEKLY else DAILY_COUNT


static func roll(kind: String, index: int) -> Array[String]:
	var pool := pool_for(kind)
	pool = pool.filter(func(quest_id: String) -> bool: return QuestService.is_base_offerable(quest_id))
	var wanted: int = min(slot_count(kind), pool.size())
	if wanted <= 0:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = _period_seed(kind, index)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := pool[i]
		pool[i] = pool[j]
		pool[j] = swap
	return pool.slice(0, wanted)


static func active_bounties(kind: String) -> Array[String]:
	var state := _state()
	var period := _period_state(state, kind)
	var offers: Variant = period.get("offers", [])
	if not offers is Array or (offers as Array).is_empty():
		offers = roll(kind, int(period.get("index", current_index(kind))))
		period["offers"] = (offers as Array).duplicate()
		state[kind] = period
		if CharacterService:
			CharacterService.set_flag(STATE_FLAG, state)
	var result: Array[String] = []
	for quest_id in offers:
		result.append(str(quest_id))
	return result


static func bounty_kind(quest_id: String) -> String:
	var def := QuestCatalog.get_definition(quest_id)
	var kind := str(def.get("bounty", ""))
	if kind == KIND_DAILY or kind == KIND_WEEKLY:
		return kind
	return ""


static func is_bounty(quest_id: String) -> bool:
	return bounty_kind(quest_id) != ""


static func is_active(quest_id: String) -> bool:
	var kind := bounty_kind(quest_id)
	if kind == "":
		return false
	return quest_id in active_bounties(kind)


static func is_claimed(quest_id: String) -> bool:
	var kind := bounty_kind(quest_id)
	if kind == "":
		return false
	return quest_id in _claimed_ids(kind)


static func is_offerable(quest_id: String) -> bool:
	if not is_bounty(quest_id):
		return true
	return is_active(quest_id) and not is_claimed(quest_id)


static func notify_accepted(quest_id: String) -> void:
	var kind := bounty_kind(quest_id)
	if kind == "" or CharacterService == null:
		return
	var def := QuestCatalog.get_definition(quest_id)
	var rewards: Variant = def.get("rewards", {})
	var progress := CharacterService.get_quest_progress(quest_id)
	progress["bountyPeriodKind"] = kind
	progress["bountyPeriodIndex"] = current_index(kind)
	progress["bountyTokenAward"] = int((rewards as Dictionary).get("bountyTokens", 0)) if rewards is Dictionary else 0
	progress["bountyRewardClaimed"] = false
	CharacterService.set_quest_progress(quest_id, progress)


static func notify_completed(quest_id: String) -> int:
	var kind := bounty_kind(quest_id)
	if kind == "" or CharacterService == null:
		return 0
	var progress := CharacterService.get_quest_progress(quest_id)
	if bool(progress.get("bountyRewardClaimed", false)):
		return 0
	var accepted_kind := str(progress.get("bountyPeriodKind", ""))
	if accepted_kind != kind and not is_active(quest_id):
		return 0
	var state := _state()
	var period := _period_state(state, kind)
	var claimed: Array = period.get("claimed", [])
	if int(progress.get("bountyPeriodIndex", -1)) == int(period.get("index", -2)):
		if quest_id not in claimed:
			claimed.append(quest_id)
		period["claimed"] = claimed
		state[kind] = period
		CharacterService.set_flag(STATE_FLAG, state)
	progress["bountyRewardClaimed"] = true
	CharacterService.set_quest_progress(quest_id, progress)
	CharacterService.set_flag(
		CLAIMED_TOTAL_FLAG, int(CharacterService.get_flag(CLAIMED_TOTAL_FLAG, 0)) + 1
	)
	var tokens := int(progress.get("bountyTokenAward", 0))
	if tokens > 0:
		add_tokens(tokens)
	return tokens


static func get_tokens() -> int:
	if CharacterService == null:
		return 0
	return int(CharacterService.get_flag(TOKENS_FLAG, 0))


static func add_tokens(amount: int) -> void:
	if amount <= 0 or CharacterService == null:
		return
	CharacterService.set_flag(TOKENS_FLAG, get_tokens() + amount)


static func _period_seed(kind: String, index: int) -> int:
	var account_seed := 0
	if CharacterService:
		account_seed = int(CharacterService.get_flag(SEED_FLAG, 0))
	return abs(hash("%s:%d:%d" % [kind, index, account_seed]))


static func _state() -> Dictionary:
	if CharacterService == null:
		return {}
	var raw: Variant = CharacterService.get_flag(STATE_FLAG, {})
	return raw.duplicate(true) if raw is Dictionary else {}


static func _period_state(state: Dictionary, kind: String) -> Dictionary:
	var raw: Variant = state.get(kind, {})
	var period: Dictionary = raw if raw is Dictionary else {}
	var index := current_index(kind)
	if int(period.get("index", -1)) != index:
		period = {"index": index, "claimed": [], "offers": []}
	if not period.has("claimed"):
		period["claimed"] = []
	if not period.has("offers"):
		period["offers"] = []
	return period


static func _claimed_ids(kind: String) -> Array:
	var period := _period_state(_state(), kind)
	var claimed: Variant = period.get("claimed", [])
	return claimed if claimed is Array else []

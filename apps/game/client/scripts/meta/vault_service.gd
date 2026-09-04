extends Node

## The Warden's Vault — permanent, per-character content unlocks.
##
## The point of this service is that run 40 can contain things run 1 could not. Anything listed in
## `content/progression/vault.json` is withheld from the run pools until its trigger fires; anything
## not listed is available from the first run, so adding an entry here is the only way to gate
## content and existing content keeps working untouched.
##
## `evaluate()` is cheap and idempotent — call it at any point where progress may have moved
## (end of run, boss down, waves finished). Newly-opened entries queue an announcement that the
## results screen drains with `consume_announcements()`.

signal vault_unlocked(entry_id: String)

const VAULT_PATH := "content/progression/vault.json"
const FLAG_UNLOCKED := "vault_unlocked"
const FLAG_PENDING := "vault_pending_announce"

const TYPE_RELIC := "relic"
const TYPE_ITEM := "item"
const TYPE_PACT := "pact"

var _entries: Dictionary = {}
var _order: Array[String] = []
var _gated_by_type: Dictionary = {}

## `is_available()` is asked once per candidate entry inside every loot-table roll, so reading the
## save flag and duplicating the dictionary each time put a dictionary copy on the loot hot path.
## The unlocked set is cached instead and dropped whenever the flag it mirrors is written.
var _unlocked_cache: Dictionary = {}
var _unlocked_cache_valid := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	# A save load swaps the whole flag set out from under the cache.
	if LocalSave and not LocalSave.save_loaded.is_connected(invalidate_cache):
		LocalSave.save_loaded.connect(invalidate_cache)


func _load() -> void:
	_entries.clear()
	_order.clear()
	_gated_by_type = {TYPE_RELIC: {}, TYPE_ITEM: {}, TYPE_PACT: {}}
	var data: Dictionary = ContentLoader.load_json(VAULT_PATH)
	if data.is_empty():
		push_error("VaultService: failed to load %s" % VAULT_PATH)
		return
	for raw in data.get("entries", []):
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var entry_id := str(entry.get("id", ""))
		var entry_type := str(entry.get("type", ""))
		var grants := str(entry.get("grants", ""))
		if entry_id == "" or grants == "" or not _gated_by_type.has(entry_type):
			continue
		_entries[entry_id] = entry
		_order.append(entry_id)
		(_gated_by_type[entry_type] as Dictionary)[grants] = entry_id


func reload() -> void:
	_load()
	invalidate_cache()


func total_count() -> int:
	return _order.size()


func unlocked_count() -> int:
	var record := _unlocked_record()
	var count := 0
	for entry_id in _order:
		if bool(record.get(entry_id, false)):
			count += 1
	return count


func invalidate_cache() -> void:
	_unlocked_cache_valid = false


func is_entry_unlocked(entry_id: String) -> bool:
	if not _unlocked_cache_valid:
		_unlocked_cache = _unlocked_record()
		_unlocked_cache_valid = true
	return bool(_unlocked_cache.get(entry_id, false))


## The gate every pool asks. An id with no vault entry is always available.
func is_available(entry_type: String, grants_id: String) -> bool:
	var gated: Variant = _gated_by_type.get(entry_type, {})
	if not gated is Dictionary:
		return true
	var entry_id: String = str((gated as Dictionary).get(grants_id, ""))
	if entry_id == "":
		return true
	return is_entry_unlocked(entry_id)


func is_relic_available(relic_id: String) -> bool:
	return is_available(TYPE_RELIC, relic_id)


func is_item_available(item_id: String) -> bool:
	return is_available(TYPE_ITEM, item_id)


func is_pact_available(pact_id: String) -> bool:
	return is_available(TYPE_PACT, pact_id)


## Re-checks every locked entry and opens the ones whose trigger is now satisfied.
## Returns the entries opened by this call.
func evaluate() -> Array[Dictionary]:
	var record := _unlocked_record()
	var pending := _pending_record()
	var opened: Array[Dictionary] = []
	var dirty := false
	for entry_id in _order:
		if bool(record.get(entry_id, false)):
			continue
		var entry: Dictionary = _entries[entry_id]
		if not _trigger_met(entry.get("trigger", {})):
			continue
		record[entry_id] = true
		pending[entry_id] = true
		dirty = true
		opened.append(entry.duplicate(true))
		vault_unlocked.emit(entry_id)
	if dirty:
		CharacterService.set_flag(FLAG_UNLOCKED, record)
		CharacterService.set_flag(FLAG_PENDING, pending)
		invalidate_cache()
	return opened


## Drains the queue of unlocks the player has not been shown yet.
func consume_announcements() -> Array[Dictionary]:
	var pending := _pending_record()
	if pending.is_empty():
		return []
	var out: Array[Dictionary] = []
	for entry_id in pending.keys():
		if not _entries.has(entry_id):
			continue
		out.append((_entries[entry_id] as Dictionary).duplicate(true))
	CharacterService.set_flag(FLAG_PENDING, {})
	return out


func describe_progress() -> String:
	return "Vault %d/%d" % [unlocked_count(), total_count()]


## AD-05: the results screen's "Next" block wants the single locked entry closest to opening, not
## the whole vault -- reuses `_trigger_met()`'s trigger-type switch but returns the progress
## numbers instead of collapsing them to a bool.
func nearest_locked_progress() -> Dictionary:
	var record := _unlocked_record()
	var best := {}
	var best_gap := INF
	for entry_id in _order:
		if bool(record.get(entry_id, false)):
			continue
		var entry: Dictionary = _entries[entry_id]
		var progress := _trigger_progress(entry.get("trigger", {}))
		if progress.is_empty():
			continue
		var have := int(progress.get("have", 0))
		var need := int(progress.get("need", 1))
		var gap := need - have
		if gap <= 0 or gap >= best_gap:
			continue
		best_gap = gap
		best = {
			"entryId": entry_id,
			"name": str(entry.get("name", entry_id)),
			"have": have,
			"need": need,
			"gap": gap,
		}
	return best


func _trigger_progress(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var trigger: Dictionary = raw
	var needed := int(trigger.get("value", 1))
	var key := str(trigger.get("key", ""))
	match str(trigger.get("type", "")):
		"biomeCleared":
			return {"have": 1 if CharacterService.get_flag("theme_%s_cleared" % key) else 0, "need": 1}
		"dungeonDepth":
			return {"have": DungeonTierService.get_max_unlocked_tier(), "need": needed}
		"dungeonDepthCleared":
			return {"have": DungeonTierService.get_deepest_cleared(), "need": needed}
		"enemyKills":
			return {"have": BestiaryService.get_kills(key), "need": needed}
		"totalKills":
			return {"have": _total_kills(), "need": needed}
		"deaths":
			return {"have": int(CharacterService.get_flag("deaths")), "need": needed}
		"wavesWave":
			return {"have": int(CharacterService.get_flag("waves_best_wave")), "need": needed}
		"wavesCompletions":
			return {"have": int(CharacterService.get_flag("waves_completions")), "need": needed}
	return {}


func _unlocked_record() -> Dictionary:
	var stored: Variant = CharacterService.get_flag(FLAG_UNLOCKED, {})
	return (stored as Dictionary).duplicate() if stored is Dictionary else {}


func _pending_record() -> Dictionary:
	var stored: Variant = CharacterService.get_flag(FLAG_PENDING, {})
	return (stored as Dictionary).duplicate() if stored is Dictionary else {}


func _trigger_met(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var trigger: Dictionary = raw
	var needed := int(trigger.get("value", 1))
	var key := str(trigger.get("key", ""))
	match str(trigger.get("type", "")):
		"biomeCleared":
			return bool(CharacterService.get_flag("theme_%s_cleared" % key))
		"dungeonDepth":
			return DungeonTierService.get_max_unlocked_tier() >= needed
		"dungeonDepthCleared":
			return DungeonTierService.get_deepest_cleared() >= needed
		"enemyKills":
			return BestiaryService.get_kills(key) >= needed
		"totalKills":
			return _total_kills() >= needed
		"deaths":
			return int(CharacterService.get_flag("deaths")) >= needed
		"wavesWave":
			return int(CharacterService.get_flag("waves_best_wave")) >= needed
		"wavesCompletions":
			return int(CharacterService.get_flag("waves_completions")) >= needed
	return false


func _total_kills() -> int:
	var stored: Variant = CharacterService.get_flag("bestiary_kills", {})
	if not stored is Dictionary:
		return 0
	var total := 0
	for enemy_id in (stored as Dictionary):
		var value: Variant = (stored as Dictionary)[enemy_id]
		if value is int or value is float:
			total += int(value)
	return total

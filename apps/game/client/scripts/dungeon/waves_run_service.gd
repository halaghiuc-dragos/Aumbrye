extends Node


signal waves_changed
signal inventory_changed

const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const WAVES_DEFINITION_PATH := "content/waves/umbral_waves.json"

const TORCH_ITEM_ID := "waves_torch"
const WAVES_DEFAULT_WEAPON_ID := "iron_sword"
const STARTER_WEAPON_IDS: Array[String] = ["iron_sword", "rogue_dagger", "hunter_bow", "sage_staff"]

const DEFAULT_FINAL_WAVE := 50
const DEFAULT_INTERMISSION_EVERY := 5
const DEFAULT_BOSS_EVERY := 10
const DEFAULT_CASH_OUT_FROM := 20

enum RunPhase { LOBBY, COMBAT, PREPARATION, REWARD }

var _final_wave := DEFAULT_FINAL_WAVE
var _intermission_every := DEFAULT_INTERMISSION_EVERY
var _boss_every := DEFAULT_BOSS_EVERY
var _cash_out_from := DEFAULT_CASH_OUT_FROM
var _arena_states: Array[String] = []

var current_wave: int = 0
var prep_active: bool = false
var lobby_ready: bool = false
var run_phase: RunPhase = RunPhase.LOBBY
var chests_opened: Dictionary = {}
var chest_set: int = 0
var torch_placed: bool = false
var torch_entitled: bool = false
var waves_inventory: GridInventory = GridInventory.new(8, 5)
var _kill_count := 0
var _run_seed := 0
var _cash_out_settled := false
var _victory_settled := false
var _definition: Dictionary = {}
var _chest_defs: Array = []
var _starter_choice_pending := false


func _ready() -> void:
	_bind_inventory_signals()
	_load_definition()


func _bind_inventory_signals() -> void:
	if waves_inventory == null:
		return
	if not waves_inventory.changed.is_connected(_on_waves_inventory_changed):
		waves_inventory.changed.connect(_on_waves_inventory_changed)


func _on_waves_inventory_changed() -> void:
	inventory_changed.emit()


func _load_definition() -> void:
	if not _definition.is_empty():
		return
	var data: Dictionary = ContentLoader.load_json(WAVES_DEFINITION_PATH)
	if data.is_empty():
		push_error("WavesRunService: failed to load %s" % WAVES_DEFINITION_PATH)
		return
	_definition = data
	_chest_defs = []
	for entry in data.get("chests", []):
		if entry is Dictionary:
			_chest_defs.append(entry)
	_final_wave = maxi(1, int(data.get("finalWave", DEFAULT_FINAL_WAVE)))
	_intermission_every = maxi(1, int(data.get("intermissionEvery", DEFAULT_INTERMISSION_EVERY)))
	_boss_every = maxi(1, int(data.get("bossEvery", DEFAULT_BOSS_EVERY)))
	_cash_out_from = maxi(1, int(data.get("cashOutFromWave", DEFAULT_CASH_OUT_FROM)))
	_arena_states = []
	for entry in data.get("arenaStates", []):
		_arena_states.append(str(entry))


func begin_new_run(run_seed: int = 0) -> void:
	current_wave = 0
	prep_active = false
	lobby_ready = false
	run_phase = RunPhase.LOBBY
	chests_opened.clear()
	chest_set = 0
	torch_placed = false
	torch_entitled = false
	_kill_count = 0
	_cash_out_settled = false
	_victory_settled = false
	_run_seed = run_seed if run_seed > 0 else randi_range(1, 2_147_483_646)
	waves_inventory = GridInventory.new(8, 5)
	_bind_inventory_signals()
	_seed_starter_weapon_choices()
	InventoryService.reset_waves_quick_slots()
	waves_changed.emit()


func restore_from_save(saved: Dictionary) -> void:
	current_wave = int(saved.get("currentWave", 0))
	prep_active = bool(saved.get("prepActive", false))
	lobby_ready = bool(saved.get("lobbyReady", false))
	run_phase = int(saved.get(
		"runPhase",
		RunPhase.PREPARATION if prep_active else (RunPhase.COMBAT if current_wave > 0 else RunPhase.LOBBY)
	)) as RunPhase
	_kill_count = int(saved.get("killCount", 0))
	_cash_out_settled = bool(saved.get("cashOutSettled", false))
	_victory_settled = bool(saved.get("victorySettled", false))
	_run_seed = int(saved.get("seed", 1))
	chest_set = int(saved.get("chestSet", 0))
	torch_placed = bool(saved.get("torchPlaced", false))
	torch_entitled = bool(saved.get("torchEntitled", false))
	var chests: Variant = saved.get("chestsOpened", {})
	chests_opened = chests if chests is Dictionary else {}
	var inv: Variant = saved.get("wavesInventory", {})
	if inv is Dictionary:
		waves_inventory.from_save_dict(inv)
	else:
		waves_inventory = GridInventory.new(8, 5)
		_bind_inventory_signals()
	InventoryService.restore_waves_quick_slots(saved.get("quickSlots", []))
	_starter_choice_pending = bool(saved.get("starterChoicePending", false))
	waves_changed.emit()


func get_seed() -> int:
	return _run_seed


## MD-01: `content/waves/umbral_waves.json:arenaStates` -- empty means "let the mutator use its
## own built-in rotation" rather than a hard failure, since a floor definition authored before this
## field existed should still get an arena that changes.
func get_arena_states() -> Array[String]:
	_ensure_definition()
	return _arena_states


func to_save_dict() -> Dictionary:
	return {
		"schemaVersion": 1,
		"runMode": "waves",
		"seed": _run_seed,
		"currentWave": current_wave,
		"prepActive": prep_active,
		"lobbyReady": lobby_ready,
		"runPhase": int(run_phase),
		"killCount": _kill_count,
		"cashOutSettled": _cash_out_settled,
		"victorySettled": _victory_settled,
		"chestSet": chest_set,
		"torchPlaced": torch_placed,
		"torchEntitled": torch_entitled,
		"starterChoicePending": _starter_choice_pending,
		"chestsOpened": chests_opened.duplicate(true),
		"wavesInventory": waves_inventory.to_save_dict(),
		"quickSlots": InventoryService.get_waves_quick_slots(),
	}


func get_chest_count() -> int:
	_ensure_definition()
	return _chest_defs.size()


func get_chest_label(index: int) -> String:
	if index < 0 or index >= _chest_defs.size():
		return ""
	var chest_def: Dictionary = _chest_defs[index]
	return str(chest_def.get("label", chest_def.get("id", "")))


func _chest_def_for_index(index: int) -> Dictionary:
	if index < 0 or index >= _chest_defs.size():
		return {}
	return _chest_defs[index]


func _chest_salt(index: int) -> int:
	return index + chest_set * 8191


## A fresh set of caches rises at every intermission. The torch hunt is a first-lobby ritual only —
## after that the cresset is already burning and the player just walks back to it when ready, so
## later intermissions are pure looting rather than a repeated fetch quest.
func begin_chest_set() -> void:
	chest_set += 1
	chests_opened.clear()
	torch_placed = true
	torch_entitled = false
	lobby_ready = true
	waves_changed.emit()


func is_first_lobby() -> bool:
	return chest_set <= 0


func get_torch_chest_index() -> int:
	_ensure_definition()
	var count := _chest_defs.size()
	if count <= 0:
		return -1
	var rng := RandomNumberGenerator.new()
	rng.seed = FloorSeedMix.mix(_run_seed, 60013 + chest_set * 31)
	return rng.randi_range(0, count - 1)


func has_torch() -> bool:
	if torch_entitled:
		return true
	for slot in waves_inventory.slots:
		if str(slot.get("itemId", "")) == TORCH_ITEM_ID:
			return true
	return false


func place_torch() -> bool:
	if torch_placed or not has_torch():
		return false
	waves_inventory.remove_items_by_id(TORCH_ITEM_ID, 1)
	torch_entitled = false
	torch_placed = true
	lobby_ready = true
	waves_changed.emit()
	return true


func open_chest(index: int) -> Dictionary:
	var key := str(index)
	if chests_opened.get(key, false):
		return {}
	var chest_def := _chest_def_for_index(index)
	if chest_def.is_empty():
		return {}
	var chest_type: String = str(chest_def.get("id", ""))
	if chest_type == "supplies":
		return _open_supplies_chest(index, chest_def)
	var salt := _chest_salt(index)
	var rarity := _roll_chest_rarity(chest_def, salt)
	var item_id := _roll_chest_item(chest_def, salt)
	if item_id == "":
		item_id = "health_potion"
	var roll_seed := FloorSeedMix.mix(
		_run_seed, salt * 997 + FloorSeedMix.stable_string_hash(rarity)
	)
	var working := GridInventory.new(waves_inventory.grid_width, waves_inventory.grid_height)
	working.from_save_dict(waves_inventory.to_save_dict())
	if not working.add_rolled_item_with_rarity(item_id, rarity, roll_seed):
		if not working.add_item(item_id, 1, {"rarity": rarity}):
			return {"error": "inventory full", "itemId": item_id, "rarity": rarity}
	waves_inventory.from_save_dict(working.to_save_dict())
	chests_opened[key] = true
	var torch_found := _grant_torch_if_hidden_here(index)
	waves_changed.emit()
	return {
		"itemId": item_id, "rarity": rarity, "chestType": chest_type, "torch": torch_found
	}


func _open_supplies_chest(index: int, chest_def: Dictionary) -> Dictionary:
	var key := str(index)
	if chests_opened.get(key, false):
		return {}
	var pool: Array = chest_def.get("pool", [])
	if pool.is_empty():
		return {}
	var multi: Dictionary = chest_def.get("multi_grant", {"min": 2, "max": 4})
	var rng := RandomNumberGenerator.new()
	rng.seed = _run_seed + _chest_salt(index) * 1597
	var item_count := rng.randi_range(int(multi.get("min", 2)), int(multi.get("max", 4)))
	var granted: Array[Dictionary] = []
	var working := GridInventory.new(waves_inventory.grid_width, waves_inventory.grid_height)
	working.from_save_dict(waves_inventory.to_save_dict())
	for i in item_count:
		var item_id := str(pool[rng.randi_range(0, pool.size() - 1)])
		var rarity := _roll_chest_rarity(chest_def, _chest_salt(index) + i * 17)
		var roll_seed := FloorSeedMix.mix(
			_run_seed, _chest_salt(index) * 997 + FloorSeedMix.stable_string_hash(rarity) + i * 131
		)
		if not working.add_rolled_item_with_rarity(item_id, rarity, roll_seed):
			if not working.add_item(item_id, 1, {"rarity": rarity}):
				return {"error": "inventory full", "items": granted}
		granted.append({"itemId": item_id, "rarity": rarity})
	waves_inventory.from_save_dict(working.to_save_dict())
	chests_opened[key] = true
	var torch_found := _grant_torch_if_hidden_here(index)
	waves_changed.emit()
	return {"items": granted, "chestType": "supplies", "torch": torch_found}


func _grant_torch_if_hidden_here(index: int) -> bool:
	if torch_placed or index != get_torch_chest_index():
		return false
	if has_torch():
		return false
	torch_entitled = true
	return true


func _roll_chest_rarity(chest_def: Dictionary, index: int) -> String:
	var weights: Dictionary = chest_def.get("rarity_weights", {"common": 100})
	var chest_type: String = str(chest_def.get("id", ""))
	var total := 0
	for rarity in weights:
		total += int(weights[rarity])
	var rng := RandomNumberGenerator.new()
	rng.seed = FloorSeedMix.mix(
		_run_seed, index * 313 + FloorSeedMix.stable_string_hash(chest_type)
	)
	if total <= 0:
		return "common"
	var roll := rng.randi_range(1, total)
	var cumulative := 0
	for rarity in RarityRegistryScript.TIER_ORDER:
		if not weights.has(rarity):
			continue
		cumulative += int(weights[rarity])
		if roll <= cumulative:
			return rarity
	return "common"


func _roll_chest_item(chest_def: Dictionary, index: int) -> String:
	var chest_type: String = str(chest_def.get("id", ""))
	var pool: Array = chest_def.get("pool", ["health_potion"]).duplicate()
	if chest_type == "weapons":
		pool = _filter_weapon_pool(pool)
	if pool.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = FloorSeedMix.mix(
		_run_seed, index * 997 + FloorSeedMix.stable_string_hash(chest_type)
	)
	return str(pool[rng.randi_range(0, pool.size() - 1)])


func _filter_weapon_pool(pool: Array) -> Array:
	var filtered: Array = []
	for item_id in pool:
		var def := ItemCatalog.get_definition(str(item_id))
		if def.get("itemType", "") != "weapon":
			continue
		if def.get("weaponId", "") == "":
			continue
		filtered.append(item_id)
	return filtered


func start_waves() -> void:
	if not lobby_ready or _starter_choice_pending:
		return
	current_wave = 1
	prep_active = false
	run_phase = RunPhase.COMBAT
	auto_equip_best_weapon()
	waves_changed.emit()


func starter_choice_pending() -> bool:
	return _starter_choice_pending


func starter_choice_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for item_id in STARTER_WEAPON_IDS:
		var index := -1
		for slot_index in waves_inventory.slots.size():
			if str(waves_inventory.slots[slot_index].get("itemId", "")) == item_id:
				index = slot_index
				break
		if index < 0:
			continue
		var slot: Dictionary = waves_inventory.slots[index]
		options.append({"itemId": item_id, "instanceId": str(slot.get("instanceId", "")), "weaponId": str(ItemCatalog.get_definition(item_id).get("weaponId", ""))})
	return options


func choose_starter_weapon(instance_id: String) -> bool:
	if not _starter_choice_pending:
		return false
	var index := waves_inventory.find_instance_index(instance_id)
	if index < 0 or str(waves_inventory.slots[index].get("itemId", "")) not in STARTER_WEAPON_IDS:
		return false
	if not waves_inventory.equip_weapon(index):
		return false
	_starter_choice_pending = false
	waves_changed.emit()
	return true


func _seed_starter_weapon_choices() -> void:
	for item_id in STARTER_WEAPON_IDS:
		if not waves_inventory.add_item(item_id, 1, {"rarity": "common"}):
			push_error("WavesRunService: unable to create starter weapon choice %s" % item_id)
			return
	_starter_choice_pending = true


## The Vigil starts you with nothing, so the first wave should not begin with a weapon sitting in
## the grid. This is an intentional safe default, never a misleading price comparison between
## different weapon verbs; the starter-choice UI owns build selection before this fallback.
func auto_equip_best_weapon() -> bool:
	if waves_inventory.get_equipped_weapon_id() != "":
		return false
	var fallback_index := -1
	for index in waves_inventory.slots.size():
		var slot: Dictionary = waves_inventory.slots[index]
		var def := ItemCatalog.get_definition(str(slot.get("itemId", "")))
		if def.get("itemType", "") != "weapon" or str(def.get("weaponId", "")) == "":
			continue
		if str(slot.get("itemId", "")) == WAVES_DEFAULT_WEAPON_ID:
			return waves_inventory.equip_weapon(index)
		if fallback_index < 0:
			fallback_index = index
	if fallback_index < 0:
		return false
	return waves_inventory.equip_weapon(fallback_index)


func advance_wave() -> void:
	current_wave += 1
	run_phase = RunPhase.COMBAT
	waves_changed.emit()


func enter_prep() -> void:
	prep_active = true
	run_phase = RunPhase.PREPARATION
	waves_changed.emit()


func leave_prep() -> void:
	prep_active = false
	run_phase = RunPhase.COMBAT
	waves_changed.emit()


func enter_reward_phase() -> void:
	prep_active = false
	run_phase = RunPhase.REWARD
	waves_changed.emit()


func is_reward_pending() -> bool:
	return run_phase == RunPhase.REWARD


func final_wave() -> int:
	_ensure_definition()
	return _final_wave


## Every fifth wave the walls come back up, a fresh set of caches rises, and the player gets to
## breathe and re-kit. The final wave never breaks — it ends the run instead.
func is_intermission_wave(wave: int) -> bool:
	_ensure_definition()
	return wave > 0 and wave < _final_wave and wave % _intermission_every == 0


## A warden walks every tenth wave, and on the last wave regardless.
func is_boss_wave(wave: int) -> bool:
	_ensure_definition()
	return wave > 0 and (wave == _final_wave or wave % _boss_every == 0)


## From here on an intermission also opens the wizard's portal, so the player can bank one item
## and walk away instead of losing the lot.
func is_cash_out_wave(wave: int) -> bool:
	_ensure_definition()
	return is_intermission_wave(wave) and wave >= _cash_out_from


func register_kill() -> void:
	_kill_count += 1


func get_kill_count() -> int:
	return _kill_count


## Every distinct item currently carried in the Vigil loadout, newest chest first, for the
## cash-out picker. Equipped pieces count — the player can bank the sword they are holding.
func get_cash_out_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var seen: Dictionary = {}
	for slot_name in waves_inventory.equipped:
		var equipped: Variant = waves_inventory.equipped[slot_name]
		if not equipped is Dictionary:
			continue
		_append_cash_out_option(options, seen, equipped as Dictionary, true)
	for slot in waves_inventory.slots:
		_append_cash_out_option(options, seen, slot, false)
	return options


func get_victory_reward_options() -> Array[Dictionary]:
	return get_cash_out_options()


func _append_cash_out_option(
	options: Array[Dictionary], seen: Dictionary, slot: Dictionary, is_equipped: bool
) -> void:
	var item_id := str(slot.get("itemId", ""))
	if item_id == "":
		return
	var rarity := waves_inventory.get_slot_rarity(slot)
	var instance_id := str(slot.get("instanceId", ""))
	if instance_id == "":
		return
	var key := instance_id
	if seen.has(key):
		return
	seen[key] = true
	options.append(
		{
			"instanceId": instance_id,
			"itemId": item_id,
			"rarity": rarity,
			"equipped": is_equipped,
			"displayName": waves_inventory.get_slot_display_name(slot),
			"quantity": int(slot.get("quantity", 1)),
		}
	)


func bank_victory_items(instance_ids: Array) -> Array[String]:
	if _victory_settled or not is_reward_pending() or current_wave < final_wave():
		return []
	if instance_ids.size() > 3:
		return []
	var seen: Dictionary = {}
	var target := InventoryService.inventory
	var working := GridInventory.new(target.grid_width, target.grid_height)
	working.from_save_dict(target.to_save_dict())
	var banked: Array[String] = []
	for raw_id in instance_ids:
		var instance_id := str(raw_id)
		if instance_id == "" or seen.has(instance_id):
			return []
		seen[instance_id] = true
		var source_slot := _source_slot_for_instance(instance_id)
		if source_slot.is_empty() or not working.add_slot(source_slot):
			return []
		banked.append(instance_id)
	if not instance_ids.is_empty() and banked.size() != instance_ids.size():
		return []
	target.from_save_dict(working.to_save_dict())
	_victory_settled = true
	return banked


func _source_slot_for_instance(instance_id: String) -> Dictionary:
	var source_index := waves_inventory.find_instance_index(instance_id)
	if source_index >= 0:
		return waves_inventory.slots[source_index].duplicate(true)
	for equipped in waves_inventory.equipped.values():
		if equipped is Dictionary and str(equipped.get("instanceId", "")) == instance_id:
			return equipped.duplicate(true)
	return {}


## Moves one chosen item out of the Vigil and into the character's real inventory.
func cash_out_item(instance_id: String) -> bool:
	if instance_id == "":
		return false
	var selected: Dictionary = {}
	for option in get_cash_out_options():
		if str(option.get("instanceId", "")) == instance_id:
			selected = option
			break
	if selected.is_empty():
		return false
	var source_slot: Dictionary = {}
	var source_index := waves_inventory.find_instance_index(instance_id)
	if source_index >= 0:
		source_slot = waves_inventory.slots[source_index].duplicate(true)
	else:
		for equipped in waves_inventory.equipped.values():
			if equipped is Dictionary and str(equipped.get("instanceId", "")) == instance_id:
				source_slot = equipped.duplicate(true)
				break
	if source_slot.is_empty() or not InventoryService.inventory.add_slot(source_slot):
		return false
	return true


## MD-02: banks each id in turn, returning only the ones that actually made it home -- a full bag
## can still strip one item out of an otherwise-successful cash-out, same as `cash_out_item()`.
func cash_out_items(item_ids: Array) -> Array[String]:
	var banked: Array[String] = []
	if _cash_out_settled or not prep_active or not is_cash_out_wave(current_wave):
		return banked
	var allowed := cash_out_bank_count(current_wave)
	if item_ids.is_empty() or item_ids.size() > allowed:
		return banked
	var seen: Dictionary = {}
	var target := InventoryService.inventory
	var working := GridInventory.new(target.grid_width, target.grid_height)
	working.from_save_dict(target.to_save_dict())
	for raw_id in item_ids:
		var instance_id := str(raw_id)
		if instance_id == "" or seen.has(instance_id):
			return []
		seen[instance_id] = true
		var source_slot: Dictionary = {}
		var source_index := waves_inventory.find_instance_index(instance_id)
		if source_index >= 0:
			source_slot = waves_inventory.slots[source_index].duplicate(true)
		else:
			for equipped in waves_inventory.equipped.values():
				if equipped is Dictionary and str(equipped.get("instanceId", "")) == instance_id:
					source_slot = equipped.duplicate(true)
					break
		if source_slot.is_empty() or not working.add_slot(source_slot):
			return []
		banked.append(instance_id)
	if banked.size() != item_ids.size():
		return []
	target.from_save_dict(working.to_save_dict())
	_cash_out_settled = true
	return banked


## MD-02: the offer escalates with depth so staying is a temptation, not just a greedy holdout --
## from wave 30 bank two, from wave 40 bank three.
func cash_out_bank_count(wave: int) -> int:
	if wave >= 40:
		return 3
	if wave >= 30:
		return 2
	return 1


## The roster slides rather than accumulates. If every band stayed in the pool forever, wave 50
## would still be mostly castle grunts by sheer weight of numbers and the escalation would read as
## noise. Keeping only the most recent bands means the player is still learning an unfamiliar
## moveset at wave 40, which is the whole reason the Vigil is fifty waves long.
const ROSTER_ACTIVE_BANDS := 3


func _roster_for_wave(wave: int) -> Array[String]:
	var unlocked: Array[Dictionary] = []
	for unlock in _definition.get("roster_unlocks", []):
		if not unlock is Dictionary:
			continue
		if wave >= int((unlock as Dictionary).get("wave", 0)):
			unlocked.append(unlock)
	unlocked.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("wave", 0)) < int(b.get("wave", 0))
	)
	var roster: Array[String] = []
	var active := unlocked.slice(maxi(0, unlocked.size() - ROSTER_ACTIVE_BANDS))
	for unlock in active:
		for enemy_id in unlock.get("ids", []):
			roster.append(str(enemy_id))
	# The castle roster is the mode's baseline and only fades out once three deeper bands are live.
	if active.size() < ROSTER_ACTIVE_BANDS or roster.is_empty():
		for enemy_id in _definition.get(
			"base_roster", ["castle_grunt", "castle_archer", "castle_shield", "castle_hound"]
		):
			roster.append(str(enemy_id))
	return roster


func _enemy_count_for_wave(wave: int) -> int:
	var count_cfg: Dictionary = _definition.get(
		"count", {"base": 3, "per_half_wave": 1, "cap": 14, "milestone_bonus": 2}
	)
	var count := mini(
		int(count_cfg.get("base", 3)) + (wave >> 1) * int(count_cfg.get("per_half_wave", 1)),
		int(count_cfg.get("cap", 14))
	)
	if is_boss_wave(wave):
		# A warden brings a smaller escort — the fight should be about the warden.
		count = maxi(2, count >> 1)
	elif is_intermission_wave(wave):
		count += int(count_cfg.get("milestone_bonus", 2))
	return count


## The wardens eligible at this wave: the deepest band the player has reached, so wave 50 does not
## roll the wave-10 captain.
func _bosses_for_wave(wave: int) -> Array[String]:
	var bands: Array = _definition.get("boss_unlocks", [])
	var best_wave := 0
	var best_ids: Array[String] = []
	for band in bands:
		if not band is Dictionary:
			continue
		var band_wave := int((band as Dictionary).get("wave", 0))
		if band_wave > wave or band_wave < best_wave:
			continue
		if band_wave > best_wave:
			best_ids.clear()
			best_wave = band_wave
		for enemy_id in (band as Dictionary).get("ids", []):
			best_ids.append(str(enemy_id))
	if best_ids.is_empty():
		for enemy_id in _definition.get("milestone_bosses", ["boss_castle_knight"]):
			best_ids.append(str(enemy_id))
	return best_ids


func get_enemies_for_wave(wave: int) -> Array[String]:
	_ensure_definition()
	var roster := _roster_for_wave(wave)
	var enemies: Array[String] = []
	if roster.is_empty():
		push_error("WavesRunService: empty roster at wave %d" % wave)
		return enemies
	var count := _enemy_count_for_wave(wave)
	var rng := RandomNumberGenerator.new()
	rng.seed = FloorSeedMix.mix(_run_seed, wave * 313)
	var candidates := _ordinary_enemy_candidates(roster)
	if candidates.is_empty():
		push_error("WavesRunService: no ordinary enemies in roster at wave %d" % wave)
		return enemies
	var introductions := _newly_unlocked_enemy_ids(wave, candidates)
	var ordinary_count := count
	for enemy_id in introductions:
		if enemies.size() >= ordinary_count:
			break
		enemies.append(enemy_id)
	while enemies.size() < ordinary_count:
		var eligible := _budget_eligible_candidates(candidates, enemies, ordinary_count)
		if eligible.is_empty():
			# Small rosters can make role caps mutually incompatible. Relax the fewest
			# concurrency limits possible, while keeping the authored threat budget hard.
			eligible = _least_violating_candidates(candidates, enemies, ordinary_count)
		enemies.append(str(eligible[rng.randi_range(0, eligible.size() - 1)]))
	if is_boss_wave(wave):
		var bosses := _bosses_for_wave(wave)
		if not bosses.is_empty():
			var boss_rng := RandomNumberGenerator.new()
			boss_rng.seed = FloorSeedMix.mix(_run_seed, wave * 911)
			enemies.append(str(bosses[boss_rng.randi_range(0, bosses.size() - 1)]))
	return enemies


func _ordinary_enemy_candidates(roster: Array[String]) -> Array[String]:
	var candidates: Array[String] = []
	for enemy_id in roster:
		var definition := EnemyCatalog.get_definition(enemy_id)
		if definition.is_empty() or str(definition.get("enemy_type", "melee")) == "boss":
			continue
		if enemy_id not in candidates:
			candidates.append(enemy_id)
	return candidates


func _newly_unlocked_enemy_ids(wave: int, candidates: Array[String]) -> Array[String]:
	var introductions: Array[String] = []
	for unlock in _definition.get("roster_unlocks", []):
		if not unlock is Dictionary or int(unlock.get("wave", -1)) != wave:
			continue
		for enemy_id_value in unlock.get("ids", []):
			var enemy_id := str(enemy_id_value)
			if enemy_id in candidates and enemy_id not in introductions:
				introductions.append(enemy_id)
	return introductions


func _enemy_budget_role(enemy_id: String) -> String:
	var definition := EnemyCatalog.get_definition(enemy_id)
	var enemy_type := str(definition.get("enemy_type", "melee"))
	if enemy_type == "ranged":
		return "ranged"
	if enemy_type == "shield":
		return "control"
	return "melee"


func _is_fast_enemy(enemy_id: String) -> bool:
	return float(EnemyCatalog.get_definition(enemy_id).get("move_speed", 0.0)) >= 5.0


func _is_long_reach_enemy(enemy_id: String) -> bool:
	var definition := EnemyCatalog.get_definition(enemy_id)
	var reach := maxf(
		float(definition.get("attack_range", 0.0)), float(definition.get("preferred_range", 0.0))
	)
	for attack in definition.get("attacks", []):
		if attack is Dictionary:
			reach = maxf(reach, float(attack.get("max_range", 0.0)))
	return reach >= 8.0


func _threat_cost(enemy_id: String) -> float:
	return maxf(0.0, float(EnemyCatalog.get_definition(enemy_id).get("threat_cost", 0.0)))


func _budget_eligible_candidates(
	candidates: Array[String], selected: Array[String], desired_count: int
) -> Array[String]:
	var budget: Dictionary = _definition.get("encounter_budget", {})
	var ranged_limit := ceili(float(budget.get("max_ranged_ratio", 0.35)) * desired_count)
	var fast_limit := ceili(float(budget.get("max_fast_ratio", 0.35)) * desired_count)
	var control_limit := ceili(float(budget.get("max_control_ratio", 0.25)) * desired_count)
	var long_reach_limit := ceili(float(budget.get("max_long_reach_ratio", 0.35)) * desired_count)
	var max_total_threat := float(budget.get("max_average_threat_cost", 35.0)) * desired_count
	var minimum_candidate_threat := INF
	for enemy_id in candidates:
		minimum_candidate_threat = minf(minimum_candidate_threat, _threat_cost(enemy_id))
	var ranged_count := 0
	var fast_count := 0
	var control_count := 0
	var long_reach_count := 0
	var melee_count := 0
	var threat_total := 0.0
	for enemy_id in selected:
		match _enemy_budget_role(enemy_id):
			"ranged": ranged_count += 1
			"control": control_count += 1
			_: melee_count += 1
		if _is_fast_enemy(enemy_id):
			fast_count += 1
		if _is_long_reach_enemy(enemy_id):
			long_reach_count += 1
		threat_total += _threat_cost(enemy_id)
	if melee_count < int(budget.get("min_melee_count", 1)):
		var melee_candidates: Array[String] = []
		for enemy_id in candidates:
			if _enemy_budget_role(enemy_id) == "melee":
				melee_candidates.append(enemy_id)
		if not melee_candidates.is_empty():
			return melee_candidates
	var eligible: Array[String] = []
	for enemy_id in candidates:
		var role := _enemy_budget_role(enemy_id)
		if role == "ranged" and ranged_count >= ranged_limit:
			continue
		if role == "control" and control_count >= control_limit:
			continue
		if _is_long_reach_enemy(enemy_id) and long_reach_count >= long_reach_limit:
			continue
		if _is_fast_enemy(enemy_id) and fast_count >= fast_limit:
			continue
		var remaining_slots := desired_count - selected.size() - 1
		var projected_minimum := threat_total + _threat_cost(enemy_id) + minimum_candidate_threat * remaining_slots
		if projected_minimum > max_total_threat:
			continue
		eligible.append(enemy_id)
	return eligible


func _least_violating_candidates(
	candidates: Array[String], selected: Array[String], desired_count: int
) -> Array[String]:
	var counts := {"melee": 0, "ranged": 0, "control": 0}
	var ranged_limit := ceili(float(_definition.get("encounter_budget", {}).get("max_ranged_ratio", 0.35)) * desired_count)
	var fast_limit := ceili(float(_definition.get("encounter_budget", {}).get("max_fast_ratio", 0.35)) * desired_count)
	var control_limit := ceili(float(_definition.get("encounter_budget", {}).get("max_control_ratio", 0.25)) * desired_count)
	var long_reach_limit := ceili(float(_definition.get("encounter_budget", {}).get("max_long_reach_ratio", 0.35)) * desired_count)
	var max_total_threat := float(_definition.get("encounter_budget", {}).get("max_average_threat_cost", 35.0)) * desired_count
	var selected_fast := 0
	var selected_long_reach := 0
	var selected_threat := 0.0
	for enemy_id in selected:
		var role := _enemy_budget_role(enemy_id)
		counts[role] = int(counts.get(role, 0)) + 1
		selected_fast += 1 if _is_fast_enemy(enemy_id) else 0
		selected_long_reach += 1 if _is_long_reach_enemy(enemy_id) else 0
		selected_threat += _threat_cost(enemy_id)
	var best_score := INF
	var fallback: Array[String] = []
	for enemy_id in candidates:
		var role := _enemy_budget_role(enemy_id)
		var score := float(counts.get(role, 0)) * 0.01
		if role == "ranged" and int(counts.ranged) >= ranged_limit:
			score += 100.0
		if role == "control" and int(counts.control) >= control_limit:
			score += 100.0
		if _is_fast_enemy(enemy_id) and selected_fast >= fast_limit:
			score += 100.0
		if _is_long_reach_enemy(enemy_id) and selected_long_reach >= long_reach_limit:
			score += 100.0
		var threat_excess := selected_threat + _threat_cost(enemy_id) - max_total_threat
		if threat_excess > 0.0:
			score += 1000.0 + threat_excess
		if score < best_score:
			best_score = score
			fallback.clear()
		if is_equal_approx(score, best_score):
			fallback.append(enemy_id)
	return fallback if not fallback.is_empty() else candidates


func apply_equipment_to_player(player: Node) -> void:
	if player == null:
		return
	InventoryService.apply_equipment_to_player_node(player, waves_inventory)


func _ensure_definition() -> void:
	if _definition.is_empty():
		_load_definition()

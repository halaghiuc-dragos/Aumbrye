extends Node


signal waves_changed
signal inventory_changed

const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const WAVES_DEFINITION_PATH := "content/waves/umbral_waves.json"

const TORCH_ITEM_ID := "waves_torch"

const DEFAULT_FINAL_WAVE := 50
const DEFAULT_INTERMISSION_EVERY := 5
const DEFAULT_BOSS_EVERY := 10
const DEFAULT_CASH_OUT_FROM := 20

var _final_wave := DEFAULT_FINAL_WAVE
var _intermission_every := DEFAULT_INTERMISSION_EVERY
var _boss_every := DEFAULT_BOSS_EVERY
var _cash_out_from := DEFAULT_CASH_OUT_FROM
var _arena_states: Array[String] = []

var current_wave: int = 0
var prep_active: bool = false
var lobby_ready: bool = false
var chests_opened: Dictionary = {}
var chest_set: int = 0
var torch_placed: bool = false
var waves_inventory: GridInventory = GridInventory.new(8, 5)
var _kill_count := 0
var _run_seed := 0
var _definition: Dictionary = {}
var _chest_defs: Array = []


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
	chests_opened.clear()
	chest_set = 0
	torch_placed = false
	_kill_count = 0
	_run_seed = run_seed if run_seed > 0 else randi_range(1, 2_147_483_646)
	waves_inventory = GridInventory.new(8, 5)
	_bind_inventory_signals()
	InventoryService.reset_waves_quick_slots()
	waves_changed.emit()


func restore_from_save(saved: Dictionary) -> void:
	current_wave = int(saved.get("currentWave", 0))
	prep_active = bool(saved.get("prepActive", false))
	lobby_ready = bool(saved.get("lobbyReady", false))
	_kill_count = int(saved.get("killCount", 0))
	_run_seed = int(saved.get("seed", 1))
	chest_set = int(saved.get("chestSet", 0))
	torch_placed = bool(saved.get("torchPlaced", false))
	var chests: Variant = saved.get("chestsOpened", {})
	chests_opened = chests if chests is Dictionary else {}
	var inv: Variant = saved.get("wavesInventory", {})
	if inv is Dictionary:
		waves_inventory.from_save_dict(inv)
	else:
		waves_inventory = GridInventory.new(8, 5)
	_bind_inventory_signals()
	InventoryService.restore_waves_quick_slots(saved.get("quickSlots", []))
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
		"killCount": _kill_count,
		"chestSet": chest_set,
		"torchPlaced": torch_placed,
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
	for slot in waves_inventory.slots:
		if str(slot.get("itemId", "")) == TORCH_ITEM_ID:
			return true
	return false


func place_torch() -> bool:
	if torch_placed or not has_torch():
		return false
	waves_inventory.remove_items_by_id(TORCH_ITEM_ID, 1)
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
	if not waves_inventory.add_rolled_item_with_rarity(item_id, rarity, roll_seed):
		waves_inventory.add_item(item_id, 1, {"rarity": rarity})
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
	for i in item_count:
		var item_id := str(pool[rng.randi_range(0, pool.size() - 1)])
		var rarity := _roll_chest_rarity(chest_def, _chest_salt(index) + i * 17)
		var roll_seed := FloorSeedMix.mix(
			_run_seed, _chest_salt(index) * 997 + FloorSeedMix.stable_string_hash(rarity) + i * 131
		)
		if not waves_inventory.add_rolled_item_with_rarity(item_id, rarity, roll_seed):
			waves_inventory.add_item(item_id, 1, {"rarity": rarity})
		granted.append({"itemId": item_id, "rarity": rarity})
	chests_opened[key] = true
	var torch_found := _grant_torch_if_hidden_here(index)
	waves_changed.emit()
	return {"items": granted, "chestType": "supplies", "torch": torch_found}


func _grant_torch_if_hidden_here(index: int) -> bool:
	if torch_placed or index != get_torch_chest_index():
		return false
	if has_torch():
		return false
	return waves_inventory.add_item(TORCH_ITEM_ID, 1)


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
	if not lobby_ready:
		return
	current_wave = 1
	prep_active = false
	auto_equip_best_weapon()
	waves_changed.emit()


## The Vigil starts you with nothing, so the first wave should not begin with a looted sword still
## sitting in the grid. If no weapon is equipped, put the best one found so far in your hand.
func auto_equip_best_weapon() -> bool:
	if waves_inventory.get_equipped_weapon_id() != "":
		return false
	var best_index := -1
	var best_value := -1.0
	for index in waves_inventory.slots.size():
		var slot: Dictionary = waves_inventory.slots[index]
		var def := ItemCatalog.get_definition(str(slot.get("itemId", "")))
		if def.get("itemType", "") != "weapon" or str(def.get("weaponId", "")) == "":
			continue
		var value := float(def.get("value", 0))
		if value > best_value:
			best_value = value
			best_index = index
	if best_index < 0:
		return false
	return waves_inventory.equip_weapon(best_index)


func advance_wave() -> void:
	current_wave += 1
	waves_changed.emit()


func enter_prep() -> void:
	prep_active = true
	waves_changed.emit()


func leave_prep() -> void:
	prep_active = false
	waves_changed.emit()


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


func _append_cash_out_option(
	options: Array[Dictionary], seen: Dictionary, slot: Dictionary, is_equipped: bool
) -> void:
	var item_id := str(slot.get("itemId", ""))
	if item_id == "":
		return
	var rarity := waves_inventory.get_slot_rarity(slot)
	var key := "%s|%s" % [item_id, rarity]
	if seen.has(key):
		return
	seen[key] = true
	options.append(
		{
			"itemId": item_id,
			"rarity": rarity,
			"equipped": is_equipped,
			"displayName": waves_inventory.get_slot_display_name(slot),
		}
	)


## Moves one chosen item out of the Vigil and into the character's real inventory.
func cash_out_item(item_id: String) -> bool:
	if item_id == "":
		return false
	var carried := false
	for option in get_cash_out_options():
		if str(option.get("itemId", "")) == item_id:
			carried = true
			break
	if not carried:
		return false
	if not InventoryService.add_item(item_id, 1):
		InventoryService.notify_reward_lost(item_id)
		return false
	return true


## MD-02: banks each id in turn, returning only the ones that actually made it home -- a full bag
## can still strip one item out of an otherwise-successful cash-out, same as `cash_out_item()`.
func cash_out_items(item_ids: Array) -> Array[String]:
	var banked: Array[String] = []
	for raw_id in item_ids:
		if cash_out_item(str(raw_id)):
			banked.append(str(raw_id))
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
	for _i in count:
		enemies.append(roster[rng.randi_range(0, roster.size() - 1)])
	if is_boss_wave(wave):
		var bosses := _bosses_for_wave(wave)
		if not bosses.is_empty():
			var boss_rng := RandomNumberGenerator.new()
			boss_rng.seed = FloorSeedMix.mix(_run_seed, wave * 911)
			enemies.append(str(bosses[boss_rng.randi_range(0, bosses.size() - 1)]))
	return enemies


func apply_equipment_to_player(player: Node) -> void:
	if player == null:
		return
	var stats := Equipment.aggregate_stats(
		waves_inventory.equipped, Callable(AffixRoller, "get_affix_stat")
	)
	var health := player.get_node_or_null("Health") as Health
	if health:
		var bonus_hp: float = float(stats.get("maxHealth", 0.0))
		health.configure(Health.MAX_HEALTH + bonus_hp, true)
	var weapon := player.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("load_weapon_from_path"):
		weapon.load_weapon_from_path(waves_inventory.get_equipped_weapon_data_path())
		if weapon.has_method("set_damage_multiplier"):
			var dmg_bonus: float = float(stats.get("damagePercent", 0.0))
			weapon.set_damage_multiplier(1.0 + dmg_bonus / 100.0)
	var locomotion := player as CharacterBody3D
	if locomotion and locomotion.has_method("set_speed_multiplier"):
		var move_bonus: float = float(stats.get("moveSpeedPercent", 0.0))
		locomotion.set_speed_multiplier(1.0 + move_bonus / 100.0)


func _ensure_definition() -> void:
	if _definition.is_empty():
		_load_definition()

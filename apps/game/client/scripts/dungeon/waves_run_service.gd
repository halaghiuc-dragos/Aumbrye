extends Node

## Autoload — Umbral Waves run state, isolated inventory, and save snapshot.

signal waves_changed
signal inventory_changed

const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const WAVES_DEFINITION_PATH := "content/waves/umbral_waves.json"

var MILESTONES: Array[int] = [5, 10, 20, 50]

var current_wave: int = 0
var prep_active: bool = false
var lobby_ready: bool = false
var chests_opened: Dictionary = {}
var waves_inventory: GridInventory = GridInventory.new(8, 5)
var _kill_count := 0
var _run_seed := 0
var _definition: Dictionary = {}
var _chest_defs: Array = []


func _ready() -> void:
	waves_inventory.changed.connect(func() -> void: inventory_changed.emit())
	_load_definition()


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
	var loaded_milestones: Variant = data.get("milestones", [])
	if loaded_milestones is Array and not (loaded_milestones as Array).is_empty():
		MILESTONES.clear()
		for wave in loaded_milestones:
			MILESTONES.append(int(wave))


func begin_new_run(run_seed: int = 0) -> void:
	current_wave = 0
	prep_active = false
	lobby_ready = false
	chests_opened.clear()
	_kill_count = 0
	_run_seed = run_seed if run_seed > 0 else randi_range(1, 2_147_483_646)
	waves_inventory = GridInventory.new(8, 5)
	waves_changed.emit()


func restore_from_save(saved: Dictionary) -> void:
	current_wave = int(saved.get("currentWave", 0))
	prep_active = bool(saved.get("prepActive", false))
	lobby_ready = bool(saved.get("lobbyReady", false))
	_kill_count = int(saved.get("killCount", 0))
	_run_seed = int(saved.get("seed", 1))
	var chests: Variant = saved.get("chestsOpened", {})
	chests_opened = chests if chests is Dictionary else {}
	var inv: Variant = saved.get("wavesInventory", {})
	if inv is Dictionary:
		waves_inventory.from_save_dict(inv)
	else:
		waves_inventory = GridInventory.new(8, 5)
	waves_changed.emit()


func to_save_dict() -> Dictionary:
	return {
		"schemaVersion": 1,
		"runMode": "waves",
		"seed": _run_seed,
		"currentWave": current_wave,
		"prepActive": prep_active,
		"lobbyReady": lobby_ready,
		"killCount": _kill_count,
		"chestsOpened": chests_opened.duplicate(true),
		"wavesInventory": waves_inventory.to_save_dict(),
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


func all_chests_opened() -> bool:
	for i in _chest_defs.size():
		if not chests_opened.get(str(i), false):
			return false
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
	var rarity := _roll_chest_rarity(chest_def, index)
	var item_id := _roll_chest_item(chest_def, index)
	if item_id == "":
		item_id = "health_potion"
	var roll_seed := _run_seed + index * 997 + rarity.hash()
	if not waves_inventory.add_rolled_item_with_rarity(item_id, rarity, roll_seed):
		waves_inventory.add_item(item_id, 1, {"rarity": rarity})
	chests_opened[key] = true
	waves_changed.emit()
	return {"itemId": item_id, "rarity": rarity, "chestType": chest_type}


func _open_supplies_chest(index: int, chest_def: Dictionary) -> Dictionary:
	var key := str(index)
	if chests_opened.get(key, false):
		return {}
	var pool: Array = chest_def.get("pool", [])
	if pool.is_empty():
		return {}
	var multi: Dictionary = chest_def.get("multi_grant", {"min": 2, "max": 4})
	var rng := RandomNumberGenerator.new()
	rng.seed = _run_seed + index * 1597
	var item_count := rng.randi_range(int(multi.get("min", 2)), int(multi.get("max", 4)))
	var granted: Array[Dictionary] = []
	for i in item_count:
		var item_id := str(pool[rng.randi_range(0, pool.size() - 1)])
		var rarity := _roll_chest_rarity(chest_def, index + i * 17)
		var roll_seed := _run_seed + index * 997 + rarity.hash() + i * 131
		if not waves_inventory.add_rolled_item_with_rarity(item_id, rarity, roll_seed):
			waves_inventory.add_item(item_id, 1, {"rarity": rarity})
		granted.append({"itemId": item_id, "rarity": rarity})
	chests_opened[key] = true
	waves_changed.emit()
	return {"items": granted, "chestType": "supplies"}


func _roll_chest_rarity(chest_def: Dictionary, index: int) -> String:
	var weights: Dictionary = chest_def.get("rarity_weights", {"common": 100})
	var chest_type: String = str(chest_def.get("id", ""))
	var total := 0
	for rarity in weights:
		total += int(weights[rarity])
	var rng := RandomNumberGenerator.new()
	rng.seed = _run_seed + index * 313 + chest_type.hash()
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
	rng.seed = _run_seed + index * 997 + chest_type.hash()
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


func mark_ready() -> void:
	if not all_chests_opened():
		return
	lobby_ready = true
	waves_changed.emit()


func start_waves() -> void:
	if not lobby_ready:
		return
	current_wave = 1
	prep_active = false
	waves_changed.emit()


func advance_wave() -> void:
	current_wave += 1
	waves_changed.emit()


func enter_prep() -> void:
	prep_active = true
	waves_changed.emit()


func leave_prep() -> void:
	prep_active = false
	waves_changed.emit()


func is_milestone(wave: int) -> bool:
	return wave in MILESTONES


func is_final_milestone() -> bool:
	return current_wave >= MILESTONES[MILESTONES.size() - 1]


func register_kill() -> void:
	_kill_count += 1


func get_kill_count() -> int:
	return _kill_count


func get_early_exit_keep_fraction() -> float:
	if current_wave >= 25:
		return 0.5
	if current_wave >= 10:
		return 0.25
	return 0.0


func transfer_early_exit_items(keep_fraction: float) -> Array[String]:
	if keep_fraction <= 0.0:
		return []
	var pool: Array[String] = []
	for slot in waves_inventory.slots:
		var item_id := str(slot.get("itemId", ""))
		if item_id != "":
			pool.append(item_id)
	if pool.is_empty():
		return []
	var keep_count := maxi(1, int(ceil(float(pool.size()) * keep_fraction)))
	keep_count = mini(keep_count, pool.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = _run_seed + current_wave * 701 + int(keep_fraction * 1000.0)
	var picked: Array[String] = []
	var working := pool.duplicate()
	for _i in keep_count:
		var idx := rng.randi_range(0, working.size() - 1)
		var item_id: String = working.pop_at(idx)
		if InventoryService.add_item(item_id, 1):
			picked.append(item_id)
	return picked


func _roster_for_wave(wave: int) -> Array[String]:
	var roster: Array[String] = []
	for enemy_id in _definition.get(
		"base_roster", ["castle_grunt", "castle_archer", "castle_shield", "castle_hound"]
	):
		roster.append(str(enemy_id))
	for unlock in _definition.get("roster_unlocks", []):
		if not unlock is Dictionary:
			continue
		if wave < int(unlock.get("wave", 0)):
			continue
		for enemy_id in unlock.get("ids", []):
			roster.append(str(enemy_id))
	return roster


func _enemy_count_for_wave(wave: int) -> int:
	var count_cfg: Dictionary = _definition.get(
		"count", {"base": 2, "per_half_wave": 1, "cap": 12, "milestone_bonus": 2}
	)
	var count := mini(
		int(count_cfg.get("base", 2)) + (wave >> 1) * int(count_cfg.get("per_half_wave", 1)),
		int(count_cfg.get("cap", 12))
	)
	if is_milestone(wave):
		count += int(count_cfg.get("milestone_bonus", 2))
	return count


func get_enemies_for_wave(wave: int) -> Array[String]:
	_ensure_definition()
	var count := _enemy_count_for_wave(wave)
	var roster := _roster_for_wave(wave)
	var enemies: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = _run_seed + wave * 313
	for i in count:
		enemies.append(roster[rng.randi_range(0, roster.size() - 1)])
	if is_milestone(wave):
		var milestone_bosses: Array = _definition.get(
			"milestone_bosses", ["boss_castle_knight", "miniboss_castle_captain"]
		)
		if not milestone_bosses.is_empty():
			var boss_rng := RandomNumberGenerator.new()
			boss_rng.seed = _run_seed + wave * 911
			enemies.append(
				str(milestone_bosses[boss_rng.randi_range(0, milestone_bosses.size() - 1)])
			)
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
		# BUG-13: same fix as InventoryService.apply_equipment_to_player_node — this is called
		# from the waves inventory UI on every equipment change, not only at wave start.
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

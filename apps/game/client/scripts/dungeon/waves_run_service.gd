extends Node

## Autoload — Umbral Waves run state, isolated inventory, and save snapshot.

signal waves_changed
signal inventory_changed

const MILESTONES: Array[int] = [5, 10, 20, 50]
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const CHEST_TYPES: Array[String] = ["potions", "scrolls", "armor", "rings", "weapons"]
const CHEST_TYPE_LABELS: Dictionary = {
	"potions": "Potions",
	"scrolls": "Buff Scrolls",
	"armor": "Armor",
	"rings": "Rings",
	"weapons": "Weapons",
}
const CHEST_RARITY_WEIGHTS: Dictionary = {
	"potions": {"common": 45, "magic": 35, "rare": 15, "epic": 5},
	"scrolls": {"common": 30, "magic": 35, "rare": 25, "epic": 8, "legendary": 2},
	"armor": {"common": 25, "magic": 30, "rare": 25, "epic": 15, "legendary": 5},
	"rings": {"magic": 30, "rare": 35, "epic": 25, "legendary": 8, "aumbral": 2},
	"weapons": {"rare": 30, "epic": 35, "legendary": 25, "aumbral": 10},
}
const CHEST_POOLS: Dictionary = {
	"potions": ["health_potion", "mana_potion", "stamina_potion"],
	"scrolls": ["elixir_might", "elixir_vigor", "mana_potion", "stamina_potion"],
	"armor": ["iron_boots", "iron_helm", "steel_plate", "steel_helm", "castle_plate", "castle_helm"],
	"rings": ["gold_ring", "silver_ring", "castle_ring", "ruby_amulet", "mythic_ring"],
	"weapons": ["iron_sword", "steel_sword", "knight_blade", "flame_sword", "war_hammer", "mythic_blade"],
}

var current_wave: int = 0
var prep_active: bool = false
var lobby_ready: bool = false
var chests_opened: Dictionary = {}
var waves_inventory: GridInventory = GridInventory.new(8, 5)
var _kill_count := 0
var _run_seed := 0


func _ready() -> void:
	waves_inventory.changed.connect(func() -> void:
		inventory_changed.emit()
	)


func begin_new_run() -> void:
	current_wave = 0
	prep_active = false
	lobby_ready = false
	chests_opened.clear()
	_kill_count = 0
	_run_seed = randi_range(1, 2_147_483_646)
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
	return CHEST_TYPES.size()


func get_chest_label(index: int) -> String:
	if index < 0 or index >= CHEST_TYPES.size():
		return ""
	var chest_type: String = CHEST_TYPES[index]
	return str(CHEST_TYPE_LABELS.get(chest_type, chest_type.capitalize()))


func all_chests_opened() -> bool:
	for i in CHEST_TYPES.size():
		if not chests_opened.get(str(i), false):
			return false
	return true


func open_chest(index: int) -> Dictionary:
	var key := str(index)
	if chests_opened.get(key, false):
		return {}
	if index < 0 or index >= CHEST_TYPES.size():
		return {}
	var chest_type: String = CHEST_TYPES[index]
	var rarity := _roll_chest_rarity(chest_type, index)
	var item_id := _roll_chest_item(chest_type, index)
	if item_id == "":
		item_id = "health_potion"
	var roll_seed := _run_seed + index * 997 + rarity.hash()
	if not waves_inventory.add_rolled_item_with_rarity(item_id, rarity, roll_seed):
		waves_inventory.add_item(item_id, 1, {"rarity": rarity})
	chests_opened[key] = true
	waves_changed.emit()
	return {"itemId": item_id, "rarity": rarity, "chestType": chest_type}


func _roll_chest_rarity(chest_type: String, index: int) -> String:
	var weights: Dictionary = CHEST_RARITY_WEIGHTS.get(chest_type, {"common": 100})
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


func _roll_chest_item(chest_type: String, index: int) -> String:
	var pool: Array = CHEST_POOLS.get(chest_type, CHEST_POOLS["potions"])
	var rng := RandomNumberGenerator.new()
	rng.seed = _run_seed + index * 997 + chest_type.hash()
	return str(pool[rng.randi_range(0, pool.size() - 1)])


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
	if is_milestone(current_wave):
		prep_active = true
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


func get_enemies_for_wave(wave: int) -> Array[String]:
	var count := mini(2 + (wave >> 1), 12)
	if is_milestone(wave):
		count += 2
	var roster := ["castle_grunt", "castle_archer", "castle_shield", "castle_hound"]
	if wave >= 5:
		roster.append("castle_knight")
	var enemies: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = _run_seed + wave * 313
	for i in count:
		enemies.append(roster[rng.randi_range(0, roster.size() - 1)])
	if wave == 5 or wave == 10 or wave == 20 or wave == 50:
		enemies.append("boss_castle_knight")
	return enemies


func apply_equipment_to_player(player: Node) -> void:
	if player == null:
		return
	var stats := Equipment.aggregate_stats(
		waves_inventory.equipped,
		Callable(AffixRoller, "get_affix_stat")
	)
	var health := player.get_node_or_null("Health") as Health
	if health:
		var bonus_hp: float = float(stats.get("maxHealth", 0.0))
		health.configure(Health.MAX_HEALTH + bonus_hp)
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

extends Node

## Autoload singleton — persisted grid inventory + equipment stats (M2/M4).

signal inventory_changed
signal equipment_stats_changed(stats: Dictionary)

var inventory: GridInventory = GridInventory.new()


func _ready() -> void:
	inventory.changed.connect(_on_inventory_changed)
	if RunBuffs:
		RunBuffs.buffs_changed.connect(_on_run_buffs_changed)
	if ProgressionService:
		ProgressionService.progression_changed.connect(_on_progression_changed)


func _on_inventory_changed() -> void:
	inventory_changed.emit()
	_apply_equipment_to_player()


func _on_run_buffs_changed() -> void:
	_apply_equipment_to_player()


func _on_progression_changed() -> void:
	_apply_equipment_to_player()


func add_item(item_id: String, quantity: int = 1) -> bool:
	var added := inventory.add_item(item_id, quantity)
	if added and RunFlow and RunFlow.is_run_active():
		var def := get_item_def(item_id)
		var relic_id: String = def.get("runRelicId", "")
		if relic_id != "" and RunBuffs:
			RunBuffs.add_relic(relic_id)
	return added


func add_rolled_item(item_id: String, roll_seed: int = -1) -> bool:
	var run_mode := RunFlow.get_run_mode() if RunFlow else ""
	return inventory.add_rolled_item(item_id, roll_seed, run_mode)


func get_item_def(item_id: String) -> Dictionary:
	return ItemCatalog.get_definition(item_id)


func get_save_inventory() -> Dictionary:
	return inventory.to_save_dict()


func apply_save_inventory(data: Dictionary) -> void:
	inventory.from_save_dict(data)
	_apply_equipment_to_player()


func get_equipment_stats() -> Dictionary:
	var equip_stats := Equipment.aggregate_stats(
		inventory.equipped,
		Callable(AffixRoller, "get_affix_stat")
	)
	var talent_stats := ProgressionService.get_talent_stat_totals() if ProgressionService else {}
	var run_stats := RunBuffs.get_stat_totals() if RunBuffs else {}
	return _merge_stat_dicts(_merge_stat_dicts(equip_stats, talent_stats), run_stats)


func compare_slot_to_equipped(index: int) -> Dictionary:
	if index < 0 or index >= inventory.slots.size():
		return {}
	var slot: Dictionary = inventory.slots[index]
	var def := get_item_def(slot.get("itemId", ""))
	var slot_name := Equipment.slot_for_item_def(def)
	if slot_name == "":
		return {}
	return Equipment.compare_stats(
		inventory.equipped,
		slot,
		Callable(AffixRoller, "get_affix_stat")
	)


func format_slot_tooltip(slot: Dictionary, compare_delta: Dictionary = {}) -> String:
	var lines: PackedStringArray = []
	lines.append(inventory.get_slot_display_name(slot))
	var def := get_item_def(slot.get("itemId", ""))
	if def.has("description"):
		lines.append(def.get("description", ""))
	var stats := Equipment.stats_for_instance(slot, Callable(AffixRoller, "get_affix_stat"))
	for stat in Equipment.STAT_KEYS:
		var line := Equipment.format_stat_line(stat, stats.get(stat, 0.0))
		if line != "":
			if compare_delta.has(stat) and not is_zero_approx(compare_delta[stat]):
				line += " (%s)" % Equipment.format_delta_line(stat, compare_delta[stat])
			lines.append(line)
	for affix in slot.get("affixes", []):
		if affix is Dictionary:
			lines.append("  %s +%s" % [affix.get("affixId", ""), affix.get("value", 0)])
	return "\n".join(lines)


func remove_run_loot(item_ids: Array) -> void:
	for item_id in item_ids:
		inventory.remove_items_by_id(str(item_id), 999)


func apply_equipment_to_player_node(player: Node) -> void:
	if player == null:
		return
	var stats := get_equipment_stats()
	var health := player.get_node_or_null("Health") as Health
	if health:
		var bonus_hp: float = float(stats.get("maxHealth", 0.0))
		health.configure(Health.MAX_HEALTH + bonus_hp)
	var weapon := player.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("load_weapon_from_path"):
		weapon.load_weapon_from_path(inventory.get_equipped_weapon_data_path())
		if weapon.has_method("set_damage_multiplier"):
			var dmg_bonus: float = float(stats.get("damagePercent", 0.0))
			weapon.set_damage_multiplier(1.0 + dmg_bonus / 100.0)
	var locomotion := player.get_node_or_null("Locomotion")
	if locomotion and locomotion.has_method("set_speed_multiplier"):
		var spd: float = float(stats.get("moveSpeedPercent", 0.0))
		locomotion.set_speed_multiplier(1.0 + spd / 100.0)
	equipment_stats_changed.emit(stats)


func _apply_equipment_to_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		apply_equipment_to_player_node(player)


func _merge_stat_dicts(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for stat in b:
		out[stat] = out.get(stat, 0.0) + float(b[stat])
	return out

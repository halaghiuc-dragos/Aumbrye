extends Node

## Autoload singleton — persisted grid inventory + equipment stats (M2/M4).

const RunModeConfigScript := preload("res://scripts/app/run_mode_config.gd")
const CombatStatModifiersScript := preload("res://scripts/combat/combat_stat_modifiers.gd")

signal inventory_changed
signal equipment_stats_changed(stats: Dictionary)

var inventory: GridInventory = GridInventory.new()
var quick_slot_indices: Array[int] = [-1, -1, -1]


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


func add_item(item_id: String, quantity: int = 1, instance_data: Dictionary = {}) -> bool:
	var added := inventory.add_item(item_id, quantity, instance_data)
	if added and RunFlow and RunFlow.is_run_active():
		var def := get_item_def(item_id)
		var relic_id: String = def.get("runRelicId", "")
		if relic_id != "" and RunBuffs:
			RunBuffs.add_relic(relic_id)
	return added


func add_dungeon_key(key_id: String, lock_id: String, label: String = "Dungeon Key") -> bool:
	return add_item(
		"dungeon_key",
		1,
		{"keyId": key_id, "lockId": lock_id, "keyLabel": label}
	)


func has_dungeon_key(key_id: String) -> bool:
	for slot in inventory.slots:
		if slot.get("itemId", "") != "dungeon_key":
			continue
		if str(slot.get("keyId", "")) == key_id:
			return true
	return false


func consume_dungeon_key(key_id: String) -> bool:
	for i in inventory.slots.size():
		var slot: Dictionary = inventory.slots[i]
		if slot.get("itemId", "") != "dungeon_key":
			continue
		if str(slot.get("keyId", "")) != key_id:
			continue
		var qty: int = int(slot.get("quantity", 1)) - 1
		if qty <= 0:
			inventory.slots.remove_at(i)
		else:
			slot["quantity"] = qty
		inventory.changed.emit()
		return true
	return false


func clear_dungeon_keys() -> void:
	var kept: Array[Dictionary] = []
	for slot in inventory.slots:
		if slot.get("itemId", "") == "dungeon_key":
			continue
		kept.append(slot)
	inventory.slots = kept
	inventory.changed.emit()


func add_rolled_item(item_id: String, roll_seed: int = -1) -> bool:
	var run_mode := RunFlow.get_run_mode() if RunFlow else ""
	return inventory.add_rolled_item(item_id, roll_seed, run_mode)


func get_item_def(item_id: String) -> Dictionary:
	return ItemCatalog.get_definition(item_id)


func get_save_inventory() -> Dictionary:
	var data := inventory.to_save_dict()
	data["quickSlots"] = quick_slot_indices.duplicate()
	return data


func apply_save_inventory(data: Dictionary) -> void:
	inventory.from_save_dict(data)
	_restore_quick_slots(data.get("quickSlots", []))
	_apply_equipment_to_player()


func get_equipment_stats() -> Dictionary:
	var equip_stats := Equipment.aggregate_stats(
		inventory.equipped,
		Callable(AffixRoller, "get_affix_stat")
	)
	var class_stats := ClassCatalog.get_stat_bonuses(CharacterService.class_id) if CharacterService else {}
	var talent_stats := ProgressionService.get_talent_stat_totals() if ProgressionService else {}
	var run_stats := RunBuffs.get_stat_totals() if RunBuffs else {}
	return _merge_stat_dicts(
		_merge_stat_dicts(_merge_stat_dicts(equip_stats, class_stats), talent_stats),
		run_stats
	)


func get_equipment_only_stats() -> Dictionary:
	return Equipment.aggregate_stats(
		inventory.equipped,
		Callable(AffixRoller, "get_affix_stat")
	)


func get_talent_stats() -> Dictionary:
	return ProgressionService.get_talent_stat_totals() if ProgressionService else {}


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


func get_class_stats() -> Dictionary:
	if CharacterService and CharacterService.class_id != "":
		return ClassCatalog.get_stat_bonuses(CharacterService.class_id)
	return {}


func apply_equipment_to_player_node(player: Node) -> void:
	if player == null:
		return
	var equip_stats := _merge_stat_dicts(get_equipment_only_stats(), get_class_stats())
	var talent_stats := get_talent_stats()
	var merged_stats := get_equipment_stats()
	var health := player.get_node_or_null("Health") as Health
	if health:
		var bonus_hp: float = float(merged_stats.get("maxHealth", 0.0))
		health.configure(Health.MAX_HEALTH + bonus_hp)
	var stamina := player.get_node_or_null("Stamina") as Stamina
	if stamina:
		var max_stamina := Stamina.MAX_STAMINA + CombatStatModifiersScript.max_stamina_bonus(equip_stats, talent_stats)
		stamina.configure(max_stamina, CombatStatModifiersScript.stamina_regen_multiplier(talent_stats))
	var poise := player.get_node_or_null("Poise") as Poise
	if poise:
		var max_poise := Poise.MAX_POISE + CombatStatModifiersScript.max_poise_bonus(equip_stats, talent_stats)
		poise.configure(max_poise)
	var weapon := player.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("load_weapon_from_path"):
		weapon.load_weapon_from_path(inventory.get_equipped_weapon_data_path())
		if weapon.has_method("set_combat_stat_modifiers"):
			weapon.set_combat_stat_modifiers(equip_stats, talent_stats, get_class_stats())
		elif weapon.has_method("set_damage_multiplier"):
			weapon.set_damage_multiplier(CombatStatModifiersScript.damage_multiplier(equip_stats, talent_stats))
	var locomotion := player.get_node_or_null("Locomotion")
	if locomotion and locomotion.has_method("set_speed_multiplier"):
		locomotion.set_speed_multiplier(CombatStatModifiersScript.move_speed_multiplier(equip_stats, talent_stats))
	var guard := player.get_node_or_null("Guard")
	if guard and guard.has_method("set_combat_stat_modifiers"):
		guard.set_combat_stat_modifiers(equip_stats, talent_stats)
	var defense_points := float(equip_stats.get("defense", 0.0)) + float(talent_stats.get("armor", 0.0))
	player.set_meta("combat_defense", defense_points)
	player.set_meta("combat_damage_reduction", float(talent_stats.get("damageReduction", 0.0)))
	equipment_stats_changed.emit(merged_stats)


func _apply_equipment_to_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		apply_equipment_to_player_node(player)


func set_quick_slot(quick_index: int, grid_index: int) -> void:
	if quick_index < 0 or quick_index > 2:
		return
	if grid_index < 0 or grid_index >= inventory.slots.size():
		quick_slot_indices[quick_index] = -1
	else:
		quick_slot_indices[quick_index] = grid_index
	if LocalSave:
		LocalSave.autosave()


func get_quick_slot_index(quick_index: int) -> int:
	if quick_index < 0 or quick_index >= quick_slot_indices.size():
		return -1
	return quick_slot_indices[quick_index]


func get_quick_slot_label(quick_index: int) -> String:
	var idx := get_quick_slot_index(quick_index)
	if idx < 0 or idx >= inventory.slots.size():
		return "Empty"
	return inventory.get_slot_display_name(inventory.slots[idx])


func activate_quick_slot(quick_index: int) -> bool:
	if RunFlow and RunModeConfigScript.is_waves(RunFlow.get_run_mode()):
		return false
	var idx := get_quick_slot_index(quick_index)
	if idx < 0 or idx >= inventory.slots.size():
		return false
	return _use_or_equip_index(idx)


func _use_or_equip_index(index: int) -> bool:
	if index < 0 or index >= inventory.slots.size():
		return false
	var slot: Dictionary = inventory.slots[index]
	var def := get_item_def(slot.get("itemId", ""))
	var item_type: String = def.get("itemType", "")
	if item_type in ["weapon", "armor", "accessory"]:
		if inventory.equip_from_index(index):
			_apply_equipment_to_player()
			return true
		return false
	if item_type == "consumable":
		return _use_consumable_at_index(index)
	return false


func _use_consumable_at_index(index: int) -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	var health := player.get_node_or_null("Health") as Health
	if health == null or health.is_dead():
		return false
	var def := inventory.consume_at(index)
	if def.is_empty():
		return false
	health.heal(def.get("healAmount", 30.0))
	return true


func _restore_quick_slots(raw: Variant) -> void:
	quick_slot_indices = [-1, -1, -1]
	if raw is Array:
		for i in mini(raw.size(), 3):
			quick_slot_indices[i] = int(raw[i])


func _merge_stat_dicts(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for stat in b:
		out[stat] = out.get(stat, 0.0) + float(b[stat])
	return out

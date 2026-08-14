extends Node

## Autoload singleton — persisted grid inventory + equipment stats (M2/M4).

const EquipmentHelper := preload("res://scripts/items/equipment.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const RunModeConfigScript := preload("res://scripts/app/run_mode_config.gd")
const CombatStatModifiersScript := preload("res://scripts/combat/combat_stat_modifiers.gd")
const CharacterSkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")
const PixelStyleScript := preload("res://scripts/art/style/pixel_diorama_style.gd")
const ConsumableServiceScript := preload("res://scripts/inventory/consumable_service.gd")
const WorldItemPickupScript := preload("res://scripts/inventory/world_item_pickup.gd")

signal inventory_changed
signal equipment_stats_changed(stats: Dictionary)
signal inventory_rejected(reason: String)

var inventory: GridInventory = GridInventory.new()
var quick_slot_instances: Array[String] = ["", "", "", ""]
var _registered_rule_sources: Array = []


func _ready() -> void:
	inventory.changed.connect(_on_inventory_changed)
	if RunBuffs:
		RunBuffs.buffs_changed.connect(_on_run_buffs_changed)
	if ProgressionService:
		ProgressionService.progression_changed.connect(_on_progression_changed)


func _on_inventory_changed() -> void:
	inventory_changed.emit()
	_check_full_equip_achievement()
	_sync_unique_rules()
	_apply_equipment_to_player()


func _sync_unique_rules() -> void:
	if not CombatEvents:
		return
	var wanted: Dictionary = {}
	for slot_name in EquipmentHelper.SLOT_ORDER:
		var instance: Dictionary = inventory.equipped.get(slot_name, {})
		if instance.is_empty():
			continue
		var item_id := str(instance.get("itemId", ""))
		var def := get_item_def(item_id)
		var rules: Variant = def.get("rules", [])
		if not rules is Array or (rules as Array).is_empty():
			continue
		wanted[_rule_source_id(item_id)] = rules
	for source_id in _registered_rule_sources:
		if not wanted.has(source_id):
			CombatEvents.unregister(str(source_id))
	for source_id in wanted:
		if not CombatEvents.is_registered(str(source_id)):
			CombatEvents.register(str(source_id), wanted[source_id])
	_registered_rule_sources = wanted.keys()


func _rule_source_id(item_id: String) -> String:
	return "item/%s" % item_id


func _on_run_buffs_changed() -> void:
	_apply_equipment_to_player()


func _on_progression_changed() -> void:
	_apply_equipment_to_player()


func add_item(item_id: String, quantity: int = 1, instance_data: Dictionary = {}) -> bool:
	var added := inventory.add_item(item_id, quantity, instance_data)
	if added:
		_on_item_added_success(item_id, instance_data)
	elif not get_item_def(item_id).is_empty():
		_emit_inventory_rejected("full")
	return added


func add_loot(item_id: String, opts: Dictionary = {}) -> bool:
	var def := get_item_def(item_id)
	if def.is_empty():
		_emit_inventory_rejected("unknown_item")
		return false

	var instance_data: Dictionary = {}
	if opts.get("instance_data") is Dictionary:
		instance_data = (opts.get("instance_data") as Dictionary).duplicate()

	var tag_run_loot := bool(opts.get("runLoot", RunFlow and RunFlow.is_run_active()))
	if tag_run_loot:
		instance_data["runLoot"] = true

	var quantity: int = int(opts.get("quantity", 1))
	var added := false
	if _should_roll_loot(def, bool(opts.get("roll", false))):
		# BUG-14: an explicit rollSeed (opts) is an intentional reproduce-this-exact-item
		# request and is reused verbatim across quantity — a natural loot roll instead mixes a
		# fresh per-drop ordinal into the seed on every unit, so two copies of the same item in
		# one run (or two units of one add_loot(quantity=N) call) do not roll identically.
		var explicit_seed: Variant = opts.get("rollSeed")
		var run_mode := RunFlow.get_run_mode() if RunFlow else ""
		for _i in quantity:
			var roll_seed := (
				int(explicit_seed) if explicit_seed != null else _loot_roll_seed(item_id)
			)
			added = inventory.add_rolled_item(item_id, roll_seed, run_mode, instance_data)
			if not added:
				break
			var placed: Dictionary = inventory.slots[inventory.slots.size() - 1]
			_on_item_added_success(item_id, placed)
	else:
		added = inventory.add_item(item_id, quantity, instance_data)
		if added:
			_on_item_added_success(item_id, instance_data)
		else:
			_emit_inventory_rejected("full")
			return false

	if not added:
		_emit_inventory_rejected("full")
	return added


func _should_roll_loot(def: Dictionary, force_roll: bool = false) -> bool:
	if force_roll:
		return true
	var item_type: String = def.get("itemType", "")
	if item_type in ["weapon", "armor", "accessory"]:
		return true
	return bool(def.get("rollAffixes", false))


## BUG-14: mixes a monotonic per-run drop ordinal into the seed so every natural drop is unique
## even for repeat copies of the same item — the previous formula was a pure function of
## (run seed, item_id), constant for the whole run, so every iron_greatsword drop in one run
## rolled the same rarity, the same affixes and the same instance id.
func _loot_roll_seed(item_id: String) -> int:
	if not RunFlow or RunFlow.current_seed <= 0:
		return -1
	var ordinal := RunFlow.next_loot_drop_ordinal()
	return (RunFlow.current_seed ^ (hash(item_id) * 2654435761) ^ (ordinal * 40503)) & 0x7fffffff


func _on_item_added_success(item_id: String, instance_data: Dictionary) -> void:
	if QuestService:
		QuestService.register_fetch(item_id)
	if RunFlow and RunFlow.is_run_active():
		var def := get_item_def(item_id)
		var relic_id: String = def.get("runRelicId", "")
		if relic_id != "" and RunBuffs:
			RunBuffs.add_relic(relic_id)
	_notify_item_obtained(item_id, instance_data)


func _emit_inventory_rejected(reason: String) -> void:
	inventory_rejected.emit(reason)


func _notify_item_obtained(item_id: String, instance_data: Dictionary) -> void:
	if not AchievementService:
		return
	var rarity := str(instance_data.get("rarity", ""))
	if rarity == "":
		rarity = str(get_item_def(item_id).get("rarity", "common"))
	AchievementService.notify("item_obtained", {"rarity": RarityRegistryScript.normalize(rarity)})
	_check_full_equip_achievement()


func _check_full_equip_achievement() -> void:
	if not AchievementService:
		return
	for slot_name in EquipmentHelper.SLOT_ORDER:
		var instance: Dictionary = inventory.equipped.get(slot_name, {})
		if instance.is_empty():
			return
	AchievementService.notify("equipment_full")


func add_dungeon_key(key_id: String, lock_id: String, label: String = "Dungeon Key") -> bool:
	return add_item("dungeon_key", 1, {"keyId": key_id, "lockId": lock_id, "keyLabel": label})


func has_dungeon_key(key_id: String) -> bool:
	return not inventory.find_slots_where(
		func(slot: Dictionary) -> bool:
			return slot.get("itemId", "") == "dungeon_key" and str(slot.get("keyId", "")) == key_id
	).is_empty()


func count_item(item_id: String) -> int:
	return inventory.count_by_id(item_id)


func consume_boss_sigil() -> bool:
	return inventory.remove_one_where(
		func(slot: Dictionary) -> bool: return slot.get("itemId", "") == "boss_sigil"
	)


func consume_dungeon_key(key_id: String) -> bool:
	return inventory.remove_one_where(
		func(slot: Dictionary) -> bool:
			return slot.get("itemId", "") == "dungeon_key" and str(slot.get("keyId", "")) == key_id
	)


func dungeon_keys_for_floor() -> Array[String]:
	var keys: Array[String] = []
	for i in inventory.find_slots_where(
		func(slot: Dictionary) -> bool: return slot.get("itemId", "") == "dungeon_key"
	):
		var key_id := str(inventory.slots[i].get("keyId", ""))
		if key_id != "":
			keys.append(key_id)
	return keys


func clear_dungeon_keys() -> void:
	var kept: Array[Dictionary] = []
	for slot in inventory.slots:
		if slot.get("itemId", "") == "dungeon_key":
			continue
		kept.append(slot)
	inventory.slots = kept
	inventory.changed.emit()


func apply_death_durability_loss(amount: int) -> void:
	if amount <= 0:
		return
	for slot_name in Equipment.SLOT_ORDER:
		var slot: Dictionary = inventory.equipped.get(slot_name, {})
		if slot.is_empty():
			continue
		var item_id: String = slot.get("itemId", "")
		var def := ItemCatalog.get_definition(item_id)
		if def.get("itemType", "") not in BlacksmithService.UPGRADEABLE_TYPES:
			continue
		var current := BlacksmithService.get_slot_durability(slot)
		slot["durability"] = maxi(0, current - amount)
	inventory.changed.emit()
	_apply_equipment_to_player()


func add_rolled_item(item_id: String, roll_seed: int = -1, instance_data: Dictionary = {}) -> bool:
	var run_mode := RunFlow.get_run_mode() if RunFlow else ""
	return inventory.add_rolled_item(item_id, roll_seed, run_mode, instance_data)


func get_item_def(item_id: String) -> Dictionary:
	return ItemCatalog.get_definition(item_id)


func get_save_inventory() -> Dictionary:
	var data := inventory.to_save_dict()
	data["quickSlotInstances"] = quick_slot_instances.duplicate()
	return data


func apply_save_inventory(data: Dictionary) -> void:
	inventory.from_save_dict(data)
	_restore_quick_slots(data.get("quickSlotInstances", data.get("quickSlots", [])))
	_apply_equipment_to_player()


func get_equipment_stats() -> Dictionary:
	var equip_stats := Equipment.aggregate_stats(
		inventory.equipped, Callable(AffixRoller, "get_affix_stat")
	)
	var class_stats := (
		ClassCatalog.get_stat_bonuses(CharacterService.class_id) if CharacterService else {}
	)
	var talent_stats := ProgressionService.get_talent_stat_totals() if ProgressionService else {}
	var run_stats := RunBuffs.get_stat_totals() if RunBuffs else {}
	var buff_stats := get_consumable_buff_stats()
	return _merge_stat_dicts(
		_merge_stat_dicts(
			_merge_stat_dicts(_merge_stat_dicts(equip_stats, class_stats), talent_stats), run_stats
		),
		buff_stats
	)


func get_consumable_buff_stats() -> Dictionary:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return {}
	return ConsumableServiceScript.active_buff_stats(player)


func get_equipment_only_stats() -> Dictionary:
	return Equipment.aggregate_stats(inventory.equipped, Callable(AffixRoller, "get_affix_stat"))


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
		inventory.equipped, slot, Callable(AffixRoller, "get_affix_stat")
	)


func format_slot_tooltip(slot: Dictionary, compare_delta: Dictionary = {}) -> String:
	var lines: PackedStringArray = []
	lines.append(inventory.get_slot_display_name(slot))
	var def := get_item_def(slot.get("itemId", ""))
	var subtitle := _format_item_subtitle(slot, def)
	if subtitle != "":
		lines.append(subtitle)
	if def.has("description"):
		lines.append(str(def.get("description", "")))
	var rule_text := str(def.get("ruleText", ""))
	if rule_text != "":
		lines.append("")
		lines.append(rule_text)
	var stats := Equipment.stats_for_instance(slot, Callable(AffixRoller, "get_affix_stat"))
	var stat_lines: PackedStringArray = []
	for stat in Equipment.STAT_KEYS:
		var line := Equipment.format_stat_line(stat, stats.get(stat, 0.0))
		if line == "":
			continue
		if compare_delta.has(stat) and not is_zero_approx(compare_delta[stat]):
			line += " (%s)" % Equipment.format_delta_line(stat, compare_delta[stat])
		stat_lines.append(line)
	if not stat_lines.is_empty():
		lines.append("")
		lines.append_array(stat_lines)
	var affix_lines: PackedStringArray = []
	for affix in slot.get("affixes", []):
		if not affix is Dictionary:
			continue
		var affix_line := AffixRoller.format_affix_line(affix)
		if affix_line != "":
			affix_lines.append(affix_line)
	if not affix_lines.is_empty():
		lines.append("")
		lines.append_array(affix_lines)
	var footer := _format_item_footer(slot, def)
	if footer != "":
		lines.append("")
		lines.append(footer)
	return "\n".join(lines)


func _format_item_subtitle(slot: Dictionary, def: Dictionary) -> String:
	var parts: PackedStringArray = []
	var slot_name := Equipment.slot_for_item_def(def)
	if slot_name != "":
		parts.append(slot_name.capitalize())
	var infusion := Equipment.infusion_label(str(slot.get("infusion", "")))
	if infusion != "":
		parts.append(infusion)
	var upgrade_level := int(slot.get("upgradeLevel", 0))
	if upgrade_level > 0:
		parts.append(
			"%s +%d" % [Equipment.upgrade_path_label(str(slot.get("upgradePath", ""))), upgrade_level]
		)
	var scaling: Variant = def.get("scaling", {})
	if scaling is Dictionary and not (scaling as Dictionary).is_empty():
		var grades: PackedStringArray = []
		for attribute in scaling:
			grades.append("%s %s" % [str(attribute).capitalize(), str(scaling[attribute])])
		parts.append(" ".join(grades))
	return "  ".join(parts)


func _format_item_footer(slot: Dictionary, def: Dictionary) -> String:
	if def.get("itemType", "") not in BlacksmithService.UPGRADEABLE_TYPES:
		return ""
	var item_id := str(slot.get("itemId", ""))
	var current := BlacksmithService.get_slot_durability(slot)
	var maximum := BlacksmithService.get_max_durability(item_id)
	if current <= 0:
		return tr("INV_DURABILITY_BROKEN")
	return tr("INV_DURABILITY") % [current, maximum]


func format_comparison_bbcode(slot: Dictionary) -> String:
	var def := get_item_def(slot.get("itemId", ""))
	var slot_name := Equipment.slot_for_item_def(def)
	if slot_name == "":
		return ""
	var resolver := Callable(AffixRoller, "get_affix_stat")
	var equipped_instance: Dictionary = inventory.equipped.get(slot_name, {})
	if equipped_instance.is_empty() or equipped_instance.get("instanceId", "") == slot.get(
		"instanceId", ""
	):
		return ""
	var current := Equipment.slot_stats(equipped_instance, resolver)
	var candidate := Equipment.slot_stats(slot, resolver)
	var lines: PackedStringArray = []
	var title: String = tr("INV_COMPARE_TITLE") % inventory.get_slot_display_name(equipped_instance)
	lines.append("[b]%s[/b]" % title)
	for stat in Equipment.STAT_KEYS:
		var new_value := float(candidate.get(stat, 0.0))
		var old_value := float(current.get(stat, 0.0))
		if is_zero_approx(new_value) and is_zero_approx(old_value):
			continue
		var delta := new_value - old_value
		var row := (
			"%s  %s → %s"
			% [
				Equipment.stat_display_name(stat),
				Equipment.format_stat_value(stat, old_value, false),
				Equipment.format_stat_value(stat, new_value, false),
			]
		)
		if is_zero_approx(delta):
			lines.append(row)
		else:
			var color := "#7fd67f" if delta > 0.0 else "#e07a7a"
			row += "  [color=%s]%s[/color]" % [color, Equipment.format_stat_value(stat, delta)]
			lines.append(row)
	if lines.size() <= 1:
		return ""
	return "\n".join(lines)


func remove_run_loot(item_ids: Array) -> void:
	var id_set: Dictionary = {}
	for raw_id in item_ids:
		id_set[str(raw_id)] = true
	for item_id in item_ids:
		inventory.remove_items_by_id(str(item_id), 999)
	inventory.strip_equipped_run_loot(id_set)
	_apply_equipment_to_player()


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
		# BUG-13: preserve_ratio=true — this path runs on every inventory change (add, remove,
		# move, split, sort all emit `changed`), so refilling here would full-heal the player
		# for free on any pickup, mid-fight.
		health.configure(Health.MAX_HEALTH + bonus_hp, true)
	var stamina := player.get_node_or_null("Stamina") as Stamina
	if stamina:
		var max_stamina := (
			Stamina.MAX_STAMINA
			+ CombatStatModifiersScript.max_stamina_bonus(equip_stats, talent_stats)
		)
		stamina.configure(
			max_stamina, CombatStatModifiersScript.stamina_regen_multiplier(equip_stats, talent_stats)
		)
	var poise := player.get_node_or_null("Poise") as Poise
	if poise:
		var max_poise := (
			Poise.MAX_POISE + CombatStatModifiersScript.max_poise_bonus(equip_stats, talent_stats)
		)
		var break_dur := float(get_class_stats().get("poise_break_duration", 1.2))
		# BUG-13: preserve_ratio=true for the same reason as Health above — this must not clear
		# an in-progress stagger build-up just because the inventory changed.
		poise.configure(max_poise, break_dur, true)
	var mana := player.get_node_or_null("Mana") as Mana
	if mana:
		var max_mana := (
			Mana.MAX_MANA + CombatStatModifiersScript.max_mana_bonus(equip_stats, talent_stats)
		)
		mana.configure(max_mana, CombatStatModifiersScript.mana_regen_multiplier(equip_stats, talent_stats))
	var weapon := player.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("load_weapon_from_path"):
		weapon.load_weapon_from_path(inventory.get_equipped_weapon_data_path())
		if weapon.has_method("set_combat_stat_modifiers"):
			weapon.set_combat_stat_modifiers(equip_stats, talent_stats, get_class_stats())
		elif weapon.has_method("set_damage_multiplier"):
			weapon.set_damage_multiplier(
				CombatStatModifiersScript.damage_multiplier(equip_stats, talent_stats)
			)
	var locomotion: Node = PlayerControls.resolve_locomotion(player) if PlayerControls else null
	if locomotion and locomotion.has_method("set_speed_multiplier"):
		locomotion.set_speed_multiplier(
			CombatStatModifiersScript.move_speed_multiplier(equip_stats, talent_stats)
		)
	var dodge := player.get_node_or_null("Dodge")
	if dodge and dodge.has_method("set_stamina_cost_multiplier"):
		dodge.set_stamina_cost_multiplier(
			CombatStatModifiersScript.stamina_cost_multiplier(equip_stats, talent_stats)
		)
	var guard := player.get_node_or_null("Guard")
	if guard and guard.has_method("set_combat_stat_modifiers"):
		var shield_inst := inventory.get_equipped_instance("secondary")
		var block_data: Dictionary = {}
		if not shield_inst.is_empty():
			var shield_def := get_item_def(str(shield_inst.get("itemId", "")))
			block_data = shield_def.get("block", {})
		guard.set_combat_stat_modifiers(equip_stats, talent_stats, block_data)
	var defense_points := CombatStatModifiersScript.defense_points(equip_stats, talent_stats)
	player.set_meta("combat_defense", defense_points)
	player.set_meta(
		"combat_damage_reduction",
		CombatStatModifiersScript.damage_reduction(equip_stats, talent_stats)
	)
	(
		player
		. set_meta(
			"combat_resistances",
			{
				DamageInfo.TYPE_PHYSICAL:
				clampf(float(merged_stats.get("resistPhysical", 0.0)), 0.0, 0.85),
				DamageInfo.TYPE_FIRE: clampf(float(merged_stats.get("resistFire", 0.0)), 0.0, 0.85),
				DamageInfo.TYPE_FROST:
				clampf(float(merged_stats.get("resistFrost", 0.0)), 0.0, 0.85),
				DamageInfo.TYPE_POISON:
				clampf(float(merged_stats.get("resistPoison", 0.0)), 0.0, 0.85),
				DamageInfo.TYPE_LIGHTNING:
				clampf(float(merged_stats.get("resistLightning", 0.0)), 0.0, 0.85),
				DamageInfo.TYPE_ARCANE:
				clampf(float(merged_stats.get("resistArcane", 0.0)), 0.0, 0.85),
			}
		)
	)
	_apply_equipment_visuals(player)
	equipment_stats_changed.emit(merged_stats)


func _apply_equipment_visuals(player: Node) -> void:
	var facing := player.get_node_or_null("Facing") as Node3D
	if facing == null:
		return
	var visual := facing.get_node_or_null(CharacterSkinScript.VISUAL_NAME) as Node3D
	if visual == null:
		return
	var theme := PixelStyleScript.PaletteTheme.HUB
	if CharacterService:
		theme = CharacterService.appearance_theme
	CharacterSkinScript.apply_equipment(visual, inventory.equipped, theme)


func _apply_equipment_to_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		apply_equipment_to_player_node(player)


func try_use_slot_index(index: int) -> Dictionary:
	if index < 0 or index >= inventory.slots.size():
		return {"ok": false, "reason": ""}
	var slot: Dictionary = inventory.slots[index]
	var def := get_item_def(str(slot.get("itemId", "")))
	if def.get("itemType", "") == "consumable":
		var in_run := RunFlow != null and RunFlow.is_run_active()
		var in_hub := not in_run
		var guard := ConsumableServiceScript.can_use(def, in_run, in_hub)
		if not bool(guard.get("ok", false)):
			return guard
	if _use_or_equip_index(index):
		return {"ok": true, "reason": ""}
	return {"ok": false, "reason": tr("INV_USE_FAILED")}


func set_quick_slot(quick_index: int, instance_id: String) -> void:
	if quick_index < 0 or quick_index > 3:
		return
	quick_slot_instances[quick_index] = instance_id if instance_id != "" else ""
	if LocalSave:
		LocalSave.request_autosave()


func get_quick_slot_index(quick_index: int) -> int:
	if quick_index < 0 or quick_index >= quick_slot_instances.size():
		return -1
	return inventory.find_instance_index(quick_slot_instances[quick_index])


func get_quick_slot_instance_id(quick_index: int) -> String:
	if quick_index < 0 or quick_index >= quick_slot_instances.size():
		return ""
	return quick_slot_instances[quick_index]


func get_quick_slot_label(quick_index: int) -> String:
	var idx := get_quick_slot_index(quick_index)
	if idx < 0 or idx >= inventory.slots.size():
		return "Empty"
	return inventory.get_slot_display_name(inventory.slots[idx])


func activate_quick_slot(quick_index: int) -> String:
	if RunFlow and RunModeConfigScript.is_waves(RunFlow.get_run_mode()):
		return ""
	var idx := get_quick_slot_index(quick_index)
	if idx < 0 or idx >= inventory.slots.size():
		return ""
	var slot: Dictionary = inventory.slots[idx]
	var item_id := str(slot.get("itemId", ""))
	if _use_or_equip_index(idx):
		return item_id
	return ""


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
	var slot: Dictionary = inventory.slots[index]
	var def := get_item_def(slot.get("itemId", ""))
	var in_run := RunFlow != null and RunFlow.is_run_active()
	var in_hub := not in_run
	var guard := ConsumableServiceScript.can_use(def, in_run, in_hub)
	if not bool(guard.get("ok", false)):
		return false
	if not ConsumableServiceScript.apply(def, player):
		return false
	inventory.consume_at(index)
	return true


func drop_slot_at_index(index: int) -> bool:
	if index < 0 or index >= inventory.slots.size():
		return false
	var slot: Dictionary = inventory.slots[index]
	var item_id: String = str(slot.get("itemId", ""))
	var qty: int = int(slot.get("quantity", 1))
	if RunFlow and RunFlow.is_run_active():
		var player := get_tree().get_first_node_in_group("player")
		if player == null:
			return false
		var removed := inventory.remove_at(index)
		if removed.is_empty():
			return false
		_spawn_world_pickup(
			player.global_position, item_id, qty, inventory.get_slot_rarity(removed)
		)
		return true
	var result := MerchantService.sell_item(index, qty)
	return bool(result.get("ok", false))


func split_stack_at_index(index: int) -> bool:
	return inventory.split_stack(index)


static func migrate_quick_slots_from_indices(slots: Array, quick_slots: Array) -> Array[String]:
	var instances: Array[String] = ["", "", "", ""]
	for i in mini(quick_slots.size(), 4):
		var idx := int(quick_slots[i])
		if idx < 0 or idx >= slots.size():
			continue
		var slot: Variant = slots[idx]
		if slot is Dictionary:
			instances[i] = str(slot.get("instanceId", ""))
	return instances


func _spawn_world_pickup(
	world_pos: Vector3, item_id: String, quantity: int, rarity: String = ""
) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var pickup: Area3D = WorldItemPickupScript.new()
	pickup.name = "DroppedItemPickup"
	root.add_child(pickup)
	pickup.global_position = world_pos + Vector3(0, 0.5, 1.0)
	pickup.configure(item_id, quantity, rarity)


func _restore_quick_slots(raw: Variant) -> void:
	quick_slot_instances = ["", "", "", ""]
	if raw is Array:
		if not raw.is_empty() and raw[0] is String:
			for i in mini(raw.size(), 4):
				quick_slot_instances[i] = str(raw[i])
			return
		quick_slot_instances = migrate_quick_slots_from_indices(inventory.slots, raw)


func _merge_stat_dicts(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for stat in b:
		out[stat] = out.get(stat, 0.0) + float(b[stat])
	return out

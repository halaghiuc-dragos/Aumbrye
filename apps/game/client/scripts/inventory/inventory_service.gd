extends Node


const EquipmentHelper := preload("res://scripts/items/equipment.gd")
const ItemQualityScript := preload("res://scripts/items/item_quality.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const RunModeConfigScript := preload("res://scripts/app/run_mode_config.gd")
const CombatStatModifiersScript := preload("res://scripts/combat/combat_stat_modifiers.gd")
const CharacterSkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")
const PixelStyleScript := preload("res://scripts/art/style/pixel_diorama_style.gd")
const PlayerControlsScript := preload("res://scripts/app/player_controls.gd")
const ConsumableServiceScript := preload("res://scripts/inventory/consumable_service.gd")

## Same green and red the equipped-stat comparison already uses, so "better" and "worse" read the
## same way wherever the player sees them.
const CONDITION_GOOD_COLOR := "#7fd67f"
const CONDITION_POOR_COLOR := "#e07a7a"
const CONDITION_NEUTRAL_COLOR := "#c9c2b4"
const WorldItemPickupScript := preload("res://scripts/inventory/world_item_pickup.gd")

signal inventory_changed
signal equipment_stats_changed(stats: Dictionary)
signal inventory_rejected(reason: String)
signal quick_slots_changed

var inventory: GridInventory = GridInventory.new()
var quick_slot_instances: Array[String] = ["", "", "", ""]
var waves_quick_slot_instances: Array[String] = ["", "", "", ""]
var _registered_rule_sources: Array = []
var _applying_status_refresh := false


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
		var instance_id := str(instance.get("instanceId", ""))
		var def := get_item_def(item_id)
		var rules: Variant = def.get("rules", [])
		if rules is Array and not (rules as Array).is_empty():
			wanted[_rule_source_id(item_id, instance_id)] = rules
		# A rolled behavioural affix carries its own rules, registered separately from the item's
		# so two instances of the same base with different rolls do not collide.
		var affix_rules := AffixRoller.rules_for_instance(instance)
		if not affix_rules.is_empty():
			wanted["affix/%s#%s" % [item_id, instance_id]] = affix_rules
	for source_id in _registered_rule_sources:
		if not wanted.has(source_id):
			CombatEvents.unregister(str(source_id))
	for source_id in wanted:
		if not CombatEvents.is_registered(str(source_id)):
			CombatEvents.register(str(source_id), wanted[source_id])
	_registered_rule_sources = wanted.keys()


func _rule_source_id(item_id: String, instance_id: String = "") -> String:
	if instance_id == "":
		return "item/%s" % item_id
	return "item/%s#%s" % [item_id, instance_id]


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


func notify_reward_lost(item_id: String) -> void:
	push_warning("InventoryService: reward '%s' could not be granted — inventory full" % item_id)
	_emit_inventory_rejected("full")


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


func count_dungeon_keys(key_id: String) -> int:
	return inventory.find_slots_where(
		func(slot: Dictionary) -> bool:
			return slot.get("itemId", "") == "dungeon_key" and str(slot.get("keyId", "")) == key_id
	).size()


func consume_dungeon_key(key_id: String) -> bool:
	return inventory.remove_one_where(
		func(slot: Dictionary) -> bool:
			return slot.get("itemId", "") == "dungeon_key" and str(slot.get("keyId", "")) == key_id
	)


func clear_dungeon_keys() -> void:
	inventory.remove_all_where(
		func(slot: Dictionary) -> bool: return slot.get("itemId", "") == "dungeon_key"
	)


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
	var status_stats := get_status_buff_stats()
	return _merge_stat_dicts(
		_merge_stat_dicts(
			_merge_stat_dicts(
				_merge_stat_dicts(_merge_stat_dicts(equip_stats, class_stats), talent_stats),
				run_stats
			),
			buff_stats
		),
		status_stats
	)


func get_combat_aggregate_stats() -> Dictionary:
	var stats := _merge_stat_dicts(get_equipment_only_stats(), get_class_stats())
	if RunBuffs:
		stats = _merge_stat_dicts(stats, RunBuffs.get_stat_totals())
	stats = _merge_stat_dicts(stats, get_consumable_buff_stats())
	return _merge_stat_dicts(stats, get_status_buff_stats())


func get_status_buff_stats() -> Dictionary:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return {}
	var controller := player.get_node_or_null("StatusController")
	if controller == null or not controller.has_method("get_stat_totals"):
		return {}
	return controller.call("get_stat_totals")


func get_consumable_buff_stats() -> Dictionary:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return {}
	return ConsumableServiceScript.active_buff_stats(player)


func get_equipment_only_stats() -> Dictionary:
	return Equipment.aggregate_stats(inventory.equipped, Callable(AffixRoller, "get_affix_stat"))


func get_talent_stats() -> Dictionary:
	return ProgressionService.get_talent_stat_totals() if ProgressionService else {}


const STAT_COLOR_BETTER := "#7fd67f"
const STAT_COLOR_WORSE := "#e07a7a"
const STAT_COLOR_EQUAL := "#e0cf7a"

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


## The item's condition, on a line of its own.
##
## It used to be appended to the subtitle beside the slot name, the infusion and the upgrade level,
## where it read as one more word in a run-on and was easy to miss entirely -- and the neutral tier
## was left out altogether, so most items said nothing about an axis that is always there. Naming
## it, always, is what makes the player aware the axis exists at all; a "Balanced" that says +0% is
## worth a line, because it tells them the roll could have gone either way.
func _format_condition_line(slot: Dictionary) -> String:
	var quality := str(slot.get("quality", ""))
	if quality == "" or not ItemQualityScript.exists(quality):
		return ""
	var delta := ItemQualityScript.stat_multiplier(quality) - 1.0
	var percent := roundi(delta * 100.0)
	var colour := CONDITION_NEUTRAL_COLOR
	if percent > 0:
		colour = CONDITION_GOOD_COLOR
	elif percent < 0:
		colour = CONDITION_POOR_COLOR
	return "%s [color=%s]%s[/color] [color=%s](%+d%% base stats)[/color]" % [
		tr("INV_CONDITION"),
		colour,
		_escape_bbcode(ItemQualityScript.display_name(quality)),
		colour,
		percent,
	]


## `include_name` defaults to true for callers (storage's description panel, the audit tool) that
## show this text on its own with nowhere else the item's name appears. `inventory_ui` renders that
## name a second time, as a separately-styled title above this body — pass false there or the name
## prints twice.
func format_slot_tooltip_bbcode(slot: Dictionary, include_name: bool = true) -> String:
	var def := get_item_def(slot.get("itemId", ""))
	var resolver := Callable(AffixRoller, "get_affix_stat")
	var lines: PackedStringArray = []
	if include_name:
		lines.append("[b]%s[/b]" % _escape_bbcode(inventory.get_slot_display_name(slot)))
	var subtitle := _format_item_subtitle(slot, def)
	if subtitle != "":
		lines.append(_escape_bbcode(subtitle))
	var condition := _format_condition_line(slot)
	if condition != "":
		lines.append(condition)
	if def.has("description"):
		lines.append(_escape_bbcode(str(def.get("description", ""))))
	var rule_text := str(def.get("ruleText", ""))
	if rule_text != "":
		lines.append("")
		lines.append(_escape_bbcode(rule_text))

	var equipped_stats: Dictionary = {}
	var slot_name := Equipment.slot_for_item_def(def)
	var is_worn := false
	if slot_name != "":
		var worn: Dictionary = inventory.equipped.get(slot_name, {})
		is_worn = (
			not worn.is_empty()
			and str(worn.get("instanceId", "")) == str(slot.get("instanceId", ""))
		)
		if not worn.is_empty() and not is_worn:
			equipped_stats = Equipment.slot_stats(worn, resolver)

	var stats := Equipment.stats_for_instance(slot, resolver)
	var keys: Array[String] = []
	for stat in Equipment.STAT_KEYS:
		if is_zero_approx(float(stats.get(stat, 0.0))) and is_zero_approx(
			float(equipped_stats.get(stat, 0.0))
		):
			continue
		keys.append(stat)
	if not keys.is_empty():
		lines.append("")
		for stat in keys:
			var value := float(stats.get(stat, 0.0))
			var line := Equipment.format_stat_line(stat, value)
			if line == "":
				line = "%s %s" % [
					Equipment.format_stat_value(stat, 0.0, false),
					Equipment.stat_display_name(stat),
				]
			if equipped_stats.is_empty():
				lines.append(_escape_bbcode(line))
				continue
			var delta := value - float(equipped_stats.get(stat, 0.0))
			var color := STAT_COLOR_EQUAL
			if delta > 0.0001:
				color = STAT_COLOR_BETTER
			elif delta < -0.0001:
				color = STAT_COLOR_WORSE
			lines.append("[color=%s]%s[/color]" % [color, _escape_bbcode(line)])

	var affix_lines: PackedStringArray = []
	for affix in slot.get("affixes", []):
		if not affix is Dictionary:
			continue
		var affix_line := AffixRoller.format_affix_line(affix)
		if affix_line != "":
			affix_lines.append(_escape_bbcode(affix_line))
	if not affix_lines.is_empty():
		lines.append("")
		lines.append_array(affix_lines)
	var footer := _format_item_footer(slot, def)
	if footer != "":
		lines.append("")
		lines.append(_escape_bbcode(footer))
	if not equipped_stats.is_empty():
		lines.append("")
		lines.append("[i]%s[/i]" % _escape_bbcode(_comparison_caption(slot_name)))
	return "\n".join(lines)


func _comparison_caption(slot_name: String) -> String:
	var worn: Dictionary = inventory.equipped.get(slot_name, {})
	var worn_name := inventory.get_slot_display_name(worn)
	var class_id := str(CharacterService.class_id) if CharacterService else ""
	var class_def := ClassCatalog.get_definition(class_id)
	var class_name_text := str(class_def.get("displayName", ""))
	if class_name_text == "":
		return tr("INV_COMPARE_TITLE") % worn_name
	return "%s  -  %s" % [tr("INV_COMPARE_TITLE") % worn_name, class_name_text]


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")

func remove_run_loot(_item_ids: Array = []) -> void:
	var doomed: Array[int] = inventory.find_slots_where(
		func(slot: Dictionary) -> bool: return bool(slot.get("runLoot", false))
	)
	doomed.sort()
	doomed.reverse()
	for index in doomed:
		inventory.remove_at(index)
	inventory.strip_equipped_run_loot()
	_apply_equipment_to_player()


func get_class_stats() -> Dictionary:
	if CharacterService and CharacterService.class_id != "":
		return ClassCatalog.get_stat_bonuses(CharacterService.class_id)
	return {}


func _bind_status_stat_refresh(player: Node) -> void:
	var controller := player.get_node_or_null("StatusController")
	if controller == null or not controller.has_signal("statuses_changed"):
		return
	if not controller.statuses_changed.is_connected(_on_player_statuses_changed):
		controller.statuses_changed.connect(_on_player_statuses_changed)


func _on_player_statuses_changed() -> void:
	if _applying_status_refresh:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return
	_applying_status_refresh = true
	apply_equipment_to_player_node(player)
	_applying_status_refresh = false


func apply_equipment_to_player_node(player: Node) -> void:
	if player == null:
		return
	_bind_status_stat_refresh(player)
	var equip_stats := get_combat_aggregate_stats()
	var talent_stats := get_talent_stats()
	var merged_stats := get_equipment_stats()
	var health := player.get_node_or_null("Health") as Health
	if health:
		var bonus_hp: float = CombatStatModifiersScript.soften_health_bonus(
			float(merged_stats.get("maxHealth", 0.0))
		)
		health.configure(Health.MAX_HEALTH + bonus_hp, true)
	var stamina := player.get_node_or_null("Stamina") as Stamina
	if stamina:
		var max_stamina := (
			Stamina.MAX_STAMINA
			+ CombatStatModifiersScript.max_stamina_bonus(equip_stats, talent_stats)
		)
		stamina.configure(
			max_stamina,
			CombatStatModifiersScript.stamina_regen_multiplier(equip_stats, talent_stats),
			true
		)
	var poise := player.get_node_or_null("Poise") as Poise
	if poise:
		var max_poise := (
			Poise.MAX_POISE + CombatStatModifiersScript.max_poise_bonus(equip_stats, talent_stats)
		)
		var break_dur := float(get_class_stats().get("poise_break_duration", 1.2))
		poise.configure(max_poise, break_dur, true)
	var mana := player.get_node_or_null("Mana") as Mana
	if mana:
		var max_mana := (
			Mana.MAX_MANA + CombatStatModifiersScript.max_mana_bonus(equip_stats, talent_stats)
		)
		mana.configure(
			max_mana,
			CombatStatModifiersScript.mana_regen_multiplier(equip_stats, talent_stats),
			true
		)
	var weapon := player.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("load_weapon_from_path"):
		weapon.load_weapon_from_path(inventory.get_equipped_weapon_data_path())
		if weapon.has_method("set_infusion"):
			weapon.call("set_infusion", str(inventory.get_equipped_weapon_infusion()))
		if weapon.has_method("set_combat_stat_modifiers"):
			weapon.set_combat_stat_modifiers(equip_stats, talent_stats, get_class_stats())
		elif weapon.has_method("set_damage_multiplier"):
			weapon.set_damage_multiplier(
				CombatStatModifiersScript.damage_multiplier(equip_stats, talent_stats)
			)
	var locomotion: Node = PlayerControlsScript.resolve_locomotion(player)
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
		"combat_evasion", CombatStatModifiersScript.evasion_chance(equip_stats, talent_stats)
	)
	player.set_meta(
		"combat_health_regen", CombatStatModifiersScript.health_regen(equip_stats, talent_stats)
	)
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
		theme = CharacterService.appearance_theme as PixelStyleScript.PaletteTheme
	CharacterSkinScript.apply_equipment(visual, inventory.equipped, theme)
	# Refitting gear builds fresh `EquipVisual_*` holders, and new geometry draws normally no matter
	# what the parts around it were set to. Equipping a helmet while in first person therefore put a
	# helmet inside the camera. The camera owns this state, so re-assert it against the rebuilt tree.
	var spring := player.get_node_or_null("CameraPivot/SpringArm3D")
	if spring and spring.has_method("is_first_person"):
		CharacterSkinScript.apply_first_person(facing, bool(spring.call("is_first_person")))


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


## The Vigil runs on its own loadout: nothing carried in from the hub, and nothing looted inside it
## leaks back out except through the summoner. Everything quick-slot related therefore has to point
## at whichever inventory is currently in play, or the potions the player just pulled out of a
## cache would be unusable while their hub potions sat uselessly on the bar.
func is_waves_context() -> bool:
	return RunFlow != null and RunModeConfigScript.is_waves(RunFlow.get_run_mode())


func active_inventory() -> GridInventory:
	if is_waves_context() and WavesRunService != null:
		return WavesRunService.waves_inventory
	return inventory


func _active_quick_slots() -> Array[String]:
	return waves_quick_slot_instances if is_waves_context() else quick_slot_instances


func reset_waves_quick_slots() -> void:
	waves_quick_slot_instances = ["", "", "", ""]
	quick_slots_changed.emit()


func get_waves_quick_slots() -> Array[String]:
	return waves_quick_slot_instances.duplicate()


func restore_waves_quick_slots(raw: Variant) -> void:
	waves_quick_slot_instances = ["", "", "", ""]
	if raw is Array:
		for i in mini((raw as Array).size(), 4):
			waves_quick_slot_instances[i] = str((raw as Array)[i])
	quick_slots_changed.emit()


func set_quick_slot(quick_index: int, instance_id: String) -> void:
	if quick_index < 0 or quick_index > 3:
		return
	_active_quick_slots()[quick_index] = instance_id if instance_id != "" else ""
	quick_slots_changed.emit()
	if LocalSave and not is_waves_context():
		LocalSave.request_autosave()


func get_quick_slot_index(quick_index: int) -> int:
	var slots := _active_quick_slots()
	if quick_index < 0 or quick_index >= slots.size():
		return -1
	return active_inventory().find_instance_index(slots[quick_index])


func get_quick_slot_label(quick_index: int) -> String:
	var target := active_inventory()
	var idx := get_quick_slot_index(quick_index)
	if idx < 0 or idx >= target.slots.size():
		return "Empty"
	return target.get_slot_display_name(target.slots[idx])


func activate_quick_slot(quick_index: int) -> String:
	var target := active_inventory()
	var idx := get_quick_slot_index(quick_index)
	if idx < 0 or idx >= target.slots.size():
		return ""
	var slot: Dictionary = target.slots[idx]
	var item_id := str(slot.get("itemId", ""))
	if _use_or_equip_index(idx):
		return item_id
	return ""


func _use_or_equip_index(index: int) -> bool:
	var target := active_inventory()
	if index < 0 or index >= target.slots.size():
		return false
	var slot: Dictionary = target.slots[index]
	var def := get_item_def(slot.get("itemId", ""))
	var item_type: String = def.get("itemType", "")
	if item_type in ["weapon", "armor", "accessory"]:
		if target.equip_from_index(index):
			_apply_active_equipment_to_player()
			return true
		return false
	if item_type == "consumable":
		return _use_consumable_at_index(index)
	return false


## Re-applies whichever loadout is live. In the Vigil that is the run's own inventory, so equipping
## a looted sword takes effect immediately without touching the character's real gear.
func _apply_active_equipment_to_player() -> void:
	if is_waves_context() and WavesRunService != null:
		var player := get_tree().get_first_node_in_group("player")
		if player != null:
			WavesRunService.apply_equipment_to_player(player)
		return
	_apply_equipment_to_player()


func _use_consumable_at_index(index: int) -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	var target := active_inventory()
	if index < 0 or index >= target.slots.size():
		return false
	var slot: Dictionary = target.slots[index]
	var def := get_item_def(slot.get("itemId", ""))
	var in_run := RunFlow != null and RunFlow.is_run_active()
	var in_hub := not in_run
	var guard := ConsumableServiceScript.can_use(def, in_run, in_hub)
	if not bool(guard.get("ok", false)):
		return false
	if not ConsumableServiceScript.apply(def, player):
		return false
	target.consume_at(index)
	return true


func drop_slot_at_index(index: int) -> bool:
	if index < 0 or index >= inventory.slots.size():
		return false
	var slot: Dictionary = inventory.slots[index]
	var item_id: String = str(slot.get("itemId", ""))
	var qty: int = int(slot.get("quantity", 1))
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	var removed := inventory.remove_at(index)
	if removed.is_empty():
		return false
	_spawn_world_pickup(player.global_position, item_id, qty, inventory.get_slot_rarity(removed))
	return true


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
	pickup.set_despawn_after_drop()


func _restore_quick_slots(raw: Variant) -> void:
	quick_slot_instances = ["", "", "", ""]
	if raw is Array:
		if not raw.is_empty() and raw[0] is String:
			for i in mini(raw.size(), 4):
				quick_slot_instances[i] = str(raw[i])
			quick_slots_changed.emit()
			return
		quick_slot_instances = migrate_quick_slots_from_indices(inventory.slots, raw)
	quick_slots_changed.emit()


func _merge_stat_dicts(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for stat in b:
		out[stat] = out.get(stat, 0.0) + float(b[stat])
	return out


## Equips `item_id` as the weapon, granting it first if the warden does not already carry one.
## The save load path, the hub's starting-weapon guard and the loadout screen each had their own
## copy; only the loadout one skipped a redundant re-equip, which is kept here for all three.
func equip_weapon_item(item_id: String) -> void:
	if inventory.get_equipped_weapon_id() == item_id:
		return
	for i in inventory.slots.size():
		if inventory.slots[i].get("itemId", "") == item_id:
			inventory.equip_weapon(i)
			return
	if inventory.add_item(item_id, 1):
		inventory.equip_weapon(inventory.slots.size() - 1)

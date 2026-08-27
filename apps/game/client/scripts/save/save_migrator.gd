extends RefCounted
class_name SaveMigrator


const CURRENT_VERSION := 12
const NIL_ACCOUNT_ID := "00000000-0000-4000-8000-000000000000"
const TALENT_TREE_PATH := "content/talents/tree.json"

const RESULT_CURRENT := 0
const RESULT_MIGRATABLE := 1
const RESULT_TOO_NEW := 2
const RESULT_UNKNOWN := 3

const ACCOUNT_SCOPE_FLAG_IDS: Array[String] = [
	"dungeon_max_tier",
	"dungeon_unlocked_count",
	"bestiary_kills",
	"bestiary_studied_count",
	"bestiary_mastered_count",
	"bestiary_complete",
	"discoveries_found",
]

const ACCOUNT_SCOPE_FLAG_PREFIXES: Array[String] = [
	"theme_",
	"lore_",
]

const WORLD_FLAG_NAMESPACES: Array[String] = [
	"lock",
	"lever",
	"door",
	"room",
	"secret",
	"chest",
	"trap",
]

const STEPS: Array[Dictionary] = [
	{"from": 1, "to": 2, "fn": "_migrate_v1_to_v2", "summary": "activeRun floor fields"},
	{
		"from": 2,
		"to": 3,
		"fn": "_migrate_v2_to_v3",
		"summary": "activeRun.runMode; drop floorDefinitions"
	},
	{
		"from": 3,
		"to": 4,
		"fn": "_migrate_v3_to_v4",
		"summary": "lastCheckpoint; snapshot.worldFlags"
	},
	{
		"from": 4,
		"to": 5,
		"fn": "_migrate_v4_to_v5",
		"summary": "typed sections; equipped instances; accountId reset",
	},
	{
		"from": 5,
		"to": 6,
		"fn": "_migrate_v5_to_v6",
		"summary": "meta.achievements mythic_loot renamed to aumbral_loot",
	},
	{
		"from": 6,
		"to": 7,
		"fn": "_migrate_v6_to_v7",
		"summary": "dungeon_unlocked_count and per-dungeon difficulty tiers",
	},
	{
		"from": 7,
		"to": 8,
		"fn": "_migrate_v7_to_v8",
		"summary": "meta.accessibility camera settings defaults",
	},
	{
		"from": 8,
		"to": 9,
		"fn": "_migrate_v8_to_v9",
		"summary": "meta.display block; ui_scale moved from accessibility",
	},
	{
		"from": 9,
		"to": 10,
		"fn": "_migrate_v9_to_v10",
		"summary": "inventory.quickSlotInstances replaces quickSlots index array",
	},
	{
		"from": 10,
		"to": 11,
		"fn": "_migrate_v10_to_v11",
		"summary": "currencies.coins collapsed into currencies.gold",
	},
	{
		"from": 11,
		"to": 12,
		"fn": "_migrate_v11_to_v12",
		"summary": "account scope block; talent ids revalidated against the grown tree",
	},
]

static func classify(data: Dictionary) -> int:
	var version := int(data.get("schemaVersion", 0))
	if version == CURRENT_VERSION:
		return RESULT_CURRENT
	if version > CURRENT_VERSION:
		return RESULT_TOO_NEW
	if version < 1:
		return RESULT_UNKNOWN
	return RESULT_MIGRATABLE


static func plan(from_version: int) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	var version := from_version
	for step in STEPS:
		var from_v: int = int(step["from"])
		var to_v: int = int(step["to"])
		if version < from_v:
			continue
		if version >= to_v:
			continue
		steps.append(step.duplicate())
		version = to_v
	return steps


static func describe(from_version: int) -> String:
	var parts: PackedStringArray = []
	for step in plan(from_version):
		parts.append("v%d→v%d: %s" % [step["from"], step["to"], step["summary"]])
	return ", ".join(parts)


static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("schemaVersion", 0))
	if version == CURRENT_VERSION:
		return data.duplicate(true)
	if version > CURRENT_VERSION:
		return _fail(
			data,
			"too_new",
			"schemaVersion %d is newer than supported %d" % [version, CURRENT_VERSION]
		)
	if version == 0:
		return _fail(data, "missing_version", "missing schemaVersion")

	var working: Dictionary = data.duplicate(true)
	version = int(working.get("schemaVersion", 0))
	for step in STEPS:
		var from_v: int = int(step["from"])
		var to_v: int = int(step["to"])
		if version < from_v:
			continue
		if version >= to_v:
			continue
		working = _run_step(step, working)
		var after: int = int(working.get("schemaVersion", 0))
		if after != to_v:
			return _fail(
				data,
				"step_error",
				"step %d->%d did not advance version (got %d)" % [from_v, to_v, after]
			)
		version = after

	if version != CURRENT_VERSION:
		return _fail(data, "unknown_version", "unsupported schemaVersion %d" % version)
	return working


static func _run_step(step: Dictionary, data: Dictionary) -> Dictionary:
	match str(step["fn"]):
		"_migrate_v1_to_v2":
			return _migrate_v1_to_v2(data)
		"_migrate_v2_to_v3":
			return _migrate_v2_to_v3(data)
		"_migrate_v3_to_v4":
			return _migrate_v3_to_v4(data)
		"_migrate_v4_to_v5":
			return _migrate_v4_to_v5(data)
		"_migrate_v5_to_v6":
			return _migrate_v5_to_v6(data)
		"_migrate_v6_to_v7":
			return _migrate_v6_to_v7(data)
		"_migrate_v7_to_v8":
			return _migrate_v7_to_v8(data)
		"_migrate_v8_to_v9":
			return _migrate_v8_to_v9(data)
		"_migrate_v9_to_v10":
			return _migrate_v9_to_v10(data)
		"_migrate_v10_to_v11":
			return _migrate_v10_to_v11(data)
		"_migrate_v11_to_v12":
			return _migrate_v11_to_v12(data)
		_:
			return data


static func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy["schemaVersion"] = 2
	var active: Variant = copy.get("activeRun", {})
	if active is Dictionary and not active.is_empty():
		var run: Dictionary = active
		if not run.has("currentFloor"):
			run["currentFloor"] = 1
		if not run.has("maxFloors"):
			run["maxFloors"] = RunFloorConfig.MAX_FLOORS
		if not run.has("floorDefinitions"):
			run["floorDefinitions"] = {}
		copy["activeRun"] = run
	return copy


static func _migrate_v2_to_v3(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy["schemaVersion"] = 3
	var active: Variant = copy.get("activeRun", {})
	if active is Dictionary and not active.is_empty():
		var run: Dictionary = active
		if not run.has("runMode"):
			run["runMode"] = "castle"
		run.erase("floorDefinitions")
		copy["activeRun"] = run
	return copy


static func _migrate_v3_to_v4(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy["schemaVersion"] = 4
	var active: Variant = copy.get("activeRun", {})
	if active is Dictionary and not active.is_empty():
		var run: Dictionary = active
		if not run.has("lastCheckpoint"):
			run["lastCheckpoint"] = {}
		var snapshot: Variant = run.get("snapshot", {})
		if snapshot is Dictionary and not snapshot.has("worldFlags"):
			snapshot["worldFlags"] = {}
			run["snapshot"] = snapshot
		run["schemaVersion"] = 4
		copy["activeRun"] = run
	return copy


static func _migrate_v4_to_v5(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy["schemaVersion"] = 5
	_normalize_character(copy)
	_normalize_currencies(copy)
	_normalize_inventory(copy)
	_normalize_storage(copy)
	_normalize_talents(copy)
	_normalize_flags(copy)
	_normalize_quests(copy)
	_normalize_item_instances(copy)
	_normalize_meta(copy)
	_normalize_active_run(copy)
	_normalize_merchants(copy)
	_normalize_recipes(copy)
	if str(copy.get("accountId", "")) == NIL_ACCOUNT_ID:
		copy["accountId"] = ""
	return copy


static func _normalize_character(copy: Dictionary) -> void:
	var raw: Variant = copy.get("character", {})
	if not raw is Dictionary:
		raw = {}
	var character: Dictionary = raw
	if not character.has("name") or str(character.get("name", "")).strip_edges() == "":
		character["name"] = "Wanderer"
	character["classId"] = str(character.get("classId", ""))
	character["level"] = maxi(1, int(character.get("level", 1)))
	character["xp"] = maxi(0, int(character.get("xp", 0)))
	var appearance: Variant = character.get("appearance", {})
	character["appearance"] = CharacterAppearance.sanitize(
		appearance if appearance is Dictionary else {"theme": character.get("appearanceTheme", 0)}
	)
	character["appearanceTheme"] = int(character["appearance"].get("theme", 0))
	character.erase("lastHubMessage")
	copy["character"] = character


static func _normalize_currencies(copy: Dictionary) -> void:
	var currencies: Variant = copy.get("currencies", {})
	if not currencies is Dictionary:
		currencies = {}
	var cur: Dictionary = currencies
	var resolved_gold: int
	if cur.has("gold"):
		resolved_gold = maxi(0, int(cur.get("gold", 0)))
	else:
		resolved_gold = maxi(0, int(cur.get("coins", 0)))
	cur["gold"] = resolved_gold
	cur.erase("coins")
	copy["currencies"] = cur


static func _normalize_inventory(copy: Dictionary) -> void:
	copy["inventory"] = _normalize_inventory_section(copy.get("inventory", {}))


static func _normalize_storage(copy: Dictionary) -> void:
	if not copy.has("storage"):
		return
	copy["storage"] = _normalize_inventory_section(copy.get("storage", {}))


static func _normalize_inventory_section(inv: Variant) -> Dictionary:
	if not inv is Dictionary:
		inv = {}
	var section: Dictionary = inv
	section["schemaVersion"] = 1
	section["gridWidth"] = maxi(1, int(section.get("gridWidth", 8)))
	section["gridHeight"] = maxi(1, int(section.get("gridHeight", 6)))
	var slots: Variant = section.get("slots", [])
	var normalized_slots: Array = []
	var dropped_slots := 0
	if slots is Array:
		for entry in slots:
			if not entry is Dictionary:
				dropped_slots += 1
				continue
			var slot: Dictionary = _normalize_slot_entry(entry)
			if slot.is_empty():
				dropped_slots += 1
				continue
			normalized_slots.append(slot)
	section["slots"] = normalized_slots
	if dropped_slots > 0:
		push_warning("SaveMigrator: dropped %d malformed inventory slot(s)" % dropped_slots)

	var equipped: Variant = section.get("equipped", {})
	var normalized_equipped := Equipment.empty_equipped()
	if equipped is Dictionary:
		if equipped.has("weapon") and equipped["weapon"] is String:
			var legacy_id: String = str(equipped["weapon"])
			if legacy_id != "":
				normalized_equipped["weapon"] = _normalize_slot_entry(
					{"itemId": legacy_id, "quantity": 1}
				)
		for slot_name in Equipment.SLOT_ORDER:
			var inst: Variant = equipped.get(slot_name, {})
			if inst is String:
				var legacy: String = str(inst)
				if legacy != "":
					normalized_equipped[slot_name] = _normalize_slot_entry(
						{"itemId": legacy, "quantity": 1}
					)
				continue
			if inst is Dictionary and not inst.is_empty():
				var normalized := _normalize_slot_entry(inst)
				if not normalized.is_empty():
					normalized_equipped[slot_name] = normalized
	section["equipped"] = normalized_equipped
	return section


static func _normalize_slot_entry(slot: Dictionary) -> Dictionary:
	var item_id: String = str(slot.get("itemId", ""))
	if item_id == "":
		return {}
	var out: Dictionary = slot.duplicate(true)
	out["itemId"] = item_id
	out["quantity"] = maxi(1, int(out.get("quantity", 1)))
	if out.has("x"):
		out["x"] = int(out.get("x", 0))
	if out.has("y"):
		out["y"] = int(out.get("y", 0))
	if out.has("rollSeed"):
		out["rollSeed"] = int(out.get("rollSeed", 0))
	if out.has("upgradeLevel"):
		out["upgradeLevel"] = int(out.get("upgradeLevel", 0))
	if out.has("durability"):
		out["durability"] = int(out.get("durability", 0))
	else:
		var def := ItemCatalog.get_definition(item_id)
		var item_type: String = def.get("itemType", "")
		if item_type in ["weapon", "armor", "accessory"]:
			out["durability"] = int(def.get("maxDurability", 100))
	if out.has("rarity"):
		out["rarity"] = RarityRegistry.normalize(str(out.get("rarity", "common")))
	var affixes: Variant = out.get("affixes", [])
	var normalized_affixes: Array = []
	var dropped_affixes := 0
	if affixes is Array:
		for entry in affixes:
			if not entry is Dictionary:
				dropped_affixes += 1
				continue
			var affix_id: String = str(entry.get("affixId", ""))
			if affix_id == "":
				dropped_affixes += 1
				continue
			(
				normalized_affixes
				. append(
					{
						"affixId": affix_id,
						"value": float(entry.get("value", 0.0)),
					}
				)
			)
	if dropped_affixes > 0:
		push_warning(
			"SaveMigrator: dropped %d malformed affix(es) on %s" % [dropped_affixes, item_id]
		)
	out["affixes"] = normalized_affixes
	if not out.has("instanceId"):
		var seed_val: int = int(out.get("rollSeed", out.get("x", 0) + out.get("y", 0)))
		out["instanceId"] = "%s_%d" % [item_id, seed_val]
	return out


static func _normalize_talents(copy: Dictionary) -> void:
	var talents: Variant = copy.get("talents", {})
	if not talents is Dictionary:
		talents = {}
	var normalized: Dictionary = {}
	var unknown := 0
	var tree := ContentLoader.load_json(TALENT_TREE_PATH)
	var known_ids: Dictionary = {}
	for branch in tree.get("branches", []):
		if not branch is Dictionary:
			continue
		for node in branch.get("nodes", []):
			if node is Dictionary:
				known_ids[str(node.get("id", ""))] = node

	for key in talents:
		var node_id: String = str(key)
		var rank: int = maxi(0, int(talents[key]))
		normalized[node_id] = rank
		if not known_ids.has(node_id):
			unknown += 1
	if unknown > 0:
		push_warning("SaveMigrator: retained %d unknown talent node id(s)" % unknown)
	copy["talents"] = normalized

	var reachable := _reachable_talent_spend(normalized, known_ids)
	var spent: int = maxi(0, int(copy.get("talentPointsSpent", 0)))
	if spent > reachable:
		push_warning("SaveMigrator: clamped talentPointsSpent from %d to %d" % [spent, reachable])
		spent = reachable
	copy["talentPointsSpent"] = spent


static func _reachable_talent_spend(talents: Dictionary, known_ids: Dictionary) -> int:
	var total := 0
	for node_id in talents:
		var rank: int = int(talents.get(node_id, 0))
		if rank <= 0:
			continue
		var node: Variant = known_ids.get(node_id, {})
		if not node is Dictionary:
			continue
		total += rank * int(node.get("costPerRank", 1))
	return total


static func _normalize_flags(copy: Dictionary) -> void:
	copy["flags"] = CharacterFlags.coerce_all(copy.get("flags", {}))


static func _normalize_quests(copy: Dictionary) -> void:
	var quests: Variant = copy.get("quests", {})
	if not quests is Dictionary:
		copy["quests"] = {"states": {}, "progress": {}}
		return
	var legacy: Dictionary = quests
	if legacy.has("states") or legacy.has("progress"):
		var split_states: Dictionary = {}
		var split_progress: Dictionary = {}
		var states_raw: Variant = legacy.get("states", {})
		if states_raw is Dictionary:
			for quest_id in states_raw:
				split_states[str(quest_id)] = str(states_raw[quest_id])
		var progress_raw: Variant = legacy.get("progress", {})
		if progress_raw is Dictionary:
			for quest_id in progress_raw:
				var entry: Variant = progress_raw[quest_id]
				if entry is Dictionary:
					split_progress[str(quest_id)] = entry.duplicate(true)
		copy["quests"] = {"states": split_states, "progress": split_progress}
		return
	var states := {}
	var progress := {}
	var dropped := 0
	for key in legacy:
		var quest_key := str(key)
		var value: Variant = legacy[key]
		if quest_key.ends_with("_progress"):
			var owner_id := quest_key.substr(0, quest_key.length() - 9)
			if value is Dictionary:
				progress[owner_id] = value.duplicate(true)
			else:
				dropped += 1
		elif value is String:
			states[quest_key] = value
		else:
			states[quest_key] = str(value)
	if dropped > 0:
		push_warning("SaveMigrator: dropped %d malformed quest progress row(s)" % dropped)
	copy["quests"] = {"states": states, "progress": progress}


static func _normalize_item_instances(copy: Dictionary) -> void:
	var instances: Variant = copy.get("itemInstances", {})
	if not instances is Dictionary:
		instances = {}
	var normalized: Dictionary = {}
	var dropped := 0
	for instance_id in instances:
		var entry: Variant = instances[instance_id]
		if entry is Dictionary:
			normalized[str(instance_id)] = entry.duplicate(true)
		else:
			dropped += 1
	if dropped > 0:
		push_warning("SaveMigrator: dropped %d malformed itemInstances entr(y/ies)" % dropped)
	copy["itemInstances"] = normalized


static func _normalize_meta(copy: Dictionary) -> void:
	var meta: Variant = copy.get("meta", {})
	if not meta is Dictionary:
		meta = {}
	var normalized: Dictionary = meta.duplicate(true)
	for sub_key in ["accessibility", "display", "leaderboard", "hub_tutorial", "achievements"]:
		if normalized.has(sub_key) and not normalized[sub_key] is Dictionary:
			normalized.erase(sub_key)
	if normalized.has("hub_tutorial") and normalized["hub_tutorial"] is Dictionary:
		normalized["hub_tutorial"] = HubTutorialService.migrate_index_to_seen(
			normalized["hub_tutorial"].duplicate(true)
		)
	if normalized.has("accessibility") and normalized["accessibility"] is Dictionary:
		var a11y: Dictionary = normalized["accessibility"].duplicate(true)
		AccessibilitySettings.apply_camera_defaults_to_dict(a11y)
		normalized["accessibility"] = a11y
	copy["meta"] = normalized


static func _normalize_active_run(copy: Dictionary) -> void:
	var active: Variant = copy.get("activeRun", {})
	if not active is Dictionary or active.is_empty():
		copy.erase("activeRun")
		return
	var run: Dictionary = active.duplicate(true)
	if not run.has("currentFloor"):
		run["currentFloor"] = 1
	if not run.has("maxFloors"):
		run["maxFloors"] = RunFloorConfig.MAX_FLOORS
	if not run.has("runMode"):
		run["runMode"] = "castle"
	if not run.has("lastCheckpoint"):
		run["lastCheckpoint"] = {}
	var snapshot: Variant = run.get("snapshot", {})
	if snapshot is Dictionary and not snapshot.has("worldFlags"):
		snapshot["worldFlags"] = {}
		run["snapshot"] = snapshot
	run.erase("floorDefinitions")

	if bool(run.get("playerDead", false)):
		var checkpoint: Variant = run.get("lastCheckpoint", {})
		if checkpoint is Dictionary and not checkpoint.is_empty():
			run["snapshot"] = (checkpoint as Dictionary).duplicate(true)
			run.erase("playerDead")
		else:
			copy.erase("activeRun")
			return

	var cleared: Variant = run.get("clearedFloors", [])
	var cleared_ints: Array = []
	if cleared is Array:
		for floor_value in cleared:
			cleared_ints.append(int(floor_value))
	run["clearedFloors"] = cleared_ints

	_migrate_world_flags_in_snapshot(run.get("snapshot", {}))
	var checkpoint_data: Variant = run.get("lastCheckpoint", {})
	if checkpoint_data is Dictionary:
		_migrate_world_flags_in_snapshot(checkpoint_data)

	run["schemaVersion"] = 5
	copy["activeRun"] = run


static func _migrate_v5_to_v6(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy["schemaVersion"] = 6
	var meta: Variant = copy.get("meta", {})
	if meta is Dictionary:
		var achievements: Variant = meta.get("achievements", {})
		if achievements is Dictionary and achievements.get("mythic_loot", false):
			var migrated: Dictionary = achievements.duplicate()
			migrated["aumbral_loot"] = true
			migrated.erase("mythic_loot")
			meta["achievements"] = migrated
			copy["meta"] = meta
	return copy


static func _migrate_v6_to_v7(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy["schemaVersion"] = 7
	var flags: Variant = copy.get("flags", {})
	if not flags is Dictionary:
		flags = {}
	var flag_dict: Dictionary = flags
	var old_max := int(flag_dict.get("dungeon_max_tier", 1))
	if not flag_dict.has("dungeon_unlocked_count"):
		flag_dict["dungeon_unlocked_count"] = old_max
	for dungeon_id in DungeonCatalog.all_dungeon_ids():
		var tier_flag := DungeonTierService.FLAG_DIFFICULTY_PREFIX + dungeon_id
		if not flag_dict.has(tier_flag):
			flag_dict[tier_flag] = 1
	copy["flags"] = flag_dict
	var active: Variant = copy.get("activeRun", {})
	if active is Dictionary and not active.is_empty():
		var run: Dictionary = active
		if not run.has("difficultyTier"):
			run["difficultyTier"] = 1
		copy["activeRun"] = run
	return copy


static func _migrate_v7_to_v8(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy["schemaVersion"] = 8
	var meta: Variant = copy.get("meta", {})
	if not meta is Dictionary:
		meta = {}
	var meta_dict: Dictionary = meta.duplicate(true)
	var accessibility: Variant = meta_dict.get("accessibility", {})
	if not accessibility is Dictionary:
		accessibility = {}
	var a11y: Dictionary = accessibility.duplicate(true)
	AccessibilitySettings.apply_camera_defaults_to_dict(a11y)
	meta_dict["accessibility"] = a11y
	copy["meta"] = meta_dict
	return copy


static func _migrate_v8_to_v9(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy["schemaVersion"] = 9
	var meta: Variant = copy.get("meta", {})
	if not meta is Dictionary:
		meta = {}
	var meta_dict: Dictionary = meta.duplicate(true)
	var display: Variant = meta_dict.get("display", {})
	if not display is Dictionary:
		display = {}
	var display_dict: Dictionary = display.duplicate(true)
	var accessibility: Variant = meta_dict.get("accessibility", {})
	if accessibility is Dictionary:
		var a11y: Dictionary = accessibility
		if a11y.has("ui_scale") and not display_dict.has("ui_scale"):
			display_dict["ui_scale"] = float(a11y.get("ui_scale", 1.0))
	if not display_dict.has("window_mode"):
		display_dict["window_mode"] = "windowed"
	if not display_dict.has("window_size"):
		display_dict["window_size"] = [1920, 1080]
	if not display_dict.has("monitor_index"):
		display_dict["monitor_index"] = 0
	if not display_dict.has("vsync_mode"):
		display_dict["vsync_mode"] = "enabled"
	if not display_dict.has("max_fps"):
		display_dict["max_fps"] = 0
	if not display_dict.has("ui_scale"):
		display_dict["ui_scale"] = 1.0
	if not display_dict.has("hud_safe_area"):
		display_dict["hud_safe_area"] = 0.0
	meta_dict["display"] = display_dict
	copy["meta"] = meta_dict
	return copy


static func _migrate_v9_to_v10(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy["schemaVersion"] = 10
	var inv: Variant = copy.get("inventory", {})
	if not inv is Dictionary:
		return copy
	var inv_dict: Dictionary = inv.duplicate(true)
	if inv_dict.has("quickSlotInstances"):
		copy["inventory"] = inv_dict
		return copy
	var slots: Array = inv_dict.get("slots", [])
	var legacy: Array = inv_dict.get("quickSlots", [])
	var instances: Array[String] = ["", "", "", ""]
	for i in mini(legacy.size(), 4):
		var idx := int(legacy[i])
		if idx < 0 or idx >= slots.size():
			continue
		var slot: Variant = slots[idx]
		if slot is Dictionary:
			instances[i] = str(slot.get("instanceId", ""))
	inv_dict["quickSlotInstances"] = instances
	inv_dict.erase("quickSlots")
	copy["inventory"] = inv_dict
	return copy


static func _migrate_v10_to_v11(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy["schemaVersion"] = 11
	_normalize_currencies(copy)
	return copy


static func _migrate_v11_to_v12(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy["schemaVersion"] = 12
	_normalize_talents(copy)
	if copy.has("account") and copy["account"] is Dictionary:
		return copy
	var storage: Variant = copy.get("storage", {})
	var flags: Variant = copy.get("flags", {})
	var account_flags: Dictionary = {}
	if flags is Dictionary:
		for flag_id in flags as Dictionary:
			if is_account_scope_flag(str(flag_id)):
				account_flags[str(flag_id)] = (flags as Dictionary)[flag_id]
	copy["account"] = {
		"schemaVersion": 1,
		"storage": (storage as Dictionary).duplicate(true) if storage is Dictionary else {},
		"flags": account_flags,
		"endlessBestFloor": 0,
		"descentTokens": 0,
	}
	return copy


static func is_account_scope_flag(flag_id: String) -> bool:
	if flag_id in ACCOUNT_SCOPE_FLAG_IDS:
		return true
	for prefix in ACCOUNT_SCOPE_FLAG_PREFIXES:
		if flag_id.begins_with(prefix):
			return true
	return false


static func _migrate_world_flags_in_snapshot(snapshot: Variant) -> void:
	if not snapshot is Dictionary:
		return
	var snap: Dictionary = snapshot
	var legacy: Variant = snap.get("worldFlags", {})
	if not legacy is Dictionary:
		snap["worldFlags"] = {}
		return
	var migrated: Dictionary = {}
	var dropped := 0
	for key in legacy:
		var flag_key: String = str(key)
		if WorldFlags.is_valid_id(flag_key):
			migrated[flag_key] = legacy[key]
			continue
		var mapped: String = WorldFlags.migrate_legacy_id(flag_key)
		if mapped != "":
			migrated[mapped] = legacy[key]
		else:
			dropped += 1
	if dropped > 0:
		push_warning("SaveMigrator: dropped %d legacy worldFlags key(s)" % dropped)
	snap["worldFlags"] = migrated


static func _normalize_merchants(copy: Dictionary) -> void:
	if not copy.has("merchants") or not copy["merchants"] is Dictionary:
		copy["merchants"] = {}


static func _normalize_recipes(copy: Dictionary) -> void:
	var owned: Variant = copy.get("recipes", [])
	var ids: Array[String] = []
	if owned is Array:
		for entry in owned:
			if entry is String:
				ids.append(entry)
			elif entry is Dictionary and entry.has("id"):
				ids.append(str(entry["id"]))
	copy["recipes"] = ids


static func _fail(data: Dictionary, kind: String, reason: String) -> Dictionary:
	push_error("SaveMigrator: %s — refusing load (%s)" % [reason, kind])
	var out := data.duplicate(true)
	out["migrationFailed"] = true
	out["migrationKind"] = kind
	out["migrationReason"] = reason
	out["originalSchemaVersion"] = int(data.get("schemaVersion", 0))
	out["requiredVersion"] = CURRENT_VERSION
	return out

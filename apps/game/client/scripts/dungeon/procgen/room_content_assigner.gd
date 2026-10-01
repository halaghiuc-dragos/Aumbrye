class_name RoomContentAssigner
extends RefCounted


const DungeonQuestCatalogScript := preload("res://scripts/quests/dungeon_quest_catalog.gd")
const BRANCH_CLUE_PROFILES_PATH := "content/ui/branch_clue_profiles.json"

static var _branch_clue_profiles: Dictionary = {}
static var _branch_clue_profiles_loaded := false


## Rooms whose chest carries a stake: a cursed cache pays double and costs a floor-long curse, a
## gauntlet chest sits behind a trap field and pays a relic offer to anyone who crosses unhurt, and a
## timed cache seals thirty seconds after the player steps in.
const RISK_CURSED := "cursed"
const RISK_GAUNTLET := "gauntlet"
const RISK_TIMED := "timed"
const TIMED_CACHE_CHANCE := 0.2
const CURSED_CACHE_CHANCE := 0.3


static func assign(
	graph: RoomGraph,
	assignment: Dictionary,
	rng: RandomNumberGenerator,
	config: RoomContentConfig = null,
	biome_id: String = "",
	tier: int = 1
) -> Dictionary:
	var result := _assign_impl(graph, assignment, rng, config, biome_id, tier)
	if result.get("ok", false):
		var inputs: Dictionary = config.generation_inputs if config != null else {}
		_add_shortcut_gates(graph, assignment, rng, biome_id, tier, result, inputs)
		var content: Dictionary = result.get("content", {})
		if (content.get("shortcutGates", []) as Array).is_empty():
			var warnings: Array = result.get("warnings", [])
			warnings.append("missing_geometric_shortcut")
			result["warnings"] = warnings
	return result


static func _assign_impl(
	graph: RoomGraph,
	assignment: Dictionary,
	rng: RandomNumberGenerator,
	config: RoomContentConfig = null,
	biome_id: String = "",
	tier: int = 1
) -> Dictionary:
	config = config if config != null else RoomContentConfig.default()
	var layout_semantic := _layout_to_semantic(assignment)
	var critical_layout: Array[String] = RoomGraphPaths.critical_path_ids(graph)
	var critical_semantic: Array[String] = []
	for layout_id in critical_layout:
		critical_semantic.append(layout_semantic.get(layout_id, layout_id))
	var critical_set := {}
	for room_id in critical_semantic:
		critical_set[room_id] = true
	var distances := RoomGraphPaths.bfs_distances(graph, graph.start_id)
	# A floor with no locked door on it is valid but flat, so a lock-free pass is held as a fallback
	# rather than returned outright. Whether a given pass produces a lock depends on which doorway
	# the spread happened to pick and whether a key room was free behind it, so the same graph will
	# often gate on one attempt and not the next -- taking the first valid pass left roughly a third
	# of floors ungated for no reason other than draw order.
	var ungated_result: Dictionary = {}
	for attempt in config.max_assignment_attempts:
		var result := _try_assign_once(
			graph,
			assignment,
			layout_semantic,
			critical_layout,
			critical_semantic,
			critical_set,
			distances,
			rng,
			config,
			biome_id,
			tier
		)
		if result.get("ok", false):
			var locks: Array = result.get("content", {}).get("locks", [])
			if locks.size() >= config.max_locks_per_floor:
				return result
			# Not enough locks yet -- keep the best attempt seen so far rather than the first, since
			# a graph that cannot support the full ring should still ship with as many as it can.
			var best_locks: Array = ungated_result.get("content", {}).get("locks", [])
			if ungated_result.is_empty() or locks.size() > best_locks.size():
				ungated_result = result
		rng.seed = rng.seed + 1_000_003 + attempt
	if not ungated_result.is_empty():
		return ungated_result
	return _fallback_assignment(
		graph,
		assignment,
		layout_semantic,
		critical_semantic,
		critical_layout,
		distances,
		rng,
		biome_id,
		config,
		tier
	)


static func _try_assign_once(
	graph: RoomGraph,
	assignment: Dictionary,
	layout_semantic: Dictionary,
	critical_layout: Array[String],
	critical_semantic: Array[String],
	critical_set: Dictionary,
	distances: Dictionary,
	rng: RandomNumberGenerator,
	config: RoomContentConfig,
	biome_id: String,
	tier: int = 1
) -> Dictionary:
	var pre_boss_layout := ""
	var boss_idx := critical_layout.find(graph.boss_id)
	if boss_idx > 0:
		pre_boss_layout = critical_layout[boss_idx - 1]
	var room_content: Array = []
	var reserved_semantics := _reserved_semantics(graph, assignment, layout_semantic)
	var no_trap_semantics := reserved_semantics.duplicate()
	for layout_id in critical_layout:
		if layout_id == graph.start_id:
			var start_slot := graph.get_slot(layout_id)
			if start_slot:
				for dir in RoomGraphPaths._dirs():
					var neighbor: RoomGraphSlot = (
						graph.slots.get(start_slot.grid_pos + dir) as RoomGraphSlot
					)
					if neighbor:
						no_trap_semantics.append(layout_semantic.get(neighbor.slot_id, ""))
	var dead_ends: Array[String] = []
	for room in assignment.get("rooms", []):
		var semantic: String = room["semantic_id"]
		var layout_id: String = room["layout_id"]
		var slot := graph.get_slot(layout_id)
		if (
			slot
			and slot.is_dead_end()
			and semantic not in reserved_semantics
			and room.get("type", "") != "filler"
		):
			dead_ends.append(semantic)
	dead_ends.sort()
	for room in assignment.get("rooms", []):
		var semantic: String = room["semantic_id"]
		var layout_id: String = room["layout_id"]
		var slot := graph.get_slot(layout_id)
		# A filler falls through to the same per-room content roll as any other off-path room below,
		# so a fifth of a floor is not rooms with nothing in them.
		if semantic in reserved_semantics:
			room_content.append(_entry_for_special(room, slot))
			continue
		if layout_id == pre_boss_layout:
			(
				room_content
				. append(
					{
						"roomId": semantic,
						"layoutId": layout_id,
						"contentType": RoomContentTypes.COMBAT,
						"templateId": "",
						# One lock-in per floor -- the room immediately before the boss, where
						# the game wants to test the player before the real test. See
						# `room_arena_gate_content.gd` for what this flag actually builds.
						"lockIn": true,
					}
				)
			)
			continue
		var on_critical := critical_set.has(semantic)
		var dist: int = int(distances.get(layout_id, 0))
		var content_type := _pick_content_type(
			on_critical, dist, semantic in dead_ends, semantic in no_trap_semantics, rng, config
		)
		(
			room_content
			. append(
				{
					"roomId": semantic,
					"layoutId": layout_id,
					"contentType": content_type,
					"templateId": RoomContentTypes.TEMPLATE_BY_TYPE.get(content_type, ""),
				}
			)
		)
	_apply_floor_recipe(room_content, graph, layout_semantic, critical_semantic, reserved_semantics, config, rng)
	var locks: Array = []
	if config.enable_locked_door and critical_semantic.size() >= 4:
		var content_by_semantic := RoomLockPlacer.content_by_semantic(room_content)
		locks = RoomLockPlacer.place_locked_doors(
			graph,
			layout_semantic,
			critical_layout,
			critical_semantic,
			distances,
			rng,
			config,
			reserved_semantics,
			false,
			content_by_semantic
		)
		# Second sweep, this time allowing the key to sit on the critical path. Only reached when
		# the floor offered nowhere off-path to hide one, and a gated floor with an obvious key
		# still beats an ungated one.
		if locks.is_empty():
			locks = RoomLockPlacer.place_locked_doors(
				graph,
				layout_semantic,
				critical_layout,
				critical_semantic,
				distances,
				rng,
				config,
				reserved_semantics,
				true,
				content_by_semantic
			)
		for lock in locks:
			RoomLockPlacer.apply_key_to_content(room_content, lock, reserved_semantics)
	var puzzles := _finalize_content_entries(
		room_content,
		graph,
		layout_semantic,
		critical_set,
		rng,
		biome_id,
		reserved_semantics,
		tier,
		config.generation_inputs
	)
	var content := {
		"roomContent": room_content,
		"locks": locks,
		"puzzles": puzzles,
	}
	var validation := RoomContentValidator.validate(graph, assignment, content, config)
	if not validation.get("ok", false):
		return validation
	return {"ok": true, "content": content}


static func _pick_content_type(
	on_critical: bool,
	distance: int,
	is_dead_end: bool,
	no_trap: bool,
	rng: RandomNumberGenerator,
	config: RoomContentConfig
) -> String:
	if is_dead_end:
		var dead_roll := rng.randf()
		var reward_ratio := clampf(config.dead_end_reward_ratio, 0.0, 1.0)
		if dead_roll < reward_ratio:
			return RoomContentTypes.REWARD
		var remainder_roll := (dead_roll - reward_ratio) / maxf(0.0001, 1.0 - reward_ratio)
		if remainder_roll < 0.35:
			return RoomContentTypes.LORE
		if remainder_roll < 0.65:
			return RoomContentTypes.COMBAT
		return RoomContentTypes.EMPTY
	if on_critical:
		if distance > 0 and distance % 4 == 0:
			if _rest_allowed() and rng.randf() < 0.65:
				return RoomContentTypes.REST
			return RoomContentTypes.EMPTY
		if distance <= 2:
			return RoomContentTypes.COMBAT if rng.randf() < 0.75 else RoomContentTypes.EMPTY
		return RoomContentTypes.COMBAT if rng.randf() < 0.88 else RoomContentTypes.EMPTY
	if distance < config.min_off_path_distance:
		return RoomContentTypes.COMBAT
	var weights := {
		RoomContentTypes.TRAP: 0.0 if no_trap else config.weight_trap,
		RoomContentTypes.HAZARD: 0.0 if no_trap else config.weight_hazard,
		RoomContentTypes.PUZZLE: config.weight_puzzle if config.weight_puzzle > 0.0 else 0.0,
		RoomContentTypes.NPC_QUEST:
		(
			config.weight_npc_quest
			if config.enable_npc_quest and config.weight_npc_quest > 0.0
			else 0.0
		),
		RoomContentTypes.COMBAT: config.weight_combat,
		RoomContentTypes.EMPTY: config.weight_empty,
		RoomContentTypes.REWARD: config.weight_reward,
		RoomContentTypes.LORE: config.weight_lore,
		RoomContentTypes.REST: 0.0 if not _rest_allowed() else config.weight_rest,
		RoomContentTypes.MERCHANT: config.weight_merchant,
		RoomContentTypes.SHRINE: config.weight_shrine,
	}
	var total := 0.0
	for weight in weights.values():
		total += float(weight)
	if total <= 0.0:
		return RoomContentTypes.COMBAT
	var roll := rng.randf() * total
	var acc := 0.0
	for content_type in weights:
		acc += float(weights[content_type])
		if roll < acc:
			return content_type
	return RoomContentTypes.EMPTY


static func _rest_allowed() -> bool:
	return not RunModifierService.has_modifier(RunModifierService.MODIFIER_NO_REST)


static func _set_content_type(entry: Dictionary, content_type: String) -> void:
	entry["contentType"] = content_type
	entry["templateId"] = str(RoomContentTypes.TEMPLATE_BY_TYPE.get(content_type, ""))


static func _is_mutable(entry: Dictionary, reserved_semantics: Array[String]) -> bool:
	var room_id := str(entry.get("roomId", ""))
	if room_id in reserved_semantics or room_id.begins_with("filler_"):
		return false
	var content_type := str(entry.get("contentType", ""))
	if content_type in [
		RoomContentTypes.BOSS,
		RoomContentTypes.STAIRS,
		RoomContentTypes.LOCKED_VAULT,
		RoomContentTypes.NPC_QUEST,
		RoomContentTypes.PUZZLE,
	]:
		return false
	return str(entry.get("templateId", "")) != "" or content_type != ""


const RECIPES_PATH := "content/progression/floor_recipes.json"
const RECIPE_TYPES := {
	"fight": RoomContentTypes.COMBAT,
	"choice": RoomContentTypes.SHRINE,
	"rest": RoomContentTypes.REST,
	"lore": RoomContentTypes.LORE,
	"reward": RoomContentTypes.REWARD,
	"trial": RoomContentTypes.TRAP,
	"merchant": RoomContentTypes.MERCHANT,
}
static var _recipes: Dictionary = {}


static func _recipe_for(block_floor: int) -> Dictionary:
	if _recipes.is_empty():
		_recipes = ContentLoader.load_json(RECIPES_PATH).get("floors", {})
	var floors := _recipes as Dictionary
	return floors.get(str(clampi(block_floor, 1, floors.size())), floors.get("1", {}))


## The floor's authored recipe (`content/progression/floor_recipes.json`) decides what every room
## holds, so the order a floor is met in is designed rather than rolled: the critical path cycles the
## recipe's `path` beats and ends on its `tail` (a rest before the arena and the boss), dead ends deal
## out `branches` from a rotating start, and any other side room is a `side` beat. Rooms that carry
## other content (a quest giver, a vault, the arena, the stairs) keep it.
static func _apply_floor_recipe(
	room_content: Array,
	graph: RoomGraph,
	layout_semantic: Dictionary,
	critical_semantic: Array[String],
	reserved_semantics: Array[String],
	config: RoomContentConfig,
	rng: RandomNumberGenerator
) -> void:
	var recipe := _recipe_for(config.block_floor)
	if recipe.is_empty():
		return
	var no_trap: Array[String] = []
	var start_slot := graph.get_slot(graph.start_id)
	if start_slot != null:
		no_trap.append(str(layout_semantic.get(graph.start_id, "")))
		for dir in RoomGraphPaths._dirs():
			var neighbour: RoomGraphSlot = graph.slots.get(start_slot.grid_pos + dir) as RoomGraphSlot
			if neighbour != null:
				no_trap.append(str(layout_semantic.get(neighbour.slot_id, "")))
	var by_room := {}
	var layout_of := {}
	for entry in room_content:
		if entry is Dictionary:
			by_room[str((entry as Dictionary).get("roomId", ""))] = entry
			layout_of[str((entry as Dictionary).get("roomId", ""))] = str((entry as Dictionary).get("layoutId", ""))
	var path_rooms: Array[Dictionary] = []
	for room_id in critical_semantic:
		var entry: Dictionary = by_room.get(room_id, {})
		if not entry.is_empty() and not bool(entry.get("lockIn", false)) and _is_mutable(entry, reserved_semantics):
			path_rooms.append(entry)
	var tail: Array = recipe.get("tail", [])
	var cycle: Array = recipe.get("path", [])
	for i in path_rooms.size():
		var from_end := path_rooms.size() - 1 - i
		var token := ""
		if from_end < tail.size():
			token = str(tail[tail.size() - 1 - from_end])
		elif not cycle.is_empty():
			token = str(cycle[i % cycle.size()])
		_apply_beat(path_rooms[i], token, no_trap)
	var branches: Array = recipe.get("branches", [])
	var side: Array = recipe.get("side", [])
	var branch_cursor := rng.randi_range(0, maxi(0, branches.size() - 1))
	var side_cursor := rng.randi_range(0, maxi(0, side.size() - 1))
	var off_path: Array[String] = []
	for room_id in by_room:
		if not critical_semantic.has(str(room_id)):
			off_path.append(str(room_id))
	off_path.sort()
	for room_id in off_path:
		var entry: Dictionary = by_room[room_id]
		if not _is_mutable(entry, reserved_semantics):
			continue
		var slot := graph.get_slot(str(layout_of.get(room_id, "")))
		if slot != null and slot.is_dead_end() and not branches.is_empty():
			_apply_beat(entry, str(branches[branch_cursor % branches.size()]), no_trap)
			branch_cursor += 1
		elif not side.is_empty():
			_apply_beat(entry, str(side[side_cursor % side.size()]), no_trap)
			side_cursor += 1


static func _apply_beat(entry: Dictionary, token: String, no_trap: Array[String]) -> void:
	var content_type: String = RECIPE_TYPES.get(token, "")
	if content_type == "":
		return
	if content_type == RoomContentTypes.REST and not _rest_allowed():
		content_type = RoomContentTypes.COMBAT
	if content_type == RoomContentTypes.TRAP and no_trap.has(str(entry.get("roomId", ""))):
		content_type = RoomContentTypes.COMBAT
	_set_content_type(entry, content_type)


static func _finalize_content_entries(
	room_content: Array,
	graph: RoomGraph,
	layout_semantic: Dictionary,
	critical_set: Dictionary,
	rng: RandomNumberGenerator,
	biome_id: String,
	reserved_semantics: Array[String],
	tier: int = 1,
	inputs: Dictionary = {}
) -> Array:
	var puzzles: Array = []
	for entry in room_content:
		if not entry is Dictionary:
			continue
		var content_type := str(entry.get("contentType", ""))
		var room_id := str(entry.get("roomId", ""))
		# Content must keep an identity independent of the runtime node name: the builder can be
		# reconstructed, while discoveries and placement validation need to refer to the same
		# authored/generated location after a reload.
		entry["placementId"] = "%s:%s:%s" % [biome_id, room_id, content_type]
		# A pre-boss rest is part of the generated progression contract, not decorative dressing.
		# Its runtime placement must therefore fail the build path if no usable authored anchor exists.
		entry["required"] = content_type == RoomContentTypes.REST and critical_set.has(room_id)
		if content_type == RoomContentTypes.LORE:
			entry["loreId"] = "%s:lore:%s" % [biome_id, room_id]
		if content_type == RoomContentTypes.REWARD or content_type == RoomContentTypes.LOCKED_VAULT:
			entry["items"] = _roll_chest_items(biome_id, rng, room_id, content_type, tier, inputs)
		if content_type == RoomContentTypes.REWARD and rng.randf() < CURSED_CACHE_CHANCE:
			entry["params"] = {"risk": RISK_CURSED}
			var extra := _roll_chest_items(biome_id, rng, room_id, content_type, tier, inputs)
			for i in extra.size():
				(extra[i] as Dictionary)["instanceId"] = "%s_c%d" % [room_id, i]
			(entry["items"] as Array).append_array(extra)
		elif content_type == RoomContentTypes.REWARD and rng.randf() < TIMED_CACHE_CHANCE:
			entry["params"] = {"risk": RISK_TIMED}
		if content_type == RoomContentTypes.TRAP:
			# A trap room guards a chest at its far end; crossing it unhurt earns a relic offer.
			entry["items"] = _roll_chest_items(biome_id, rng, room_id, content_type, tier, inputs)
			entry["params"] = {"risk": RISK_GAUNTLET}
		if content_type == RoomContentTypes.NPC_QUEST:
			var quest := _pick_dungeon_quest(biome_id, rng)
			entry["questId"] = str(quest.get("questId", ""))
			entry["questKeyId"] = str(quest.get("questKeyId", ""))
			entry["dialogueId"] = str(quest.get("dialogueId", "dungeon_npc_stranded"))
			entry["targetNpcId"] = str(quest.get("targetNpcId", ""))
			entry["delivery"] = DungeonQuestCatalogScript.delivery_for_quest(quest)
		if content_type == RoomContentTypes.PUZZLE:
			var puzzle := _build_puzzle_entry(
				entry, graph, layout_semantic, critical_set, rng, reserved_semantics
			)
			if not puzzle.is_empty():
				puzzles.append(puzzle)
				entry["flagId"] = str(puzzle.get("flagId", ""))
				_stock_puzzle_reward(
					room_content, puzzle, reserved_semantics, biome_id, rng, tier, inputs
				)
	return puzzles


## A gate that opens onto nothing is a chore, so the room behind a puzzle gate holds a chest.
static func _stock_puzzle_reward(
	room_content: Array,
	puzzle: Dictionary,
	reserved_semantics: Array[String],
	biome_id: String,
	rng: RandomNumberGenerator,
	tier: int,
	inputs: Dictionary
) -> void:
	var gate_room := str(puzzle.get("gateRoomId", ""))
	for gate_entry in room_content:
		if not gate_entry is Dictionary or str((gate_entry as Dictionary).get("roomId", "")) != gate_room:
			continue
		if _is_mutable(gate_entry as Dictionary, reserved_semantics):
			_set_content_type(gate_entry as Dictionary, RoomContentTypes.REWARD)
			(gate_entry as Dictionary)["items"] = _roll_chest_items(
				biome_id, rng, gate_room, RoomContentTypes.REWARD, tier, inputs
			)
		return


## One-way circularity: a loop the lattice managed to seat flush becomes a real door the player can
## always walk up to but can only ever open from the side reached the hard way. Approaching from the
## easy side finds it barred -- a warning, not a puzzle, since there is nothing to solve, only a
## longer route to take. The harder side always gets a guaranteed piece of gear: a shortcut nobody
## has a reason to go looking for the hard way isn't a shortcut, it's a wall with a door drawn on it.
static func _add_shortcut_gates(
	graph: RoomGraph,
	assignment: Dictionary,
	rng: RandomNumberGenerator,
	biome_id: String,
	tier: int,
	result: Dictionary,
	inputs: Dictionary = {}
) -> void:
	if graph.loop_edges.is_empty():
		return
	var content: Dictionary = result.get("content", {})
	var room_content: Array = content.get("roomContent", [])
	if room_content.is_empty():
		return
	var layout_semantic := _layout_to_semantic(assignment)
	var distances := RoomGraphPaths.bfs_distances(graph, graph.start_id)
	var reserved_semantics := _reserved_semantics(graph, assignment, layout_semantic)
	var by_room: Dictionary = {}
	for entry in room_content:
		if entry is Dictionary:
			by_room[str((entry as Dictionary).get("roomId", ""))] = entry
	var gates: Array = []
	var used_open_rooms := {}
	for loop_edge in graph.loop_edges:
		var slot_a := graph.get_slot_at(loop_edge["a"])
		var slot_b := graph.get_slot_at(loop_edge["b"])
		if slot_a == null or slot_b == null:
			continue
		var layout_a := slot_a.slot_id
		var layout_b := slot_b.slot_id
		if layout_a in [graph.start_id, graph.boss_id, graph.stairs_id]:
			continue
		if layout_b in [graph.start_id, graph.boss_id, graph.stairs_id]:
			continue
		var sem_a := str(layout_semantic.get(layout_a, ""))
		var sem_b := str(layout_semantic.get(layout_b, ""))
		if sem_a == "" or sem_b == "" or not by_room.has(sem_a) or not by_room.has(sem_b):
			continue
		var dist_a := int(distances.get(layout_a, 0))
		var dist_b := int(distances.get(layout_b, 0))
		var open_sem := sem_a if dist_a >= dist_b else sem_b
		var locked_sem := sem_b if dist_a >= dist_b else sem_a
		if used_open_rooms.has(open_sem):
			continue
		var gate := {
			"gateId": "shortcut_%s_%s" % [locked_sem, open_sem],
			"roomA": locked_sem,
			"roomB": open_sem,
			"openRoomId": open_sem,
		}
		# A barred door is only a shortcut if the floor stays winnable with it shut from that side:
		# a loop the lattice realised as the only way into a pocket is a wall, not a shortcut.
		content["shortcutGates"] = gates + [gate]
		if not _floor_winnable(graph, layout_semantic, content):
			continue
		used_open_rooms[open_sem] = true
		gates.append(gate)
		var open_entry: Variant = by_room.get(open_sem)
		if (
			open_entry is Dictionary
			and _is_mutable(open_entry as Dictionary, reserved_semantics)
			and str((open_entry as Dictionary).get("contentType", "")) != RoomContentTypes.REST
			and not bool((open_entry as Dictionary).get("lockIn", false))
		):
			_set_content_type(open_entry as Dictionary, RoomContentTypes.REWARD)
			(open_entry as Dictionary)["items"] = _roll_armory_chest_items(
				biome_id, rng, open_sem, tier, inputs
			)
	if gates.is_empty():
		content.erase("shortcutGates")
		return
	content["shortcutGates"] = gates
	result["content"] = content


## The boss, the stairs and every key room reachable from the entrance with only the keys, levers
## and one-way doors the walk itself can earn.
static func _floor_winnable(
	graph: RoomGraph, layout_semantic: Dictionary, content: Dictionary
) -> bool:
	var required: Array = []
	for layout_id in [graph.boss_id, graph.stairs_id]:
		var semantic := str(layout_semantic.get(layout_id, ""))
		if semantic != "":
			required.append(semantic)
	for lock in content.get("locks", []):
		if lock is Dictionary:
			required.append_array((lock as Dictionary).get("keyRoomIds", []))
	return RoomContentValidator._required_rooms_reachable(
		graph,
		layout_semantic,
		content,
		str(layout_semantic.get(graph.start_id, "")),
		required
	)


## Loot for the room on the far side of a one-way shortcut -- rolled from the armory table rather
## than the general side-room table, and topped up with a forced pick if the roll came back without
## one, so the reward for taking the hard way around is never just consumables.
static func _roll_armory_chest_items(
	biome_id: String, rng: RandomNumberGenerator, room_id: String, tier: int, inputs: Dictionary
) -> Array:
	var biome := BiomeRegistry.get_biome(biome_id)
	if biome.is_empty():
		return []
	var table: Array = ProcgenLootRoller.roll_chest(
		biome, "armory", maxi(1, tier), rng, 0.0, inputs.get("lockedItems", [])
	)
	var has_equipment := false
	for row in table:
		if _is_equipment_item(str(row.get("itemId", ""))):
			has_equipment = true
			break
	if not has_equipment:
		var armory_table: Array = biome.get("lootTables", {}).get("armory", [])
		var forced := _pick_equipment_entry(armory_table, tier, rng)
		if not forced.is_empty():
			table.append(forced)
	var items: Array = []
	for i in table.size():
		var row: Dictionary = table[i]
		items.append(
			{
				"itemId": str(row.get("itemId", "")),
				"quantity": int(row.get("quantity", 1)),
				"instanceId": "%s_%d" % [room_id, i],
			}
		)
	return items


static func _is_equipment_item(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	return str(ItemCatalog.get_definition(item_id).get("equipmentSlot", "")) != ""


static func _pick_equipment_entry(
	table: Array, tier: int, rng: RandomNumberGenerator
) -> Dictionary:
	var eligible: Array = []
	for entry in table:
		var item_id := str(entry.get("itemId", ""))
		if int(entry.get("minTier", 1)) > tier:
			continue
		if _is_equipment_item(item_id):
			eligible.append(entry)
	if eligible.is_empty():
		return {}
	var entry: Dictionary = eligible[rng.randi_range(0, eligible.size() - 1)]
	var qty: Variant = entry.get("quantity", 1)
	var quantity := int(qty[0]) if qty is Array and not (qty as Array).is_empty() else int(qty)
	return {"itemId": str(entry.get("itemId", "")), "quantity": maxi(1, quantity)}


static func _roll_chest_items(
	biome_id: String,
	rng: RandomNumberGenerator,
	room_id: String,
	content_type: String,
	tier: int = 1,
	inputs: Dictionary = {}
) -> Array:
	var biome := BiomeRegistry.get_biome(biome_id)
	if biome.is_empty():
		return []
	var role := "secret" if content_type == RoomContentTypes.LOCKED_VAULT else "side"
	var table: Array = ProcgenLootRoller.roll_chest(
		biome, role, maxi(1, tier), rng, 0.0, inputs.get("lockedItems", [])
	)
	var items: Array = []
	for i in table.size():
		var row: Dictionary = table[i]
		items.append(
			{
				"itemId": str(row.get("itemId", "")),
				"quantity": int(row.get("quantity", 1)),
				"instanceId": "%s_%d" % [room_id, i],
			}
		)
	return items


## An accepted escort quest (`content/quests/*.json`, type `escort`) names a `targetNpcId`;
## `dungeon_quests.json`'s matching `rescue_<name>` entry carries the same id, so an active escort
## quest's NPC is preferred over the uniform-random pick whenever this biome can place it.
static func _pick_dungeon_quest(biome_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var quests: Array = []
	for candidate in DungeonQuestCatalogScript.quests_for_biome(biome_id):
		if candidate is Dictionary and _rescue_quest_is_available(candidate):
			quests.append(candidate)
	if quests.is_empty():
		return {
			"questKeyId": "met_dungeon_npc",
			"dialogueId": "dungeon_npc_stranded",
		}
	if QuestService:
		var active_targets: Dictionary = {}
		for quest_def in QuestService.get_active_quests():
			if str(quest_def.get("type", "")) != "escort":
				continue
			var target_npc := str(quest_def.get("targetNpcId", ""))
			if target_npc != "":
				active_targets[target_npc] = true
		if not active_targets.is_empty():
			for quest in quests:
				if active_targets.has(str(quest.get("targetNpcId", ""))):
					return quest
	return quests[rng.randi_range(0, quests.size() - 1)]


## A committed rescue remains represented in the world for this run, but must not be offered as a
## second rescue. Completed or failed rescues resolve to an empty-landing dialogue and must not be
## regenerated at all; deferred rescues intentionally remain available for a later revisit.
static func _rescue_quest_is_available(quest: Dictionary) -> bool:
	var dialogue_id := str(quest.get("dialogueId", ""))
	if not dialogue_id.begins_with("rescue_"):
		return true
	var npc_id := dialogue_id.trim_prefix("rescue_")
	if npc_id == "" or CharacterService == null:
		return true
	for prefix in ["rescued_", "lost_", "rescue_committed_"]:
		if bool(CharacterService.get_flag(prefix + npc_id, false)):
			return false
	return true


static func _build_puzzle_entry(
	entry: Dictionary,
	graph: RoomGraph,
	layout_semantic: Dictionary,
	critical_set: Dictionary,
	rng: RandomNumberGenerator,
	reserved_semantics: Array[String]
) -> Dictionary:
	var room_id := str(entry.get("roomId", ""))
	var layout_id := str(entry.get("layoutId", ""))
	var gate_layout := _find_puzzle_gate_layout(
		graph, layout_id, layout_semantic, critical_set, reserved_semantics, rng
	)
	if gate_layout == "":
		return {}
	var lever_count := rng.randi_range(1, 3)
	var flag_id := "puzzle_%s" % room_id
	return {
		"puzzleId": flag_id,
		"roomId": room_id,
		"kind": "lever_gate",
		"flagId": flag_id,
		"gateRoomId": str(layout_semantic.get(gate_layout, "")),
		"gateLayoutId": gate_layout,
		"leverCount": lever_count,
		"solutionOrder": _shuffled_indices(lever_count, rng),
	}


static func _find_puzzle_gate_layout(
	graph: RoomGraph,
	puzzle_layout: String,
	layout_semantic: Dictionary,
	critical_set: Dictionary,
	reserved_semantics: Array[String],
	rng: RandomNumberGenerator
) -> String:
	var adj := RoomGraphPaths.build_adjacency(graph)
	var candidates: Array[Dictionary] = []
	for neighbor_id in adj.get(puzzle_layout, []):
		var semantic := str(layout_semantic.get(neighbor_id, ""))
		if semantic in reserved_semantics or critical_set.has(semantic):
			continue
		var off_depth := RoomGraphPaths.branch_depth_for_slot(graph, neighbor_id)
		if off_depth < 1:
			continue
		(
			candidates
			. append({"layoutId": neighbor_id, "offDepth": off_depth})
		)
	if candidates.is_empty():
		return ""
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("offDepth", 0)) > int(b.get("offDepth", 0))
	)
	var best_off := int(candidates[0].get("offDepth", 0))
	var tied: Array[Dictionary] = []
	for candidate in candidates:
		if int(candidate.get("offDepth", 0)) == best_off:
			tied.append(candidate)
	return str(tied[rng.randi_range(0, tied.size() - 1)].get("layoutId", ""))


static func _shuffled_indices(count: int, rng: RandomNumberGenerator) -> Array:
	var indices: Array = []
	for i in count:
		indices.append(i)
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = int(indices[i])
		indices[i] = indices[j]
		indices[j] = tmp
	return indices


static func _entry_for_special(room: Dictionary, slot: RoomGraphSlot) -> Dictionary:
	var content_type := RoomContentTypes.COMBAT
	if slot:
		match slot.slot_type:
			RoomGraphSlot.SlotType.BOSS:
				content_type = RoomContentTypes.BOSS
			RoomGraphSlot.SlotType.TREASURE:
				content_type = RoomContentTypes.REWARD
			RoomGraphSlot.SlotType.STAIRS:
				content_type = RoomContentTypes.STAIRS
			RoomGraphSlot.SlotType.START:
				content_type = RoomContentTypes.EMPTY
	return {
		"roomId": room["semantic_id"],
		"layoutId": room["layout_id"],
		"contentType": content_type,
		"templateId": "",
	}


static func _reserved_semantics(
	graph: RoomGraph, _assignment: Dictionary, layout_semantic: Dictionary
) -> Array[String]:
	var reserved: Array[String] = []
	reserved.append(layout_semantic.get(graph.start_id, "entrance"))
	reserved.append(layout_semantic.get(graph.stairs_id, "stairs"))
	reserved.append(layout_semantic.get(graph.boss_id, "boss"))
	if graph.treasure_id != "":
		reserved.append(layout_semantic.get(graph.treasure_id, "treasure"))
	return reserved


static func build_branch_previews(
	graph: RoomGraph, assignment: Dictionary, room_content: Array
) -> Array:
	var layout_semantic := _layout_to_semantic(assignment)
	var content_by_room: Dictionary = {}
	for entry in room_content:
		if entry is Dictionary:
			content_by_room[str((entry as Dictionary).get("roomId", ""))] = entry
	var critical_layout: Array[String] = RoomGraphPaths.critical_path_ids(graph)
	var critical_layout_set := {}
	for layout_id in critical_layout:
		critical_layout_set[layout_id] = true
	var adj := RoomGraphPaths.build_adjacency(graph)
	var previews: Array = []
	var seen: Dictionary = {}
	for layout_id in adj:
		for neighbor_layout in adj.get(layout_id, []):
			if critical_layout_set.has(neighbor_layout):
				continue
			var from_sem := str(layout_semantic.get(layout_id, layout_id))
			var to_sem := str(layout_semantic.get(neighbor_layout, neighbor_layout))
			var key := "%s>%s" % [from_sem, to_sem]
			if seen.has(key):
				continue
			seen[key] = true
			var destination_content: Dictionary = content_by_room.get(to_sem, {}) as Dictionary
			var clue := _branch_clue_for_content_type(
				str(destination_content.get("contentType", ""))
			)
			(
				previews
				. append(
					{
						"fromRoomId": from_sem,
						"toRoomId": to_sem,
						# The profile is authored content, not an inference from map topology. A type
						# appears only when its room family has a designed doorway clue; every other
						# branch remains an outline so the map supports spatial learning, not routing.
						"hint": str(clue.get("hint", "unknown")),
						"clueQuality": int(clue.get("clueQuality", 0)),
					}
				)
			)
	previews.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var ak := "%s>%s" % [a.get("fromRoomId", ""), a.get("toRoomId", "")]
			var bk := "%s>%s" % [b.get("fromRoomId", ""), b.get("toRoomId", "")]
			return ak < bk
	)
	return previews


static func _branch_clue_for_content_type(content_type: String) -> Dictionary:
	_ensure_branch_clue_profiles()
	var profile: Variant = _branch_clue_profiles.get(content_type, {})
	return profile.duplicate(true) if profile is Dictionary else {}


static func _ensure_branch_clue_profiles() -> void:
	if _branch_clue_profiles_loaded:
		return
	_branch_clue_profiles_loaded = true
	var raw: Dictionary = ContentLoader.load_json(BRANCH_CLUE_PROFILES_PATH)
	var profiles: Variant = raw.get("contentTypes", {})
	if profiles is Dictionary:
		_branch_clue_profiles = (profiles as Dictionary).duplicate(true)


static func _layout_to_semantic(assignment: Dictionary) -> Dictionary:
	var map := {}
	for room in assignment.get("rooms", []):
		map[room["layout_id"]] = room["semantic_id"]
	return map


static func _fallback_assignment(
	graph: RoomGraph,
	assignment: Dictionary,
	layout_semantic: Dictionary,
	critical_semantic: Array[String],
	critical_layout: Array[String],
	distances: Dictionary,
	rng: RandomNumberGenerator,
	biome_id: String,
	config: RoomContentConfig,
	tier: int
) -> Dictionary:
	var room_content: Array = []
	for room in assignment.get("rooms", []):
		var entry := {
			"roomId": room["semantic_id"],
			"layoutId": room["layout_id"],
			"contentType":
			RoomContentTypes.COMBAT if room.get("type", "") != "filler" else RoomContentTypes.EMPTY,
			"templateId": "",
		}
		room_content.append(entry)
	var locks: Array = []
	var reserved_semantics := _reserved_semantics(graph, assignment, layout_semantic)
	# A fallback is still a playable floor, not permission to discard the pacing contract. In
	# particular, this keeps the guaranteed lore location present when a complex assignment rerolls.
	_apply_floor_recipe(room_content, graph, layout_semantic, critical_semantic, reserved_semantics, config, rng)
	if critical_semantic.size() >= 4:
		locks = RoomLockPlacer.place_locked_doors(
			graph,
			layout_semantic,
			critical_layout,
			critical_semantic,
			distances,
			rng,
			config,
			reserved_semantics,
			false,
			RoomLockPlacer.content_by_semantic(room_content)
		)
		for lock in locks:
			RoomLockPlacer.apply_key_to_content(room_content, lock, reserved_semantics)
	var critical_set := {}
	for room_id in critical_semantic:
		critical_set[room_id] = true
	var puzzles := _finalize_content_entries(
		room_content,
		graph,
		layout_semantic,
		critical_set,
		rng,
		biome_id,
		reserved_semantics,
		tier,
		config.generation_inputs
	)
	var content := {"roomContent": room_content, "locks": locks, "puzzles": puzzles}
	var warnings: Array[String] = []
	var check := RoomContentValidator.validate(graph, assignment, content, config)
	if not bool(check.get("ok", false)):
		var reason := str(check.get("reason", "unknown"))
		push_warning(
			"RoomContentAssigner: fallback floor failed validation (%s) — dropping locks" % reason
		)
		# Peel one lock at a time rather than clearing them all. It is usually a single bad lock
		# that sinks the check -- one whose key room the fallback could not actually furnish -- and
		# discarding its siblings with it is what left these floors with no gating at all.
		warnings.append("fallback_locks_peeled: %s" % reason)
		while not locks.is_empty():
			var dropped: Dictionary = locks.pop_back()
			RoomLockPlacer.revert_key_rooms(room_content, dropped)
			content = {"roomContent": room_content, "locks": locks, "puzzles": puzzles}
			if locks.is_empty():
				break
			if bool(
				RoomContentValidator.validate(graph, assignment, content, config).get("ok", false)
			):
				break
		content = {"roomContent": room_content, "locks": locks, "puzzles": puzzles}
	return {
		"ok": true,
		"content": content,
		"used_fallback": true,
		"warnings": warnings,
	}


class_name RoomGraphAssigner
extends RefCounted


const COMBAT_SEMANTICS := ["courtyard", "hall", "arena"]

static var _fallback_warned: Dictionary = {}


static func assign(
	biome: Dictionary, graph: RoomGraph, rng: RandomNumberGenerator, config: RoomGraphConfig = null
) -> Dictionary:
	var prefix := RoomTemplateCatalog.template_prefix_for_biome(
		str(biome.get("id", "forgotten_castle"))
	)
	var biome_templates: Array = biome.get("roomTemplateIds", [])
	var combat_preferred := {
		"courtyard": "%s_courtyard" % prefix,
		"hall": "%s_hall" % prefix,
		"arena": "%s_arena" % prefix,
	}
	var rooms: Array[Dictionary] = []
	var combat_index := 0
	var filler_index := 0
	var dropped_layout_ids: Array[String] = []
	# RM-17: the one piece of role information `_combat_size_kind()` cannot derive from a slot
	# alone -- whether it is the room immediately before the boss on the critical path.
	var pre_boss_layout := ""
	var critical_layout := RoomGraphPaths.critical_path_ids(graph)
	var boss_idx := critical_layout.find(graph.boss_id)
	if boss_idx > 0:
		pre_boss_layout = critical_layout[boss_idx - 1]
	for layout_id in _sorted_layout_ids(graph):
		var slot := graph.get_slot(layout_id)
		var resolved := _resolve_room(
			graph,
			slot,
			prefix,
			combat_preferred,
			biome_templates,
			combat_index,
			filler_index,
			rng,
			pre_boss_layout
		)
		if str(resolved.get("template_id", "")).is_empty():
			dropped_layout_ids.append(layout_id)
			continue
		if resolved["type"] == "combat":
			combat_index += 1
		if resolved["type"] == "filler":
			filler_index += 1
		(
			rooms
			. append(
				{
					"layout_id": layout_id,
					"semantic_id": resolved["semantic_id"],
					"template_id": resolved["template_id"],
					"type": resolved["type"],
					"tags": resolved["tags"],
				}
			)
		)
	if config != null:
		_convert_corridors(graph, rooms, prefix, config, rng)
		_convert_one_balcony(graph, rooms, prefix, config, rng)
	return {
		"rooms": rooms,
		"entrance_layout_id": graph.start_id,
		"boss_layout_id": graph.boss_id,
		"secret_layout_ids": _without(graph.secret_ids, dropped_layout_ids),
		"treasure_layout_id": graph.treasure_id,
		"stairs_layout_id": graph.stairs_id,
	}


## RM-14: the lattice seats every room flush against its neighbours with no threshold between them,
## so this converts `config.corridor_ratio` of the rooms that can host one -- a NORMAL combat slot
## with exactly two doors, north and south -- into an actual corridor template after the fact.
##
## Restricted to north/south only, not any two-opposite-doors slot: `corridor`'s own door mask
## (north|south, not a single bit) never gets the auto-yaw rotation `_yaw_for()` gives single-door
## templates, so a corridor placed against an east/west slot would build with doors on the wrong
## walls entirely. An east/west two-door slot simply is not eligible here.
##
## The "must not hand a corridor a slot needing a third door" trap the plan calls out is already
## closed by `supports_doors()`: corridor's mask has two bits set, so `primary_door_mask()` returns
## 0 for it and the loose single-bit fallback never engages -- only the exact-subset check can match
## it, which a 3+ door slot can never satisfy. No separate strict-doors list needed.
static func _convert_corridors(
	graph: RoomGraph,
	rooms: Array[Dictionary],
	prefix: String,
	config: RoomGraphConfig,
	rng: RandomNumberGenerator
) -> void:
	if config.corridor_ratio <= 0.0:
		return
	var ns_mask := RoomGraphSlot.DOOR_NORTH | RoomGraphSlot.DOOR_SOUTH
	var eligible: Array[int] = []
	for i in rooms.size():
		var room: Dictionary = rooms[i]
		if str(room.get("type", "")) != "combat":
			continue
		var slot := graph.get_slot(str(room.get("layout_id", "")))
		if slot == null or slot.door_mask != ns_mask:
			continue
		eligible.append(i)
	if eligible.is_empty():
		return
	for i in range(eligible.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := eligible[i]
		eligible[i] = eligible[j]
		eligible[j] = tmp
	var target := int(round(float(eligible.size()) * config.corridor_ratio))
	for pick in range(mini(target, eligible.size())):
		var idx: int = eligible[pick]
		var template_id := "%s_corridor" % prefix
		if rng.randf() < 0.4:
			template_id = "%s_corridor_long" % prefix
		rooms[idx]["template_id"] = template_id
		rooms[idx]["type"] = "corridor"


## RM-17: "small" (`hall`), "medium" (`courtyard`) or "large" (`arena`), picked from the room's
## depth and role rather than a fixed rotation -- the floor should open up as it goes, so starting
## big and ending small reads backwards. Checked in priority order: a junction always wants the
## space to fight in regardless of depth, then the pre-boss room, then the near-entrance and
## dead-end cases that want to stay small, and anything left over (mid-path, on the critical path)
## gets the medium default.
static func _combat_size_kind(slot: RoomGraphSlot, pre_boss_layout: String) -> String:
	if slot.connection_count() >= 3:
		return "arena"
	if pre_boss_layout != "" and slot.slot_id == pre_boss_layout:
		return "arena"
	if slot.graph_distance <= 2:
		return "hall"
	if slot.is_dead_end():
		return "hall"
	return "courtyard"


## RM-19: one balcony per floor, only on a floor that actually has a second height level to put
## one on. Eligibility mirrors `_convert_corridors()` exactly -- a NORMAL combat slot with exactly
## north and south doors -- since `balcony`'s "split" shape shares the same north/south-only
## restriction corridors do (an east/west door would sit on the seam between the two floor
## heights). Picked at random from the eligible set via the same seeded `rng` the rest of
## assignment uses, so it is deterministic per floor seed like everything else here.
static func _convert_one_balcony(
	graph: RoomGraph,
	rooms: Array[Dictionary],
	prefix: String,
	config: RoomGraphConfig,
	rng: RandomNumberGenerator
) -> void:
	if config.max_height_level < 2:
		return
	var ns_mask := RoomGraphSlot.DOOR_NORTH | RoomGraphSlot.DOOR_SOUTH
	var eligible: Array[int] = []
	for i in rooms.size():
		var room: Dictionary = rooms[i]
		if str(room.get("type", "")) != "combat":
			continue
		var slot := graph.get_slot(str(room.get("layout_id", "")))
		if slot == null or slot.door_mask != ns_mask:
			continue
		eligible.append(i)
	if eligible.is_empty():
		return
	var idx: int = eligible[rng.randi_range(0, eligible.size() - 1)]
	rooms[idx]["template_id"] = "%s_balcony" % prefix


static func _pick_required_template(
	preferred_template_id: String,
	required_doors: int,
	biome_templates: Array,
	rng: RandomNumberGenerator,
	required_kind: String
) -> String:
	var picked := RoomTemplateCatalog.pick_template_for_doors(
		preferred_template_id, required_doors, biome_templates, rng, required_kind
	)
	if not picked.is_empty():
		return picked
	var warn_key := "%s/%d" % [required_kind, required_doors]
	if not _fallback_warned.has(warn_key):
		_fallback_warned[warn_key] = true
		push_warning(
			(
				"RoomGraphAssigner: no '%s' template fits door mask %d; using an unfiltered"
				+ " fallback. (further occurrences for this combination suppressed)"
			)
			% [required_kind, required_doors]
		)
	return RoomTemplateCatalog.pick_template_for_doors(
		preferred_template_id, required_doors, biome_templates, rng
	)


static func _without(source: Array, excluded: Array) -> Array:
	var kept: Array = []
	for value in source:
		if not excluded.has(value):
			kept.append(value)
	return kept


static func _sorted_layout_ids(graph: RoomGraph) -> Array[String]:
	var ids: Array[String] = []
	for cell in graph.occupied_cells():
		ids.append(graph.slots[cell].slot_id)
	return ids


static func _resolve_room(
	graph: RoomGraph,
	slot: RoomGraphSlot,
	prefix: String,
	combat_preferred: Dictionary,
	biome_templates: Array,
	combat_index: int,
	filler_index: int,
	rng: RandomNumberGenerator,
	pre_boss_layout: String = ""
) -> Dictionary:
	if slot.is_filler:
		var filler_doors := _required_doors_for_slot(graph, slot)
		return {
			"semantic_id": "filler_%d" % filler_index,
			"template_id":
			RoomTemplateCatalog.pick_template_for_doors(
				"%s_hall" % prefix, filler_doors, biome_templates, rng
			),
			"type": "filler",
			"tags": ["filler"],
		}
	match slot.slot_type:
		RoomGraphSlot.SlotType.START:
			var start_doors := _required_doors_for_slot(graph, slot)
			return {
				"semantic_id": "entrance",
				"template_id":
				_pick_required_template(
					"%s_entrance" % prefix, start_doors, biome_templates, rng, "entrance"
				),
				"type": "hub",
				"tags": ["spawn"],
			}
		RoomGraphSlot.SlotType.BOSS:
			var boss_doors := _required_doors_for_slot(graph, slot)
			return {
				"semantic_id": "boss",
				"template_id":
				_pick_required_template(
					"%s_boss" % prefix, boss_doors, biome_templates, rng, "boss"
				),
				"type": "boss",
				"tags": ["exit_portal"],
			}
		RoomGraphSlot.SlotType.TREASURE:
			var treasure_doors := _required_doors_for_slot(graph, slot)
			return {
				"semantic_id": "treasure",
				"template_id":
				RoomTemplateCatalog.pick_template_for_doors(
					"%s_treasure" % prefix, treasure_doors, biome_templates, rng
				),
				"type": "treasure",
				"tags": [],
			}
		RoomGraphSlot.SlotType.STAIRS:
			var stairs_doors := _required_doors_for_slot(graph, slot)
			return {
				"semantic_id": "stairs",
				"template_id":
				_pick_required_template(
					"%s_stairs" % prefix, stairs_doors, biome_templates, rng, "stairs"
				),
				"type": "corridor",
				"tags": [],
			}
		RoomGraphSlot.SlotType.OBSTACLE:
			var obstacle_doors := _required_doors_for_slot(graph, slot)
			return {
				"semantic_id": "obstacle",
				"template_id":
				RoomTemplateCatalog.pick_template_for_doors(
					"%s_puzzle" % prefix, obstacle_doors, biome_templates, rng
				),
				"type": "obstacle",
				"tags": ["traversal"],
			}
		RoomGraphSlot.SlotType.SECRET:
			var secret_index := graph.secret_ids.find(slot.slot_id)
			var semantic: String = (
				"secret" if graph.secret_ids.size() <= 1 else "secret_%d" % (secret_index + 1)
			)
			var secret_doors := _required_doors_for_secret(graph, slot)
			return {
				"semantic_id": semantic,
				"template_id":
				RoomTemplateCatalog.pick_template_for_doors(
					"%s_secret" % prefix, secret_doors, biome_templates, rng, "secret"
				),
				"type": "secret",
				"tags": ["secret_room"],
			}
		_:
			# RM-17: the semantic id still cycles through the three combat names for a readable
			# label (`courtyard`, `hall`, `arena`, `combat_3`, ...), but which *template* gets
			# preferred is now the room's role in the graph, not that same index. A floor that
			# opens up as it goes needs its size to track depth and junction-ness, not turn order.
			var semantic: String = (
				COMBAT_SEMANTICS[combat_index]
				if combat_index < COMBAT_SEMANTICS.size()
				else "combat_%d" % combat_index
			)
			var size_kind := _combat_size_kind(slot, pre_boss_layout)
			var required_doors := _required_doors_for_slot(graph, slot)
			var preferred: String = combat_preferred.get(size_kind, "%s_courtyard" % prefix)
			return {
				"semantic_id": semantic,
				"template_id":
				RoomTemplateCatalog.pick_template_for_doors(
					preferred, required_doors, biome_templates, rng
				),
				"type": "combat",
				"tags": [],
			}


static func _required_doors_for_slot(_graph: RoomGraph, slot: RoomGraphSlot) -> int:
	return slot.door_mask


static func _required_doors_for_secret(graph: RoomGraph, secret_slot: RoomGraphSlot) -> int:
	if secret_slot.secret_parent_id == "":
		return RoomGraphSlot.DOOR_EAST
	var parent := graph.get_slot(secret_slot.secret_parent_id)
	if parent == null:
		return RoomGraphSlot.DOOR_EAST
	var dx := secret_slot.grid_pos.x - parent.grid_pos.x
	var dz := secret_slot.grid_pos.y - parent.grid_pos.y
	var doors := RoomTemplateCatalog.doors_for_step(dx, dz)
	return int(doors[1])

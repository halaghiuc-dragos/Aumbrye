class_name RoomGraphAssigner
extends RefCounted

## Assign semantic ids, templates, and types from a validated Phase 1 graph.

const COMBAT_SEMANTICS := ["courtyard", "hall", "arena"]


static func assign(biome: Dictionary, graph: RoomGraph, rng: RandomNumberGenerator) -> Dictionary:
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
	for layout_id in _sorted_layout_ids(graph):
		var slot := graph.get_slot(layout_id)
		var resolved := _resolve_room(
			graph, slot, prefix, combat_preferred, biome_templates, combat_index, filler_index, rng
		)
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
	return {
		"rooms": rooms,
		"entrance_layout_id": graph.start_id,
		"boss_layout_id": graph.boss_id,
		"secret_layout_ids": graph.secret_ids.duplicate(),
		"treasure_layout_id": graph.treasure_id,
		"stairs_layout_id": graph.stairs_id,
	}


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
	rng: RandomNumberGenerator
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
				RoomTemplateCatalog.pick_template_for_doors(
					"%s_entrance" % prefix, start_doors, biome_templates, rng, "entrance"
				),
				"type": "hub",
				"tags": ["spawn"],
			}
		RoomGraphSlot.SlotType.BOSS:
			return {
				"semantic_id": "boss",
				"template_id": "%s_boss" % prefix,
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
				RoomTemplateCatalog.pick_template_for_doors(
					"%s_stairs" % prefix, stairs_doors, biome_templates, rng, "stairs"
				),
				"type": "corridor",
				"tags": [],
			}
		RoomGraphSlot.SlotType.SHOP:
			var shop_doors := _required_doors_for_slot(graph, slot)
			return {
				"semantic_id": "shop",
				"template_id":
				RoomTemplateCatalog.pick_template_for_doors(
					"%s_shop" % prefix, shop_doors, biome_templates, rng
				),
				"type": "shop",
				"tags": ["merchant"],
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
			var semantic: String = (
				COMBAT_SEMANTICS[combat_index]
				if combat_index < COMBAT_SEMANTICS.size()
				else "combat_%d" % combat_index
			)
			var required_doors := _required_doors_for_slot(graph, slot)
			var preferred: String = combat_preferred.get(semantic, "%s_courtyard" % prefix)
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

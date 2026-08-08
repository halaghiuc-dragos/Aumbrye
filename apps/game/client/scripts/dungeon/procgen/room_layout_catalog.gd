class_name RoomLayoutCatalog
extends RefCounted

## Per-biome room layout variants from content/rooms/. Variant 0 is always the room kit's own
## anchor set; the rest come from data, so two courtyards in one floor rarely lay out the same.

const LAYOUT_DIR := "content/rooms"

static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


static func variants_for_kind(biome_id: String, kind: String) -> Array:
	var layouts := _layouts_for_biome(biome_id)
	var list: Variant = layouts.get(kind, [])
	return list if list is Array else []


static func variant_count(biome_id: String, kind: String) -> int:
	return 1 + variants_for_kind(biome_id, kind).size()


## Pure: the same seed and room id always resolve to the same variant, in any call order.
static func variant_for_room(biome_id: String, run_seed: int, room_id: String, template_id: String) -> int:
	var kind := RoomTemplateCatalog.kind_from_template_id(template_id)
	var count := variant_count(biome_id, kind)
	if count <= 1 or room_id == "":
		return 0
	var salt := absi(room_id.hash()) % 1_000_000 + 2
	var mixed := FloorSeedMix.mix(maxi(1, run_seed), salt)
	return absi(mixed) % count


static func anchors_for(
	biome_id: String, template_id: String, role: String, variant: int = 0
) -> Array:
	if variant <= 0:
		return RoomTemplateCatalog.anchors_for(template_id, role)
	var kind := RoomTemplateCatalog.kind_from_template_id(template_id)
	var variants := variants_for_kind(biome_id, kind)
	var index := variant - 1
	if index < 0 or index >= variants.size():
		return RoomTemplateCatalog.anchors_for(template_id, role)
	var entry: Variant = variants[index]
	if not entry is Dictionary:
		return RoomTemplateCatalog.anchors_for(template_id, role)
	var anchors: Variant = (entry as Dictionary).get("anchors", {})
	if not anchors is Dictionary:
		return RoomTemplateCatalog.anchors_for(template_id, role)
	var rows: Variant = (anchors as Dictionary).get(role, [])
	if not rows is Array or (rows as Array).is_empty():
		return RoomTemplateCatalog.anchors_for(template_id, role)
	var out: Array = []
	for row in rows:
		if row is Array and (row as Array).size() >= 3:
			out.append(Vector3(float(row[0]), float(row[1]), float(row[2])))
	if out.is_empty():
		return RoomTemplateCatalog.anchors_for(template_id, role)
	return out


static func _layouts_for_biome(biome_id: String) -> Dictionary:
	if _cache.has(biome_id):
		return _cache[biome_id]
	var data := ContentLoader.load_json("%s/%s.json" % [LAYOUT_DIR, biome_id])
	var variants: Variant = data.get("variants", {}) if data is Dictionary else {}
	var resolved: Dictionary = variants if variants is Dictionary else {}
	_cache[biome_id] = resolved
	return resolved

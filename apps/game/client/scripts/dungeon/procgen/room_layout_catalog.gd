class_name RoomLayoutCatalog
extends RefCounted


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


## Weighted pick across the template's own baseline (index 0, weight 1) and every authored variant
## (index 1..n, `"weight"` defaults to 1). Deterministic per room via the same seed mix every other
## per-room roll in this generator uses.
static func variant_for_room(biome_id: String, run_seed: int, room_id: String, template_id: String) -> int:
	var kind := RoomTemplateCatalog.kind_from_template_id(template_id)
	var variants := variants_for_kind(biome_id, kind)
	if variants.is_empty() or room_id == "":
		return 0
	var weights: Array[int] = [1]
	for entry in variants:
		var w := 1
		if entry is Dictionary:
			w = maxi(1, int(round(float((entry as Dictionary).get("weight", 1.0)))))
		weights.append(w)
	var total := 0
	for w in weights:
		total += w
	var salt := absi(room_id.hash()) % 1_000_000 + 2
	var mixed := FloorSeedMix.mix(maxi(1, run_seed), salt)
	var roll := absi(mixed) % total
	var cursor := 0
	for i in weights.size():
		cursor += weights[i]
		if roll < cursor:
			return i
	return 0


## The full variant record (shape/anchors/props/coverPattern), whatever subset of those keys the
## content author actually wrote -- every key is optional (RM-03). Returns `{}` for variant 0 (the
## template's own baseline, not a JSON-authored variant) or an out-of-range/malformed index.
static func variant_data_for(biome_id: String, template_id: String, variant: int) -> Dictionary:
	if variant <= 0:
		return {}
	var kind := RoomTemplateCatalog.kind_from_template_id(template_id)
	var variants := variants_for_kind(biome_id, kind)
	var index := variant - 1
	if index < 0 or index >= variants.size():
		return {}
	var entry: Variant = variants[index]
	return entry if entry is Dictionary else {}


static func anchors_for(
	biome_id: String, template_id: String, role: String, variant: int = 0
) -> Array:
	var entry := variant_data_for(biome_id, template_id, variant)
	var anchors: Variant = entry.get("anchors", {})
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


## `""` when the variant does not override shape -- callers should keep the template's own shape.
static func shape_for(biome_id: String, template_id: String, variant: int) -> String:
	var entry := variant_data_for(biome_id, template_id, variant)
	var shape: Variant = entry.get("shape", "")
	return str(shape)


## Raw `props` list (`[{kind, at:[x,y,z], yaw}, ...]`) authored on the variant, or `[]`.
static func props_for(biome_id: String, template_id: String, variant: int) -> Array:
	var entry := variant_data_for(biome_id, template_id, variant)
	var props: Variant = entry.get("props", [])
	return props if props is Array else []


## `""` when the variant does not override the cover pattern -- callers should keep the default.
static func cover_pattern_for(biome_id: String, template_id: String, variant: int) -> String:
	var entry := variant_data_for(biome_id, template_id, variant)
	var pattern: Variant = entry.get("coverPattern", "")
	return str(pattern)


static func _layouts_for_biome(biome_id: String) -> Dictionary:
	if _cache.has(biome_id):
		return _cache[biome_id]
	var data := ContentLoader.load_json("%s/%s.json" % [LAYOUT_DIR, biome_id])
	var variants: Variant = data.get("variants", {}) if data is Dictionary else {}
	var resolved: Dictionary = variants if variants is Dictionary else {}
	_cache[biome_id] = resolved
	return resolved

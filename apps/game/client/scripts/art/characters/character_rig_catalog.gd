extends RefCounted
class_name CharacterRigCatalog

## Loads character rig manifests from content/characters/.

const CONTENT_DIR := "res://../../content/characters/"
const MANIFEST_SUFFIX := ".json"

const BIOME_ARCHETYPE_IDS := {
	PixelDioramaStyle.PaletteTheme.CASTLE: "enemy_biome_castle",
	PixelDioramaStyle.PaletteTheme.CRYSTAL: "enemy_biome_crystal",
	PixelDioramaStyle.PaletteTheme.SWAMP: "enemy_biome_swamp",
	PixelDioramaStyle.PaletteTheme.FROZEN: "enemy_biome_frost",
	PixelDioramaStyle.PaletteTheme.CATHEDRAL: "enemy_biome_cathedral",
	PixelDioramaStyle.PaletteTheme.VAULT: "enemy_biome_vault",
	PixelDioramaStyle.PaletteTheme.PRISM: "enemy_biome_prism",
	PixelDioramaStyle.PaletteTheme.MIRE: "enemy_biome_mire",
	PixelDioramaStyle.PaletteTheme.HOLLOW: "enemy_biome_hollow",
	PixelDioramaStyle.PaletteTheme.UMBRAL: "enemy_biome_umbral",
	PixelDioramaStyle.PaletteTheme.HUB: "enemy_biome_castle",
}

static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


static func list_archetype_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	var dir := DirAccess.open(CONTENT_DIR)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(MANIFEST_SUFFIX):
			ids.append(file_name.trim_suffix(MANIFEST_SUFFIX))
		file_name = dir.get_next()
	dir.list_dir_end()
	ids.sort()
	return ids


static func has_manifest(archetype_id: String) -> bool:
	return not get_manifest(archetype_id).is_empty()


static func get_manifest(archetype_id: String) -> Dictionary:
	if _cache.has(archetype_id):
		return _cache[archetype_id]
	var path := CONTENT_DIR + archetype_id + MANIFEST_SUFFIX
	if not FileAccess.file_exists(path):
		_cache[archetype_id] = {}
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_cache[archetype_id] = parsed
		return parsed
	_cache[archetype_id] = {}
	return {}


static func archetype_for_player(profile: Dictionary) -> String:
	var height := str(
		profile.get(
			"heightVariant",
			CharacterAppearance.height_variant_from_legacy(float(profile.get("height", 1.0)))
		)
	)
	var bulk := str(
		profile.get(
			"bulkVariant",
			CharacterAppearance.bulk_variant_from_legacy(float(profile.get("bulk", 1.0)))
		)
	)
	var archetype := "player_warden"
	if height != CharacterAppearance.HEIGHT_VARIANT_STANDARD:
		archetype += "_%s" % height
	if bulk != CharacterAppearance.BULK_VARIANT_STANDARD:
		archetype += "_%s" % bulk
	if has_manifest(archetype):
		return archetype
	if has_manifest("player_warden_%s" % height):
		return "player_warden_%s" % height
	return "player_warden"


static func archetype_for_enemy(enemy_id: String, data: Dictionary) -> String:
	var profile := DioramaCharacterSkin.profile_for_enemy_data(data)
	match profile:
		"hound":
			return "enemy_hound"
		"ranged":
			return "enemy_ranged"
		"shield":
			return "enemy_shield"
		"brute":
			return "enemy_brute"
		"dummy":
			return "enemy_dummy"
	var theme := DioramaCharacterSkin.theme_for_enemy_id(enemy_id)
	return BIOME_ARCHETYPE_IDS.get(theme, "enemy_biome_castle")

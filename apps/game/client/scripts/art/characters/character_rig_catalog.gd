extends RefCounted
class_name CharacterRigCatalog


const CONTENT_RELATIVE := "content/characters"
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


static func has_manifest(archetype_id: String) -> bool:
	return not get_manifest(archetype_id).is_empty()


static func get_manifest(archetype_id: String) -> Dictionary:
	if _cache.has(archetype_id):
		return _cache[archetype_id]
	var path := ContentLoader.content_path(CONTENT_RELATIVE).path_join(archetype_id + MANIFEST_SUFFIX)
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
	var frame := str(profile.get("frame", ""))
	if not (frame in CharacterAppearance.FRAME_VARIANTS):
		frame = CharacterAppearance.frame_from_legacy(
			str(
				profile.get(
					"heightVariant",
					CharacterAppearance.height_variant_from_legacy(
						float(profile.get("height", 1.0))
					)
				)
			),
			str(
				profile.get(
					"bulkVariant",
					CharacterAppearance.bulk_variant_from_legacy(float(profile.get("bulk", 1.0)))
				)
			)
		)
	if frame == CharacterAppearance.FRAME_STANDARD:
		return "player_warden"
	var archetype := "player_warden_%s" % frame
	return archetype if has_manifest(archetype) else "player_warden"


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

class_name CharacterAppearance
extends RefCounted

## Warden visual customization — persisted on character save.

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")

const HEAD_OPEN := "open"
const HEAD_VISOR := "visor"
const HEAD_HOOD := "hood"

const HEIGHT_PRESETS := [0.9, 1.0, 1.1]
const HEIGHT_LABELS := ["Compact", "Standard", "Tall"]

const BULK_PRESETS := [0.88, 1.0, 1.14]
const BULK_LABELS := ["Lean", "Standard", "Heavy"]

const HEAD_LABELS := ["Open face", "Visor helm", "Hooded"]

const TRIM_LABELS := ["Plain", "Trimmed", "Pauldrons"]


static func default_profile() -> Dictionary:
	return {
		"theme": PixelStyle.PaletteTheme.CASTLE,
		"height": 1.0,
		"bulk": 1.0,
		"head": HEAD_VISOR,
		"trim": 1,
	}


static func profile_from_indices(
	theme: int,
	height_idx: int,
	bulk_idx: int,
	head_idx: int,
	trim_idx: int
) -> Dictionary:
	return {
		"theme": theme,
		"height": HEIGHT_PRESETS[clampi(height_idx, 0, HEIGHT_PRESETS.size() - 1)],
		"bulk": BULK_PRESETS[clampi(bulk_idx, 0, BULK_PRESETS.size() - 1)],
		"head": _head_from_index(head_idx),
		"trim": clampi(trim_idx, 0, TRIM_LABELS.size() - 1),
	}


static func _head_from_index(index: int) -> String:
	match clampi(index, 0, 2):
		0:
			return HEAD_OPEN
		1:
			return HEAD_VISOR
		_:
			return HEAD_HOOD


static func sanitize(profile: Dictionary) -> Dictionary:
	var clean := default_profile()
	if profile.has("theme"):
		clean["theme"] = int(profile.get("theme", clean["theme"]))
	clean["height"] = clampf(float(profile.get("height", clean["height"])), 0.82, 1.18)
	clean["bulk"] = clampf(float(profile.get("bulk", clean["bulk"])), 0.82, 1.22)
	var head := str(profile.get("head", clean["head"]))
	if head in [HEAD_OPEN, HEAD_VISOR, HEAD_HOOD]:
		clean["head"] = head
	clean["trim"] = clampi(int(profile.get("trim", clean["trim"])), 0, TRIM_LABELS.size() - 1)
	return clean


static func apply_to_service(profile: Dictionary) -> void:
	if CharacterService == null:
		return
	var clean := sanitize(profile)
	CharacterService.appearance_theme = int(clean["theme"])
	CharacterService.appearance_profile = clean


static func from_character_dict(character: Dictionary) -> Dictionary:
	if character.is_empty():
		return default_profile()
	var nested: Variant = character.get("appearance", {})
	var appearance: Dictionary = nested if nested is Dictionary else {}
	return sanitize({
		"theme": character.get("appearanceTheme", appearance.get("theme", 0)),
		"height": appearance.get("height", 1.0),
		"bulk": appearance.get("bulk", 1.0),
		"head": appearance.get("head", HEAD_VISOR),
		"trim": appearance.get("trim", 1),
	})


static func from_service() -> Dictionary:
	if CharacterService == null:
		return default_profile()
	return sanitize(CharacterService.appearance_profile)


static func theme_from_service() -> int:
	return int(from_service().get("theme", PixelStyle.PaletteTheme.CASTLE))

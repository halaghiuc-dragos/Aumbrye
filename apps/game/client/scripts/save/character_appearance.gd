class_name CharacterAppearance
extends RefCounted

## Warden visual customization — persisted on character save.

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const DungeonCatalogScript := preload("res://scripts/dungeon/dungeon_catalog.gd")

const PROFILE_VERSION := 1
const THEME_MIN := 0

const HEAD_OPEN := "open"
const HEAD_VISOR := "visor"
const HEAD_HOOD := "hood"

const HEIGHT_VARIANT_COMPACT := "compact"
const HEIGHT_VARIANT_STANDARD := "standard"
const HEIGHT_VARIANT_TALL := "tall"
const HEIGHT_VARIANTS := [HEIGHT_VARIANT_COMPACT, HEIGHT_VARIANT_STANDARD, HEIGHT_VARIANT_TALL]
const HEIGHT_LABELS := ["Compact", "Standard", "Tall"]

const BULK_VARIANT_LEAN := "lean"
const BULK_VARIANT_STANDARD := "standard"
const BULK_VARIANT_HEAVY := "heavy"
const BULK_VARIANTS := [BULK_VARIANT_LEAN, BULK_VARIANT_STANDARD, BULK_VARIANT_HEAVY]
const BULK_LABELS := ["Lean", "Standard", "Heavy"]

const SKIN_TONE_WARM := "warm"
const SKIN_TONE_NEUTRAL := "neutral"
const SKIN_TONE_COOL := "cool"
const SKIN_TONE_PALE := "pale"
const SKIN_TONE_TAN := "tan"
const SKIN_TONE_UMBER := "umber"
const SKIN_TONE_ASHEN := "ashen"
const SKIN_TONE_RUDDY := "ruddy"
const SKIN_TONES := [
	SKIN_TONE_PALE,
	SKIN_TONE_WARM,
	SKIN_TONE_NEUTRAL,
	SKIN_TONE_COOL,
	SKIN_TONE_TAN,
	SKIN_TONE_UMBER,
	SKIN_TONE_ASHEN,
	SKIN_TONE_RUDDY,
]
const SKIN_TONE_LABELS := [
	"Pale",
	"Warm",
	"Neutral",
	"Cool",
	"Tanned",
	"Umber",
	"Ashen",
	"Ruddy",
]

const HAIR_NONE := "none"
const HAIR_SHORT := "short"
const HAIR_LONG := "long"
const HAIR_SHAVEN := "shaven"
const HAIR_BRAIDED := "braided"
const HAIR_TIED := "tied"
const HAIR_WILD := "wild"
const HAIR_STYLES := [
	HAIR_NONE,
	HAIR_SHAVEN,
	HAIR_SHORT,
	HAIR_TIED,
	HAIR_BRAIDED,
	HAIR_LONG,
	HAIR_WILD,
]
const HAIR_LABELS := [
	"Bald",
	"Shaven",
	"Short crop",
	"Tied back",
	"Braided",
	"Long",
	"Unkept",
]

const FACE_OPEN := "open"
const FACE_STERN := "stern"
const FACE_KIND := "kind"
const FACE_WEARY := "weary"
const FACE_SCARRED := "scarred"
const FACE_HOLLOW := "hollow"
const FACE_STYLES := [
	FACE_OPEN,
	FACE_STERN,
	FACE_KIND,
	FACE_WEARY,
	FACE_SCARRED,
	FACE_HOLLOW,
]
const FACE_LABELS := ["Open", "Stern", "Kind", "Weary", "Scarred", "Hollow"]

const HEAD_LABELS := ["Open face", "Visor helm", "Hooded"]

const TRIM_LABELS := ["Plain", "Trimmed", "Pauldrons"]

## Legacy float presets kept for save migration only.
const HEIGHT_PRESETS := [0.9, 1.0, 1.1]
const BULK_PRESETS := [0.88, 1.0, 1.14]

## Legacy float clamps kept for migration validation.
const HEIGHT_MIN := 0.92
const HEIGHT_MAX := 1.08
const BULK_MIN := 0.90
const BULK_MAX := 1.12

const THEME_OPTIONS: Array[Dictionary] = [
	{"label": "Castle iron", "theme": PixelStyle.PaletteTheme.CASTLE},
	{"label": "Crystal frost", "theme": PixelStyle.PaletteTheme.CRYSTAL},
	{"label": "Umbral void", "theme": PixelStyle.PaletteTheme.UMBRAL},
	{"label": "Cathedral gold", "theme": PixelStyle.PaletteTheme.CATHEDRAL},
	{"label": "Hub ember", "theme": PixelStyle.PaletteTheme.HUB},
	{"label": "Swamp bile", "theme": PixelStyle.PaletteTheme.SWAMP, "dungeonId": "poison_swamp"},
	{"label": "Frozen steel", "theme": PixelStyle.PaletteTheme.FROZEN, "dungeonId": "frozen_fortress"},
	{"label": "Vault iron", "theme": PixelStyle.PaletteTheme.VAULT, "dungeonId": "iron_vault"},
	{"label": "Prism light", "theme": PixelStyle.PaletteTheme.PRISM, "dungeonId": "prism_depths"},
	{"label": "Mire venom", "theme": PixelStyle.PaletteTheme.MIRE, "dungeonId": "venom_mire"},
	{"label": "Hollow ice", "theme": PixelStyle.PaletteTheme.HOLLOW, "dungeonId": "glacial_hollow"},
]


static func theme_max() -> int:
	return PixelStyle.PALETTES.size() - 1


static func default_profile() -> Dictionary:
	return {
		"profileVersion": PROFILE_VERSION,
		"theme": PixelStyle.PaletteTheme.CASTLE,
		"heightVariant": HEIGHT_VARIANT_STANDARD,
		"bulkVariant": BULK_VARIANT_STANDARD,
		"skinTone": SKIN_TONE_NEUTRAL,
		"hair": HAIR_NONE,
		"face": FACE_OPEN,
		"head": HEAD_VISOR,
		"trim": 1,
		"title": "",
	}


static func profile_from_indices(
	theme: int,
	height_idx: int,
	bulk_idx: int,
	head_idx: int,
	trim_idx: int,
	skin_idx: int = 1,
	hair_idx: int = 0,
	face_idx: int = 0
) -> Dictionary:
	return {
		"profileVersion": PROFILE_VERSION,
		"theme": theme,
		"heightVariant": HEIGHT_VARIANTS[clampi(height_idx, 0, HEIGHT_VARIANTS.size() - 1)],
		"bulkVariant": BULK_VARIANTS[clampi(bulk_idx, 0, BULK_VARIANTS.size() - 1)],
		"skinTone": SKIN_TONES[clampi(skin_idx, 0, SKIN_TONES.size() - 1)],
		"hair": HAIR_STYLES[clampi(hair_idx, 0, HAIR_STYLES.size() - 1)],
		"face": FACE_STYLES[clampi(face_idx, 0, FACE_STYLES.size() - 1)],
		"head": _head_from_index(head_idx),
		"trim": clampi(trim_idx, 0, TRIM_LABELS.size() - 1),
		"title": "",
	}


static func _head_from_index(index: int) -> String:
	match clampi(index, 0, 2):
		0:
			return HEAD_OPEN
		1:
			return HEAD_VISOR
		_:
			return HEAD_HOOD


static func height_variant_from_legacy(height: float) -> String:
	var clamped := clampf(height, HEIGHT_MIN, HEIGHT_MAX)
	if clamped <= 0.94:
		return HEIGHT_VARIANT_COMPACT
	if clamped >= 1.06:
		return HEIGHT_VARIANT_TALL
	return HEIGHT_VARIANT_STANDARD


static func bulk_variant_from_legacy(bulk: float) -> String:
	var clamped := clampf(bulk, BULK_MIN, BULK_MAX)
	if clamped <= 0.94:
		return BULK_VARIANT_LEAN
	if clamped >= 1.06:
		return BULK_VARIANT_HEAVY
	return BULK_VARIANT_STANDARD


static func _character_service() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("CharacterService")


static func available_theme_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var svc := _character_service()
	for entry in THEME_OPTIONS:
		var dungeon_id := str(entry.get("dungeonId", ""))
		if dungeon_id == "":
			out.append(entry)
			continue
		var flag := DungeonCatalogScript.get_clear_flag(dungeon_id)
		if flag == "":
			out.append(entry)
			continue
		if svc != null and svc.has_method("has_flag") and svc.call("has_flag", flag):
			out.append(entry)
	return out


static func theme_label(theme: int) -> String:
	for entry in THEME_OPTIONS:
		if int(entry.get("theme", -1)) == theme:
			return str(entry.get("label", "Unknown"))
	return "Unknown"


static func sanitize(profile: Variant) -> Dictionary:
	if not profile is Dictionary:
		push_warning(
			"CharacterAppearance.sanitize: expected Dictionary, got %s" % typeof(profile)
		)
		return default_profile()
	var clean := default_profile()
	var input: Dictionary = profile
	if input.has("theme"):
		var theme := int(input.get("theme", clean["theme"]))
		var max_theme := theme_max()
		if theme < THEME_MIN or theme > max_theme:
			push_warning(
				"CharacterAppearance.sanitize: theme %d out of range, clamped to %d..%d"
				% [theme, THEME_MIN, max_theme]
			)
		clean["theme"] = clampi(theme, THEME_MIN, max_theme)
	var height_variant := str(input.get("heightVariant", ""))
	if height_variant in HEIGHT_VARIANTS:
		clean["heightVariant"] = height_variant
	elif input.has("height"):
		clean["heightVariant"] = height_variant_from_legacy(float(input.get("height", 1.0)))
	var bulk_variant := str(input.get("bulkVariant", ""))
	if bulk_variant in BULK_VARIANTS:
		clean["bulkVariant"] = bulk_variant
	elif input.has("bulk"):
		clean["bulkVariant"] = bulk_variant_from_legacy(float(input.get("bulk", 1.0)))
	var skin := str(input.get("skinTone", clean["skinTone"]))
	if skin in SKIN_TONES:
		clean["skinTone"] = skin
	var hair := str(input.get("hair", clean["hair"]))
	if hair in HAIR_STYLES:
		clean["hair"] = hair
	var face := str(input.get("face", clean["face"]))
	if face in FACE_STYLES:
		clean["face"] = face
	var head := str(input.get("head", clean["head"]))
	if head in [HEAD_OPEN, HEAD_VISOR, HEAD_HOOD]:
		clean["head"] = head
	clean["trim"] = clampi(int(input.get("trim", clean["trim"])), 0, TRIM_LABELS.size() - 1)
	var title := str(input.get("title", ""))
	clean["title"] = title if AppearanceCatalog.is_title_id(title) else ""
	clean["profileVersion"] = PROFILE_VERSION
	return clean


static func is_valid(profile: Variant) -> bool:
	if not profile is Dictionary:
		return false
	var input: Dictionary = profile
	if int(input.get("profileVersion", -1)) != PROFILE_VERSION:
		return false
	var theme := int(input.get("theme", -1))
	if theme < THEME_MIN or theme > theme_max():
		return false
	var height_variant := str(input.get("heightVariant", ""))
	if height_variant not in HEIGHT_VARIANTS:
		return false
	var bulk_variant := str(input.get("bulkVariant", ""))
	if bulk_variant not in BULK_VARIANTS:
		return false
	if str(input.get("skinTone", "")) not in SKIN_TONES:
		return false
	if str(input.get("hair", "")) not in HAIR_STYLES:
		return false
	if str(input.get("face", "")) not in FACE_STYLES:
		return false
	var head := str(input.get("head", ""))
	if head not in [HEAD_OPEN, HEAD_VISOR, HEAD_HOOD]:
		return false
	var trim := int(input.get("trim", -1))
	if trim < 0 or trim > TRIM_LABELS.size() - 1:
		return false
	return true


static func describe(profile: Dictionary) -> String:
	var clean := sanitize(profile)
	var height_idx := HEIGHT_VARIANTS.find(clean["heightVariant"])
	var bulk_idx := BULK_VARIANTS.find(clean["bulkVariant"])
	var head_label := HEAD_LABELS[1]
	match clean["head"]:
		HEAD_OPEN:
			head_label = HEAD_LABELS[0]
		HEAD_HOOD:
			head_label = HEAD_LABELS[2]
	var trim_idx := int(clean["trim"])
	return "%s / %s / %s / %s / %s" % [
		HEIGHT_LABELS[height_idx] if height_idx >= 0 else "Standard",
		BULK_LABELS[bulk_idx] if bulk_idx >= 0 else "Standard",
		head_label,
		TRIM_LABELS[trim_idx] if trim_idx >= 0 and trim_idx < TRIM_LABELS.size() else "Plain",
		theme_label(int(clean["theme"])),
	]


static func skin_tint_vector(skin_tone: String) -> Vector3:
	match skin_tone:
		SKIN_TONE_WARM:
			return Vector3(1.06, 0.98, 0.92)
		SKIN_TONE_COOL:
			return Vector3(0.94, 0.98, 1.04)
		SKIN_TONE_PALE:
			return Vector3(1.09, 1.05, 1.02)
		SKIN_TONE_TAN:
			return Vector3(0.98, 0.88, 0.74)
		SKIN_TONE_UMBER:
			return Vector3(0.74, 0.62, 0.52)
		SKIN_TONE_ASHEN:
			return Vector3(0.86, 0.87, 0.88)
		SKIN_TONE_RUDDY:
			return Vector3(1.08, 0.9, 0.85)
		_:
			return Vector3.ONE


static func apply_to_service(profile: Dictionary) -> void:
	var svc := _character_service()
	if svc == null:
		return
	var clean := sanitize(profile)
	svc.appearance_theme = int(clean["theme"])
	svc.appearance_profile = clean
	svc.appearance_changed.emit(clean)


static func from_character_dict(character: Dictionary) -> Dictionary:
	if character.is_empty():
		return default_profile()
	var nested: Variant = character.get("appearance", {})
	var appearance: Dictionary = nested if nested is Dictionary else {}
	return sanitize(
		{
			"theme": character.get("appearanceTheme", appearance.get("theme", 0)),
			"heightVariant": appearance.get("heightVariant", ""),
			"bulkVariant": appearance.get("bulkVariant", ""),
			"height": appearance.get("height", 1.0),
			"bulk": appearance.get("bulk", 1.0),
			"skinTone": appearance.get("skinTone", SKIN_TONE_NEUTRAL),
			"hair": appearance.get("hair", HAIR_NONE),
			"face": appearance.get("face", FACE_OPEN),
			"head": appearance.get("head", HEAD_VISOR),
			"trim": appearance.get("trim", 1),
			"title": appearance.get("title", ""),
			"profileVersion": appearance.get("profileVersion", PROFILE_VERSION),
		}
	)


static func from_service() -> Dictionary:
	var svc := _character_service()
	if svc == null:
		return default_profile()
	return sanitize(svc.appearance_profile)

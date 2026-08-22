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

## One axis, five bodies.
##
## Stature and build were two independent five-step sliders — twenty-five rigs to build and animate
## for a choice the player experiences as "what shape is my warden", and twenty-one of the
## twenty-five were interpolations nobody would pick deliberately. Five named frames cover the four
## corners of that grid plus the middle, and each is a silhouette you can tell from the other four
## across a room. The ids match `PLAYER_FRAMES` in `tools/voxel-import/archetypes.py`, which is what
## actually builds them.
const FRAME_SLIGHT := "slight"
const FRAME_LEAN := "lean"
const FRAME_STANDARD := "standard"
const FRAME_STOUT := "stout"
const FRAME_TOWERING := "towering"
const FRAME_VARIANTS := [
	FRAME_SLIGHT,
	FRAME_LEAN,
	FRAME_STANDARD,
	FRAME_STOUT,
	FRAME_TOWERING,
]
const FRAME_LABELS := ["Slight", "Lean", "Standard", "Stout", "Towering"]


## Characters created before the two sliders became one still carry `heightVariant` and
## `bulkVariant`. Mapped rather than dropped: a player who built a short broad warden gets the short
## broad frame, not the default.
static func frame_from_legacy(height_variant: String, bulk_variant: String) -> String:
	var tall := height_variant in ["tall", "towering"]
	var short := height_variant in ["slight", "compact"]
	var broad := bulk_variant in ["heavy", "massive"]
	var narrow := bulk_variant in ["gaunt", "lean"]
	if tall:
		return FRAME_TOWERING if broad else FRAME_LEAN
	if short:
		return FRAME_STOUT if broad else FRAME_SLIGHT
	if broad:
		return FRAME_STOUT
	if narrow:
		return FRAME_LEAN
	return FRAME_STANDARD


const SKIN_TONE_WARM := "warm"
const SKIN_TONE_NEUTRAL := "neutral"
const SKIN_TONE_COOL := "cool"
const SKIN_TONE_PALE := "pale"
const SKIN_TONE_TAN := "tan"
const SKIN_TONE_UMBER := "umber"
const SKIN_TONE_ASHEN := "ashen"
const SKIN_TONE_RUDDY := "ruddy"
## Every appearance axis is one ordered table: id, label, and (where it has one) colour.
##
## These used to be three separate literals per axis — an id array, a label array and a `match`
## returning a colour — kept in alignment by hand. That is fine at eight entries and a bug waiting
## at twenty-five, because the UI selects by *index* into the label array and reads back by index
## into the id array. One table means an id and its label cannot drift apart.
##
## The hair and face id lists are the sculptor's own (`tools/voxel_sculpt.py`), so the game cannot
## offer a style with no mesh behind it.
const SKIN_TONE_TABLE: Array = [
	["pale", "Pale", Color(0.94, 0.82, 0.75)],
	["porcelain", "Porcelain", Color(0.96, 0.88, 0.83)],
	["rose", "Rose", Color(0.93, 0.78, 0.73)],
	["warm", "Warm", Color(0.86, 0.66, 0.51)],
	["neutral", "Neutral", Color(0.80, 0.62, 0.48)],
	["cool", "Cool", Color(0.78, 0.66, 0.62)],
	["sand", "Sand", Color(0.84, 0.70, 0.53)],
	["honey", "Honey", Color(0.82, 0.63, 0.42)],
	["tan", "Tanned", Color(0.71, 0.52, 0.36)],
	["olive", "Olive", Color(0.68, 0.58, 0.42)],
	["bronze", "Bronze", Color(0.66, 0.46, 0.30)],
	["amber", "Amber", Color(0.74, 0.52, 0.30)],
	["clay", "Clay", Color(0.62, 0.42, 0.32)],
	["chestnut", "Chestnut", Color(0.55, 0.37, 0.26)],
	["umber", "Umber", Color(0.44, 0.30, 0.21)],
	["walnut", "Walnut", Color(0.38, 0.26, 0.19)],
	["ebony", "Ebony", Color(0.28, 0.19, 0.15)],
	["deep", "Deep", Color(0.22, 0.15, 0.12)],
	["ruddy", "Ruddy", Color(0.83, 0.56, 0.47)],
	["sunburnt", "Sunburnt", Color(0.80, 0.50, 0.40)],
	["ashen", "Ashen", Color(0.62, 0.62, 0.63)],
	["slate", "Slate", Color(0.52, 0.54, 0.58)],
	["wan", "Wan", Color(0.72, 0.72, 0.68)],
	["frostbit", "Frostbit", Color(0.70, 0.75, 0.80)],
	["grave", "Grave", Color(0.46, 0.46, 0.52)],
]

const HAIR_COLOR_TABLE: Array = [
	["black", "Black", Color(0.11, 0.10, 0.13)],
	["raven", "Raven", Color(0.14, 0.13, 0.18)],
	["soot", "Soot", Color(0.20, 0.19, 0.20)],
	["ash", "Ash", Color(0.42, 0.40, 0.40)],
	["slate", "Slate", Color(0.36, 0.38, 0.42)],
	["brown", "Brown", Color(0.32, 0.21, 0.13)],
	["chestnut", "Chestnut", Color(0.42, 0.26, 0.15)],
	["auburn", "Auburn", Color(0.44, 0.18, 0.12)],
	["copper", "Copper", Color(0.72, 0.33, 0.12)],
	["ginger", "Ginger", Color(0.80, 0.44, 0.18)],
	["rust", "Rust", Color(0.58, 0.28, 0.14)],
	["blond", "Blond", Color(0.85, 0.72, 0.42)],
	["flaxen", "Flaxen", Color(0.90, 0.82, 0.58)],
	["wheat", "Wheat", Color(0.78, 0.68, 0.44)],
	["honey", "Honey", Color(0.72, 0.56, 0.28)],
	["silver", "Silver", Color(0.82, 0.84, 0.88)],
	["white", "White", Color(0.94, 0.94, 0.92)],
	["pewter", "Pewter", Color(0.58, 0.60, 0.64)],
	["teal", "Teal", Color(0.20, 0.52, 0.52)],
	["verdigris", "Verdigris", Color(0.28, 0.56, 0.46)],
	["moss", "Moss", Color(0.34, 0.44, 0.24)],
	["violet", "Violet", Color(0.45, 0.30, 0.62)],
	["plum", "Plum", Color(0.38, 0.20, 0.36)],
	["ember", "Ember", Color(0.72, 0.24, 0.16)],
	["gilt", "Gilt", Color(0.86, 0.68, 0.28)],
]

const HAIR_STYLE_TABLE: Array = [
	["shaven", "Shaven"],
	["short", "Short crop"],
	["crop", "Cropped"],
	["bowl", "Bowl cut"],
	["tied", "Tied back"],
	["topknot", "Topknot"],
	["ponytail", "Ponytail"],
	["braided", "Braided"],
	["twin_falls", "Twin falls"],
	["long", "Long"],
	["flowing", "Flowing"],
	["mane", "Mane"],
	["wild", "Unkept"],
	["windswept", "Windswept"],
	["mohawk", "Mohawk"],
	["crest", "Crested"],
	["tonsure", "Tonsure"],
	["widow", "Widow's peak"],
	["shag", "Shag"],
	["bob", "Bob"],
	["cropped_tail", "Cropped tail"],
	["warrior", "Warrior's knot"],
	["loose", "Loose"],
	["shorn_sides", "Shorn sides"],
	["veiled", "Veiled"],
]

const FACE_STYLE_TABLE: Array = [
	["open", "Open"],
	["stern", "Stern"],
	["kind", "Kind"],
	["weary", "Weary"],
	["scarred", "Scarred"],
	["hollow", "Hollow"],
	["grim", "Grim"],
	["watchful", "Watchful"],
	["hardened", "Hardened"],
	["gaunt", "Gaunt"],
	["wry", "Wry"],
	["grave", "Grave"],
	["young", "Young"],
	["seamed", "Seamed"],
	["burned", "Burned"],
	["veteran", "Veteran"],
	["sleepless", "Sleepless"],
	["resolute", "Resolute"],
	["wolfish", "Wolfish"],
	["sunken", "Sunken"],
	["brand", "Branded"],
	["split", "Split"],
	["patient", "Patient"],
	["cold", "Cold"],
	["ruined", "Ruined"],
]


static func _ids(table: Array) -> Array:
	var out: Array = []
	for row: Array in table:
		out.append(str(row[0]))
	return out


static func _labels(table: Array) -> Array:
	var out: Array = []
	for row: Array in table:
		out.append(str(row[1]))
	return out


static func _color_for(table: Array, id: String, fallback: Color) -> Color:
	for row: Array in table:
		if str(row[0]) == id:
			return row[2] as Color
	return fallback

static var SKIN_TONES: Array = _ids(SKIN_TONE_TABLE)
static var SKIN_TONE_LABELS: Array = _labels(SKIN_TONE_TABLE)

const HAIR_NONE := "none"
const HAIR_SHORT := "short"
const HAIR_LONG := "long"
const HAIR_SHAVEN := "shaven"
const HAIR_BRAIDED := "braided"
const HAIR_TIED := "tied"
const HAIR_WILD := "wild"
static var HAIR_STYLES: Array = _ids(HAIR_STYLE_TABLE)
static var HAIR_LABELS: Array = _labels(HAIR_STYLE_TABLE)

const FACE_OPEN := "open"
const FACE_STERN := "stern"
const FACE_KIND := "kind"
const FACE_WEARY := "weary"
const FACE_SCARRED := "scarred"
const FACE_HOLLOW := "hollow"
static var FACE_STYLES: Array = _ids(FACE_STYLE_TABLE)
static var FACE_LABELS: Array = _labels(FACE_STYLE_TABLE)

## Hair colour, as an axis of its own.
##
## There was none: every warden's hair resolved to one palette slot, so the only thing the seven
## hair *styles* could vary was silhouette, and two characters in the same biome were identical from
## the neck up. These are literal RGB, deliberately not palette slots — hair colour is a choice the
## player makes about their character, not a property of the room they are standing in, and snapping
## it to the biome palette is exactly what made every warden look the same.
const HAIR_COLOR_BLACK := "black"
const HAIR_COLOR_ASH := "ash"
const HAIR_COLOR_BROWN := "brown"
const HAIR_COLOR_AUBURN := "auburn"
const HAIR_COLOR_COPPER := "copper"
const HAIR_COLOR_BLOND := "blond"
const HAIR_COLOR_SILVER := "silver"
const HAIR_COLOR_TEAL := "teal"
static var HAIR_COLORS: Array = _ids(HAIR_COLOR_TABLE)
static var HAIR_COLOR_LABELS: Array = _labels(HAIR_COLOR_TABLE)

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
		"frame": FRAME_STANDARD,
		"skinTone": SKIN_TONE_NEUTRAL,
		"hair": HAIR_NONE,
		"hairColor": HAIR_COLOR_BROWN,
		"face": FACE_OPEN,
		"head": HEAD_VISOR,
		"trim": 1,
		"title": "",
	}


static func profile_from_indices(
	theme: int,
	frame_idx: int,
	head_idx: int,
	trim_idx: int,
	skin_idx: int = 1,
	hair_idx: int = 0,
	face_idx: int = 0,
	hair_color_idx: int = 2
) -> Dictionary:
	return {
		"profileVersion": PROFILE_VERSION,
		"theme": theme,
		"frame": FRAME_VARIANTS[clampi(frame_idx, 0, FRAME_VARIANTS.size() - 1)],
		"skinTone": SKIN_TONES[clampi(skin_idx, 0, SKIN_TONES.size() - 1)],
		"hair": HAIR_STYLES[clampi(hair_idx, 0, HAIR_STYLES.size() - 1)],
		"hairColor": HAIR_COLORS[clampi(hair_color_idx, 0, HAIR_COLORS.size() - 1)],
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


## The two legacy axes, as the strings the *old* save format used. They are not choices any more —
## nothing offers them and no constant names them — but a profile written before the change still
## carries them, and `frame_from_legacy` reads them to decide which frame that character becomes.
static func height_variant_from_legacy(height: float) -> String:
	var clamped := clampf(height, HEIGHT_MIN, HEIGHT_MAX)
	if clamped <= 0.94:
		return "compact"
	if clamped >= 1.06:
		return "tall"
	return "standard"


static func bulk_variant_from_legacy(bulk: float) -> String:
	var clamped := clampf(bulk, BULK_MIN, BULK_MAX)
	if clamped <= 0.94:
		return "lean"
	if clamped >= 1.06:
		return "heavy"
	return "standard"


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
	var frame := str(input.get("frame", ""))
	if frame in FRAME_VARIANTS:
		clean["frame"] = frame
	elif input.has("heightVariant") or input.has("bulkVariant"):
		clean["frame"] = frame_from_legacy(
			str(input.get("heightVariant", "standard")), str(input.get("bulkVariant", "standard"))
		)
	elif input.has("height") or input.has("bulk"):
		clean["frame"] = frame_from_legacy(
			height_variant_from_legacy(float(input.get("height", 1.0))),
			bulk_variant_from_legacy(float(input.get("bulk", 1.0)))
		)
	var skin := str(input.get("skinTone", clean["skinTone"]))
	if skin in SKIN_TONES:
		clean["skinTone"] = skin
	var hair := str(input.get("hair", clean["hair"]))
	if hair in HAIR_STYLES:
		clean["hair"] = hair
	var hair_color := str(input.get("hairColor", clean["hairColor"]))
	if hair_color in HAIR_COLORS:
		clean["hairColor"] = hair_color
	var face := str(input.get("face", clean["face"]))
	if face in FACE_STYLES:
		clean["face"] = face
	var head := str(input.get("head", clean["head"]))
	if head in [HEAD_OPEN, HEAD_VISOR, HEAD_HOOD]:
		clean["head"] = head
	clean["trim"] = clampi(int(input.get("trim", clean["trim"])), 0, TRIM_LABELS.size() - 1)
	var title := str(input.get("title", ""))
	clean["title"] = title if AppearanceCatalog.is_title_id(title) else ""
	# Carried through rather than validated: it is not an appearance choice, it is the class whose
	# default clothing the rig should wear, and character creation supplies it before the class is
	# committed anywhere else.
	var class_id := str(input.get("classId", ""))
	if class_id != "":
		clean["classId"] = class_id
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
	if str(input.get("frame", "")) not in FRAME_VARIANTS:
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
	var frame_idx: int = maxi(0, FRAME_VARIANTS.find(clean["frame"]))
	var head_label := HEAD_LABELS[1]
	match clean["head"]:
		HEAD_OPEN:
			head_label = HEAD_LABELS[0]
		HEAD_HOOD:
			head_label = HEAD_LABELS[2]
	var trim_idx := int(clean["trim"])
	return "%s / %s / %s / %s" % [
		FRAME_LABELS[frame_idx],
		head_label,
		TRIM_LABELS[trim_idx] if trim_idx >= 0 and trim_idx < TRIM_LABELS.size() else "Plain",
		theme_label(int(clean["theme"])),
	]


## Literal hair colour. Multiplied into the hair mesh's own instance tint, so it is the only thing
## on the model that does not track the biome palette.
static func hair_color_rgb(hair_color: String) -> Color:
	return _color_for(HAIR_COLOR_TABLE, hair_color, Color(0.32, 0.21, 0.13))


## Literal skin colour for the face plate, rather than the near-white multiplier `skin_tint_vector`
## returns. That multiplier was applied to the *whole body* and ranged 0.74..1.09, so a tone change
## moved every surface on the warden by a few percent and none of the eight tones was tellable from
## any other.
static func skin_color_rgb(skin_tone: String) -> Color:
	return _color_for(SKIN_TONE_TABLE, skin_tone, Color(0.80, 0.62, 0.48))


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
	svc.notify_appearance_changed(clean)


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

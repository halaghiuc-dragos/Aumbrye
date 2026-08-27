class_name ContentSchemaValidator
extends RefCounted


const XP_CURVE_KEYS: PackedStringArray = [
	"baseXpPerKill",
	"bossBonusXp",
	"escapeBonusXp",
	"deathXpFraction",
	"abandonedXpFraction",
	"talentPointsPerLevel",
	"levels",
]

const LEGACY_XP_CURVE_KEYS: PackedStringArray = [
	"baseXpPerRun",
	"tierXpBonus",
]

const ROLL_INSTANCE_KEYS: PackedStringArray = [
	"instanceId",
	"itemId",
	"quantity",
	"rarity",
	"affixes",
	"rollSeed",
]

const ITEM_DEFINITION_KEYS: PackedStringArray = [
	"id",
	"name",
	"itemType",
	"gridWidth",
	"gridHeight",
	"stackSize",
]

const VALID_RARITIES: PackedStringArray = [
	"common",
	"magic",
	"rare",
	"epic",
	"legendary",
	"aumbral",
]


static func validate_loaded(relative_path: String, data: Dictionary) -> void:
	if data.is_empty():
		return
	var normalized := relative_path.replace("\\", "/")
	if normalized == "content/progression/xp_curve.json":
		_validate_xp_curve(data)
	elif normalized.begins_with("content/items/") and normalized.ends_with(".json"):
		if not normalized.ends_with("catalog.json"):
			_validate_item_definition(normalized, data)
	elif (
		normalized == "content/affixes/prefixes.json"
		or normalized == "content/affixes/suffixes.json"
	):
		_validate_affix_pack(normalized, data)
	elif normalized == "content/affixes/rarity_rules.json":
		_validate_rarity_rules(data)


static func validate_roll_instance(instance: Dictionary, context: String = "") -> void:
	for key in ROLL_INSTANCE_KEYS:
		if not instance.has(key):
			_fail("roll instance missing '%s' (%s)" % [key, context])
	var rarity: String = str(instance.get("rarity", ""))
	if not rarity in VALID_RARITIES:
		_fail("roll instance invalid rarity '%s' (%s)" % [rarity, context])
	var affixes: Variant = instance.get("affixes", [])
	if not affixes is Array:
		_fail("roll instance affixes must be an array (%s)" % context)
		return
	for entry in affixes:
		if not entry is Dictionary:
			_fail("roll instance affix entry must be an object (%s)" % context)
			continue
		if str(entry.get("affixId", "")).is_empty():
			_fail("roll instance affix missing affixId (%s)" % context)


static func _validate_xp_curve(data: Dictionary) -> void:
	for legacy_key in LEGACY_XP_CURVE_KEYS:
		if data.has(legacy_key):
			_fail("xp_curve.json still uses legacy key '%s'" % legacy_key)
	for key in XP_CURVE_KEYS:
		if not data.has(key):
			_fail("xp_curve.json missing required key '%s'" % key)
	var levels: Variant = data.get("levels", [])
	if not levels is Array or (levels as Array).size() < 2:
		_fail("xp_curve.json levels must be an array with at least 2 entries")


static func _validate_item_definition(path: String, data: Dictionary) -> void:
	for key in ITEM_DEFINITION_KEYS:
		if not data.has(key):
			_fail("%s missing required key '%s'" % [path, key])
	if data.has("rarity"):
		var rarity: String = str(data.get("rarity", ""))
		if not rarity in VALID_RARITIES:
			_fail("%s uses invalid rarity '%s'" % [path, rarity])


static func _validate_affix_pack(path: String, data: Dictionary) -> void:
	if not data.has("schemaVersion") or not data.has("affixes"):
		_fail("%s missing schemaVersion or affixes" % path)
		return
	var affixes: Variant = data.get("affixes", [])
	if not affixes is Array:
		_fail("%s affixes must be an array" % path)
		return
	for affix in affixes:
		if not affix is Dictionary:
			continue
		var tiers: Variant = affix.get("tiers", {})
		if tiers is Dictionary and (tiers as Dictionary).has("mythic"):
			_fail("%s affix '%s' still uses mythic tier key" % [path, affix.get("id", "?")])


static func _validate_rarity_rules(data: Dictionary) -> void:
	for section in ["affixCounts", "rarityWeights"]:
		var block: Variant = data.get(section, {})
		if block is Dictionary and (block as Dictionary).has("mythic"):
			_fail("rarity_rules.json still uses mythic in %s" % section)


static func _fail(message: String) -> void:
	push_error("ContentSchemaValidator: %s" % message)

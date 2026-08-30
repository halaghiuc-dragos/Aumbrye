extends RefCounted
class_name ItemQuality

## The condition an item was found in, rolled once at drop time and fixed for its lifetime.
##
## This is a third axis alongside rarity and affixes, and it is deliberately the only one that
## touches the item's *own* numbers. Rarity decides how many affixes an item carries, affixes add
## flat stats on top of it, and quality scales the base stats the item already had. A rusted ring
## is still a ring of its rarity; it is a worse example of one.
##
## The ladder runs worst to best and is the same length for every category, so a roll index means
## the same thing whether it lands on a sword, a cuirass or a pendant -- only the word changes.
## A weapon is Chipped where a pendant is Tarnished.

const PATH := "content/affixes/quality_tiers.json"

## The tier every item falls back to: the middle of the ladder, no scaling either way. Items that
## predate the system, and item types that carry no stats, resolve here.
const NEUTRAL_INDEX := 2

static var _tiers: Dictionary = {}
static var _categories: Dictionary = {}
static var _rarity_bias: Dictionary = {}
static var _weights: Array = []
static var _loaded := false


static func ladder_for(item_type: String) -> Array:
	_ensure_loaded()
	var ladder: Variant = _categories.get(item_type, null)
	if ladder is Array:
		return ladder as Array
	return []


## Whether an item of this type is rolled a condition at all. Consumables and materials have no
## base stats to scale, so a "Keen" health potion would be a word with nothing behind it.
static func applies_to(item_type: String) -> bool:
	return not ladder_for(item_type).is_empty()


## Deterministic in the item's own roll seed, so the same seed always produces the same item --
## the same guarantee `AffixRoller.roll_identical` already relies on.
static func roll(item_type: String, rarity: String, rng: RandomNumberGenerator) -> String:
	var ladder := ladder_for(item_type)
	if ladder.is_empty():
		return ""
	var index := _weighted_index(rng)
	index += int(_rarity_bias.get(rarity, 0))
	index = clampi(index, 0, ladder.size() - 1)
	return str(ladder[index])


static func stat_multiplier(quality_id: String) -> float:
	return float(_tier(quality_id).get("statMultiplier", 1.0))


static func value_multiplier(quality_id: String) -> float:
	return float(_tier(quality_id).get("valueMultiplier", 1.0))


static func display_name(quality_id: String) -> String:
	var tier := _tier(quality_id)
	if tier.is_empty():
		return ""
	var key := "QUALITY_%s" % quality_id.to_upper()
	var localized := TranslationServer.translate(key)
	if localized != key:
		return localized
	return str(tier.get("displayName", ""))


## The neutral tier is not decoration -- it is the one condition that changes nothing, so the
## inventory does not need to shout a word at the player for the majority of their drops.
static func is_neutral(quality_id: String) -> bool:
	return is_equal_approx(stat_multiplier(quality_id), 1.0)


static func exists(quality_id: String) -> bool:
	_ensure_loaded()
	return _tiers.has(quality_id)


static func reload() -> void:
	_loaded = false
	_tiers.clear()
	_categories.clear()
	_rarity_bias.clear()
	_weights.clear()


static func _tier(quality_id: String) -> Dictionary:
	_ensure_loaded()
	var entry: Variant = _tiers.get(quality_id, null)
	if entry is Dictionary:
		return entry as Dictionary
	return {}


static func _weighted_index(rng: RandomNumberGenerator) -> int:
	if _weights.is_empty():
		return NEUTRAL_INDEX
	var total := 0
	for weight in _weights:
		total += int(weight)
	if total <= 0:
		return NEUTRAL_INDEX
	var pick := rng.randi_range(0, total - 1)
	for i in _weights.size():
		pick -= int(_weights[i])
		if pick < 0:
			return i
	return _weights.size() - 1


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data := ContentLoader.load_json(PATH)
	if data.is_empty():
		push_error("ItemQuality: could not load %s" % PATH)
		return
	for entry in data.get("tiers", []):
		if entry is Dictionary and str((entry as Dictionary).get("id", "")) != "":
			_tiers[str((entry as Dictionary)["id"])] = entry
	var categories: Dictionary = data.get("categories", {})
	for key in categories:
		_categories[str(key)] = categories[key]
	var bias: Dictionary = data.get("rarityBias", {})
	for key in bias:
		_rarity_bias[str(key)] = int(bias[key])
	# Every ladder is the same length and the tiers at a given rung share a weight, so the roll
	# distribution is read off whichever ladder is first rather than duplicated per category.
	var first: Array = []
	if not _categories.is_empty():
		first = _categories.values()[0] as Array
	for quality_id in first:
		_weights.append(int(_tier(str(quality_id)).get("weight", 1)))

extends RefCounted
class_name ClassCatalog

## Loads playable class definitions from content/classes/.

const CLASSES_DIR := "content/classes"

static var _definitions: Dictionary = {}
static var _load_attempted := false


static func get_definition(class_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(class_id, {})


static func get_all_classes() -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for class_id in _definitions:
		out.append(_definitions[class_id])
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return out


static func has_class(class_id: String) -> bool:
	_ensure_loaded()
	return _definitions.has(class_id)


static func is_weapon_allowed(class_id: String, item_id: String) -> bool:
	var def := get_definition(class_id)
	if def.is_empty():
		return true
	var allowed: Variant = def.get("allowedWeapons", [])
	if allowed is Array and item_id in (allowed as Array):
		return true
	var families: Variant = def.get("allowedWeaponFamilies", [])
	if families is Array and not (families as Array).is_empty():
		var family := _weapon_family(item_id)
		if family == "":
			return true
		return family in (families as Array)
	if allowed is Array and not (allowed as Array).is_empty():
		return false
	return true


static func get_rules(class_id: String) -> Array:
	var rules: Variant = get_definition(class_id).get("rules", [])
	return rules if rules is Array else []


static func get_talent_branch_id(class_id: String) -> String:
	return str(get_definition(class_id).get("talentBranchId", ""))


static func _weapon_family(item_id: String) -> String:
	var item_def := ItemCatalog.get_definition(item_id)
	if item_def.is_empty():
		return ""
	if str(item_def.get("itemType", "")) != "weapon":
		return ""
	return str(item_def.get("weaponId", ""))


## Every class is described by twelve ratings on one shared scale rather than by twelve signed
## deltas on twelve different scales. RATING_STANDARD is the reference warden; a class sits
## somewhere in RATING_MIN..RATING_MAX on each stat and the ratings always total RATING_BUDGET, so
## no class can be strictly better than another and the comparison is legible at a glance.
##
## A rating never produces a negative bonus: RATING_MIN maps to the engine's own baseline and every
## point above it adds. That matters beyond presentation — `armor` and `blockReduction` are clamped
## at zero where they are applied, so under the old signed scheme a class authored as "poor at
## blocking" was mechanically identical to one authored as average.
const RATING_MIN := 4
const RATING_STANDARD := 10
const RATING_MAX := 16
const RATING_STAT_COUNT := 12
const RATING_BUDGET := RATING_STANDARD * RATING_STAT_COUNT

## Canonical stat order for anything that lists all twelve.
const RATING_STATS: PackedStringArray = [
	"maxHealth",
	"armor",
	"poise",
	"blockReduction",
	"physicalDamage",
	"poiseDamage",
	"critChance",
	"moveSpeed",
	"staminaMax",
	"staminaRegen",
	"manaMax",
	"manaRegen",
]

## What one rating point is worth in engine units. This table is the balance lever: because every
## class spends the same RATING_BUDGET, fairness lives entirely in these numbers being comparable
## amounts of power rather than in the ratings themselves.
const STAT_RATING_UNITS: Dictionary = {
	"maxHealth": 5.0,
	"armor": 1.0,
	"poise": 4.0,
	"blockReduction": 0.01,
	"physicalDamage": 0.02,
	"poiseDamage": 0.02,
	"critChance": 0.01,
	"moveSpeed": 0.015,
	"staminaMax": 5.0,
	"staminaRegen": 0.03,
	"manaMax": 5.0,
	"manaRegen": 0.03,
}

## The engine value a stat has with no class bonus at all, so the UI can resolve a rating into the
## figure it actually produces. Mirrors Health.MAX_HEALTH, Stamina.MAX_STAMINA, Poise.MAX_POISE,
## Mana.MAX_MANA, Hurtbox's defence baseline and WeaponController's crit floor.
const STAT_BASELINE: Dictionary = {
	"maxHealth": 100.0,
	"armor": 0.0,
	"poise": 50.0,
	"blockReduction": 0.0,
	"physicalDamage": 1.0,
	"poiseDamage": 1.0,
	"critChance": 0.05,
	"moveSpeed": 1.0,
	"staminaMax": 100.0,
	"staminaRegen": 1.0,
	"manaMax": 100.0,
	"manaRegen": 1.0,
}


static func rating_unit(stat_name: String) -> float:
	return float(STAT_RATING_UNITS.get(stat_name, 1.0))


## Engine bonus produced by a rating. RATING_MIN yields zero, so a low rating is "gains nothing
## here" rather than a penalty that would be clamped away.
static func bonus_for_rating(stat_name: String, rating: float) -> float:
	return (clampf(rating, RATING_MIN, RATING_MAX) - float(RATING_MIN)) * rating_unit(stat_name)


## The resolved in-game value a rating produces, for display.
static func resolved_value(stat_name: String, rating: float) -> float:
	return float(STAT_BASELINE.get(stat_name, 0.0)) + bonus_for_rating(stat_name, rating)


static func bonuses_from_ratings(ratings: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for stat_name in RATING_STATS:
		out[stat_name] = bonus_for_rating(stat_name, float(ratings.get(stat_name, RATING_MIN)))
	return out


static func get_stat_ratings(class_id: String) -> Dictionary:
	var ratings: Variant = get_definition(class_id).get("statRatings", {})
	return ratings if ratings is Dictionary else {}


## The stats a class is most defined by: its highest ratings first, then its lowest.
##
## Ratings are already on one scale, so ranking is a plain distance from RATING_STANDARD — no
## weighting step, and a "strength" is exactly what the comparison table shows as an above-average
## number. Used where there is only room for a summary; a class card cannot show all twelve stats
## without becoming unreadable, but it can show what the class is best and worst at.
##
## Returns entries of {"stat": String, "rating": int, "points": int}, where points is the distance
## from the standard rating.
static func notable_stats(ratings: Dictionary, ups: int = 2, downs: int = 1) -> Array:
	var gains: Array = []
	var losses: Array = []
	for stat_name in RATING_STATS:
		if not ratings.has(stat_name):
			continue
		var rating := int(round(float(ratings[stat_name])))
		var delta := rating - RATING_STANDARD
		if delta == 0:
			continue
		var entry := {"stat": str(stat_name), "rating": rating, "points": absi(delta)}
		if delta > 0:
			gains.append(entry)
		else:
			losses.append(entry)
	gains.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.points > b.points)
	losses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.points > b.points)
	return gains.slice(0, maxi(ups, 0)) + losses.slice(0, maxi(downs, 0))


static func get_stat_bonuses(class_id: String) -> Dictionary:
	var def := get_definition(class_id)
	var bonuses: Variant = def.get("statBonuses", {})
	return bonuses if bonuses is Dictionary else {}


static func get_starting_weapon_item_id(class_id: String) -> String:
	return str(get_definition(class_id).get("startingWeaponItemId", "castle_sword"))


static func get_perk(class_id: String) -> String:
	return str(get_definition(class_id).get("perk", ""))


static func clear_cache() -> void:
	_definitions.clear()
	_load_attempted = false


static func _ensure_loaded() -> void:
	if _load_attempted:
		return
	_load_attempted = true
	_definitions = ContentDirLoader.load_id_map([CLASSES_DIR], "id", "ClassCatalog", false, true)
	if _definitions.is_empty():
		push_error("ClassCatalog: no class definitions loaded from %s" % CLASSES_DIR)
	_derive_bonuses_from_ratings()


## Ratings are the source of truth; the `statBonuses` block in content is the derived form kept for
## the schema and for tools that read the numeric deltas. Recomputing it here means a hand-edit to
## one of the two can never leave the displayed rating disagreeing with the applied bonus.
static func _derive_bonuses_from_ratings() -> void:
	for class_id in _definitions:
		var def: Dictionary = _definitions[class_id]
		var ratings: Variant = def.get("statRatings", null)
		if not ratings is Dictionary or (ratings as Dictionary).is_empty():
			continue
		var total := 0
		for stat_name in RATING_STATS:
			if not (ratings as Dictionary).has(stat_name):
				push_error(
					"ClassCatalog: class '%s' is missing a rating for '%s'" % [class_id, stat_name]
				)
			total += int(round(float((ratings as Dictionary).get(stat_name, RATING_MIN))))
		if total != RATING_BUDGET:
			push_error(
				(
					"ClassCatalog: class '%s' spends %d rating points, expected %d — "
					+ "the roster is no longer balanced"
				)
				% [class_id, total, RATING_BUDGET]
			)
		def["statBonuses"] = bonuses_from_ratings(ratings as Dictionary)

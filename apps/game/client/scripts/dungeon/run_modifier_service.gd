extends RefCounted
class_name RunModifierService

## Named run modifiers from difficulty tiers, descent pacts and endless depth (DCT-13).

const FloorSeedMixScript := preload("res://scripts/dungeon/floor_seed_mix.gd")

const MODIFIER_ELITE_PACKS := "elite_packs"
const MODIFIER_ELITE_VIGIL := "elite_vigil"
const MODIFIER_ARMOURED_FOES := "armoured_foes"
const MODIFIER_FRENZIED_FOES := "frenzied_foes"
const MODIFIER_VOLATILE_FOES := "volatile_foes"
const MODIFIER_RELENTLESS_FOES := "relentless_foes"
const MODIFIER_NO_REST := "no_rest"
const MODIFIER_STARVED_HEARTH := "starved_hearth"
const MODIFIER_SEALED_DOORS := "sealed_doors"
const MODIFIER_BARRED_WAYS := "barred_ways"
const MODIFIER_FOG_OF_WAR := "fog_of_war"
const MODIFIER_HOSTILE_HALLS := "hostile_halls"
const MODIFIER_THICK_TRAPS := "thick_traps"
const MODIFIER_NO_MERCHANT := "no_merchant"
const MODIFIER_RICH_VEINS := "rich_veins"
const MODIFIER_BOSS_HOARD := "boss_hoard"

const DESCRIPTIONS := {
	MODIFIER_ELITE_PACKS: "Elite packs — some rooms keep a stronger one.",
	MODIFIER_ELITE_VIGIL: "Vigil — a warden walks every floor.",
	MODIFIER_ARMOURED_FOES: "Armoured — tougher, and slower to swing.",
	MODIFIER_FRENZIED_FOES: "Frenzied — they recover between blows far quicker.",
	MODIFIER_VOLATILE_FOES: "Volatile — thinner, and they hit far harder.",
	MODIFIER_RELENTLESS_FOES: "Relentless — they close the distance and do not stop.",
	MODIFIER_NO_REST: "No rest — the hearths have gone out.",
	MODIFIER_STARVED_HEARTH: "Starved hearth — what rest remains gives little back.",
	MODIFIER_SEALED_DOORS: "Sealed doors — every lock takes two keys.",
	MODIFIER_BARRED_WAYS: "Barred ways — more of the floor is locked away.",
	MODIFIER_FOG_OF_WAR: "Unlit — the map learns nothing you have not walked.",
	MODIFIER_HOSTILE_HALLS: "Hostile halls — the quiet rooms are gone.",
	MODIFIER_THICK_TRAPS: "Old malice — the floor is laid with traps.",
	MODIFIER_NO_MERCHANT: "No market — nobody trades this deep.",
	MODIFIER_RICH_VEINS: "Rich veins — the vaults hold more.",
	MODIFIER_BOSS_HOARD: "Hoard — the floor boss keeps something worth taking.",
}

const ENDLESS_MODIFIER_POOL: Array[String] = [
	MODIFIER_ELITE_PACKS,
	MODIFIER_ARMOURED_FOES,
	MODIFIER_FRENZIED_FOES,
	MODIFIER_VOLATILE_FOES,
	MODIFIER_RELENTLESS_FOES,
	MODIFIER_NO_REST,
	MODIFIER_STARVED_HEARTH,
	MODIFIER_SEALED_DOORS,
	MODIFIER_BARRED_WAYS,
	MODIFIER_FOG_OF_WAR,
	MODIFIER_HOSTILE_HALLS,
	MODIFIER_THICK_TRAPS,
	MODIFIER_ELITE_VIGIL,
]


const ENDLESS_BAND_FLOORS := 25
const ENDLESS_FIRST_BAND := 2
const ENDLESS_MAX_MODIFIERS := 5

static var _active: Array[String] = []


static func set_modifiers(modifiers: Array) -> void:
	_active.clear()
	for entry in modifiers:
		var id := str(entry)
		if id != "" and id not in _active:
			_active.append(id)


static func clear() -> void:
	_active.clear()


static func has_modifier(modifier_id: String) -> bool:
	return modifier_id in _active


static func active_modifiers() -> Array[String]:
	return _active.duplicate()


static func describe(modifier_id: String) -> String:
	return str(DESCRIPTIONS.get(modifier_id, modifier_id.capitalize()))


static func describe_all(modifiers: Array) -> String:
	var lines: Array[String] = []
	for entry in modifiers:
		lines.append(describe(str(entry)))
	return "\n".join(lines)


## Endless floors draw a seeded handful from the whole pool per band of floors, so two bands at
## the same depth on different seeds differ, and no depth settles on one permanent set.
static func endless_modifiers_for_floor(floor_index: int, run_seed: int = 0) -> Array[String]:
	var floor_clamped := maxi(1, floor_index)
	var band := int((floor_clamped - 1) / float(ENDLESS_BAND_FLOORS))
	if band < ENDLESS_FIRST_BAND:
		return []
	var count := mini(1 + int((band - ENDLESS_FIRST_BAND) / 2.0), ENDLESS_MAX_MODIFIERS)
	var rng := RandomNumberGenerator.new()
	rng.seed = FloorSeedMixScript.mix(maxi(1, run_seed), band * 7919 + 13)
	var pool: Array[String] = ENDLESS_MODIFIER_POOL.duplicate()
	var picked: Array[String] = []
	for i in count:
		if pool.is_empty():
			break
		var idx := rng.randi_range(0, pool.size() - 1)
		picked.append(pool[idx])
		pool.remove_at(idx)
	return picked


static func apply_endless_floor_modifiers(floor_index: int, run_seed: int = 0) -> void:
	set_modifiers(endless_modifiers_for_floor(floor_index, run_seed))

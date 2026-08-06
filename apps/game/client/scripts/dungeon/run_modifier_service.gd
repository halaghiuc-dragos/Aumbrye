extends RefCounted
class_name RunModifierService

## Named run modifiers from difficulty tiers and endless depth (DCT-13).

const MODIFIER_ELITE_PACKS := "elite_packs"
const MODIFIER_NO_REST := "no_rest"
const MODIFIER_SEALED_DOORS := "sealed_doors"

const ENDLESS_MODIFIER_ORDER: Array[String] = [
	MODIFIER_ELITE_PACKS,
	MODIFIER_NO_REST,
	MODIFIER_SEALED_DOORS,
]

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


static func endless_modifiers_for_floor(floor_index: int) -> Array[String]:
	var count := int(maxi(0, floor_index) / 50)
	var mods: Array[String] = []
	for i in range(mini(count, ENDLESS_MODIFIER_ORDER.size())):
		mods.append(ENDLESS_MODIFIER_ORDER[i])
	return mods


static func apply_endless_floor_modifiers(floor_index: int) -> void:
	set_modifiers(endless_modifiers_for_floor(floor_index))

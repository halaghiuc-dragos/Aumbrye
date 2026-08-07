extends RefCounted
class_name SaveValidator

const REQUIRED_TOP_LEVEL: Array[String] = [
	"schemaVersion",
	"character",
	"currencies",
	"inventory",
	"talents",
	"flags",
]

const NIL_UUID := "00000000-0000-4000-8000-000000000000"


## True for a native int, or a float with no fractional part. JSON has no int type, so
## JSON.parse_string() always returns float for numbers (Godot 4, documented behaviour) — any
## code path that validates data straight off a JSON round-trip (LocalSave._write_save()'s own
## verify-before-commit step, in particular) would otherwise fail a strict `typeof() == TYPE_INT`
## check for every legitimately-integer field, every time, because the values it is checking
## have already gone through JSON.stringify()/parse_string() and arrive as e.g. 5.0. The load
## path avoids this only because SaveMigrator.migrate() happens to re-coerce these same fields
## with int() before validate() runs; the write path's verify step has no such pass. Validating
## by numeric value rather than by native Variant type is correct for both paths.
static func _is_whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		return is_equal_approx(value, roundf(value))
	return false


## Returns human-readable problem strings; empty means valid.
static func validate(data: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var version := int(data.get("schemaVersion", 0))
	if version < 1 or version > SaveMigrator.CURRENT_VERSION:
		problems.append("schemaVersion")
	for key in REQUIRED_TOP_LEVEL:
		if not data.has(key):
			problems.append(key)
			continue
		var value: Variant = data[key]
		match key:
			"schemaVersion":
				if not _is_whole_number(value):
					problems.append("schemaVersion")
			"character":
				if not value is Dictionary:
					problems.append("character")
				else:
					problems.append_array(_validate_character(value))
			"currencies":
				if not value is Dictionary:
					problems.append("currencies")
				else:
					problems.append_array(_validate_currencies(value))
			"inventory":
				if not value is Dictionary:
					problems.append("inventory")
				else:
					problems.append_array(_validate_inventory(value))
			"talents":
				if not value is Dictionary:
					problems.append("talents")
				else:
					problems.append_array(_validate_talents(value))
			"flags":
				if not value is Dictionary:
					problems.append("flags")
	return problems


static func _validate_character(character: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	if not character.has("level"):
		problems.append("character.level")
	elif not _is_whole_number(character.get("level")) or int(character.get("level")) < 1:
		problems.append("character.level")
	if character.has("xp"):
		if not _is_whole_number(character.get("xp")) or int(character.get("xp")) < 0:
			problems.append("character.xp")
	return problems


static func _validate_currencies(currencies: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	if currencies.has("gold"):
		var gold: Variant = currencies.get("gold")
		if not (gold is int or gold is float) or float(gold) < 0.0:
			problems.append("currencies.gold")
	return problems


static func _validate_inventory(inventory: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	if int(inventory.get("schemaVersion", 0)) != 1:
		problems.append("inventory.schemaVersion")
	for dim_key in ["gridWidth", "gridHeight"]:
		if not inventory.has(dim_key):
			problems.append("inventory.%s" % dim_key)
		elif not _is_whole_number(inventory.get(dim_key)) or int(inventory.get(dim_key)) < 1:
			problems.append("inventory.%s" % dim_key)
	var slots: Variant = inventory.get("slots", [])
	if not slots is Array:
		problems.append("inventory.slots")
	else:
		for i in slots.size():
			if not slots[i] is Dictionary:
				problems.append("inventory.slots[%d]" % i)
				continue
			problems.append_array(_validate_slot(slots[i], "inventory.slots[%d]" % i))
	var equipped: Variant = inventory.get("equipped", {})
	if not equipped is Dictionary:
		problems.append("inventory.equipped")
	else:
		for slot_name in equipped:
			if slot_name not in Equipment.SLOT_ORDER:
				problems.append("inventory.equipped.%s" % slot_name)
				continue
			var inst: Variant = equipped[slot_name]
			if inst is Dictionary and not inst.is_empty():
				problems.append_array(_validate_slot(inst, "inventory.equipped.%s" % slot_name))
	return problems


static func _validate_slot(slot: Dictionary, prefix: String) -> Array[String]:
	var problems: Array[String] = []
	var item_id: String = str(slot.get("itemId", ""))
	if item_id == "":
		problems.append("%s.itemId" % prefix)
	if slot.has("quantity"):
		if not _is_whole_number(slot.get("quantity")) or int(slot.get("quantity")) < 1:
			problems.append("%s.quantity" % prefix)
	return problems


static func _validate_talents(talents: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for talent_id in talents:
		var value: Variant = talents[talent_id]
		if not _is_whole_number(value) or int(value) < 0:
			problems.append("talents.%s" % talent_id)
	return problems

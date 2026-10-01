extends RefCounted
class_name SaveValidator

## Two tiers. `validate()` lists the *fatal* problems: a file that cannot be read as a save, or is
## missing something a character cannot exist without. `repair()` fixes the small ones in place --
## an unknown equipment slot, a bad quantity, a fractional talent rank -- and reports what it did,
## so one stray field does not cost the player everything since the last backup.

const REQUIRED_TOP_LEVEL: Array[String] = [
	"schemaVersion",
	"character",
	"currencies",
	"inventory",
	"talents",
	"flags",
]


static func _is_whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		return is_equal_approx(value, roundf(value))
	return false


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
			"character", "currencies", "talents", "flags":
				if not value is Dictionary:
					problems.append(key)
			"inventory":
				if not value is Dictionary:
					problems.append("inventory")
				else:
					problems.append_array(_validate_inventory_shape(value))
	return problems


static func _validate_inventory_shape(inventory: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	if int(inventory.get("schemaVersion", 0)) != 1:
		problems.append("inventory.schemaVersion")
	for dim_key in ["gridWidth", "gridHeight"]:
		if not inventory.has(dim_key):
			problems.append("inventory.%s" % dim_key)
		elif not _is_whole_number(inventory.get(dim_key)) or int(inventory.get(dim_key)) < 1:
			problems.append("inventory.%s" % dim_key)
	if not inventory.get("slots", []) is Array:
		problems.append("inventory.slots")
	if not inventory.get("equipped", {}) is Dictionary:
		problems.append("inventory.equipped")
	return problems


## Fixes everything `validate()` tolerates, in place. Returns one line per repair; empty when the
## document was already clean. Call it on a document that has no fatal problems.
static func repair(data: Dictionary) -> Array[String]:
	var repairs: Array[String] = []
	_repair_character(data.get("character", {}), repairs)
	_repair_currencies(data.get("currencies", {}), repairs)
	_repair_inventory(data.get("inventory", {}), repairs)
	_repair_talents(data.get("talents", {}), repairs)
	return repairs


static func _repair_character(character: Variant, repairs: Array[String]) -> void:
	if not character is Dictionary:
		return
	var record: Dictionary = character
	if not record.has("level") or not _is_whole_number(record.get("level")) or int(record.get("level")) < 1:
		record["level"] = 1
		repairs.append("character.level reset to 1")
	if record.has("xp") and (not _is_whole_number(record.get("xp")) or int(record.get("xp")) < 0):
		record["xp"] = 0
		repairs.append("character.xp reset to 0")


static func _repair_currencies(currencies: Variant, repairs: Array[String]) -> void:
	if not currencies is Dictionary:
		return
	var record: Dictionary = currencies
	if record.has("gold"):
		var gold: Variant = record.get("gold")
		if not (gold is int or gold is float) or float(gold) < 0.0:
			record["gold"] = 0
			repairs.append("currencies.gold reset to 0")


static func _repair_inventory(inventory: Variant, repairs: Array[String]) -> void:
	if not inventory is Dictionary:
		return
	var record: Dictionary = inventory
	var slots: Array = record.get("slots", [])
	for i in range(slots.size() - 1, -1, -1):
		if not slots[i] is Dictionary or str((slots[i] as Dictionary).get("itemId", "")) == "":
			slots.remove_at(i)
			repairs.append("inventory slot %d dropped: no item" % i)
			continue
		_repair_quantity(slots[i] as Dictionary, "inventory slot %d" % i, repairs)
	var equipped: Dictionary = record.get("equipped", {})
	for slot_name in equipped.keys():
		if slot_name not in Equipment.SLOT_ORDER:
			equipped.erase(slot_name)
			repairs.append("equipped slot '%s' dropped: unknown slot" % slot_name)
			continue
		var instance: Variant = equipped[slot_name]
		if not instance is Dictionary:
			equipped.erase(slot_name)
			repairs.append("equipped slot '%s' dropped: not an item" % slot_name)
		elif not (instance as Dictionary).is_empty():
			if str((instance as Dictionary).get("itemId", "")) == "":
				equipped.erase(slot_name)
				repairs.append("equipped slot '%s' dropped: no item" % slot_name)
			else:
				_repair_quantity(instance as Dictionary, "equipped slot '%s'" % slot_name, repairs)


static func _repair_quantity(slot: Dictionary, label: String, repairs: Array[String]) -> void:
	if slot.has("quantity") and (not _is_whole_number(slot.get("quantity")) or int(slot.get("quantity")) < 1):
		slot["quantity"] = 1
		repairs.append("%s quantity reset to 1" % label)


static func _repair_talents(talents: Variant, repairs: Array[String]) -> void:
	if not talents is Dictionary:
		return
	var record: Dictionary = talents
	for talent_id in record.keys():
		var value: Variant = record[talent_id]
		if _is_whole_number(value) and int(value) >= 0:
			continue
		if value is int or value is float:
			record[talent_id] = maxi(0, roundi(float(value)))
			repairs.append("talent '%s' rank rounded" % talent_id)
		else:
			record.erase(talent_id)
			repairs.append("talent '%s' dropped: not a rank" % talent_id)

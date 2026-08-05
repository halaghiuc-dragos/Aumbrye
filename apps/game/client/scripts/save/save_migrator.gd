extends RefCounted
class_name SaveMigrator

## SCHEMA-7.1 — versioned save migrations.

const CURRENT_VERSION := 3
const MIGRATION_DOC := "docs/SAVE_MIGRATIONS.md"


static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("schemaVersion", 0))
	if version == CURRENT_VERSION:
		return data
	if version == 0:
		return _fail(data, "missing schemaVersion")
	if version == 1:
		data = _migrate_v1_to_v2(data)
		version = int(data.get("schemaVersion", 0))
	if version == 2:
		data = _migrate_v2_to_v3(data)
		version = int(data.get("schemaVersion", 0))
	if version != CURRENT_VERSION:
		return _fail(data, "unsupported schemaVersion %d" % version)
	return data


static func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy["schemaVersion"] = 2
	var active: Variant = copy.get("activeRun", {})
	if active is Dictionary and not active.is_empty():
		var run: Dictionary = active
		if not run.has("currentFloor"):
			run["currentFloor"] = 1
		if not run.has("maxFloors"):
			run["maxFloors"] = RunFloorConfig.MAX_FLOORS
		if not run.has("floorDefinitions"):
			run["floorDefinitions"] = {}
		copy["activeRun"] = run
	return copy


static func _migrate_v2_to_v3(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy["schemaVersion"] = 3
	var active: Variant = copy.get("activeRun", {})
	if active is Dictionary and not active.is_empty():
		var run: Dictionary = active
		if not run.has("runMode"):
			run["runMode"] = "castle"
		run.erase("floorDefinitions")
		copy["activeRun"] = run
	return copy


static func _fail(data: Dictionary, reason: String) -> Dictionary:
	push_error("SaveMigrator: %s — refusing load" % reason)
	return {
		"migrationFailed": true,
		"migrationReason": reason,
		"originalSchemaVersion": int(data.get("schemaVersion", 0)),
	}

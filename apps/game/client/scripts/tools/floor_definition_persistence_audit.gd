extends Node

const RunFlowScript := preload("res://scripts/app/run_flow.gd")

var _failures := 0


func _ready() -> void:
	FloorDefinitionCache.clear_floor_cache()
	FloorDefinitionCache.begin_run_cache("persistence-audit")
	for floor_index in range(1, 10):
		FloorDefinitionCache.store_floor_cache(floor_index, {"floor": floor_index, "doors": [floor_index]})
	_check(FloorDefinitionCache.get_floor_cache(1).is_empty(), "far floor is evicted from bounded memory")
	_check(FloorDefinitionCache.get_floor_cache(9).get("doors", []) == [9], "recent cached topology is exact")
	await _check_evicted_floor_restore()
	var migrated := SaveMigrator.migrate({
		"schemaVersion": 12,
		"activeRun": {"floorDefinitions": {"3": {"definition": {"doors": ["a"], "loot": ["b"]}, "definitionHash": "audit"}}},
	})
	var active: Dictionary = migrated.get("activeRun", {})
	var definitions: Dictionary = active.get("floorDefinitions", {})
	_check(
		int(migrated.get("schemaVersion", 0)) == SaveMigrator.CURRENT_VERSION
		and definitions.get("3", {}).get("definition", {}).get("loot", []) == ["b"],
		"migration retains saved immutable floor definition"
	)
	print("FLOOR DEFINITION PERSISTENCE RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_evicted_floor_restore() -> void:
	var original_active := LocalSave.get_active_run().duplicate(true)
	var definition := {
		"rooms": [{"id": "entrance"}, {"id": "vault"}],
		"edges": [{"from": "entrance", "to": "vault", "kind": "locked"}],
		"loot": [{"instanceId": "audit-unique-loot", "roomId": "vault"}],
	}
	var snapshot := {
		"snapshotVersion": 1,
		"bossDoorState": "OPEN",
		"lootClaimedInstanceIds": ["audit-unique-loot"],
		"enemies": {"audit-enemy": {"dead": true}},
		"worldFlags": {"explored_vault": true},
	}
	var flow := RunFlowScript.new()
	flow.current_biome_id = "forgotten_castle"
	flow.current_dungeon_id = "forgotten_castle"
	flow.current_generator = "gdscript"
	var record: Dictionary = flow._floor_definition_record(definition)
	LocalSave.set_active_run({
		"floorDefinitions": {
			"1": record
		},
		"floorSnapshots": {"1": snapshot},
	}, false)
	var restored: Dictionary = await flow._resolve_floor_definition(1)
	var restored_snapshot: Dictionary = LocalSave.get_active_run().get("floorSnapshots", {}).get("1", {})
	_check(
		restored.get("edges", []) == definition["edges"]
		and restored.get("loot", []) == definition["loot"],
		"an evicted floor restores its exact saved doors and loot identities"
	)
	_check(
		restored_snapshot.get("bossDoorState", "") == "OPEN"
		and restored_snapshot.get("lootClaimedInstanceIds", []) == ["audit-unique-loot"]
		and bool(restored_snapshot.get("worldFlags", {}).get("explored_vault", false))
		and int(restored_snapshot.get("snapshotVersion", 0)) == 1,
		"an evicted floor retains mutable door, loot, and exploration state"
	)
	_check(
		int(record.get("recordVersion", 0)) == 1
		and str(record.get("contentHash", "")).length() == 64
		and str(record.get("generatorHash", "")).length() == 64,
		"floor records version snapshots and store content/generator fingerprints"
	)
	LocalSave.set_active_run(original_active, false)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)

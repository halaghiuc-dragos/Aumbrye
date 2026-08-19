extends "res://scripts/validation/validation_suite.gd"

const SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")


func get_category() -> String:
	return "save"


func _init(context) -> void:
	super._init(context)
	manage_save_file = true


func run() -> void:
	var backup: Dictionary = ctx.backup_save_file()
	_test_corrupt_json_recovers()
	_test_truncated_json_recovers()
	_test_future_schema_version_refused()
	_test_missing_item_id_dropped()
	ctx.restore_save_file(backup)


func _write_save_text(text: String) -> void:
	var file := FileAccess.open(TC.SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()


func _test_corrupt_json_recovers() -> void:
	var start := Time.get_ticks_msec()
	_write_save_text("not json at all")
	var ok: bool = not LocalSave.load_into_services() and FileAccess.file_exists(TC.SAVE_PATH)
	ctx.timed_record(
		"error.save.corrupt_json_recovers",
		get_category(),
		ok,
		"corrupt save rejected without crash",
		start,
		"VSU-09"
	)


func _test_truncated_json_recovers() -> void:
	var start := Time.get_ticks_msec()
	_write_save_text('{"schemaVersion": 5, "characters": [')
	var ok: bool = not LocalSave.load_into_services()
	ctx.timed_record(
		"error.save.truncated_json_recovers",
		get_category(),
		ok,
		"truncated save rejected without crash",
		start,
		"VSU-09"
	)


func _test_future_schema_version_refused() -> void:
	var start := Time.get_ticks_msec()
	var future_version := SaveMigratorScript.CURRENT_VERSION + 10
	_write_save_text(
		JSON.stringify(
			{
				"schemaVersion": future_version,
				"characters": [],
				"inventory": {"slots": [], "equipped": {}},
			}
		)
	)
	var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(TC.SAVE_PATH))
	var migrated: Dictionary = SaveMigratorScript.migrate(payload if payload is Dictionary else {})
	ctx.timed_record(
		"error.migration.future_schema_version",
		get_category(),
		migrated.is_empty(),
		"future schemaVersion is refused",
		start,
		"VSU-09"
	)


func _test_missing_item_id_dropped() -> void:
	var start := Time.get_ticks_msec()
	var grid := GridInventory.new()
	grid.from_save_dict(
		{
			"gridWidth": 10,
			"gridHeight": 6,
			"slots": [{"itemId": "__missing_item__", "quantity": 1, "x": 0, "y": 0}],
			"equipped": {},
		}
	)
	var cleaned := grid.to_save_dict()
	var slots: Array = cleaned.get("slots", [])
	var ok := slots.is_empty() or str(slots[0].get("itemId", "")) != "__missing_item__"
	ctx.timed_record(
		"error.content.missing_item_id",
		get_category(),
		ok,
		"unknown inventory item id is dropped on sanitize",
		start,
		"VSU-09"
	)

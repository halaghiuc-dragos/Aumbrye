extends RefCounted


const META_KEY := "cloudOutbox"
const MAX_ATTEMPTS := 5
const MAX_ENTRIES := 32


static func _read() -> Array:
	var meta := LocalSave.get_meta_data()
	var raw: Variant = meta.get(META_KEY, [])
	return raw if raw is Array else []


static func _write(entries: Array) -> void:
	var meta := LocalSave.get_meta_data()
	if entries.is_empty():
		meta.erase(META_KEY)
	else:
		meta[META_KEY] = entries
	LocalSave.patch_meta(meta)


static func enqueue(
	run_id: String,
	outcome: String,
	elapsed: float,
	boss_defeated: bool,
	loot_instance_ids: Array,
	floor_index: int,
	kills: int = 0
) -> void:
	if run_id == "":
		return
	var entries := _read()
	for entry in entries:
		if entry is Dictionary and str((entry as Dictionary).get("runId", "")) == run_id:
			return
	entries.append(
		{
			"runId": run_id,
			"outcome": outcome,
			"elapsed": elapsed,
			"bossDefeated": boss_defeated,
			"lootIds": loot_instance_ids.duplicate(),
			"floor": maxi(1, floor_index),
			"kills": maxi(0, kills),
			"attempts": 0,
		}
	)
	while entries.size() > MAX_ENTRIES:
		entries.pop_front()
	_write(entries)


static func resolve(run_id: String) -> void:
	var entries := _read()
	var kept: Array = []
	for entry in entries:
		if entry is Dictionary and str((entry as Dictionary).get("runId", "")) == run_id:
			continue
		kept.append(entry)
	if kept.size() != entries.size():
		_write(kept)


static func replay() -> void:
	if not ApiConfig.cloud_calls_enabled():
		return
	var entries := _read()
	if entries.is_empty():
		return

	var kept: Array = []
	for entry in entries:
		if not entry is Dictionary:
			continue
		var record: Dictionary = entry
		var run_id := str(record.get("runId", ""))
		if run_id == "":
			continue

		var result := await ApiClient.complete_run(
			run_id,
			str(record.get("outcome", "escaped")),
			float(record.get("elapsed", 0.0)),
			bool(record.get("bossDefeated", false)),
			record.get("lootIds", []),
			int(record.get("floor", 1)),
			int(record.get("kills", 0))
		)
		if result.get("ok", false):
			continue

		var attempts := int(record.get("attempts", 0)) + 1
		if attempts >= MAX_ATTEMPTS:
			push_warning(
				(
					"CloudOutbox: dropping run %s after %d failed attempts — %s"
					% [run_id, attempts, str(result.get("error", "unknown"))]
				)
			)
			continue
		record["attempts"] = attempts
		kept.append(record)

	_write(kept)
	if kept.size() != entries.size():
		LocalSave.autosave()

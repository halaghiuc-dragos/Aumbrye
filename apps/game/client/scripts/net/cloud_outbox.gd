extends RefCounted


const META_KEY := "cloudOutbox"
const DEAD_LETTER_KEY := "cloudOutboxDeadLetters"
const MAX_ATTEMPTS := 5
const MAX_ENTRIES := 32
static var _replay_running := false


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


static func _read_dead_letters() -> Array:
	var raw: Variant = LocalSave.get_meta_data().get(DEAD_LETTER_KEY, [])
	return (raw as Array).duplicate(true) if raw is Array else []


static func _write_dead_letters(entries: Array) -> void:
	var meta := LocalSave.get_meta_data()
	meta[DEAD_LETTER_KEY] = entries
	LocalSave.patch_meta(meta)


static func enqueue(
	run_id: String,
	outcome: String,
	elapsed: float,
	boss_defeated: bool,
	loot_instance_ids: Array,
	floor_index: int,
	kills: int = 0,
	submit_ranked: bool = false
) -> void:
	if run_id == "":
		return
	var entries := _read()
	for entry in entries:
		if entry is Dictionary and str((entry as Dictionary).get("runId", "")) == run_id:
			return
	entries.append(
		{
			"operationId": "complete_run:%s" % run_id,
			"runId": run_id,
			"outcome": outcome,
			"elapsed": elapsed,
			"bossDefeated": boss_defeated,
			"lootIds": loot_instance_ids.duplicate(),
			"floor": maxi(1, floor_index),
			"kills": maxi(0, kills),
			# Keep this beside the completion operation.  A retry must not acknowledge an
			# eligible clear before its server-side leaderboard submission has succeeded.
			"submitRanked": submit_ranked,
			"attempts": 0,
		}
	)
	while entries.size() > MAX_ENTRIES:
		_move_to_dead_letter(entries.pop_front(), "capacity", "outbox capacity exceeded")
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
	if _replay_running or not ApiConfig.cloud_calls_enabled():
		return
	var entries := _read()
	if entries.is_empty():
		return
	_replay_running = true
	for entry in entries.duplicate(true):
		if not entry is Dictionary:
			continue
		var record: Dictionary = entry
		var run_id := str(record.get("runId", ""))
		if run_id == "":
			continue
		if int(record.get("nextRetryAt", 0)) > int(Time.get_unix_time_from_system()):
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
			if not bool(record.get("submitRanked", false)):
				_acknowledge(str(record.get("operationId", "complete_run:%s" % run_id)))
				continue
			var leaderboard := await ApiClient.submit_leaderboard(run_id, true)
			if leaderboard.get("ok", false):
				_acknowledge(str(record.get("operationId", "complete_run:%s" % run_id)))
				continue
			# CompleteRunAsync is idempotent.  Keep the record so the next retry can
			# safely replay completion then make the ranked submission again.
			result = leaderboard

		var attempts := int(record.get("attempts", 0)) + 1
		var error_kind := _classify_error(result)
		if attempts >= MAX_ATTEMPTS or error_kind in ["auth", "version", "permanent"]:
			_move_latest_to_dead_letter(
				str(record.get("operationId", "complete_run:%s" % run_id)),
				error_kind,
				str(result.get("error", "unknown"))
			)
			continue
		record["attempts"] = attempts
		record["lastError"] = str(result.get("error", "unknown"))
		record["nextRetryAt"] = int(Time.get_unix_time_from_system()) + mini(3600, 1 << mini(attempts, 10))
		_update_latest(record)
	_replay_running = false
	LocalSave.autosave()


static func _acknowledge(operation_id: String) -> void:
	var latest := _read()
	latest = latest.filter(func(row: Variant) -> bool:
		return not (row is Dictionary and str((row as Dictionary).get("operationId", "")) == operation_id)
	)
	_write(latest)


static func _update_latest(record: Dictionary) -> void:
	var latest := _read()
	var operation_id := str(record.get("operationId", ""))
	for index in latest.size():
		if latest[index] is Dictionary and str(latest[index].get("operationId", "")) == operation_id:
			latest[index] = record
			_write(latest)
			return


static func _move_latest_to_dead_letter(operation_id: String, kind: String, error: String) -> void:
	var latest := _read()
	for index in range(latest.size() - 1, -1, -1):
		var row: Variant = latest[index]
		if row is Dictionary and str((row as Dictionary).get("operationId", "")) == operation_id:
			latest.remove_at(index)
			_move_to_dead_letter(row, kind, error)
			break
	_write(latest)


static func _move_to_dead_letter(record: Variant, kind: String, error: String) -> void:
	if not record is Dictionary:
		return
	var failed := (record as Dictionary).duplicate(true)
	failed["failureKind"] = kind
	failed["lastError"] = error
	failed["failedAt"] = int(Time.get_unix_time_from_system())
	var dead := _read_dead_letters()
	dead.append(failed)
	_write_dead_letters(dead)


static func _classify_error(result: Dictionary) -> String:
	var status := int(result.get("status", result.get("status_code", 0)))
	if status in [401, 403]:
		return "auth"
	if status in [409, 410, 426]:
		return "version"
	if status >= 400 and status < 500 and status not in [408, 429]:
		return "permanent"
	return "transient"


static func get_dead_letters() -> Array:
	return _read_dead_letters()


static func retry_dead_letter(operation_id: String) -> bool:
	var dead := _read_dead_letters()
	for index in dead.size():
		var row: Dictionary = dead[index]
		if str(row.get("operationId", "")) != operation_id:
			continue
		dead.remove_at(index)
		row.erase("failureKind")
		row.erase("failedAt")
		row["attempts"] = 0
		row["nextRetryAt"] = 0
		var pending := _read()
		pending.append(row)
		_write_dead_letters(dead)
		_write(pending)
		return true
	return false


static func discard_dead_letter(operation_id: String) -> bool:
	var dead := _read_dead_letters()
	var kept := dead.filter(func(row: Variant) -> bool:
		return not (row is Dictionary and str((row as Dictionary).get("operationId", "")) == operation_id)
	)
	if kept.size() == dead.size():
		return false
	_write_dead_letters(kept)
	return true

extends RefCounted

## Intentionally NOT declared with `class_name`. This script references the LocalSave, ApiConfig
## and ApiClient autoloads, and scripts in the global-class table are compiled before autoload
## singletons are registered as global identifiers — which fails the whole compile. Consumers
## preload it instead (see RunFlow.CloudOutboxScript).

## Durable queue of run completions that still owe the server a call.
##
## Cloud finalisation is deliberately fire-and-forget so the results screen never waits on the
## network. The cost was that quitting on the results screen lost the completion outright: the
## client had already cleared its local active run, while the server kept the run Active forever —
## which also blocks leaderboard submission, since that requires a Completed run.
##
## Entries are persisted in the save's meta block and replayed on the next boot. Replay is safe
## because `/runs/{id}/complete` is idempotent server-side: it claims the run with a guarded status
## flip and replays its cached result for any repeat call.

const META_KEY := "cloudOutbox"
const MAX_ATTEMPTS := 5
## Bounds the queue so a permanently offline player cannot grow their save without limit.
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


## Records a completion that has not been acknowledged by the server yet.
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


## Drops an entry the server has acknowledged.
static func resolve(run_id: String) -> void:
	var entries := _read()
	var kept: Array = []
	for entry in entries:
		if entry is Dictionary and str((entry as Dictionary).get("runId", "")) == run_id:
			continue
		kept.append(entry)
	if kept.size() != entries.size():
		_write(kept)


static func pending_count() -> int:
	return _read().size()


## Retries every queued completion once. Called after the session is restored at boot.
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
			# Give up rather than retrying a permanently rejected completion every boot.
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

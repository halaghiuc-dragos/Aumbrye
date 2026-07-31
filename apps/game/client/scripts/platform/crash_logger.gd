extends Node

## PERF-7.2 — structured crash logging with content version tag.

const LOG_DIR := "user://crash_reports/"
const CONTENT_VERSION := "ea-m7"

var _session_id := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session_id = "%d-%d" % [Time.get_unix_time_from_system(), randi()]
	_ensure_log_dir()


func _notification(what: int) -> void:
	if what == NOTIFICATION_CRASH:
		_write_crash_report("engine_crash", "Godot engine crash notification")


func log_error(context: String, details: Dictionary = {}) -> void:
	var payload := _base_payload(context, details)
	payload["severity"] = "error"
	_append_log(payload)


func log_exception(context: String, error: Variant) -> void:
	log_error(context, {"exception": str(error)})


func _write_crash_report(context: String, message: String) -> void:
	var payload := _base_payload(context, {"message": message})
	payload["severity"] = "crash"
	var path := LOG_DIR.path_join("crash_%s.json" % _session_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(payload, "\t"))


func _base_payload(context: String, details: Dictionary) -> Dictionary:
	return {
		"contentVersion": CONTENT_VERSION,
		"sessionId": _session_id,
		"context": context,
		"timestamp": Time.get_datetime_string_from_system(),
		"os": OS.get_name(),
		"details": details,
	}


func _append_log(payload: Dictionary) -> void:
	var path := LOG_DIR.path_join("session_%s.log" % _session_id)
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line(JSON.stringify(payload))


func _ensure_log_dir() -> void:
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		DirAccess.make_dir_recursive_absolute(LOG_DIR)

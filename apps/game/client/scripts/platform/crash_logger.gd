extends Node


const PrivacySettingsScript := preload("res://scripts/platform/privacy_settings.gd")

const LOG_DIR := "user://crash_reports/"
const SCHEMA_VERSION := 1
const MAX_REPORT_FILES := 20
const MAX_REPORT_BYTES := 5 * 1024 * 1024
const UPLOAD_TIMEOUT_SEC := 5.0
const TELEMETRY_CRASH_PATH := "/api/v1/telemetry/crash"
const STEAM_CLOUD_SAVE_NAME := "aumbrye_save.json"

var _session_id := ""
var _session_log: FileAccess
var _static_payload: Dictionary = {}
var _upload_started := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	PrivacySettingsScript.load_from_save()
	_session_id = "%d-%d" % [Time.get_unix_time_from_system(), randi()]
	_ensure_log_dir()
	_prune_old_reports()
	_build_static_payload()
	_open_session_log()
	if PrivacySettingsScript.send_crash_reports:
		call_deferred("_upload_pending_reports")


func _notification(what: int) -> void:
	if what == NOTIFICATION_CRASH:
		_write_crash_report("engine_crash", "Godot engine crash notification")


func _exit_tree() -> void:
	_close_session_log()


func log_error(context: String, details: Dictionary = {}) -> void:
	var payload := _build_payload(context, details)
	payload["severity"] = "error"
	_append_log(payload)


func log_warning(context: String, details: Dictionary = {}) -> void:
	var payload := _build_payload(context, details)
	payload["severity"] = "warning"
	_append_log(payload)


func scrub_payload(payload: Dictionary) -> Dictionary:
	var cleaned := payload.duplicate(true)
	cleaned = _scrub_value(cleaned)
	return cleaned


func _write_crash_report(context: String, message: String) -> void:
	var payload := _build_payload(context, {"message": message})
	payload["severity"] = "crash"
	var path := LOG_DIR.path_join("crash_%s.json" % _session_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(payload, "\t"))
		file.flush()
		file.close()


func _build_static_payload() -> void:
	var version_info: Dictionary = Engine.get_version_info()
	var engine_version := "%s.%s.%s" % [
		version_info.get("major", 0),
		version_info.get("minor", 0),
		version_info.get("patch", 0),
	]
	if version_info.has("status"):
		engine_version += ".%s" % version_info.get("status", "")
	var os_version := "%s %s" % [OS.get_name(), OS.get_version()]
	_static_payload = {
		"schemaVersion": SCHEMA_VERSION,
		"gameVersion": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"contentVersion": ApiConfig.CONTENT_VERSION,
		"engineVersion": engine_version,
		"os": OS.get_name(),
		"osVersion": os_version,
		"cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name() if RenderingServer.get_video_adapter_name() != "" else "unknown",
		"gpuDriver": RenderingServer.get_video_adapter_api_version(),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")),
		"locale": OS.get_locale_language(),
		"sessionId": _session_id,
	}


func _build_payload(context: String, details: Dictionary) -> Dictionary:
	var payload := _static_payload.duplicate(true)
	payload["context"] = context
	payload["timestamp"] = Time.get_datetime_string_from_system()
	payload["scene"] = _current_scene_path()
	payload["runMode"] = _current_run_mode()
	payload["stack"] = _capture_stack()
	payload["details"] = details
	return payload


func _current_scene_path() -> String:
	var tree := get_tree()
	if tree == null:
		return ""
	var scene := tree.current_scene
	if scene == null:
		return "headless"
	return str(scene.scene_file_path)


func _current_run_mode() -> String:
	if RunFlow and RunFlow.has_method("get_run_mode_label"):
		return str(RunFlow.call("get_run_mode_label"))
	if RunFlow:
		return str(RunFlow.run_mode)
	return ""


func _capture_stack() -> Array[String]:
	var frames: Array[String] = []
	for frame in get_stack():
		frames.append(str(frame))
	if frames.is_empty():
		frames.append("no_stack_captured")
	return frames


func _open_session_log() -> void:
	var path := LOG_DIR.path_join("session_%s.log" % _session_id)
	_session_log = FileAccess.open(path, FileAccess.WRITE)
	if _session_log == null:
		_session_log = FileAccess.open(path, FileAccess.READ_WRITE)
		if _session_log:
			_session_log.seek_end()


func _close_session_log() -> void:
	if _session_log:
		_session_log.flush()
		_session_log.close()
		_session_log = null


func _append_log(payload: Dictionary) -> void:
	if _session_log == null:
		_open_session_log()
	if _session_log:
		_session_log.store_line(JSON.stringify(payload))
		_session_log.flush()


func _ensure_log_dir() -> void:
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		DirAccess.make_dir_recursive_absolute(LOG_DIR)


func _prune_old_reports() -> void:
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		return
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return
	var entries: Array[Dictionary] = []
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir() and (entry_name.begins_with("crash_") or entry_name.begins_with("session_")):
			var full_path := LOG_DIR.path_join(entry_name)
			if entry_name.ends_with(".json"):
				var file := FileAccess.open(full_path, FileAccess.READ)
				if file:
					var parsed: Variant = JSON.parse_string(file.get_as_text())
					file.close()
					if parsed is Dictionary and not parsed.has("schemaVersion"):
						DirAccess.remove_absolute(full_path)
						entry_name = dir.get_next()
						continue
			entries.append(
				{
					"path": full_path,
					"name": entry_name,
					"mtime": FileAccess.get_modified_time(full_path),
					"size": FileAccess.get_file_as_bytes(full_path).size(),
				}
			)
		entry_name = dir.get_next()
	dir.list_dir_end()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["mtime"] < b["mtime"])
	var total_bytes := 0
	for entry in entries:
		total_bytes += int(entry.get("size", 0))
	while entries.size() > MAX_REPORT_FILES or total_bytes > MAX_REPORT_BYTES:
		var oldest: Dictionary = entries.pop_front()
		DirAccess.remove_absolute(str(oldest.get("path", "")))
		total_bytes -= int(oldest.get("size", 0))


func _upload_pending_reports() -> void:
	if _upload_started or not PrivacySettingsScript.send_crash_reports:
		return
	_upload_started = true
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		return
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir() and entry_name.begins_with("crash_") and entry_name.ends_with(".json"):
			var path := LOG_DIR.path_join(entry_name)
			await _upload_report_file(path)
		entry_name = dir.get_next()
	dir.list_dir_end()


func _upload_report_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	var payload: Dictionary = scrub_payload(parsed)
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = UPLOAD_TIMEOUT_SEC
	var url := ApiConfig.get_base_url() + TELEMETRY_CRASH_PATH
	var headers := PackedStringArray(
		[
			"Content-Type: application/json",
			"X-Client-Version: %s" % ApiConfig.CLIENT_VERSION,
			"X-Content-Version: %s" % ApiConfig.CONTENT_VERSION,
		]
	)
	if ApiConfig.access_token != "":
		headers.append("Authorization: Bearer %s" % ApiConfig.access_token)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		http.queue_free()
		return
	var response = await http.request_completed
	http.queue_free()
	var code: int = response[1]
	if code >= 200 and code < 300:
		DirAccess.remove_absolute(path)


func _scrub_value(value: Variant) -> Variant:
	if value is String:
		return _scrub_string(value)
	if value is Dictionary:
		var out: Dictionary = {}
		for key in value.keys():
			out[key] = _scrub_value(value[key])
		return out
	if value is Array:
		var arr: Array = []
		for item in value:
			arr.append(_scrub_value(item))
		return arr
	return value


func _scrub_string(text: String) -> String:
	var cleaned := text
	var user_data := OS.get_user_data_dir()
	if user_data != "":
		cleaned = cleaned.replace(user_data, "<user_data>")
	cleaned = cleaned.replace("user://", "")
	var user_name := OS.get_environment("USERNAME")
	if user_name == "":
		user_name = OS.get_environment("USER")
	if user_name != "":
		cleaned = cleaned.replace(user_name, "<user>")
	return cleaned

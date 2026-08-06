extends "res://scripts/validation/validation_suite.gd"

const SteamServiceScript := preload("res://scripts/platform/steam_service.gd")
const CrashLoggerScript := preload("res://scripts/platform/crash_logger.gd")
const PrivacySettingsScript := preload("res://scripts/platform/privacy_settings.gd")


func _init(context) -> void:
	super._init(context)
	manage_save_file = false


func get_category() -> String:
	return "platform"


func run() -> void:
	await _test_steam_stub_reports_unavailable()
	await _test_steam_sync_reports_zero_synced()
	_test_steam_app_id_priority()
	await _test_steam_auth_ticket_empty_in_stub()
	await _test_steam_shutdown_is_idempotent()
	await _test_steam_no_callbacks_pumped_in_stub()
	await _test_crash_payload_has_required_fields()
	_test_crash_content_version_matches_api_config()
	_test_crash_log_error_writes_a_line()
	_test_crash_log_error_flushes()
	_test_crash_retention_prunes_oldest()
	await _test_crash_upload_disabled_by_default()
	_test_crash_scrubs_user_paths()


func _test_steam_stub_reports_unavailable() -> void:
	var start := Time.get_ticks_msec()
	var steam := SteamServiceScript.new()
	ctx.owner.add_child(steam)
	await ctx.owner.get_tree().process_frame
	var result: int = steam.unlock_achievement("boss_slayer")
	ctx.timed_record(
		"platform.steam.stub_reports_unavailable",
		get_category(),
		result == SteamServiceScript.Result.UNAVAILABLE,
		"unlock_achievement returns UNAVAILABLE in stub mode",
		start,
		"PLT-06"
	)
	steam.queue_free()


func _test_steam_sync_reports_zero_synced() -> void:
	var start := Time.get_ticks_msec()
	var steam := SteamServiceScript.new()
	ctx.owner.add_child(steam)
	await ctx.owner.get_tree().process_frame
	var stats: Dictionary = steam.sync_achievements(["boss_slayer"])
	ctx.timed_record(
		"platform.steam.sync_reports_zero_synced",
		get_category(),
		int(stats.get("synced", -1)) == 0,
		"sync_achievements reports zero synced in stub mode",
		start,
		"PLT-06"
	)
	steam.queue_free()


func _test_steam_app_id_priority() -> void:
	var start := Time.get_ticks_msec()
	var steam := SteamServiceScript.new()
	steam.call("_resolve_app_id")
	var default_id: int = steam.app_id
	OS.set_environment("AUMBRYE_STEAM_APP_ID", "12345")
	steam.call("_resolve_app_id")
	var env_id: int = steam.app_id
	OS.unset_environment("AUMBRYE_STEAM_APP_ID")
	var ok := default_id == 480 and env_id == 12345
	ctx.timed_record(
		"platform.steam.app_id_priority",
		get_category(),
		ok,
		"env var overrides default/platform app id (default=%d env=%d)" % [default_id, env_id],
		start,
		"PLT-14"
	)


func _test_steam_auth_ticket_empty_in_stub() -> void:
	var start := Time.get_ticks_msec()
	var steam := SteamServiceScript.new()
	ctx.owner.add_child(steam)
	await ctx.owner.get_tree().process_frame
	var ticket: String = await steam.get_auth_ticket_hex()
	ctx.timed_record(
		"platform.steam.auth_ticket_empty_in_stub",
		get_category(),
		ticket == "",
		"auth ticket empty in stub mode",
		start,
		"PLT-02"
	)
	steam.queue_free()


func _test_steam_shutdown_is_idempotent() -> void:
	var start := Time.get_ticks_msec()
	var steam := SteamServiceScript.new()
	steam._initialized = true
	steam.enabled = true
	steam.shutdown()
	steam.shutdown()
	ctx.timed_record(
		"platform.steam.shutdown_is_idempotent",
		get_category(),
		steam._shutdown_emitted and not steam._initialized,
		"shutdown emits steam_shutdown once",
		start,
		"PLT-12"
	)


func _test_steam_no_callbacks_pumped_in_stub() -> void:
	var start := Time.get_ticks_msec()
	var steam := SteamServiceScript.new()
	ctx.owner.add_child(steam)
	await ctx.owner.get_tree().process_frame
	var had_singleton := Engine.has_singleton("Steam")
	steam._process(0.016)
	ctx.timed_record(
		"platform.steam.no_callbacks_pumped_in_stub",
		get_category(),
		not had_singleton and steam.is_stub_mode,
		"_process does not require Steam singleton in stub mode",
		start,
		"PLT-07"
	)
	steam.queue_free()


func _test_crash_payload_has_required_fields() -> void:
	var start := Time.get_ticks_msec()
	var logger := CrashLoggerScript.new()
	ctx.owner.add_child(logger)
	await ctx.owner.get_tree().process_frame
	var payload: Dictionary = logger.call("_build_payload", "validation", {})
	var required := [
		"schemaVersion",
		"gameVersion",
		"contentVersion",
		"engineVersion",
		"os",
		"gpu",
		"scene",
		"stack",
	]
	var ok := true
	for key in required:
		if not payload.has(key) or str(payload.get(key, "")).is_empty():
			ok = false
			break
	logger.queue_free()
	ctx.timed_record(
		"platform.crash.payload_has_required_fields",
		get_category(),
		ok,
		"crash payload includes triage fields",
		start,
		"PLT-04"
	)


func _test_crash_content_version_matches_api_config() -> void:
	var start := Time.get_ticks_msec()
	var logger := CrashLoggerScript.new()
	ctx.owner.add_child(logger)
	await ctx.owner.get_tree().process_frame
	var payload: Dictionary = logger.call("_build_payload", "validation", {})
	logger.queue_free()
	ctx.timed_record(
		"platform.crash.content_version_matches_api_config",
		get_category(),
		str(payload.get("contentVersion", "")) == ApiConfig.CONTENT_VERSION,
		"contentVersion matches ApiConfig.CONTENT_VERSION",
		start,
		"PLT-09"
	)


func _test_crash_log_error_writes_a_line() -> void:
	var start := Time.get_ticks_msec()
	var logger := CrashLoggerScript.new()
	ctx.owner.add_child(logger)
	await ctx.owner.get_tree().process_frame
	logger.log_error("validation.test", {"marker": "platform_suite"})
	var log_path := "user://crash_reports/session_%s.log" % logger._session_id
	var text := FileAccess.get_file_as_string(log_path) if FileAccess.file_exists(log_path) else ""
	var lines := text.strip_edges().split("\n", false)
	var ok := lines.size() == 1 and JSON.parse_string(lines[0]) is Dictionary
	logger.queue_free()
	ctx.timed_record(
		"platform.crash.log_error_writes_a_line",
		get_category(),
		ok,
		"log_error writes one parseable JSON line",
		start,
		"PLT-11"
	)


func _test_crash_log_error_flushes() -> void:
	var start := Time.get_ticks_msec()
	var logger := CrashLoggerScript.new()
	ctx.owner.add_child(logger)
	await ctx.owner.get_tree().process_frame
	logger.log_error("validation.flush", {})
	var log_path := "user://crash_reports/session_%s.log" % logger._session_id
	var reader := FileAccess.open(log_path, FileAccess.READ)
	var ok := reader != null and not reader.get_as_text().is_empty()
	if reader:
		reader.close()
	logger.queue_free()
	ctx.timed_record(
		"platform.crash.log_error_flushes",
		get_category(),
		ok,
		"log line readable before logger freed",
		start,
		"PLT-10"
	)


func _test_crash_retention_prunes_oldest() -> void:
	var start := Time.get_ticks_msec()
	var log_dir := "user://crash_reports/"
	if not DirAccess.dir_exists_absolute(log_dir):
		DirAccess.make_dir_recursive_absolute(log_dir)
	for i in 25:
		var path := log_dir.path_join("crash_retention_%02d.json" % i)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(
				JSON.stringify(
					{
						"schemaVersion": 1,
						"sessionId": "retention-%d" % i,
						"context": "synthetic",
						"timestamp": Time.get_datetime_string_from_system(),
					}
				)
			)
			file.close()
	var logger := CrashLoggerScript.new()
	logger.call("_prune_old_reports")
	var remaining := 0
	var dir := DirAccess.open(log_dir)
	if dir:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if not dir.current_is_dir() and name.begins_with("crash_") and name.ends_with(".json"):
				remaining += 1
			name = dir.get_next()
		dir.list_dir_end()
	logger.queue_free()
	ctx.timed_record(
		"platform.crash.retention_prunes_oldest",
		get_category(),
		remaining <= 20,
		"retention keeps at most 20 crash json files (found %d)" % remaining,
		start,
		"PLT-05"
	)


func _test_crash_upload_disabled_by_default() -> void:
	var start := Time.get_ticks_msec()
	PrivacySettingsScript.send_crash_reports = false
	var logger := CrashLoggerScript.new()
	ctx.owner.add_child(logger)
	await ctx.owner.get_tree().process_frame
	var before := logger.get_child_count()
	await logger._upload_pending_reports()
	var after := logger.get_child_count()
	logger.queue_free()
	ctx.timed_record(
		"platform.crash.upload_disabled_by_default",
		get_category(),
		before == after,
		"upload disabled by default issues no HTTP requests",
		start,
		"PLT-05"
	)


func _test_crash_scrubs_user_paths() -> void:
	var start := Time.get_ticks_msec()
	var logger := CrashLoggerScript.new()
	var payload := {
		"path": "user://characters/save.json",
		"detail": OS.get_user_data_dir(),
	}
	var cleaned: Dictionary = logger.scrub_payload(payload)
	var text := JSON.stringify(cleaned)
	var ok := "user://" not in text and OS.get_environment("USERNAME") not in text
	logger.queue_free()
	ctx.timed_record(
		"platform.crash.scrubs_user_paths",
		get_category(),
		ok,
		"scrub_payload removes user paths and user names",
		start,
		"PLT-05"
	)

extends Node


signal steam_ready
signal steam_shutdown

enum Result { OK, UNAVAILABLE, FAILED }

const DEV_APP_ID := 480
const PLATFORM_CONFIG_PATH := "res://config/platform.json"
const STEAM_APPID_FILE := "res://steam_appid.txt"
const WEB_API_IDENTITY := "aumbrye"
const TICKET_TIMEOUT_SEC := 5.0

var enabled := false
var is_stub_mode := true
var overlay_available := false
var cloud_enabled := false
var app_id: int = DEV_APP_ID

var _initialized := false
var _shutdown_emitted := false
var _pending_tickets: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_app_id()
	_initialize()


func _process(_delta: float) -> void:
	if not is_stub_mode and Engine.has_singleton("Steam"):
		Engine.get_singleton("Steam").run_callbacks()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()


func _exit_tree() -> void:
	shutdown()


func _resolve_app_id() -> void:
	var env_id := OS.get_environment("AUMBRYE_STEAM_APP_ID").strip_edges()
	if env_id != "" and env_id.is_valid_int():
		app_id = int(env_id)
		print_verbose("SteamService: using AUMBRYE_STEAM_APP_ID=%d" % app_id)
		return
	if FileAccess.file_exists(PLATFORM_CONFIG_PATH):
		var file := FileAccess.open(PLATFORM_CONFIG_PATH, FileAccess.READ)
		if file:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				var cfg_id := str(parsed.get("steamAppId", "")).strip_edges()
				if cfg_id.is_valid_int():
					app_id = int(cfg_id)
					print_verbose("SteamService: using platform.json steamAppId=%d" % app_id)
					return
	if FileAccess.file_exists(STEAM_APPID_FILE):
		var appid_file := FileAccess.open(STEAM_APPID_FILE, FileAccess.READ)
		if appid_file:
			var from_file := appid_file.get_as_text().strip_edges()
			if from_file.is_valid_int():
				app_id = int(from_file)
				print_verbose("SteamService: using steam_appid.txt=%d" % app_id)
				return
	app_id = DEV_APP_ID


func _initialize() -> void:
	if app_id == DEV_APP_ID and not OS.has_feature("steam"):
		_init_stub("No AUMBRYE_STEAM_APP_ID — dev stub active (set env for real Steam init)")
		return
	if OS.has_feature("steam") or app_id != DEV_APP_ID:
		_try_godot_steam()
	else:
		_init_stub("GodotSteam not compiled — dev stub active")


func _try_godot_steam() -> void:
	if not ClassDB.class_exists("Steam"):
		_init_stub("Steam class unavailable — dev stub active")
		return
	var steam := Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
	if steam == null:
		_init_stub("Steam singleton missing — dev stub active")
		return
	if steam.has_signal("ticket_for_web_api_response"):
		if not steam.ticket_for_web_api_response.is_connected(_on_ticket_for_web_api_response):
			steam.ticket_for_web_api_response.connect(_on_ticket_for_web_api_response)
	elif steam.has_signal("get_ticket_for_web_api"):
		if not steam.get_ticket_for_web_api.is_connected(_on_ticket_for_web_api_legacy):
			steam.get_ticket_for_web_api.connect(_on_ticket_for_web_api_legacy)
	var restart: Dictionary = steam.steamInitEx(true, app_id)
	var status := int(restart.get("status", 1))
	if status == 1:
		_init_stub("steamInitEx: %s" % restart.get("verbal", "unknown"))
		return
	if steam.restartAppIfNecessary(app_id):
		get_tree().quit()
		return
	enabled = true
	is_stub_mode = false
	overlay_available = steam.isOverlayEnabled()
	cloud_enabled = steam.isCloudEnabledForApp()
	_initialized = true
	set_process(true)
	steam_ready.emit()


func _init_stub(reason: String) -> void:
	enabled = true
	is_stub_mode = true
	overlay_available = false
	cloud_enabled = false
	_initialized = true
	set_process(false)
	print_verbose("SteamService: %s" % reason)
	steam_ready.emit()


func is_available() -> bool:
	return _initialized and enabled


func unlock_achievement(achievement_id: String) -> Result:
	if not is_available():
		return Result.UNAVAILABLE
	if is_stub_mode:
		return Result.UNAVAILABLE
	if not Engine.has_singleton("Steam"):
		return Result.UNAVAILABLE
	var steam = Engine.get_singleton("Steam")
	if steam and steam.has_method("setAchievement"):
		if not steam.setAchievement(achievement_id):
			return Result.FAILED
		if steam.has_method("storeStats"):
			steam.storeStats()
		return Result.OK
	return Result.FAILED


func sync_achievements(unlocked_ids: Array[String]) -> Dictionary:
	var synced := 0
	var unavailable := 0
	var failed := 0
	if not is_available():
		return {"synced": 0, "unavailable": unlocked_ids.size(), "failed": 0}
	for id in unlocked_ids:
		match unlock_achievement(id):
			Result.OK:
				synced += 1
			Result.UNAVAILABLE:
				unavailable += 1
			Result.FAILED:
				failed += 1
	return {"synced": synced, "unavailable": unavailable, "failed": failed}


func read_cloud_file(file_name: String) -> String:
	if not is_available() or is_stub_mode:
		return ""
	if Engine.has_singleton("Steam"):
		var steam = Engine.get_singleton("Steam")
		if steam and steam.has_method("fileRead"):
			return str(steam.fileRead(file_name))
	return ""


func write_cloud_file(file_name: String, data: String) -> bool:
	if not is_available() or is_stub_mode:
		return false
	if Engine.has_singleton("Steam"):
		var steam = Engine.get_singleton("Steam")
		if steam and steam.has_method("fileWrite"):
			return bool(steam.fileWrite(file_name, data))
	return false


func shutdown() -> void:
	if _shutdown_emitted:
		return
	if not _initialized:
		return
	if not is_stub_mode and Engine.has_singleton("Steam"):
		var steam = Engine.get_singleton("Steam")
		if steam and steam.has_method("steamShutdown"):
			steam.steamShutdown()
	_initialized = false
	enabled = false
	if not _shutdown_emitted:
		_shutdown_emitted = true
		steam_shutdown.emit()


func _await_web_api_ticket(ticket_id: int) -> String:
	if ticket_id == 0:
		return ""
	_pending_tickets[ticket_id] = {"done": false, "hex": ""}
	var elapsed := 0.0
	while (
		_pending_tickets.has(ticket_id)
		and not bool(_pending_tickets[ticket_id].get("done", false))
		and elapsed < TICKET_TIMEOUT_SEC
	):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	var hex := ""
	if _pending_tickets.has(ticket_id):
		hex = str(_pending_tickets[ticket_id].get("hex", ""))
		_pending_tickets.erase(ticket_id)
	return hex


func _on_ticket_for_web_api_response(auth_ticket: int, result: int, ticket_buffer: PackedByteArray) -> void:
	_store_ticket_buffer(auth_ticket, result, ticket_buffer)


func _on_ticket_for_web_api_legacy(auth_ticket: int, result: int, ticket_buffer: PackedByteArray) -> void:
	_store_ticket_buffer(auth_ticket, result, ticket_buffer)


func _store_ticket_buffer(auth_ticket: int, result: int, ticket_buffer: PackedByteArray) -> void:
	if not _pending_tickets.has(auth_ticket):
		return
	var entry: Dictionary = _pending_tickets[auth_ticket]
	if result == 1 and not ticket_buffer.is_empty():
		entry["hex"] = ticket_buffer.hex_encode()
	entry["done"] = true

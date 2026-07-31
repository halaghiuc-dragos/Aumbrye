extends Node

## STEAM-7.1–7.4 — Steamworks integration with dev stub when SDK missing.

signal steam_ready
signal steam_shutdown

const DEV_APP_ID := 480

var enabled := false
var is_stub_mode := true
var overlay_available := false
var cloud_enabled := false
var app_id: int = DEV_APP_ID

var _initialized := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_initialize()


func _initialize() -> void:
	if OS.has_feature("steam"):
		_try_godot_steam()
	else:
		_init_stub("GodotSteam not compiled — dev stub active")


func _try_godot_steam() -> void:
	# GodotSteam optional; fall back to stub when class missing.
	if not ClassDB.class_exists("Steam"):
		_init_stub("Steam class unavailable — dev stub active")
		return
	var steam := Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
	if steam == null:
		_init_stub("Steam singleton missing — dev stub active")
		return
	var restart: Variant = steam.steamInitEx(true, app_id)
	if restart.get("status", 1) != 0:
		_init_stub("steamInitEx failed: %s" % restart.get("verbal", "unknown"))
		return
	enabled = true
	is_stub_mode = false
	overlay_available = steam.isOverlayEnabled()
	cloud_enabled = steam.isCloudEnabledForApp()
	_initialized = true
	steam_ready.emit()


func _init_stub(reason: String) -> void:
	enabled = true
	is_stub_mode = true
	overlay_available = false
	cloud_enabled = false
	_initialized = true
	push_warning("SteamService: %s" % reason)
	steam_ready.emit()


func is_available() -> bool:
	return _initialized and enabled


func unlock_achievement(achievement_id: String) -> bool:
	if not is_available():
		return false
	if is_stub_mode:
		return true
	if Engine.has_singleton("Steam"):
		var steam = Engine.get_singleton("Steam")
		if steam and steam.has_method("setAchievement"):
			steam.setAchievement(achievement_id)
			steam.storeStats()
			return true
	return false


func sync_achievements(unlocked_ids: Array[String]) -> int:
	if not is_available():
		return 0
	var synced := 0
	for id in unlocked_ids:
		if unlock_achievement(id):
			synced += 1
	return synced


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


func get_auth_ticket_hex() -> String:
	# STEAM-7.4 deferred — returns empty in stub/dev mode.
	if is_stub_mode:
		return ""
	return ""


func shutdown() -> void:
	if not _initialized:
		return
	if not is_stub_mode and Engine.has_singleton("Steam"):
		var steam = Engine.get_singleton("Steam")
		if steam and steam.has_method("steamShutdown"):
			steam.steamShutdown()
	_initialized = false
	enabled = false
	steam_shutdown.emit()

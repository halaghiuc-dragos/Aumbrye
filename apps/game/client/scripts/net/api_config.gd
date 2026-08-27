extends Node


signal cloud_state_changed(state: int, detail: String)
signal version_mismatch

enum CloudState { DISABLED, SIGNED_OUT, SYNCING, SYNCED, ERROR, VERSION_MISMATCH }

const DEFAULT_BASE_URL := "https://api.aumbrye.example"
const CLIENT_VERSION := "0.4.0"
const CONTENT_VERSION := "1"
const REQUEST_TIMEOUT_SECONDS := 8.0
const SESSION_PATH := "user://session.json"
const INSTALL_KEY_PATH := "user://install_key"
const USER_API_CONFIG_PATH := "user://api_config.json"
const DEV_API_CONFIG_PATH := "res://config/dev_api.json"
const HTTP_POOL_SIZE := 2
const HTTP_ACQUIRE_TIMEOUT_SECONDS := 10.0
const HTTP_BUSY_WATCHDOG_SECONDS := REQUEST_TIMEOUT_SECONDS + 5.0

var base_url: String = ""
var access_token: String = ""
var refresh_token: String = ""
var account_id: String = ""
var session_email: String = ""
var cloud_state: CloudState = CloudState.DISABLED
var version_mismatch_flag: bool = false

var _http_pool: Array[HTTPRequest] = []
var _http_busy: Dictionary = {}
var _http_busy_since_msec: Dictionary = {}
var _active_http: Array[HTTPRequest] = []

var _test_is_debug_build: Variant = null
var _cached_install_secret := ""
var _test_env_api_url: Variant = null
var _test_user_api_config: Variant = null
var _test_dev_api_config: Variant = null
var _last_acquired_http: HTTPRequest = null


func _ready() -> void:
	_init_http_pool()
	base_url = _resolve_base_url()
	_update_cloud_state_from_config()
	_load_session_and_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		cancel_all()


func get_base_url() -> String:
	return base_url.strip_edges().trim_suffix("/")


func auth_headers() -> PackedStringArray:
	return PackedStringArray(
		[
			"Authorization: Bearer %s" % access_token,
			"X-Client-Version: %s" % CLIENT_VERSION,
			"X-Content-Version: %s" % CONTENT_VERSION,
			"Content-Type: application/json",
		]
	)


func cloud_calls_enabled() -> bool:
	return get_base_url() != "" and not version_mismatch_flag


func set_cloud_state(state: CloudState, detail: String = "") -> void:
	if cloud_state == state and detail == "":
		return
	cloud_state = state
	cloud_state_changed.emit(state, detail)


func _update_cloud_state_from_config() -> void:
	if version_mismatch_flag:
		set_cloud_state(CloudState.VERSION_MISMATCH, "Client update required")
	elif get_base_url() == "":
		set_cloud_state(CloudState.DISABLED, "")
	elif refresh_token == "" and access_token == "":
		set_cloud_state(CloudState.SIGNED_OUT, "")
	else:
		set_cloud_state(CloudState.SYNCED, session_email)


func _init_http_pool() -> void:
	for i in HTTP_POOL_SIZE:
		var http := HTTPRequest.new()
		http.name = "HttpPool_%d" % i
		add_child(http)
		_http_pool.append(http)


func acquire_http() -> HTTPRequest:
	var deadline_msec := Time.get_ticks_msec() + int(HTTP_ACQUIRE_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		_release_stalled_http()
		for http in _http_pool:
			var id := http.get_instance_id()
			if not _http_busy.has(id):
				_http_busy[id] = true
				_http_busy_since_msec[id] = Time.get_ticks_msec()
				_active_http.append(http)
				_last_acquired_http = http
				return http
		await get_tree().process_frame
	push_warning("ApiConfig: acquire_http timed out waiting for a free connection")
	return null


func release_http(http: HTTPRequest) -> void:
	if http == null:
		return
	var id := http.get_instance_id()
	_http_busy.erase(id)
	_http_busy_since_msec.erase(id)
	_active_http.erase(http)
	if _last_acquired_http == http:
		_last_acquired_http = null


func _release_stalled_http() -> void:
	var stall_deadline_msec := int(HTTP_BUSY_WATCHDOG_SECONDS * 1000.0)
	var now_msec := Time.get_ticks_msec()
	for http in _http_pool:
		var id := http.get_instance_id()
		if not _http_busy.has(id):
			continue
		var since: int = _http_busy_since_msec.get(id, now_msec)
		if now_msec - since >= stall_deadline_msec:
			push_warning("ApiConfig: force-releasing stalled HTTP connection")
			if http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
				http.cancel_request()
			release_http(http)


func cancel_all() -> void:
	for http in _http_pool:
		if http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
			http.cancel_request()
		if http.get_parent() == self:
			remove_child(http)
		http.queue_free()
	_http_pool.clear()
	_http_busy.clear()
	_http_busy_since_msec.clear()
	_active_http.clear()
	_last_acquired_http = null


func persist_session() -> void:
	if refresh_token == "":
		clear_session_file()
		return
	var data := {
		"refreshToken": refresh_token,
		"accountId": account_id,
		"email": session_email,
	}
	var file := FileAccess.open_encrypted_with_pass(SESSION_PATH, FileAccess.WRITE, _session_pass())
	if file == null:
		push_warning("ApiConfig: failed to write session file")
		return
	file.store_string(JSON.stringify(data))


func load_session() -> bool:
	if not FileAccess.file_exists(SESSION_PATH):
		return false
	var file := FileAccess.open_encrypted_with_pass(SESSION_PATH, FileAccess.READ, _session_pass())
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false
	var data: Dictionary = parsed
	refresh_token = str(data.get("refreshToken", ""))
	account_id = str(data.get("accountId", ""))
	session_email = str(data.get("email", ""))
	access_token = ""
	return refresh_token != ""


func clear_session() -> void:
	access_token = ""
	refresh_token = ""
	account_id = ""
	session_email = ""
	clear_session_file()
	_update_cloud_state_from_config()


func clear_session_file() -> void:
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(SESSION_PATH)


func mark_version_mismatch(detail: String = "Client update required") -> void:
	version_mismatch_flag = true
	set_cloud_state(CloudState.VERSION_MISMATCH, detail)
	version_mismatch.emit()


func _load_session_and_refresh() -> void:
	if not cloud_calls_enabled():
		return
	if not load_session():
		return
	if refresh_token == "":
		return
	_refresh_session_background()


func _refresh_session_background() -> void:
	set_cloud_state(CloudState.SYNCING, session_email)
	var ok: bool = await ApiClient.refresh_session()
	if ok:
		set_cloud_state(CloudState.SYNCED, session_email)
	else:
		clear_session()
		set_cloud_state(CloudState.SIGNED_OUT, "")


func _resolve_base_url() -> String:
	var resolved := ""
	if _test_env_api_url != null:
		resolved = str(_test_env_api_url).strip_edges()
	elif OS.has_environment("AUMBRYE_API_URL"):
		resolved = OS.get_environment("AUMBRYE_API_URL").strip_edges()
	elif _test_user_api_config != null:
		if _test_user_api_config is Dictionary:
			resolved = str(_test_user_api_config.get("apiBaseUrl", "")).strip_edges()
	elif FileAccess.file_exists(USER_API_CONFIG_PATH):
		var user_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(USER_API_CONFIG_PATH))
		if user_parsed is Dictionary:
			resolved = str(user_parsed.get("apiBaseUrl", "")).strip_edges()
	if resolved == "":
		var dev_cfg: Dictionary
		if _test_dev_api_config != null and _test_dev_api_config is Dictionary:
			dev_cfg = _test_dev_api_config
		else:
			dev_cfg = ContentLoader.load_json(DEV_API_CONFIG_PATH)
		resolved = str(dev_cfg.get("apiBaseUrl", "")).strip_edges()
	if resolved == "":
		resolved = DEFAULT_BASE_URL
	resolved = resolved.strip_edges().trim_suffix("/")
	if _is_release_build() and not resolved.begins_with("https://"):
		push_error("ApiConfig: refusing non-HTTPS base URL in a release build")
		return ""
	return resolved


func _session_pass() -> String:
	var secret := _install_secret()
	var machine := OS.get_unique_id()
	if secret == "" and machine == "":
		push_warning("ApiConfig: no install secret or machine id; session file is weakly protected")
		return "aumbrye-session-fallback"
	return secret + ":" + machine


func _install_secret() -> String:
	if _cached_install_secret != "":
		return _cached_install_secret

	if FileAccess.file_exists(INSTALL_KEY_PATH):
		var reader := FileAccess.open(INSTALL_KEY_PATH, FileAccess.READ)
		if reader != null:
			var stored := reader.get_as_text().strip_edges()
			if stored != "":
				_cached_install_secret = stored
				return _cached_install_secret

	var crypto := Crypto.new()
	var generated := crypto.generate_random_bytes(32).hex_encode()
	var writer := FileAccess.open(INSTALL_KEY_PATH, FileAccess.WRITE)
	if writer == null:
		push_warning("ApiConfig: could not persist install key; falling back to machine id only")
		return ""
	writer.store_string(generated)
	writer.close()
	_cached_install_secret = generated
	return _cached_install_secret


func _is_release_build() -> bool:
	if _test_is_debug_build != null:
		return not bool(_test_is_debug_build)
	return not OS.is_debug_build()

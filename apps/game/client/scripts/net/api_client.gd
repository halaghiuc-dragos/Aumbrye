extends RefCounted
class_name ApiClient

## HTTP client for auth, runs, saves, and leaderboards.

const AUTH_REGISTER := "/api/v1/auth/register"
const AUTH_LOGIN := "/api/v1/auth/login"
const AUTH_STEAM := "/api/v1/auth/steam"
const AUTH_REFRESH := "/api/v1/auth/refresh"
const AUTH_LOGOUT := "/api/v1/auth/logout"
const RUNS_CREATE := "/api/v1/runs"
const RUNS_DUNGEON := "/api/v1/runs/%s/dungeon"
const RUNS_COMPLETE := "/api/v1/runs/%s/complete"
const SAVES_CURRENT := "/api/v1/saves/current"
const LEADERBOARDS := "/api/v1/leaderboards"
const LEADERBOARDS_SUBMIT := "/api/v1/leaderboards/submit"

const MAX_ATTEMPTS := 3
const RETRY_BASE_DELAY := 0.4

static var _transport_override: Callable = Callable()


static func set_transport_override(handler: Callable) -> void:
	_transport_override = handler


static func clear_transport_override() -> void:
	_transport_override = Callable()


static func register(email: String, password: String) -> Dictionary:
	var result := await _request_json(
		_build_url(AUTH_REGISTER), HTTPClient.METHOD_POST, {"email": email, "password": password}, false
	)
	if result.get("ok", false):
		_store_tokens(result.get("body", {}), email)
	return result


static func login(email: String, password: String) -> Dictionary:
	var result := await _request_json(
		_build_url(AUTH_LOGIN), HTTPClient.METHOD_POST, {"email": email, "password": password}, false
	)
	if result.get("ok", false):
		_store_tokens(result.get("body", {}), email)
	return result


static func login_steam(ticket_hex: String, app_id: int) -> Dictionary:
	var result := await _request_json(
		_build_url(AUTH_STEAM),
		HTTPClient.METHOD_POST,
		{"ticketHex": ticket_hex, "appId": app_id},
		false
	)
	if result.get("ok", false):
		_store_tokens(result.get("body", {}), "Steam")
	return result


static func upload_crash_report(payload: Dictionary) -> Dictionary:
	return await _request_json(
		_build_url("/api/v1/telemetry/crash"), HTTPClient.METHOD_POST, payload, access_token_optional()
	)


static func access_token_optional() -> bool:
	return ApiConfig.access_token != ""


static func logout() -> void:
	if ApiConfig.refresh_token != "" and ApiConfig.cloud_calls_enabled():
		await _request_json(
			_build_url(AUTH_LOGOUT),
			HTTPClient.METHOD_POST,
			{"refreshToken": ApiConfig.refresh_token},
			true
		)
	ApiConfig.clear_session()
	ApiConfig.set_cloud_state(ApiConfig.CloudState.SIGNED_OUT, "")


static func refresh_session() -> bool:
	if ApiConfig.refresh_token == "":
		return false
	var result := await _request_json(
		_build_url(AUTH_REFRESH),
		HTTPClient.METHOD_POST,
		{"refreshToken": ApiConfig.refresh_token},
		false
	)
	if result.get("ok", false):
		_store_tokens(result.get("body", {}))
		return true
	ApiConfig.clear_session()
	return false


static func require_session() -> bool:
	if not ApiConfig.cloud_calls_enabled():
		return false
	if ApiConfig.access_token != "":
		return true
	if ApiConfig.refresh_token != "":
		return await refresh_session()
	if (
		OS.is_debug_build()
		and OS.has_environment("AUMBRYE_DEV_EMAIL")
		and OS.has_environment("AUMBRYE_DEV_PASSWORD")
	):
		var login_result := await login(
			OS.get_environment("AUMBRYE_DEV_EMAIL"), OS.get_environment("AUMBRYE_DEV_PASSWORD")
		)
		return login_result.get("ok", false)
	return false


static func create_run(biome_id: String, run_seed: Variant = null, tier: int = 1) -> Dictionary:
	# Creating a run is not idempotent — a retried POST that actually succeeded server-side would
	# leave an orphan Active run behind, so this one never replays.
	return await _authed_json(
		RUNS_CREATE,
		HTTPClient.METHOD_POST,
		_run_create_payload(biome_id, run_seed, tier),
		false
	)


static func get_dungeon(run_id: String) -> Dictionary:
	var path := RUNS_DUNGEON % run_id
	return await _authed_json(path, HTTPClient.METHOD_GET, {})


static func complete_run(
	run_id: String,
	outcome: String,
	elapsed: float,
	boss_defeated: bool,
	loot_claimed_ids: Array = [],
	floor: int = 1
) -> Dictionary:
	var payload := {
		"outcome": outcome,
		"elapsedSeconds": elapsed,
		"bossDefeated": boss_defeated,
		"lootClaimedInstanceIds": loot_claimed_ids,
		# The server validates loot claims against the floors this run generated and needs to know
		# which floor the run ended on. Omitting it made every multi-floor completion validate as
		# floor 1 and reject legitimate claims from floors 2+.
		"floor": maxi(1, floor),
	}
	# Safe to replay: the server claims the run with a guarded status flip and replays the cached
	# result for a repeat call, so a retry after a timeout cannot double-grant progression.
	return await _authed_json(RUNS_COMPLETE % run_id, HTTPClient.METHOD_POST, payload, true)


static func get_save() -> Dictionary:
	var result := await _authed_json(SAVES_CURRENT, HTTPClient.METHOD_GET, {})
	if result.get("ok", false):
		var body: Dictionary = result.get("body", {})
		return {
			"ok": true,
			"stateJson": body.get("stateJson", ""),
			"updatedAt": body.get("updatedAt", ""),
		}
	return result


static func put_save(state_json: String, client_updated_at: Variant = null) -> Dictionary:
	var payload := {"stateJson": state_json}
	if client_updated_at != null and str(client_updated_at) != "":
		payload["clientUpdatedAt"] = str(client_updated_at)
	var result := await _authed_json(SAVES_CURRENT, HTTPClient.METHOD_PUT, payload)
	if result.get("code", 0) == 409:
		var body: Dictionary = result.get("body", {})
		return {
			"ok": false,
			"conflict": true,
			"stateJson": body.get("serverStateJson", body.get("state", "")),
			"updatedAt": str(body.get("updatedAt", "")),
			"error": _error_message(body, "conflict"),
		}
	if result.get("ok", false):
		var ok_body: Dictionary = result.get("body", {})
		return {"ok": true, "updatedAt": ok_body.get("updatedAt", "")}
	return result


static func submit_leaderboard(run_id: String, opt_in: bool) -> Dictionary:
	if not opt_in:
		return {"ok": true, "submitted": false, "reason": "opt_out"}
	if not await require_session():
		return {"ok": false, "error": "not signed in"}
	var payload := {
		"runId": run_id,
		"optIn": true,
	}
	return await _authed_json(LEADERBOARDS_SUBMIT, HTTPClient.METHOD_POST, payload)


## GET /leaderboards is public server-side, so viewing boards deliberately does NOT require a
## session — signed-out players can still browse them from the menus.
static func fetch_leaderboard(biome_id: String, tier: int, limit: int = 10) -> Dictionary:
	var url := (
		_build_url(LEADERBOARDS)
		# Encoded so a biome id containing '&' or a space cannot corrupt the query string.
		+ "?biomeId=%s&tier=%d&limit=%d" % [biome_id.uri_encode(), tier, limit]
	)
	var result := await _request_json(url, HTTPClient.METHOD_GET, {}, false)
	if result.get("ok", false):
		return {"ok": true, "body": result.get("body", {})}
	return result


static func _run_create_payload(biome_id: String, run_seed: Variant, tier: int) -> Dictionary:
	var payload := {"biomeId": biome_id, "tier": maxi(1, tier)}
	if run_seed != null:
		payload["seed"] = int(run_seed)
	return payload


static func _authed_json(
	path: String, method: int, payload: Dictionary, allow_retry: bool = true
) -> Dictionary:
	if not await require_session():
		return {"ok": false, "error": "not signed in"}
	ApiConfig.set_cloud_state(ApiConfig.CloudState.SYNCING, ApiConfig.session_email)
	var url := _build_url(path) if path.begins_with("/") else path
	var result := await _request_json(url, method, payload, true, allow_retry)
	if not result.get("ok", false) and result.get("code", 0) == 401:
		if await refresh_session():
			result = await _request_json(url, method, payload, true, allow_retry)
	if result.get("ok", false):
		ApiConfig.set_cloud_state(ApiConfig.CloudState.SYNCED, ApiConfig.session_email)
	elif ApiConfig.cloud_state != ApiConfig.CloudState.VERSION_MISMATCH:
		ApiConfig.set_cloud_state(
			ApiConfig.CloudState.ERROR, str(result.get("error", "cloud request failed"))
		)
	return result


static func _build_url(path: String) -> String:
	return ApiConfig.get_base_url() + path


## Whether a method is safe to replay after a timeout or 5xx.
##
## A POST that times out may well have been applied server-side already, so blind retries can
## double-create runs or double-complete them. GET/PUT/DELETE are idempotent by contract, so they
## always retry; POST only retries when the caller opts in (because the endpoint honours an
## idempotency key, or because the operation is genuinely repeatable).
static func _is_idempotent(method: int) -> bool:
	return method != HTTPClient.METHOD_POST


static func _request_json(
	url: String, method: int, payload: Dictionary, auth: bool, allow_retry: bool = true
) -> Dictionary:
	if not ApiConfig.cloud_calls_enabled() and url.begins_with(ApiConfig.get_base_url()):
		return {"ok": false, "error": "cloud disabled", "code": 0}
	var retryable := allow_retry and _is_idempotent(method)
	var attempts := MAX_ATTEMPTS if retryable else 1
	for attempt in attempts:
		var result := await _request_once(url, method, payload, auth)
		var code: int = int(result.get("code", 0))
		if result.get("ok", false):
			return result
		if code == 426:
			ApiConfig.mark_version_mismatch(str(result.get("error", "Client update required")))
			return result
		if code == 429 or code >= 500 or code == 0:
			if attempt < attempts - 1:
				await _sleep(_backoff_delay(attempt, float(result.get("retry_after", 0.0))))
				continue
		return result
	return {"ok": false, "error": "unreachable", "code": 0}


static func _request_once(url: String, method: int, payload: Dictionary, auth: bool) -> Dictionary:
	if _transport_override.is_valid():
		return await _transport_override.call(url, method, payload, auth)
	if not ApiConfig.cloud_calls_enabled():
		return {"ok": false, "error": "cloud disabled", "code": 0}

	var headers: PackedStringArray
	if auth:
		headers = ApiConfig.auth_headers()
	else:
		headers = PackedStringArray(
			[
				"X-Client-Version: %s" % ApiConfig.CLIENT_VERSION,
				"X-Content-Version: %s" % ApiConfig.CONTENT_VERSION,
				"Content-Type: application/json",
			]
		)

	var http: HTTPRequest = await ApiConfig.acquire_http()
	if http == null:
		return {"ok": false, "error": "connection pool exhausted", "code": 0}
	http.timeout = ApiConfig.REQUEST_TIMEOUT_SECONDS
	var body := ""
	if method != HTTPClient.METHOD_GET:
		body = JSON.stringify(payload)
	var err := http.request(url, headers, method, body)
	if err != OK:
		ApiConfig.release_http(http)
		if CrashLogger:
			CrashLogger.log_warning("api_client.request_failed", {"url": url, "error": err})
		return {"ok": false, "error": "request failed", "code": 0}
	var response = await http.request_completed
	ApiConfig.release_http(http)
	return _parse_response(response, method)


static func _parse_response(response: Array, method: int) -> Dictionary:
	var code: int = int(response[1])
	var response_headers: PackedStringArray = response[2]
	var body_text: String = response[3].get_string_from_utf8()
	var dict := _parse_body(body_text)
	if code < 200 or code >= 300:
		var err_msg: String = _error_message(dict, "HTTP %d" % code)
		if CrashLogger and code >= 500:
			CrashLogger.log_warning("api_client.http_error", {"code": code, "error": err_msg})
		return {
			"ok": false,
			"error": err_msg,
			"code": code,
			"body": dict,
			"retry_after": _parse_retry_after(response_headers),
		}
	return {"ok": true, "body": dict, "code": code}


static func _error_message(body: Dictionary, fallback: String) -> String:
	if body.has("detail"):
		return str(body.get("detail"))
	if body.has("error"):
		return str(body.get("error"))
	if body.has("title"):
		return str(body.get("title"))
	if body.has("raw"):
		return str(body.get("raw"))
	return fallback


static func _parse_body(body_text: String) -> Dictionary:
	var trimmed := body_text.strip_edges()
	if trimmed.begins_with("{") or trimmed.begins_with("["):
		var parsed: Variant = JSON.parse_string(trimmed)
		if parsed is Dictionary:
			return parsed
		if parsed != null:
			return {"raw": str(parsed)}
	return {"raw": trimmed.substr(0, min(200, trimmed.length()))}


static func _parse_retry_after(headers: PackedStringArray) -> float:
	for header in headers:
		if header.to_lower().begins_with("retry-after:"):
			var value := header.split(":", false, 1)[1].strip_edges()
			if value.is_valid_float():
				return float(value)
	return 0.0


static func _backoff_delay(attempt: int, retry_after: float) -> float:
	if retry_after > 0.0:
		return retry_after
	var base := RETRY_BASE_DELAY * pow(2.0, attempt)
	var jitter := randf_range(-0.25, 0.25) * base
	return maxf(0.05, base + jitter)


static func _sleep(seconds: float) -> void:
	if seconds <= 0.0:
		await Engine.get_main_loop().process_frame
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		await Engine.get_main_loop().process_frame
		return
	await tree.create_timer(seconds).timeout


static func _store_tokens(body: Dictionary, email: String = "") -> void:
	var tokens: Dictionary = body.get("tokens", {})
	ApiConfig.access_token = str(tokens.get("accessToken", ""))
	ApiConfig.refresh_token = str(tokens.get("refreshToken", ""))
	var user: Dictionary = body.get("user", {})
	if user.has("id"):
		ApiConfig.account_id = str(user.get("id", ""))
	if email != "":
		ApiConfig.session_email = email
	elif user.has("email"):
		ApiConfig.session_email = str(user.get("email", ""))
	ApiConfig.persist_session()
	ApiConfig.set_cloud_state(ApiConfig.CloudState.SYNCED, ApiConfig.session_email)

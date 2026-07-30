extends RefCounted
class_name ApiClient

## HTTP client for auth + runs (NET-3.1).

const AUTH_REGISTER := "/api/v1/auth/register"
const AUTH_LOGIN := "/api/v1/auth/login"
const AUTH_REFRESH := "/api/v1/auth/refresh"
const RUNS_CREATE := "/api/v1/runs"
const RUNS_DUNGEON := "/api/v1/runs/%s/dungeon"
const RUNS_COMPLETE := "/api/v1/runs/%s/complete"
const SAVES_CURRENT := "/api/v1/saves/current"


static func register(email: String, password: String) -> Dictionary:
	return await _post_json(AUTH_REGISTER, {"email": email, "password": password}, false)


static func login(email: String, password: String) -> Dictionary:
	var result := await _post_json(AUTH_LOGIN, {"email": email, "password": password}, false)
	if result.get("ok", false):
		_store_tokens(result.get("body", {}))
	return result


static func refresh_session() -> bool:
	if ApiConfig.refresh_token == "":
		return false
	var result := await _post_json(AUTH_REFRESH, {"refreshToken": ApiConfig.refresh_token}, false)
	if result.get("ok", false):
		_store_tokens(result.get("body", {}))
		return true
	ApiConfig.access_token = ""
	return false


static func ensure_dev_session() -> bool:
	if ApiConfig.access_token != "":
		return true
	var email := "dev_%s@test.local" % OS.get_unique_id().substr(0, 8)
	var password := "devpassword123"
	var reg := await register(email, password)
	if reg.get("ok", false):
		_store_tokens(reg.get("body", {}))
		return true
	var login_result := await login(email, password)
	return login_result.get("ok", false)


static func create_run(biome_id: String, run_seed: Variant = null) -> Dictionary:
	if not await ensure_dev_session():
		return {"ok": false, "error": "auth failed"}
	var payload := {"biomeId": biome_id, "tier": 1}
	if run_seed != null:
		payload["seed"] = int(run_seed)
	var result := await _post_json_with_retry(RUNS_CREATE, payload)
	if not result.get("ok", false) and result.get("code", 0) == 401:
		if await refresh_session():
			result = await _post_json_with_retry(RUNS_CREATE, payload)
	return result


static func get_dungeon(run_id: String) -> Dictionary:
	if ApiConfig.access_token == "":
		return {"ok": false, "error": "not authenticated"}
	var url := ApiConfig.get_base_url() + (RUNS_DUNGEON % run_id)
	var result := await _request_json(url, HTTPClient.METHOD_GET, {}, true)
	if not result.get("ok", false) and result.get("code", 0) == 401:
		if await refresh_session():
			result = await _request_json(url, HTTPClient.METHOD_GET, {}, true)
	return result


static func complete_run(
	run_id: String,
	outcome: String,
	elapsed: float,
	boss_defeated: bool,
	loot_claimed_ids: Array = []
) -> Dictionary:
	if not await ensure_dev_session():
		return {"ok": false, "error": "auth failed"}
	var payload := {
		"outcome": outcome,
		"elapsedSeconds": elapsed,
		"bossDefeated": boss_defeated,
		"lootClaimedInstanceIds": loot_claimed_ids,
	}
	var path := RUNS_COMPLETE % run_id
	var result := await _post_json_with_retry(path, payload)
	if not result.get("ok", false) and result.get("code", 0) == 401:
		if await refresh_session():
			result = await _post_json_with_retry(path, payload)
	return result


static func get_save() -> Dictionary:
	if not await ensure_dev_session():
		return {"ok": false, "error": "auth failed"}
	var url := ApiConfig.get_base_url() + SAVES_CURRENT
	var result := await _request_json(url, HTTPClient.METHOD_GET, {}, true)
	if not result.get("ok", false) and result.get("code", 0) == 401:
		if await refresh_session():
			result = await _request_json(url, HTTPClient.METHOD_GET, {}, true)
	if result.get("ok", false):
		var body: Dictionary = result.get("body", {})
		return {
			"ok": true,
			"stateJson": body.get("stateJson", ""),
			"updatedAt": body.get("updatedAt", ""),
		}
	return result


static func put_save(state_json: String, client_updated_at: Variant = null) -> Dictionary:
	if not await ensure_dev_session():
		return {"ok": false, "error": "auth failed"}
	var payload := {"stateJson": state_json}
	if client_updated_at != null and str(client_updated_at) != "":
		payload["clientUpdatedAt"] = str(client_updated_at)
	var url := ApiConfig.get_base_url() + SAVES_CURRENT
	var result := await _request_json(url, HTTPClient.METHOD_PUT, payload, true)
	if not result.get("ok", false) and result.get("code", 0) == 401:
		if await refresh_session():
			result = await _request_json(url, HTTPClient.METHOD_PUT, payload, true)
	if result.get("code", 0) == 409:
		var body: Dictionary = result.get("body", {})
		return {
			"ok": false,
			"conflict": true,
			"stateJson": body.get("state", ""),
			"updatedAt": str(body.get("updatedAt", "")),
			"error": body.get("error", "conflict"),
		}
	if result.get("ok", false):
		var body: Dictionary = result.get("body", {})
		return {"ok": true, "updatedAt": body.get("updatedAt", "")}
	return result


static func _post_json_with_retry(path: String, payload: Dictionary) -> Dictionary:
	return await _request_json(ApiConfig.get_base_url() + path, HTTPClient.METHOD_POST, payload, true)


static func _post_json(path: String, payload: Dictionary, auth: bool) -> Dictionary:
	return await _request_json(ApiConfig.get_base_url() + path, HTTPClient.METHOD_POST, payload, auth)


static func _request_json(url: String, method: int, payload: Dictionary, auth: bool) -> Dictionary:
	var headers: PackedStringArray
	if auth:
		headers = ApiConfig.auth_headers()
	else:
		headers = PackedStringArray([
			"X-Client-Version: %s" % ApiConfig.CLIENT_VERSION,
			"X-Content-Version: %s" % ApiConfig.CONTENT_VERSION,
			"Content-Type: application/json",
		])
	var http := HTTPRequest.new()
	Engine.get_main_loop().root.add_child(http)
	var body := ""
	if method != HTTPClient.METHOD_GET:
		body = JSON.stringify(payload)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "request failed"}
	var response = await http.request_completed
	http.queue_free()
	var code: int = response[1]
	var body_text: String = response[3].get_string_from_utf8()
	var dict: Dictionary = {}
	var trimmed := body_text.strip_edges()
	if trimmed.begins_with("{") or trimmed.begins_with("["):
		var parsed: Variant = JSON.parse_string(trimmed)
		if parsed is Dictionary:
			dict = parsed
		elif parsed != null:
			dict = {"raw": str(parsed)}
		else:
			dict = {"raw": trimmed.substr(0, min(200, trimmed.length()))}
	else:
		dict = {"raw": trimmed.substr(0, min(200, trimmed.length()))}
	if code < 200 or code >= 300:
		var err_msg: String = str(dict.get("error", dict.get("raw", "HTTP %d" % code)))
		return {"ok": false, "error": err_msg, "code": code, "body": dict}
	if method == HTTPClient.METHOD_GET:
		return {"ok": true, "definition": dict}
	return {"ok": true, "body": dict}


static func _store_tokens(body: Dictionary) -> void:
	var tokens: Dictionary = body.get("tokens", {})
	ApiConfig.access_token = tokens.get("accessToken", "")
	ApiConfig.refresh_token = tokens.get("refreshToken", "")

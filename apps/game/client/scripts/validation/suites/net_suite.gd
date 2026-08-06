extends "res://scripts/validation/validation_suite.gd"

const ApiVersionsPath := "packages/shared/Contracts/ApiVersions.cs"


class NetHttpStub:
	var responses: Array = []
	var attempts: int = 0
	var requests: Array = []

	func reset() -> void:
		responses.clear()
		attempts = 0
		requests.clear()

	func push_response(response: Dictionary) -> void:
		responses.append(response)

	func handle(_url: String, _method: int, payload: Dictionary, auth: bool) -> Dictionary:
		attempts += 1
		requests.append({"payload": payload.duplicate(true), "auth": auth})
		if responses.is_empty():
			return {"ok": false, "error": "no stub response", "code": 0}
		var idx := mini(attempts - 1, responses.size() - 1)
		return responses[idx].duplicate(true)


var _stub := NetHttpStub.new()
var _saved_base_url := ""
var _saved_access := ""
var _saved_refresh := ""
var _saved_email := ""
var _saved_account := ""
var _saved_version_mismatch := false
var _saved_cloud_state: int = ApiConfig.CloudState.DISABLED


func get_category() -> String:
	return "net"


func _init(context) -> void:
	super._init(context)
	manage_save_file = false


func run() -> void:
	_snapshot_api_state()
	_test_version_constants()
	await _test_base_url_priority()
	_test_rejects_http_in_release()
	await _test_transport_suite()
	await _test_auth_suite()
	await _test_save_suite()
	await _test_offline_suite()
	_test_leaderboard_tier_source()
	_restore_api_state()


func _snapshot_api_state() -> void:
	if not is_instance_valid(ApiConfig):
		return
	_saved_base_url = ApiConfig.base_url
	_saved_access = ApiConfig.access_token
	_saved_refresh = ApiConfig.refresh_token
	_saved_email = ApiConfig.session_email
	_saved_account = ApiConfig.account_id
	_saved_version_mismatch = ApiConfig.version_mismatch_flag
	_saved_cloud_state = ApiConfig.cloud_state
	ApiConfig.reset_test_overrides()
	ApiClient.clear_transport_override()
	_stub.reset()


func _restore_api_state() -> void:
	if not is_instance_valid(ApiConfig):
		return
	ApiClient.clear_transport_override()
	ApiConfig.reset_test_overrides()
	ApiConfig.clear_session_file()
	ApiConfig.base_url = _saved_base_url
	ApiConfig.access_token = _saved_access
	ApiConfig.refresh_token = _saved_refresh
	ApiConfig.session_email = _saved_email
	ApiConfig.account_id = _saved_account
	ApiConfig.version_mismatch_flag = _saved_version_mismatch
	ApiConfig.cloud_state = _saved_cloud_state
	if ApiConfig._http_pool.is_empty():
		ApiConfig._init_http_pool()


func _bind_stub() -> void:
	ApiClient.set_transport_override(Callable(_stub, "handle"))


func _test_version_constants() -> void:
	var path: String = ctx.repo_root().path_join(ApiVersionsPath)
	var text := ""
	if FileAccess.file_exists(path):
		text = FileAccess.get_file_as_string(path)
	var client_match := _extract_cs_const(text, "ExpectedClientVersion")
	var content_match := _extract_cs_const(text, "ExpectedContentVersion")
	check_eq(
		"net.config.version_constants_match_shared.client",
		ApiConfig.CLIENT_VERSION,
		client_match,
		"ApiConfig.CLIENT_VERSION matches shared contract",
		"NET-12"
	)
	check_eq(
		"net.config.version_constants_match_shared.content",
		ApiConfig.CONTENT_VERSION,
		content_match,
		"ApiConfig.CONTENT_VERSION matches shared contract",
		"NET-12"
	)


func _extract_cs_const(text: String, const_name: String) -> String:
	var needle := 'public const string %s = "' % const_name
	var start := text.find(needle)
	if start < 0:
		return ""
	start += needle.length()
	var end := text.find('"', start)
	if end < 0:
		return ""
	return text.substr(start, end - start)


func _test_base_url_priority() -> void:
	ApiConfig._test_dev_api_config = {"apiBaseUrl": "https://dev.example"}
	ApiConfig._test_user_api_config = {"apiBaseUrl": "https://user.example"}
	ApiConfig._test_env_api_url = "https://env.example"
	ApiConfig.apply_test_base_url_resolution()
	check_eq(
		"net.config.base_url_priority",
		ApiConfig.get_base_url(),
		"https://env.example",
		"environment beats user and dev config",
		"NET-06"
	)

	ApiConfig._test_env_api_url = null
	ApiConfig.apply_test_base_url_resolution()
	check_eq(
		"net.config.base_url_priority.user",
		ApiConfig.get_base_url(),
		"https://user.example",
		"user config beats dev config",
		"NET-06"
	)

	ApiConfig._test_user_api_config = null
	ApiConfig.apply_test_base_url_resolution()
	check_eq(
		"net.config.base_url_priority.dev",
		ApiConfig.get_base_url(),
		"https://dev.example",
		"dev config beats default",
		"NET-06"
	)

	ApiConfig._test_dev_api_config = null
	ApiConfig.apply_test_base_url_resolution()
	check_eq(
		"net.config.base_url_priority.default",
		ApiConfig.get_base_url(),
		ApiConfig.DEFAULT_BASE_URL,
		"default base URL is the final fallback",
		"NET-06"
	)


func _test_rejects_http_in_release() -> void:
	ApiConfig._test_is_debug_build = false
	ApiConfig._test_env_api_url = "http://insecure.example"
	ApiConfig.apply_test_base_url_resolution()
	check_eq(
		"net.config.rejects_http_in_release",
		ApiConfig.get_base_url(),
		"",
		"release builds reject non-HTTPS base URLs",
		"NET-04"
	)
	ApiConfig._test_is_debug_build = true


func _test_transport_suite() -> void:
	ApiConfig.base_url = "https://stub.example"
	ApiConfig.version_mismatch_flag = false
	_bind_stub()

	_stub.push_response({"ok": true, "body": {"stateJson": "{}"}, "code": 200})
	var get_result := await ApiClient._request_json(
		ApiConfig.get_base_url() + ApiClient.SAVES_CURRENT, HTTPClient.METHOD_GET, {}, true
	)
	check(
		"net.transport.get_returns_body_key",
		get_result.get("ok", false) and get_result.has("body"),
		"GET responses use body key",
		"NET-01"
	)

	if ApiConfig._http_pool.is_empty():
		ApiConfig._init_http_pool()
	var http: HTTPRequest = await ApiConfig.acquire_http()
	http.timeout = ApiConfig.REQUEST_TIMEOUT_SECONDS
	var captured_timeout := http.timeout
	ApiConfig.release_http(http)
	check_eq(
		"net.transport.timeout_is_set",
		captured_timeout,
		ApiConfig.REQUEST_TIMEOUT_SECONDS,
		"HTTPRequest timeout is 8 seconds",
		"NET-03"
	)

	_stub.reset()
	_bind_stub()
	_stub.push_response({"ok": false, "error": "rate limited", "code": 429, "retry_after": 0.0})
	_stub.push_response({"ok": false, "error": "rate limited", "code": 429, "retry_after": 0.0})
	_stub.push_response({"ok": true, "body": {"ok": true}, "code": 200})
	var retry_result := await ApiClient._request_json(
		ApiConfig.get_base_url() + "/retry", HTTPClient.METHOD_GET, {}, false
	)
	check(
		"net.transport.retries_on_429_then_succeeds",
		retry_result.get("ok", false) and _stub.attempts == 3,
		"429 responses retry until success",
		"NET-08"
	)

	_stub.reset()
	_bind_stub()
	_stub.push_response({"ok": false, "error": "bad request", "code": 400})
	await ApiClient._request_json(
		ApiConfig.get_base_url() + "/bad", HTTPClient.METHOD_POST, {}, false
	)
	check_eq(
		"net.transport.does_not_retry_on_400",
		_stub.attempts,
		1,
		"400 responses are not retried",
		"NET-08"
	)

	_stub.reset()
	_bind_stub()
	ApiConfig.version_mismatch_flag = false
	ApiConfig.cloud_state = ApiConfig.CloudState.SIGNED_OUT
	_stub.push_response({"ok": false, "error": "upgrade required", "code": 426})
	await ApiClient._request_json(
		ApiConfig.get_base_url() + "/version", HTTPClient.METHOD_GET, {}, false
	)
	check(
		"net.transport.426_sets_version_mismatch",
		ApiConfig.cloud_state == ApiConfig.CloudState.VERSION_MISMATCH and _stub.attempts == 1,
		"426 sets VERSION_MISMATCH without retry",
		"NET-13"
	)

	if ApiConfig._http_pool.is_empty():
		ApiConfig._init_http_pool()
	var pool_count := ApiConfig._http_pool.size()
	check("net.transport.http_pool_initialized", pool_count > 0, "http pool initialized", "NET-14")
	ApiConfig.cancel_all()
	var remaining := 0
	for child in ApiConfig.get_children():
		if child is HTTPRequest:
			remaining += 1
	check(
		"net.transport.cancel_all_frees_nodes",
		remaining == 0,
		"cancel_all removes pooled HTTPRequest nodes",
		"NET-15"
	)
	ApiConfig._init_http_pool()


func _test_auth_suite() -> void:
	ApiConfig.base_url = "https://stub.example"
	ApiConfig.version_mismatch_flag = false
	ApiConfig.clear_session()
	_bind_stub()

	var signed_in := await ApiClient.require_session()
	check(
		"net.auth.require_session_without_credentials_returns_false",
		not signed_in and _stub.attempts == 0,
		"require_session does not hit the network without credentials",
		"NET-02"
	)

	check(
		"net.auth.no_hardcoded_password",
		not ctx.file_contains("res://scripts/net/api_client.gd", "devpassword"),
		"api_client.gd contains no devpassword substring",
		"NET-18"
	)

	ApiConfig.refresh_token = "dead-token"
	ApiConfig.access_token = "old-access"
	ApiConfig.session_email = "dead@example.com"
	ApiConfig.persist_session()
	_stub.reset()
	_bind_stub()
	_stub.push_response({"ok": false, "error": "invalid refresh", "code": 401})
	var refreshed := await ApiClient.refresh_session()
	check(
		"net.auth.failed_refresh_clears_both_tokens",
		not refreshed
		and ApiConfig.access_token == ""
		and ApiConfig.refresh_token == ""
		and not FileAccess.file_exists(ApiConfig.SESSION_PATH),
		"failed refresh clears tokens and session file",
		"NET-09"
	)

	ApiConfig.refresh_token = "persist-me"
	ApiConfig.account_id = "account-123"
	ApiConfig.session_email = "persist@example.com"
	ApiConfig.access_token = ""
	ApiConfig.persist_session()
	ApiConfig.refresh_token = ""
	ApiConfig.account_id = ""
	ApiConfig.session_email = ""
	var loaded := ApiConfig.load_session()
	check(
		"net.auth.session_round_trip",
		loaded
		and ApiConfig.refresh_token == "persist-me"
		and ApiConfig.account_id == "account-123"
		and ApiConfig.session_email == "persist@example.com",
		"encrypted session file round-trips refresh metadata",
		"NET-07"
	)


func _test_save_suite() -> void:
	ApiConfig.base_url = "https://stub.example"
	ApiConfig.version_mismatch_flag = false
	ApiConfig.access_token = "token"
	ApiConfig.refresh_token = "refresh"
	_stub.reset()
	_bind_stub()

	var state := {"schemaVersion": 6, "character": {"name": "NetTest"}}
	var state_json := JSON.stringify(state)
	_stub.push_response({"ok": true, "body": {"updatedAt": "2026-01-01T00:00:00Z"}, "code": 200})
	_stub.push_response(
		{
			"ok": true,
			"body": {"stateJson": state_json, "updatedAt": "2026-01-01T00:00:00Z"},
			"code": 200,
		}
	)
	var put_result := await ApiClient.put_save(state_json)
	var get_result := await ApiClient.get_save()
	check(
		"net.save.round_trip_with_stub",
		put_result.get("ok", false)
		and get_result.get("ok", false)
		and str(get_result.get("stateJson", "")) == state_json,
		"put_save and get_save round-trip stateJson",
		"NET-01"
	)

	_stub.reset()
	_bind_stub()
	_stub.push_response(
		{
			"ok": false,
			"error": "conflict",
			"code": 409,
			"body": {
				"state": JSON.stringify({"schemaVersion": 6, "character": {"name": "Server"}}),
				"updatedAt": "2026-01-02T00:00:00Z",
			},
		}
	)
	var conflict := await ApiClient.put_save(state_json, "2026-01-01T00:00:00Z")
	check(
		"net.save.conflict_applies_server_state",
		conflict.get("conflict", false) and str(conflict.get("stateJson", "")).find("Server") >= 0,
		"409 conflict returns server state payload",
		"NET-01"
	)


func _test_offline_suite() -> void:
	ApiConfig.base_url = ""
	ApiConfig.clear_session()
	_stub.reset()
	_bind_stub()

	var start_usec := Time.get_ticks_usec()
	RunFlow._cloud_finalize_run("run-offline", "escaped", 12.0, true, [])
	await ctx.await_frame(1)
	var elapsed_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	check(
		"net.offline.run_finalize_does_not_block",
		elapsed_ms < 100.0,
		"_cloud_finalize_run returns immediately when cloud is disabled",
		"NET-03"
	)

	ApiConfig.base_url = "https://stub.example"
	ApiConfig.clear_session()
	_stub.reset()
	_bind_stub()
	RunFlow._cloud_finalize_run("run-signed-out", "escaped", 12.0, true, [])
	await ctx.await_frame(2)
	check(
		"net.offline.no_requests_when_signed_out",
		_stub.attempts == 0,
		"signed-out run finalize issues zero HTTP requests",
		"NET-02"
	)


func _test_leaderboard_tier_source() -> void:
	check(
		"net.leaderboard.submits_dungeon_tier",
		ctx.file_contains(
			"res://scripts/app/run_flow.gd", "_submit_leaderboard_async(current_biome_id, current_dungeon_tier"
		),
		"leaderboard submit uses current_dungeon_tier",
		"NET-05"
	)

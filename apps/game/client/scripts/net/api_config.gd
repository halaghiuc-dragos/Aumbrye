extends Node

## Legacy API settings — dungeon generation is fully offline (LocalProcgen).
## Kept for future online features (leaderboards, cloud saves).

const DEFAULT_BASE_URL := "http://localhost:5000"
const CLIENT_VERSION := "0.3.0"
const CONTENT_VERSION := "1"

@export var base_url: String = DEFAULT_BASE_URL

var access_token: String = ""
var refresh_token: String = ""


func get_base_url() -> String:
	return base_url.strip_edges().trim_suffix("/")


func auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer %s" % access_token,
		"X-Client-Version: %s" % CLIENT_VERSION,
		"X-Content-Version: %s" % CONTENT_VERSION,
		"Content-Type: application/json",
	])

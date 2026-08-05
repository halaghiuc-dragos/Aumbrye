extends Node

## Limits simultaneous enemy attack commitments per room group.

const DEFAULT_MAX_TOKENS := 2

var _active_counts: Dictionary = {}


func request_token(group_id: String, max_tokens: int = DEFAULT_MAX_TOKENS) -> bool:
	var count: int = int(_active_counts.get(group_id, 0))
	if count >= max_tokens:
		return false
	_active_counts[group_id] = count + 1
	return true


func release_token(group_id: String) -> void:
	var count: int = int(_active_counts.get(group_id, 0))
	if count <= 1:
		_active_counts.erase(group_id)
	else:
		_active_counts[group_id] = count - 1


func reset_group(group_id: String) -> void:
	_active_counts.erase(group_id)


func reset_all() -> void:
	_active_counts.clear()

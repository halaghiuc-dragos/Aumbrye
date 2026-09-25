class_name FloorDefinitionCache
extends RefCounted

## Keeps a run's already-generated floor definitions around so stepping back onto a floor (ascend
## then descend, a boss retry, a saved-run continue) rebuilds it from the cached definition instead
## of re-rolling generation and getting a different floor. Bounded and keyed by run, not per
## `DungeonBuilder` instance, since the builder that generated a floor is long gone by the time the
## player steps back onto it -- a new one is created per floor load and reads this cache instead.

const MAX_CACHED_FLOORS := 8
const MAX_CACHED_BYTES := 8 * 1024 * 1024

static var _floor_definition_cache: Dictionary = {}
static var _cache_run_key := ""
static var _cache_reference_floor := -1
static var _cache_bytes := 0


static func begin_run_cache(run_key: String) -> void:
	if run_key != _cache_run_key:
		_floor_definition_cache.clear()
		_cache_bytes = 0
	_cache_run_key = run_key
	_cache_reference_floor = -1


static func set_reference_floor(floor_index: int) -> void:
	_cache_reference_floor = floor_index


static func store_floor_cache(floor_index: int, floor_definition: Dictionary) -> void:
	if floor_definition.is_empty():
		return
	var key := str(floor_index)
	if _floor_definition_cache.has(key):
		_cache_bytes -= _definition_bytes(_floor_definition_cache[key])
	_floor_definition_cache[key] = floor_definition.duplicate(true)
	_cache_bytes += _definition_bytes(floor_definition)
	_trim_floor_cache(_cache_reference_floor if _cache_reference_floor > 0 else floor_index)


static func get_floor_cache(floor_index: int) -> Dictionary:
	var cached: Variant = _floor_definition_cache.get(str(floor_index), {})
	return cached.duplicate(true) if cached is Dictionary else {}


static func erase_floor_cache(floor_index: int) -> void:
	var key := str(floor_index)
	if _floor_definition_cache.has(key):
		_cache_bytes -= _definition_bytes(_floor_definition_cache[key])
	_floor_definition_cache.erase(key)


static func clear_floor_cache() -> void:
	_floor_definition_cache.clear()
	_cache_bytes = 0
	_cache_run_key = ""
	_cache_reference_floor = -1


static func _trim_floor_cache(reference_floor: int) -> void:
	if _floor_definition_cache.size() <= MAX_CACHED_FLOORS and _cache_bytes <= MAX_CACHED_BYTES:
		return
	var keys: Array[int] = []
	for key in _floor_definition_cache:
		keys.append(int(key))
	keys.sort_custom(
		func(a: int, b: int) -> bool: return absi(a - reference_floor) > absi(b - reference_floor)
	)
	while _floor_definition_cache.size() > MAX_CACHED_FLOORS or _cache_bytes > MAX_CACHED_BYTES:
		var evicted_key := str(keys.pop_front())
		_cache_bytes -= _definition_bytes(_floor_definition_cache[evicted_key])
		_floor_definition_cache.erase(evicted_key)


static func _definition_bytes(definition: Variant) -> int:
	return JSON.stringify(definition).to_utf8_buffer().size()

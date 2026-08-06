class_name ProcgenRng
extends RefCounted

## Named deterministic RNG streams for procgen (PLC-05).

static var _stream_cache: Dictionary = {}


static func stream(run_seed: int, name: String) -> RandomNumberGenerator:
	var key := "%d|%s" % [run_seed, name]
	if _stream_cache.has(key):
		return _stream_cache[key] as RandomNumberGenerator
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash64(run_seed, name)
	_stream_cache[key] = rng
	return rng


static func stream_with_mix(run_seed: int, name: String, mix_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = FloorSeedMix.mix(_hash64(run_seed, name), mix_value)
	return rng


static func clear_cache() -> void:
	_stream_cache.clear()


static func _hash64(seed: int, name: String) -> int:
	var name_hash := name.hash() & 0x7FFFFFFF
	return FloorSeedMix.mix(seed, name_hash)

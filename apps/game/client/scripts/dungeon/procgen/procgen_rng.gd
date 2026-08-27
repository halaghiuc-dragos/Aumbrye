class_name ProcgenRng
extends RefCounted


static func stream(run_seed: int, name: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash64(run_seed, name)
	return rng


static func stream_with_mix(run_seed: int, name: String, mix_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = FloorSeedMix.mix(_hash64(run_seed, name), mix_value)
	return rng


static func clear_cache() -> void:
	pass


static func _hash64(seed_value: int, name: String) -> int:
	var name_hash := name.hash() & 0x7FFFFFFF
	return FloorSeedMix.mix(seed_value, name_hash)

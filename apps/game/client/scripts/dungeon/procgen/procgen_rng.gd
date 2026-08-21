class_name ProcgenRng
extends RefCounted

## Named deterministic RNG streams for procgen (PLC-05).

## C-142: this used to cache the generator *object* per `(run_seed, name)` and hand the same
## instance back on every call — carrying whatever state previous draws had left it in. Nothing on
## any gameplay path ever called `clear_cache()`: its only callers were validation suites. So the
## second generation for a given seed and stream name continued where the first left off, and the
## same seed produced a different floor on reuse — regenerating a floor after a save/continue, or
## revisiting one in endless mode, diverged from what the seed originally produced.
##
## Every call site draws its stream once per generation pass and then uses that object for the whole
## pass, so nothing needs the caching: a freshly seeded generator per call is both cheaper to reason
## about and deterministic by construction. Seeding is a single `FloorSeedMix.mix`.
static func stream(run_seed: int, name: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash64(run_seed, name)
	return rng


static func stream_with_mix(run_seed: int, name: String, mix_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = FloorSeedMix.mix(_hash64(run_seed, name), mix_value)
	return rng


## C-142: kept as a no-op so external callers do not break; there is no longer any state to clear.
static func clear_cache() -> void:
	pass


static func _hash64(seed_value: int, name: String) -> int:
	var name_hash := name.hash() & 0x7FFFFFFF
	return FloorSeedMix.mix(seed_value, name_hash)

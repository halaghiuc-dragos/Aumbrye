class_name ProcgenBiomeLoader
extends RefCounted

## Deprecated — use BiomeRegistry.get_biome().


static func fetch(biome_id: String) -> Dictionary:
	return BiomeRegistry.get_biome(biome_id)


static func load(biome_id: String) -> Dictionary:
	return BiomeRegistry.get_biome(biome_id)


static func clear_cache() -> void:
	BiomeRegistry.clear_caches()

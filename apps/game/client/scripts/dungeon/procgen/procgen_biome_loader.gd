class_name ProcgenBiomeLoader
extends RefCounted


static func load(biome_id: String) -> Dictionary:
	return ContentLoader.load_json("content/biomes/%s.json" % biome_id)

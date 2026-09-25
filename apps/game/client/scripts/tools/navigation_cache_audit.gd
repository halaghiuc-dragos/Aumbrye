extends Node3D

const CastleBlockoutScript := preload("res://scripts/dungeon/castle/castle_blockout.gd")
const ROOM_COUNT := 12
const MAX_TEMPLATE_BUILD_USEC := 50_000

var _failures := 0


func _ready() -> void:
	var cache_before := CastleBlockout.navigation_template_cache_size()
	var blocks: Array[CastleBlockout] = []
	for index in ROOM_COUNT:
		var block := CastleBlockoutScript.new() as CastleBlockout
		block.name = "NavCacheRoom%d" % index
		block.shape = &"hall"
		block.room_width = 16.0
		block.room_depth = 20.0
		block.position = Vector3(float(index * 24), 0.0, 0.0)
		add_child(block)
		block.set_navigation_map(get_world_3d().navigation_map)
		block.finalize_geometry()
		blocks.append(block)
	var initial_builds := 0
	for block in blocks:
		initial_builds += block.navigation_template_build_count()
	_expect(initial_builds <= 1, "identical room footprints must create at most one nav template")
	for block in blocks:
		block.door_north = true
		block.finalize_geometry()
	var rebuild_builds := 0
	for block in blocks:
		rebuild_builds += block.navigation_template_build_count()
	_expect(rebuild_builds == initial_builds, "door rebuilds must reuse the immutable nav template")
	var cache_after := CastleBlockout.navigation_template_cache_size()
	_expect(cache_after - cache_before <= 1, "repeated room builds must add at most one cache entry")
	var max_usec := CastleBlockout.navigation_template_max_usec()
	_expect(max_usec <= MAX_TEMPLATE_BUILD_USEC, "largest synchronous template build exceeded %dus" % MAX_TEMPLATE_BUILD_USEC)
	print("NAVIGATION CACHE RESULT %d failures; templates=%d max_usec=%d" % [_failures, cache_after, max_usec])
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Navigation cache audit: %s" % message)

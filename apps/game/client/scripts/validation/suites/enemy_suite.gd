extends "res://scripts/validation/validation_suite.gd"

const FloorSnap := preload("res://scripts/art/characters/character_floor_snap.gd")

const PROFILE_ENEMIES := {
	"melee": "castle_grunt",
	"ranged": "castle_archer",
	"shield": "castle_shield",
	"brute": "swamp_brute",
	"hound": "castle_hound",
}


func get_category() -> String:
	return "enemy"


func run() -> void:
	await _test_enemy_spawns_on_platform_floor()


func _make_platform(top_y: float) -> StaticBody3D:
	var platform := StaticBody3D.new()
	platform.name = "EnemyFloorSnapPlatform"
	platform.collision_layer = 1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 0.4, 12.0)
	collision.shape = box
	collision.position = Vector3(0.0, top_y - 0.2, 0.0)
	platform.add_child(collision)
	ctx.owner.add_child(platform)
	return platform


func _test_enemy_spawns_on_platform_floor() -> void:
	var start := Time.get_ticks_msec()
	var platform := _make_platform(2.4)
	await ctx.await_physics(4)
	var ok := true
	var last_feet := 0.0
	for profile in PROFILE_ENEMIES:
		var enemy_id: String = PROFILE_ENEMIES[profile]
		var scene := EnemyCatalog.get_scene(enemy_id)
		if scene == null:
			ok = false
			break
		var enemy: CharacterBody3D = scene.instantiate() as CharacterBody3D
		if enemy == null:
			ok = false
			break
		if enemy.has_method("set_catalog_id"):
			enemy.call("set_catalog_id", enemy_id)
		ctx.owner.add_child(enemy)
		await ctx.await_physics(1)
		enemy.global_position = Vector3(0.0, 5.0, 0.0)
		await ctx.await_physics(2)
		var visual := enemy.get_node_or_null("DioramaVisual") as Node3D
		FloorSnap.snap_character(enemy, visual)
		await ctx.await_physics(1)
		last_feet = FloorSnap.feet_world_y(enemy)
		if absf(last_feet - 2.4) > 0.02:
			ok = false
		enemy.queue_free()
		await ctx.await_physics(1)
		if not ok:
			break
	platform.queue_free()
	ctx.timed_record(
		"enemy.spawns_on_platform_floor",
		get_category(),
		ok,
		"each enemy profile stands on a 2.4 m platform within 0.02 m (last feet %.3f)" % last_feet,
		start,
		"SNP-02"
	)

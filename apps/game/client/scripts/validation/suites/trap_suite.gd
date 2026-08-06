extends "res://scripts/validation/validation_suite.gd"

const RoomTrapContentScript := preload("res://scripts/dungeon/room_content/room_trap_content.gd")
const CombatFixtureScript := preload("res://scripts/validation/combat_fixture.gd")

const TRAP_IDS := [
	"spike_trap",
	"falling_trap",
	"poison_pool",
	"frost_trap",
	"shadow_trap",
]


func get_category() -> String:
	return "traps"


func run() -> void:
	await _test_damage_export_forward()
	await _test_room_content_offset()
	await _test_active_scan_hit()
	_test_builder_ids_resolve()


func _test_damage_export_forward() -> void:
	var start := Time.get_ticks_msec()
	var trap_scene: PackedScene = load("res://scenes/traps/spike_trap.tscn")
	var trap: Node3D = trap_scene.instantiate() as Node3D
	trap.set("damage", 30.0)
	trap.set("poise_damage", 14.0)
	ctx.owner.add_child(trap)
	await ctx.await_physics(2)
	var hitbox: TrapDamageArea = trap.get_node("DamageArea") as TrapDamageArea
	var ok := is_instance_valid(hitbox) and hitbox.damage == 30.0 and hitbox.poise_damage == 14.0
	ctx.timed_record(
		"trp.damage.export_forward",
		get_category(),
		ok,
		"spike_trap forwards @export damage to DamageArea after _ready",
		start,
		"TRP-01"
	)
	trap.queue_free()
	await ctx.await_frame()


func _test_room_content_offset() -> void:
	var start := Time.get_ticks_msec()
	var root := Node3D.new()
	root.name = "TrapContentRoot"
	ctx.owner.add_child(root)
	var anchor := Node3D.new()
	anchor.name = "PropAnchor_0"
	root.add_child(anchor)
	var content := Node3D.new()
	content.name = "RoomContent_trap_spike_pack"
	content.set_script(RoomTrapContentScript)
	root.add_child(content)
	content.call("configure", {"z": 5.0}, {})
	await ctx.await_frame()
	var trap: Node3D = null
	for child in root.get_children():
		if child is Node3D and child.name == "SpikeTrap":
			trap = child as Node3D
			break
	var ok := trap != null and is_equal_approx(trap.position.z, 5.0)
	ctx.timed_record(
		"trp.room_content.offset",
		get_category(),
		ok,
		"trap_spike_pack honors entry z offset",
		start,
		"TRP-03"
	)
	root.queue_free()
	await ctx.await_frame()


func _test_active_scan_hit() -> void:
	var start := Time.get_ticks_msec()
	var fixture := CombatFixtureScript.new(ctx)
	await fixture.setup()
	fixture.defender_hurtbox().team = "enemy"

	var trap_area := TrapDamageArea.new()
	trap_area.team = "trap"
	trap_area.damage = 20.0
	trap_area.collision_layer = 4
	trap_area.collision_mask = 8
	ctx.owner.add_child(trap_area)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.0, 2.0)
	shape.shape = box
	trap_area.add_child(shape)
	trap_area.global_position = fixture.defender_hurtbox().global_position
	await ctx.await_physics(2)

	var hp_before := fixture.defender_health().current
	trap_area.set_damage_active(true)
	await ctx.await_physics(2)
	var hp_lost := hp_before - fixture.defender_health().current
	var ok := hp_lost > 0.0

	ctx.timed_record(
		"trp.active.scan_hit",
		get_category(),
		ok,
		"trap_damage_area scan hits overlapping hurtbox on enable",
		start,
		"TRP-04"
	)
	trap_area.queue_free()
	await fixture.teardown()


func _test_builder_ids_resolve() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	var missing: Array[String] = []
	for trap_id in TRAP_IDS:
		var scene_path := TrapCatalog.get_scene_path(trap_id)
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			ok = false
			missing.append(trap_id)

	ctx.timed_record(
		"trp.builder.ids_resolve",
		get_category(),
		ok,
		(
			"TrapCatalog ids map to existing scenes"
			if ok
			else "missing trap scenes for: %s" % ", ".join(missing)
		),
		start,
		"TRP-05"
	)

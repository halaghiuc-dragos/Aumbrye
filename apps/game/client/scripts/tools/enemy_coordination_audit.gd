extends Node3D

const ENEMY_SCENE := preload("res://scenes/enemies/castle_grunt.tscn")
const ARCHER_SCENE := preload("res://scenes/enemies/castle_archer.tscn")

var _failures := 0


func _ready() -> void:
	EnemyBlackboard.clear_all()
	var player := CharacterBody3D.new()
	add_child(player)
	var near_enemy := _spawn_enemy(Vector3(0.0, 0.0, -1.5), player)
	var second_enemy := _spawn_enemy(Vector3(1.5, 0.0, -1.5), player)
	var blocked_enemy := _spawn_enemy(Vector3(0.0, 0.0, -4.5), player)
	var ranged_support := _spawn_enemy_scene(ARCHER_SCENE, Vector3(0.0, 0.0, 7.0), player)
	_add_los_blocker(Vector3(0.0, 1.0, -2.8))
	await get_tree().physics_frame
	var room_id := 991
	EnemyBlackboard.report_engaged(room_id, near_enemy, true)
	EnemyBlackboard.report_engaged(room_id, second_enemy, true)
	EnemyBlackboard.report_engaged(room_id, blocked_enemy, true)
	EnemyBlackboard.report_engaged(room_id, ranged_support, true)
	_expect(near_enemy.get_ai_role() == EnemyBlackboard.Role.ENGAGER, "first ready melee actor must receive an engager slot")
	_expect(second_enemy.get_ai_role() == EnemyBlackboard.Role.ENGAGER, "second ready melee actor must receive an engager slot")
	_expect(blocked_enemy.get_ai_role() != EnemyBlackboard.Role.ENGAGER, "blocked actor must not take an engager slot")
	_expect(ranged_support.get_ai_role() != EnemyBlackboard.Role.ENGAGER, "ranged support must not displace two ready melee attackers")
	EnemyBlackboard.yield_engager(room_id, near_enemy)
	_expect(near_enemy.get_ai_role() != EnemyBlackboard.Role.ENGAGER, "yielded engager must not reclaim its slot immediately")
	_expect(second_enemy.get_ai_role() == EnemyBlackboard.Role.ENGAGER, "ready nearby actor must receive yielded slot")
	_test_encounter_token_ownership()
	print("ENEMY COORDINATION RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _spawn_enemy(position_value: Vector3, player: Node3D) -> CastleEnemyBase:
	return _spawn_enemy_scene(ENEMY_SCENE, position_value, player)


func _spawn_enemy_scene(scene: PackedScene, position_value: Vector3, player: Node3D) -> CastleEnemyBase:
	var enemy := scene.instantiate() as CastleEnemyBase
	enemy.position = position_value
	enemy.set_meta("encounter_key", 991)
	enemy.set_player(player)
	add_child(enemy)
	return enemy


func _test_encounter_token_ownership() -> void:
	AttackTokenService.reset_all()
	var room_a_one := Node.new()
	var room_a_two := Node.new()
	var summoned_add := Node.new()
	var room_b_one := Node.new()
	for actor in [room_a_one, room_a_two, summoned_add, room_b_one]:
		add_child(actor)
	var encounter_a := "audit_room_a:pressure"
	var encounter_b := "audit_room_b:pressure"
	_expect(AttackTokenService.request_token(encounter_a, room_a_one), "first room-A actor gets a permit")
	_expect(AttackTokenService.request_token(encounter_a, room_a_two), "second room-A actor gets a permit")
	_expect(not AttackTokenService.request_token(encounter_a, summoned_add), "summoned add shares its encounter pressure cap")
	_expect(AttackTokenService.request_token(encounter_b, room_b_one), "connected room-B encounter has an independent permit budget")
	AttackTokenService.release_token(encounter_a, room_a_one)
	_expect(AttackTokenService.request_token(encounter_a, summoned_add), "released owner lease admits a summoned replacement")
	room_a_one.queue_free()
	room_a_two.queue_free()
	summoned_add.queue_free()
	room_b_one.queue_free()


func _add_los_blocker(position_value: Vector3) -> void:
	var blocker := StaticBody3D.new()
	blocker.position = position_value
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.1, 2.0, 0.5)
	collision.shape = shape
	blocker.add_child(collision)
	add_child(blocker)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Enemy coordination audit: %s" % message)

extends Node

## Do enemies actually fight? Every boss and elite, and a spread of ordinary enemies, is dropped
## next to a player-shaped body and must reach a wind-up and an attack within ten seconds. Also
## checks that a corpse stays put with its physics off, and that a stun lands in pulses rather than
## holding the target for the whole status.

const ORDINARY_SAMPLE: Array[String] = [
	"castle_grunt", "castle_archer", "castle_hound", "castle_shield", "crystal_guardian"
]
const FRAMES_TO_FIGHT := 600
const CORPSE_FRAMES := 900

var _failures := 0
var _root: Node3D


func _ready() -> void:
	await get_tree().physics_frame
	for enemy_id in _enemy_ids():
		await _check_attacks(enemy_id)
	await _check_corpse()
	await _check_stun()
	print("ENEMY ATTACK RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _enemy_ids() -> Array[String]:
	var ids: Array[String] = ORDINARY_SAMPLE.duplicate()
	for sub_dir in ["content/enemies", "content/bosses"]:
		var dir_path := ContentLoader.content_root().path_join(sub_dir)
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			if not file.ends_with(".json"):
				continue
			var enemy_id := file.get_basename()
			var definition := EnemyCatalog.get_definition(enemy_id)
			if (bool(definition.get("isBoss", false)) or bool(definition.get("isElite", false))) and enemy_id not in ids:
				ids.append(enemy_id)
	return ids


func _make_arena() -> Node3D:
	var arena := Node3D.new()
	add_child(arena)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	arena.add_child(floor_body)
	return arena


func _spawn_enemy(arena: Node3D, enemy_id: String, player: Node3D) -> CastleEnemyBase:
	var scene: PackedScene = EnemyCatalog.get_scene(enemy_id)
	if scene == null:
		return null
	var enemy := scene.instantiate() as CastleEnemyBase
	if enemy == null:
		return null
	enemy.set_catalog_id(enemy_id)
	# A dungeon placement is kept (hidden) after it dies, so its corpse can be measured.
	enemy.set_meta("placement_id", "audit_%s" % enemy_id)
	arena.add_child(enemy)
	enemy.global_position = Vector3(0, 0.1, 0)
	enemy.set_player(player)
	return enemy


func _make_player(arena: Node3D) -> CharacterBody3D:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = CombatLayers.PLAYER_BODY
	player.collision_mask = CombatLayers.WORLD
	var hull := CollisionShape3D.new()
	hull.shape = CapsuleShape3D.new()
	player.add_child(hull)
	arena.add_child(player)
	player.global_position = Vector3(0, 1, 2.2)
	return player


func _check_attacks(enemy_id: String) -> void:
	_root = _make_arena()
	var player := _make_player(_root)
	var enemy := _spawn_enemy(_root, enemy_id, player)
	if enemy == null:
		_fail("%s has no scene to spawn" % enemy_id)
		_root.queue_free()
		return
	var seen := {}
	for frame in FRAMES_TO_FIGHT:
		await get_tree().physics_frame
		if frame == 5:
			enemy._latch_aggro()
		seen[enemy._state] = true
		if seen.has(CastleEnemyBase.State.WINDUP) and seen.has(CastleEnemyBase.State.ATTACK):
			break
	if not (seen.has(CastleEnemyBase.State.WINDUP) and seen.has(CastleEnemyBase.State.ATTACK)):
		_fail("%s never winds up and attacks in %d frames (states %s)" % [enemy_id, FRAMES_TO_FIGHT, seen.keys()])
	_root.queue_free()
	await get_tree().process_frame


func _check_corpse() -> void:
	_root = _make_arena()
	var enemy := _spawn_enemy(_root, "castle_grunt", null)
	if enemy == null:
		_fail("castle_grunt has no scene for the corpse check")
		_root.queue_free()
		return
	for _i in 30:
		await get_tree().physics_frame
	(enemy.get_node("Health") as Health).take_damage(99999.0)
	for _i in 120:
		await get_tree().physics_frame
	var settled_y := enemy.global_position.y
	for _i in CORPSE_FRAMES:
		await get_tree().physics_frame
	if absf(enemy.global_position.y - settled_y) > 0.05:
		_fail("a corpse keeps moving: y %.2f -> %.2f" % [settled_y, enemy.global_position.y])
	if enemy.is_physics_processing():
		_fail("a corpse still runs physics")
	_root.queue_free()
	await get_tree().process_frame


func _check_stun() -> void:
	var body := Node3D.new()
	add_child(body)
	var health := Health.new()
	health.name = "Health"
	body.add_child(health)
	health.configure(100.0)
	var status := StatusController.new()
	body.add_child(status)
	status.set_health(health)
	status.apply_status("torpor", 1)
	var elapsed := 0.0
	var marks := {0.1: true, 0.6: false, 1.5: true, 2.2: false}
	var pending := marks.keys()
	while not pending.is_empty():
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if elapsed >= float(pending[0]):
			var mark: float = pending.pop_front()
			if status.is_stunned() != bool(marks[mark]):
				_fail("torpor at %.1fs: stunned=%s, expected %s" % [mark, status.is_stunned(), marks[mark]])
	body.queue_free()


func _fail(message: String) -> void:
	_failures += 1
	push_error("Enemy attack audit: %s" % message)

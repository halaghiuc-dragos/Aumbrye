extends CastleEnemyBase


const PROJECTILE_SCENE := preload("res://scenes/combat/enemy_projectile.tscn")
const ProjectileContainerScript := preload("res://scripts/combat/projectile_container.gd")
const ProjectileScript := preload("res://scripts/combat/enemy_projectile.gd")

var _locked_shot_direction := Vector3.FORWARD
var _locked_shot_speed := 12.0
var _locked_shot_target := Vector3.INF
var _shot_reachable := true

## A ranged enemy must not keep feeding a blocked backward vector into physics forever.  It picks
## one reachable retreat/side-step for a short window, then reassesses; if every option is blocked
## it holds its ground, leaving a player who has cornered it a deliberate punish opportunity.
const REPOSITION_DISTANCE := 3.2
const REPOSITION_TIMEOUT := 1.1
const REPOSITION_ARRIVAL_DISTANCE := 0.7
var _reposition_target := Vector3.INF
var _reposition_timer := 0.0


func _resolve_enemy_id() -> String:
	return "castle_archer"


func _process_chase(delta: float) -> void:
	if not _has_aggro():
		_state = State.INVESTIGATE
		_state_timer = 2.5
		return
	_last_known_player_pos = _player.global_position
	if _can_attack():
		_start_windup()
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var move_dir := Vector3.ZERO
	if dist < _retreat_range:
		_reposition_timer -= delta
		if (
			_reposition_timer <= 0.0
			or _reposition_target == Vector3.INF
			or global_position.distance_to(_reposition_target) <= REPOSITION_ARRIVAL_DISTANCE
		):
			_reposition_target = _choose_reposition_target(to_player)
			_reposition_timer = REPOSITION_TIMEOUT
		if _reposition_target != Vector3.INF:
			move_dir = _direction_toward(_reposition_target, delta, false)
	elif dist > _preferred_range:
		_reposition_target = Vector3.INF
		_reposition_timer = 0.0
		move_dir = _direction_toward(_player.global_position, delta, true)
	else:
		_reposition_target = Vector3.INF
		_reposition_timer = 0.0
	velocity = move_dir * _move_speed
	if to_player.length_squared() > 0.01:
		_face_direction(to_player, delta)


func _choose_reposition_target(to_player: Vector3) -> Vector3:
	if to_player.length_squared() < 0.01 or not is_inside_tree():
		return Vector3.INF
	var away := -to_player.normalized()
	var left := Vector3(-away.z, 0.0, away.x)
	# Prefer a true retreat, then deliberately try each lateral escape.  The order alternates with
	# the inherited circle direction so a row of archers does not all choose the same wall.
	var candidates: Array[Vector3] = [away]
	if _circle_direction >= 0.0:
		candidates.append((away + left * 0.9).normalized())
		candidates.append((away - left * 0.9).normalized())
	else:
		candidates.append((away - left * 0.9).normalized())
		candidates.append((away + left * 0.9).normalized())
	for direction in candidates:
		var target := global_position + direction * REPOSITION_DISTANCE
		if _is_reachable_reposition_target(target):
			return target
	return Vector3.INF


func _is_reachable_reposition_target(target: Vector3) -> bool:
	var world := get_world_3d()
	if world == null:
		return false
	var map: RID = world.navigation_map
	if map.is_valid() and not NavigationServer3D.map_get_regions(map).is_empty():
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			map, global_position, target, true
		)
		return path.size() >= 2 and path[path.size() - 1].distance_to(target) <= 1.0
	# Small debug arenas and bespoke encounters can intentionally omit a navigation map.  A world
	# ray still refuses a visibly blocked rear step rather than preserving the old wall-pushing
	# fallback.  There is no synthetic escape when all three directions are obstructed.
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.7, target + Vector3.UP * 0.7
	)
	query.exclude = [get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _start_windup() -> void:
	_lock_shot_trajectory()
	if not _shot_reachable:
		_state = State.CHASE
		return
	super._start_windup()


func _on_windup_tick(committed: bool) -> void:
	if committed:
		return
	_lock_shot_trajectory()
	if not _shot_reachable:
		hide_attack_windup_bar()
		_release_attack_token()
		_state = State.CHASE


func _telegraph_radius_scale() -> float:
	return 1.4


func _lock_shot_trajectory() -> void:
	_locked_shot_speed = _data.get("projectile_speed", 12.0)
	var shot_damage_type := str(_current_attack_data.get("damage_type", _data.get("damage_type", DamageInfo.TYPE_PHYSICAL)))
	var projectile_archetype := _resolved_projectile_archetype(shot_damage_type)
	var projectile_gravity := ProjectileScript.gravity_for_archetype(projectile_archetype)
	if _player == null:
		_locked_shot_direction = CombatFacing.forward_of(self)
		_locked_shot_target = Vector3.INF
		_shot_reachable = true
		return
	var spawn_pos := global_position + Vector3(0, 1.2, 0)
	var target_pos := _player.global_position + Vector3(0, 1.0, 0)
	_locked_shot_target = target_pos
	var to_target := target_pos - spawn_pos
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		_locked_shot_direction = CombatFacing.forward_of(self)
	else:
		_locked_shot_direction = to_target.normalized()
	var solution := ProjectileScript.solve_launch_velocity(
		_locked_shot_direction, _locked_shot_speed, spawn_pos, target_pos, 1.0, projectile_gravity
	)
	_shot_reachable = bool(solution.get("reachable", false))
	if _shot_reachable:
		var space := get_world_3d().direct_space_state
		var excluded: Array[RID] = [get_rid()]
		_shot_reachable = ProjectileScript.trajectory_is_clear(
			space, spawn_pos, solution["velocity"], target_pos, excluded, projectile_gravity
		)


func _start_attack() -> void:
	if str(_current_attack_data.get("attackBehavior", "projectile")) != "projectile":
		super._start_attack()
		return
	if is_dead() or (_health and _health.is_dead()):
		_release_attack_token()
		return
	_state = State.ATTACK
	_state_timer = float(
		_current_attack_data.get("active_duration", _data.get("active_duration", 0.05))
	)
	hide_attack_windup_bar()
	_fire_projectile()
	attack_active.emit()


func _fire_projectile() -> void:
	var projectile: Node3D = ProjectileContainerScript.acquire(self, PROJECTILE_SCENE)
	if projectile == null:
		return
	projectile.global_position = _projectile_origin()
	projectile.set("projectile_archetype", _resolved_projectile_archetype(str(_current_attack_data.get("damage_type", _data.get("damage_type", DamageInfo.TYPE_PHYSICAL)))))
	if not projectile.has_method("launch"):
		ProjectileContainerScript.recycle(projectile)
		return
	var launched: Variant = projectile.call(
		"launch",
		_locked_shot_direction,
		float(_current_attack_data.get("projectile_speed", _locked_shot_speed)),
		float(_current_attack_data.get("attack_damage", _data.get("attack_damage", 12.0)))
		* _damage_multiplier,
		float(
			_current_attack_data.get("attack_poise_damage", _data.get("attack_poise_damage", 8.0))
		)
		* _damage_multiplier,
		self,
		_current_attack_data.get("damage_type", _data.get("damage_type", DamageInfo.TYPE_PHYSICAL)),
		_current_attack_data.get("status_on_hit", _data.get("status_on_hit", "")),
		int(
			_current_attack_data.get(
				"status_stacks_on_hit", _data.get("status_stacks_on_hit", 1)
			)
		),
		0.0,
		1.5,
		_current_attack_class(),
		float(_current_attack_data.get("knockback", _data.get("knockback", 0.0))),
		_locked_shot_target
	)
	if launched is bool and not launched:
		_shot_reachable = false


func _projectile_origin() -> Vector3:
	for anchor_name in ["ProjectileMuzzle", "Muzzle", "AimAnchor"]:
		var anchor := find_child(anchor_name, true, false) as Node3D
		if anchor:
			return anchor.global_position
	return global_position + Vector3(0.0, 1.2, 0.0)


func _resolved_projectile_archetype(damage_type: String) -> String:
	var authored := str(_current_attack_data.get("projectile_archetype", _data.get("projectile_archetype", "")))
	if authored in ["arrow", "bolt_orb", "lobbed_item"]:
		return authored
	return "arrow" if damage_type == DamageInfo.TYPE_PHYSICAL else "bolt_orb"

extends Node3D

const ProjectileScene := preload("res://scenes/combat/enemy_projectile.tscn")

var _failures := 0


class ParryHurtbox extends Area3D:
	var team := "player"

	func receive_hit(_info: DamageInfo) -> RefCounted:
		var resolution := DamageResolution.new()
		resolution.parried = true
		return resolution


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _make_target(target_position: Vector3, extra_region: bool = false) -> Dictionary:
	var body := CharacterBody3D.new()
	body.position = target_position
	var health := Health.new()
	health.name = "Health"
	body.add_child(health)
	body.set_meta("projectile_audit_hits", 0)
	_make_hurtbox(body, "Hurtbox", Vector3.ZERO)
	if extra_region:
		_make_hurtbox(body, "HurtboxUpper", Vector3(0.0, 0.45, 0.0))
	add_child(body)
	return {"body": body, "health": health}


func _make_hurtbox(body: CharacterBody3D, node_name: String, offset: Vector3) -> void:
	var hurtbox := Hurtbox.new()
	hurtbox.name = node_name
	hurtbox.team = "player"
	hurtbox.collision_layer = CombatLayers.HURTBOX
	hurtbox.health_path = NodePath("../Health")
	hurtbox.damaged.connect(func(_info: DamageInfo) -> void:
		body.set_meta("projectile_audit_hits", int(body.get_meta("projectile_audit_hits")) + 1)
	)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.45
	collision.shape = shape
	collision.position = offset
	hurtbox.add_child(collision)
	body.add_child(hurtbox)


func _make_wall(wall_position: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.position = wall_position
	wall.collision_layer = CombatLayers.WORLD_OCCLUDERS
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, 2.0, 2.0)
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	return wall


func _make_parry_target(target_position: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.position = target_position
	var hurtbox := ParryHurtbox.new()
	hurtbox.name = "ParryHurtbox"
	hurtbox.collision_layer = CombatLayers.HURTBOX
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.45
	collision.shape = shape
	hurtbox.add_child(collision)
	body.add_child(hurtbox)
	add_child(body)
	return body


func _fire(speed: float, pierce: int = 0) -> Projectile:
	var projectile := ProjectileScene.instantiate() as Projectile
	projectile.position = Vector3.ZERO
	projectile.pierce = pierce
	add_child(projectile)
	await get_tree().physics_frame
	var launched := projectile.launch(Vector3.RIGHT, speed, 20.0, 0.0, self)
	_check(launched, "Projectile launch must succeed")
	return projectile


func _clear_fixture() -> void:
	for child in get_children():
		child.queue_free()
	await get_tree().physics_frame


func _ready() -> void:
	RunBuffs.clear_all()
	var sample_resolution := DamageResolution.new()
	sample_resolution.outgoing = 12.5
	sample_resolution.crit = true
	sample_resolution.backstab = true
	RunBuffs.note_player_hit(sample_resolution)
	var recorded_hit: Dictionary = RunBuffs.offer_state_to_save().get("bestHit", {})
	_check(
		float(recorded_hit.get("amount", 0.0)) == 12.5
		and bool(recorded_hit.get("crit", false))
		and bool(recorded_hit.get("backstab", false)),
		"RunBuffs records typed DamageResolution values without Dictionary-style get calls"
	)
	RunBuffs.clear_all()
	# The one-second step deliberately crosses every fixture object. This is the regression for a
	# high-speed thin-wall shot: contact ordering must not depend on a later Area3D overlap frame.
	var near_target := _make_target(Vector3(3.0, 0.0, 0.0))
	_make_wall(Vector3(6.0, 0.0, 0.0))
	var target_first := await _fire(10.0)
	target_first._resolve_motion_contacts(get_world_3d().direct_space_state, Vector3.RIGHT * 10.0)
	_check(float((near_target["health"] as Health).current) < 100.0, "Target before wall must receive the projectile")
	await _clear_fixture()

	var behind_wall := _make_target(Vector3(6.0, 0.0, 0.0))
	_make_wall(Vector3(3.0, 0.0, 0.0))
	var wall_first := await _fire(10.0)
	wall_first._resolve_motion_contacts(get_world_3d().direct_space_state, Vector3.RIGHT * 10.0)
	_check(is_equal_approx(float((behind_wall["health"] as Health).current), 100.0), "Wall before target must block the projectile")
	await _clear_fixture()

	var first_target := _make_target(Vector3(3.0, 0.0, 0.0), true)
	var second_target := _make_target(Vector3(6.0, 0.0, 0.0))
	var piercing := await _fire(10.0, 1)
	piercing._resolve_motion_contacts(get_world_3d().direct_space_state, Vector3.RIGHT * 10.0)
	_check(float((first_target["health"] as Health).current) < 100.0, "Piercing projectile must damage the first target")
	_check(float((second_target["health"] as Health).current) < 100.0, "Piercing projectile must continue to a second collinear target")
	_check(
		int((first_target["body"] as CharacterBody3D).get_meta("projectile_audit_hits")) == 1,
		"Two hurtboxes on one actor must consume one projectile hit and one pierce charge"
	)
	await _clear_fixture()

	# DamageResolution is also the projectile outcome contract: a deliberate dodge has no damage
	# reward, but it remains a physical contact that consumes a non-piercing projectile.
	var dodging := _make_target(Vector3(3.0, 0.0, 0.0))
	var dodge := Dodge.new()
	dodge.name = "Dodge"
	(dodging["body"] as CharacterBody3D).add_child(dodge)
	await get_tree().physics_frame
	for child in (dodging["body"] as CharacterBody3D).get_children():
		if child is Hurtbox:
			(child as Hurtbox)._refresh_sibling_cache()
	dodge.grant_external_iframes(true)
	var dodge_projectile := await _fire(10.0, 1)
	dodge_projectile._resolve_motion_contacts(get_world_3d().direct_space_state, Vector3.RIGHT * 10.0)
	_check(is_equal_approx(float((dodging["health"] as Health).current), 100.0), "Dodged projectile must not deal damage")
	await get_tree().physics_frame
	_check(not is_instance_valid(dodge_projectile), "A dodged projectile must be consumed instead of piercing")
	await _clear_fixture()

	# A parry has the same terminal-shot semantics as dodge, while its outcome remains distinct
	# in DamageResolution for guard feedback and downstream combat rules.
	_make_parry_target(Vector3(3.0, 0.0, 0.0))
	var parry_projectile := await _fire(10.0, 1)
	parry_projectile._resolve_motion_contacts(get_world_3d().direct_space_state, Vector3.RIGHT * 10.0)
	await get_tree().physics_frame
	_check(not is_instance_valid(parry_projectile), "A parried projectile must be consumed instead of piercing")
	await _clear_fixture()

	# World contacts do not pass through Hurtbox/HitFeedback, so the projectile must provide its
	# own terrain-contact cue. Inspect the director's active cue ownership to verify dispatch.
	var audio_director := get_node_or_null("/root/AudioDirector")
	var impact_projectile := await _fire(10.0)
	if audio_director != null:
		var active_counts: Dictionary = audio_director.get("_sfx_active_counts")
		var previous_stone_hits := int(active_counts.get("hit_stone", 0))
		impact_projectile._on_world_impact({"position": impact_projectile.global_position, "normal": Vector3.UP})
		_check(
			int(active_counts.get("hit_stone", 0)) > previous_stone_hits,
			"Terrain impact must dispatch the authored stone-contact cue"
		)
	else:
		_check(false, "AudioDirector autoload must exist for terrain impact audio verification")
	await get_tree().physics_frame

	print("PROJECTILE COLLISION RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

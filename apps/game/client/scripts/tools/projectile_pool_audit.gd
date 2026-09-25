extends Node3D

const ProjectileScene := preload("res://scenes/combat/player_arrow.tscn")
const ThrowableScene := preload("res://scenes/combat/throwable_projectile.tscn")
const ProjectileContainerScript := preload("res://scripts/combat/projectile_container.gd")

var _failures := 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _ready() -> void:
	var arrow_visual := Projectile._visual_variant(DamageInfo.TYPE_PHYSICAL, "arrow")
	var orb_visual := Projectile._visual_variant(DamageInfo.TYPE_ARCANE, "bolt_orb")
	_check(arrow_visual["parts"].size() == 4, "Arrow archetype must retain shaft, head, and fletching parts")
	_check(orb_visual["parts"].size() == 1 and orb_visual["parts"][0]["mesh"] is SphereMesh, "Bolt/orb archetype must use its cached orb silhouette")
	_check(Projectile.gravity_for_archetype("arrow") > Projectile.gravity_for_archetype("bolt_orb"), "Bolt/orb profile must have a flatter trajectory than an arrow")
	_check(Projectile.gravity_for_archetype("lobbed_item") > Projectile.gravity_for_archetype("arrow"), "Lobbed items must have a steeper trajectory than arrows")
	Projectile.reset_metrics()
	var first := ProjectileContainerScript.acquire(self, ProjectileScene) as Projectile
	_check(first != null, "Pool must create a projectile on first acquisition")
	if first == null:
		get_tree().quit(1)
		return
	await get_tree().physics_frame
	first.pierce = 3
	first.global_position = Vector3(4.0, 2.0, -1.0)
	_check(first.launch(Vector3.FORWARD, 18.0, 7.0, 2.0, self), "Initial pooled launch must work")
	_check(first._pierce_remaining == 3, "Launch must initialize pierce state")
	_check(not first.monitoring, "Projectile root Area must not run a redundant overlap monitor")
	first._finish_lifecycle()
	await get_tree().process_frame
	_check(first.get_parent() != null and first.get_parent().name == ProjectileContainerScript.POOL_NAME, "Finished projectile must return to the inactive pool")
	_check(first._owner_node == null and first._pierce_remaining == 0, "Pool reset must clear owner and pierce state")
	_check(first._hitbox._combat_owner == null, "Pool reset must clear hitbox shooter ownership")
	_check(first._visual.scale.is_equal_approx(Vector3.ONE), "Pool reset must restore visual scale")

	var second := ProjectileContainerScript.acquire(self, ProjectileScene) as Projectile
	_check(second == first, "Second acquisition must reuse the inactive projectile instance")
	await get_tree().physics_frame
	second.pierce = 1
	second.projectile_archetype = "bolt_orb"
	_check(second.launch(Vector3.RIGHT, 12.0, 4.0, 1.0, self, DamageInfo.TYPE_ARCANE), "Reused elemental projectile launch must work")
	_check(second._owner_node == self and second._pierce_remaining == 1, "Reuse must establish fresh owner and pierce state")
	for part_index in range(1, 4):
		var stale_arrow_part := second._visual.get_node_or_null("Part%d" % part_index) as MeshInstance3D
		if stale_arrow_part:
			_check(not stale_arrow_part.visible, "Switching from arrow to orb must hide stale shaft/fletching parts")
	var shared_ember_node := second._visual.get_node_or_null("LightEmbers")
	if PixelDioramaSettings.particle_quality > 0:
		_check(shared_ember_node is GPUParticles3D, "Elemental projectile must have its ember trail")
	second._finish_lifecycle()
	await get_tree().process_frame
	var reused_elemental := ProjectileContainerScript.acquire(self, ProjectileScene) as Projectile
	_check(reused_elemental == second, "Elemental projectile must return to and reuse the pool")
	if reused_elemental:
		await get_tree().physics_frame
		reused_elemental.projectile_archetype = "bolt_orb"
		reused_elemental.launch(Vector3.RIGHT, 12.0, 4.0, 1.0, self, DamageInfo.TYPE_ARCANE)
		if shared_ember_node is GPUParticles3D:
			_check(reused_elemental._visual.get_node_or_null("LightEmbers") == shared_ember_node, "Elemental reuse must retain its particle node")
		reused_elemental._finish_lifecycle()
		await get_tree().process_frame
	var throwable := ProjectileContainerScript.acquire(self, ThrowableScene) as ThrowableProjectile
	_check(throwable != null, "Throwable pool must create an instance")
	if throwable:
		await get_tree().physics_frame
		throwable.configure("burn", 2, 8.0, 5.0, 10.0, DamageInfo.TYPE_FIRE, true, "lobbed_item")
		throwable.launch(Vector3.FORWARD, 16.0, 0.0, 0.0, self)
		throwable._exploded = true
		throwable._finish_lifecycle()
		await get_tree().process_frame
		_check(not throwable._exploded and throwable._status_id.is_empty() and not throwable._lure, "Throwable reset must clear explosion, status, and lure state")
		var reused_throwable := ProjectileContainerScript.acquire(self, ThrowableScene) as ThrowableProjectile
		_check(reused_throwable == throwable, "Throwable pool must reuse the inactive instance")
		if reused_throwable:
			reused_throwable.configure("freeze", 1, 5.0, 3.0, 4.0, DamageInfo.TYPE_FROST, false, "lobbed_item")
			_check(reused_throwable._status_id == "freeze" and not reused_throwable._exploded, "Reconfigured throwable must start with fresh payload state")
			reused_throwable._finish_lifecycle()
			await get_tree().process_frame
	await _measure_volley()
	print("PROJECTILE POOL RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _measure_volley() -> void:
	Projectile.reset_metrics()
	var volley: Array[Projectile] = []
	for index in 24:
		var projectile := ProjectileContainerScript.acquire(self, ProjectileScene) as Projectile
		if projectile == null:
			_check(false, "Volley acquisition must succeed")
			continue
		projectile.position = Vector3(float(index) * 0.45, 0.0, 0.0)
		projectile.launch(Vector3.FORWARD, 18.0, 5.0, 1.0, self)
		volley.append(projectile)
	var frame_times_usec: Array[int] = []
	for frame_index in 12:
		var frame_start := Time.get_ticks_usec()
		await get_tree().physics_frame
		frame_times_usec.append(Time.get_ticks_usec() - frame_start)
	var max_frame_usec := 0
	for elapsed_usec in frame_times_usec:
		max_frame_usec = maxi(max_frame_usec, elapsed_usec)
	var volley_metrics := Projectile.metrics()
	print(
		"PROJECTILE VOLLEY METRICS count=%d created=%d reused=%d visual_variant_builds=%d cached_visual_variants=%d swept_queries=%d frames=%d max_frame_usec=%d"
		% [
			volley.size(),
			int(volley_metrics["projectiles_created"]),
			int(volley_metrics["projectiles_reused"]),
			int(volley_metrics["visual_variant_builds"]),
			int(volley_metrics["cached_visual_variants"]),
			int(volley_metrics["swept_queries"]),
			frame_times_usec.size(),
			max_frame_usec,
		]
	)
	for projectile in volley:
		projectile._finish_lifecycle()

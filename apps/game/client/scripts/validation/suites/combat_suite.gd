extends "res://scripts/validation/validation_suite.gd"

const CombatFixtureScript := preload("res://scripts/validation/combat_fixture.gd")


func get_category() -> String:
	return "combat"


func run() -> void:
	await _test_combat_components()
	await _test_combat_pipeline()
	await _test_guard_and_dodge()
	await _test_weapon_attacks()
	await _test_hit_feedback_and_tokens()
	await _test_enemy_attack_commitment()
	await _test_enemy_death_guards()
	_test_waves_run()


func _test_combat_components() -> void:
	var start := Time.get_ticks_msec()
	var health := Health.new()
	health.configure(120.0)
	var health_ok := health.max_health == 120.0 and not health.is_dead()
	var signal_state: Array[bool] = [false]
	health.health_changed.connect(func(_c: float, _m: float) -> void: signal_state[0] = true)
	health.take_damage(10.0)
	ctx.timed_record(
		"combat.health_configure_signals",
		get_category(),
		health_ok and signal_state[0] and health.current == 110.0,
		"Health configure + health_changed signal",
		start,
		"M1.combat.health"
	)
	health.free()

	start = Time.get_ticks_msec()
	var stamina := Stamina.new()
	var consumed := stamina.consume(20.0)
	ctx.timed_record(
		"combat.stamina_consume",
		get_category(),
		consumed and stamina.current == 80.0,
		"Stamina.consume() deducts cost",
		start,
		"M1.combat.stamina"
	)
	stamina.free()

	start = Time.get_ticks_msec()
	var poise := Poise.new()
	poise.configure(80.0)
	poise.take_poise_damage(80.0)
	ctx.timed_record(
		"combat.poise_break",
		get_category(),
		poise.is_broken(),
		"Poise breaks at zero",
		start,
		"M1.combat.poise"
	)
	poise.free()

	start = Time.get_ticks_msec()
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	await ctx.await_frame()
	var weapon := player.get_node_or_null("WeaponController")
	var hitbox_node: Node = null
	if weapon:
		var hitbox_path: NodePath = weapon.get("hitbox_path")
		if hitbox_path != NodePath():
			hitbox_node = weapon.get_node_or_null(hitbox_path)
	var wired: bool = hitbox_node != null and hitbox_node.has_method("enable")
	ctx.timed_record(
		"combat.weapon_hitbox_wiring",
		get_category(),
		wired,
		"WeaponController hitbox path resolves to Hitbox",
		start,
		"M1.combat.weapon"
	)

	start = Time.get_ticks_msec()
	var facing_node := player.get_node_or_null("Facing") as Node3D
	var hitbox_shape := (
		player.get_node_or_null("Facing/WeaponPivot/Hitbox/CollisionShape3D") as CollisionShape3D
	)
	var forward_hitbox := false
	if facing_node and hitbox_shape:
		var visual_forward := facing_node.global_transform.basis.z
		var to_hitbox := hitbox_shape.global_position - facing_node.global_position
		forward_hitbox = visual_forward.dot(to_hitbox) > 0.1
	ctx.timed_record(
		"combat.player_hitbox_forward",
		get_category(),
		forward_hitbox,
		"player weapon hitbox extends along visual forward (+Facing Z)",
		start,
		"M1.combat.weapon"
	)
	player.queue_free()


func _test_combat_pipeline() -> void:
	var fixture := CombatFixtureScript.new(ctx)
	await fixture.setup()
	var start := Time.get_ticks_msec()

	var result := await fixture.strike({"damage": 12.0})
	ctx.assert_near(
		"combat.damage_reaches_health",
		get_category(),
		float(result.get("hp_lost", 0.0)),
		12.0,
		0.001,
		"strike damage reaches defender health",
		start,
		"M1.combat.pipeline"
	)

	start = Time.get_ticks_msec()
	result = await fixture.strike({"damage": 12.0, "team": "enemy"})
	ctx.assert_near(
		"combat.team_filter_blocks_friendly",
		get_category(),
		float(result.get("hp_lost", -1.0)),
		0.0,
		0.001,
		"same-team hitbox does not damage defender",
		start,
		"M1.combat.teams"
	)

	start = Time.get_ticks_msec()
	fixture.attacker_hitbox().team = "player"
	fixture.defender_hurtbox().team = "enemy"
	result = await fixture.strike({"damage": 12.0, "team": "player"})
	ctx.assert_near(
		"combat.team_filter_allows_hostile",
		get_category(),
		float(result.get("hp_lost", 0.0)),
		12.0,
		0.001,
		"hostile teams allow damage",
		start,
		"M1.combat.teams"
	)

	fixture.defender_health().configure(60.0)
	fixture.defender_body().set_meta("combat_defense", 20)
	start = Time.get_ticks_msec()
	result = await fixture.strike({"damage": 30.0})
	var expected_defense := 30.0 * (1.0 - clampf(20.0 * 0.02, 0.0, 0.9))
	ctx.assert_near(
		"combat.defense_reduces_damage",
		get_category(),
		float(result.get("hp_lost", 0.0)),
		expected_defense,
		0.001,
		"combat_defense meta reduces incoming damage",
		start,
		"M1.combat.pipeline"
	)

	fixture.defender_health().configure(60.0)
	fixture.defender_body().set_meta("combat_defense", 0)
	var dodge := await fixture.add_dodge_to_defender()
	dodge.iframes_active = true
	start = Time.get_ticks_msec()
	result = await fixture.strike({"damage": 40.0})
	ctx.assert_near(
		"combat.iframes_block_all_damage",
		get_category(),
		float(result.get("hp_lost", -1.0)),
		0.0,
		0.001,
		"active dodge iframes block damage",
		start,
		"M1.combat.dodge"
	)
	dodge.iframes_active = false

	fixture.defender_health().configure(60.0)
	start = Time.get_ticks_msec()
	result = await fixture.strike({"damage": 10.0, "crit_chance": 1.0})
	ctx.assert_true(
		"combat.crit_applies_multiplier",
		get_category(),
		float(result.get("hp_lost", 0.0)) > 10.0,
		"guaranteed crit increases damage",
		start,
		"M1.combat.pipeline"
	)

	fixture.defender_health().configure(60.0)
	var status_ctrl := await fixture.add_status_controller_to_defender()
	await fixture.strike({"damage": 1.0, "status_id": "bleed", "status_stacks": 1})
	start = Time.get_ticks_msec()
	var has_bleed := false
	for entry in status_ctrl.get_active_statuses():
		if entry.get("id", "") == "bleed":
			has_bleed = true
			break
	var bleed_build_up := 0.0
	for meter in status_ctrl.get_build_up_meters():
		if str(meter.get("id", "")) == "bleed":
			bleed_build_up = float(meter.get("value", 0.0))
			break
	ctx.assert_true(
		"combat.status_lands_on_enemy",
		get_category(),
		has_bleed or bleed_build_up > 0.0,
		"status from hitbox reaches defender StatusController",
		start,
		"M1.combat.status"
	)

	fixture.defender_health().take_damage(fixture.defender_health().max_health + 10.0)
	start = Time.get_ticks_msec()
	result = await fixture.strike({"damage": 20.0})
	ctx.assert_near(
		"combat.dead_target_absorbs_nothing",
		get_category(),
		float(result.get("hp_lost", -1.0)),
		0.0,
		0.001,
		"dead defender ignores further hits",
		start,
		"M2.combat.death"
	)

	await fixture.teardown()


func _test_guard_and_dodge() -> void:
	var fixture := CombatFixtureScript.new(ctx)
	await fixture.setup()
	var guard := await fixture.add_guard_to_defender()
	var stamina := fixture.defender_body().get_node("Stamina") as Stamina
	stamina.configure(100.0)
	fixture.defender_health().configure(60.0)
	guard.is_guard_active = true

	# The arc gate reads the attacker's *position*, not the hit direction, so these cases have to
	# place a real attacker. Passing the defender as its own source made the offset zero, which
	# DamageInfo.classify_arc treats as FRONT unconditionally — so the "rear hit" case below was
	# not testing a rear hit at all, and asserted a number the code could not produce.
	# Forward is +Z (see CombatFacing), so an attacker at +Z is in front of the defender.
	var attacker := fixture.attacker_body()
	fixture.place(Vector3(0.0, 0.0, 1.2), Vector3(0.0, 0.0, 0.0))
	var start := Time.get_ticks_msec()
	var info := DamageInfo.create(
		30.0, 10.0, attacker, DamageInfo.TYPE_PHYSICAL, Vector3(0.0, 0.0, -1.0)
	)
	fixture.direct_hit(info)
	var chip := fixture.hp_lost()
	var expected_chip := 30.0 * (1.0 - 0.55)
	ctx.assert_near(
		"guard.block_reduces_damage",
		get_category(),
		chip,
		expected_chip,
		0.001,
		"frontal block reduces incoming damage",
		start,
		"M1.combat.guard"
	)

	# Attacker moved behind the defender: the guard must not apply, and the hit takes the
	# backstab arc multiplier it has earned.
	fixture.place(Vector3(0.0, 0.0, -1.2), Vector3(0.0, 0.0, 0.0))
	fixture.defender_health().configure(60.0)
	guard.is_guard_active = true
	start = Time.get_ticks_msec()
	info = DamageInfo.create(
		30.0, 10.0, attacker, DamageInfo.TYPE_PHYSICAL, Vector3(0.0, 0.0, 1.0)
	)
	fixture.direct_hit(info)
	ctx.assert_near(
		"guard.block_requires_frontal",
		get_category(),
		fixture.hp_lost(),
		30.0 * DamageInfo.BACKSTAB_DAMAGE_MULT,
		0.001,
		"rear hit bypasses guard reduction",
		start,
		"M1.combat.guard"
	)

	# A parry from behind used to succeed, because the arc was computed and then never consulted.
	fixture.defender_health().configure(60.0)
	guard.is_guard_active = true
	guard.parry_window_active = true
	start = Time.get_ticks_msec()
	var rear_parry: bool = guard.try_parry_attack(attacker, DamageInfo.HitArc.BACK)
	ctx.timed_record(
		"guard.parry_requires_frontal",
		get_category(),
		not rear_parry,
		"parry is refused for a non-frontal attacker",
		start,
		"M1.combat.guard"
	)

	stamina.configure(100.0)
	guard.is_guard_active = true
	var stamina_before := stamina.current
	start = Time.get_ticks_msec()
	info = DamageInfo.create(
		30.0, 10.0, fixture.defender_body(), DamageInfo.TYPE_PHYSICAL, Vector3(0.0, 0.0, -1.0)
	)
	fixture.direct_hit(info)
	ctx.assert_true(
		"guard.block_costs_stamina",
		get_category(),
		stamina.current < stamina_before,
		"blocking consumes stamina",
		start,
		"M1.combat.guard"
	)

	await fixture.teardown()

	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	await ctx.await_physics(2)
	var player_stamina := player.get_node("Stamina") as Stamina
	var player_dodge := player.get_node("Dodge")
	player_stamina.configure(100.0)
	player_dodge.call("configure", {}, "medium")
	start = Time.get_ticks_msec()
	var before_dodge := player_stamina.current
	player_dodge.call("_start_dash")
	var dodge_delta := before_dodge - player_stamina.current
	ctx.assert_near(
		"dodge.stamina_deducted",
		get_category(),
		dodge_delta,
		float(player_dodge.get("DODGE_STAMINA_COST")),
		0.001,
		"dodge entry deducts authored stamina cost",
		start,
		"M1.combat.dodge"
	)
	player.queue_free()


func _spawn_test_player() -> CharacterBody3D:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	player.global_position = Vector3.ZERO
	return player


func _wait_until(condition: Callable, max_frames: int = 90) -> bool:
	for _i in max_frames:
		if condition.call():
			return true
		await ctx.await_physics()
	return false


func _wait_until_idle(weapon: Node, max_frames: int = 120) -> void:
	for _i in max_frames:
		if not weapon.is_attacking:
			return
		await ctx.await_physics()


func _test_weapon_attacks() -> void:
	var player := _spawn_test_player()
	await ctx.await_physics(2)
	var weapon := player.get_node("WeaponController")
	var stamina := player.get_node("Stamina") as Stamina
	var hitbox := weapon.get_hitbox() as Hitbox
	stamina.configure(100.0)

	var start := Time.get_ticks_msec()
	weapon.request_light_attack()
	var hitbox_activated := await _wait_until(func() -> bool: return hitbox.is_active())
	var hitbox_deactivates := true
	if hitbox_activated:
		hitbox_deactivates = await _wait_until(func() -> bool: return not hitbox.is_active(), 90)
	ctx.assert_true(
		"weapon.light_attack_enables_hitbox",
		get_category(),
		hitbox_activated and hitbox_deactivates,
		"light attack enables hitbox during active window",
		start,
		"M1.combat.weapon"
	)
	await _wait_until_idle(weapon)

	weapon.load_weapon_from_path("content/weapons/greatsword.json")
	stamina.configure(100.0)
	weapon.request_light_attack()
	await _wait_until(func() -> bool: return weapon.is_attacking)
	var first_combo: int = weapon.get_combo_index()
	await _wait_until_idle(weapon)
	stamina.configure(100.0)
	weapon.request_light_attack()
	await _wait_until(func() -> bool: return weapon.is_attacking)
	start = Time.get_ticks_msec()
	var second_combo: int = weapon.get_combo_index()
	ctx.assert_true(
		"weapon.combo_advances",
		get_category(),
		first_combo == 0 and second_combo == 1,
		"second attack in chain window uses combo index 1",
		start,
		"M1.combat.weapon"
	)
	await _wait_until_idle(weapon)

	stamina.configure(100.0)
	weapon.request_light_attack()
	await _wait_until_idle(weapon)
	for _i in 40:
		await ctx.await_physics()
	stamina.configure(100.0)
	weapon.request_light_attack()
	await _wait_until(func() -> bool: return weapon.is_attacking)
	start = Time.get_ticks_msec()
	var reset_combo: int = weapon.get_combo_index()
	ctx.assert_eq(
		"weapon.combo_resets",
		get_category(),
		reset_combo,
		0,
		"attack after chain window expires resets combo index",
		start,
		"M1.combat.weapon"
	)
	await _wait_until_idle(weapon)

	stamina.configure(1.0)
	start = Time.get_ticks_msec()
	var refused_stamina: bool = not weapon.request_light_attack() and not hitbox.is_active()
	ctx.assert_true(
		"weapon.attack_refused_without_stamina",
		get_category(),
		refused_stamina,
		"attack refused when stamina is below cost",
		start,
		"M1.combat.weapon"
	)

	var status_ctrl := StatusController.new()
	player.add_child(status_ctrl)
	await ctx.await_physics(1)
	status_ctrl.apply_status("stun", 1)
	stamina.configure(100.0)
	start = Time.get_ticks_msec()
	var refused_stun: bool = not weapon.request_light_attack() and not hitbox.is_active()
	ctx.assert_true(
		"weapon.attack_refused_while_stunned",
		get_category(),
		refused_stun,
		"attack refused while stunned",
		start,
		"M1.combat.status"
	)
	status_ctrl.queue_free()

	stamina.configure(100.0)
	weapon.load_weapon_from_path("content/weapons/greatsword.json")
	weapon.set_damage_multiplier(1.0)
	weapon.request_light_attack()
	await _wait_until(func() -> bool: return hitbox.is_active())
	var weapon_data: Dictionary = weapon.get_weapon_data()
	var expected_damage: float = float(weapon_data.get("light_attacks", [{}])[0].get("damage", 0.0))
	start = Time.get_ticks_msec()
	ctx.assert_near(
		"weapon.json_values_reach_hitbox",
		get_category(),
		hitbox.damage_amount,
		expected_damage,
		0.001,
		"equipped weapon JSON damage reaches hitbox",
		start,
		"M1.combat.weapon"
	)
	await _wait_until_idle(weapon)

	stamina.configure(100.0)
	var lunge_distance: float = float(weapon_data.get("lunge_distance", 0.0))
	var start_pos := player.global_position
	weapon.request_light_attack()
	var max_lunge := 0.0
	for _i in 30:
		if weapon.is_attacking:
			var delta_xz := (
				Vector2(
					player.global_position.x - start_pos.x, player.global_position.z - start_pos.z
				)
				. length()
			)
			max_lunge = maxf(max_lunge, delta_xz)
		await ctx.await_physics()
	start = Time.get_ticks_msec()
	var min_expected := lunge_distance * 0.7
	ctx.assert_true(
		"weapon.lunge_moves_the_body",
		get_category(),
		max_lunge >= min_expected,
		"attack lunge moves body at least 70 percent of authored distance",
		start,
		"M1.combat.weapon"
	)
	await _wait_until_idle(weapon)

	stamina.configure(100.0)
	weapon.load_weapon_from_path("content/weapons/greatsword.json")
	start = Time.get_ticks_msec()
	weapon.request_weapon_art()
	var art_started := await _wait_until(func() -> bool: return hitbox.is_active())
	ctx.assert_true(
		"weapon.art_input_produces_an_attack",
		get_category(),
		art_started,
		"weapon art activates hitbox with authored attack",
		start,
		"M1.combat.weapon"
	)
	await _wait_until_idle(weapon)
	player.queue_free()


func _test_hit_feedback_and_tokens() -> void:
	var fixture := CombatFixtureScript.new(ctx)
	await fixture.setup()
	await fixture.add_hit_feedback_to_defender()
	var guard := await fixture.add_guard_to_defender()
	var stamina := fixture.defender_body().get_node("Stamina") as Stamina
	stamina.configure(100.0)
	fixture.defender_health().configure(60.0)
	guard.is_guard_active = true

	var info := DamageInfo.create(
		30.0,
		10.0,
		fixture.attacker_hitbox().get_parent(),
		DamageInfo.TYPE_PHYSICAL,
		Vector3(0.0, 0.0, -1.0)
	)
	fixture.direct_hit(info)
	await ctx.await_frame()
	var start := Time.get_ticks_msec()
	ctx.assert_eq(
		"feedback.one_label_per_hit",
		get_category(),
		fixture.labels().size(),
		1,
		"blocked hit spawns exactly one damage label",
		start,
		"M1.combat.feedback"
	)

	fixture.defender_health().configure(60.0)
	guard.is_guard_active = false
	await fixture.strike({"damage": 15.0})
	var hp_lost := fixture.hp_lost()
	var spawned := fixture.labels()
	var label_matches := false
	if spawned.size() > 0:
		label_matches = fixture.label_amount(spawned[0]) == int(round(hp_lost))
	start = Time.get_ticks_msec()
	ctx.assert_true(
		"feedback.label_matches_hp_lost",
		get_category(),
		label_matches,
		"damage label text matches health lost",
		start,
		"M1.combat.feedback"
	)

	var dodge := await fixture.add_dodge_to_defender()
	dodge.iframes_active = true
	fixture.defender_health().configure(60.0)
	await fixture.strike({"damage": 20.0})
	start = Time.get_ticks_msec()
	ctx.assert_true(
		"feedback.dodge_produces_a_cue",
		get_category(),
		fixture.last_cue() != "",
		"iframe dodge produces a combat audio cue",
		start,
		"M1.combat.feedback"
	)
	dodge.iframes_active = false

	var hit_feedback := fixture.defender_body().get_node("HitFeedback")
	var low_stop: float = hit_feedback.preview_hitstop_duration(12.0)
	var high_stop: float = hit_feedback.preview_hitstop_duration(48.0)
	start = Time.get_ticks_msec()
	ctx.assert_true(
		"feedback.hitstop_scales_with_damage",
		get_category(),
		high_stop > low_stop,
		"hitstop duration scales with damage dealt",
		start,
		"M1.combat.feedback"
	)

	await fixture.teardown()

	if AttackTokenService:
		AttackTokenService.reset_all()
		var group_id := "validation_token_group"
		var max_tokens := 2
		var granted := 0
		for _i in 6:
			if AttackTokenService.request_token(group_id, max_tokens):
				granted += 1
		start = Time.get_ticks_msec()
		ctx.assert_eq(
			"tokens.concurrent_attackers_capped",
			get_category(),
			granted,
			max_tokens,
			"attack tokens cap concurrent holders",
			start,
			"M1.combat.tokens"
		)

		AttackTokenService.reset_all()
		var acquired := AttackTokenService.request_token(group_id, 1)
		var blocked := not AttackTokenService.request_token(group_id, 1)
		AttackTokenService.release_token(group_id)
		var reacquired := AttackTokenService.request_token(group_id, 1)
		start = Time.get_ticks_msec()
		ctx.assert_true(
			"tokens.released_on_death",
			get_category(),
			acquired and blocked and reacquired,
			"releasing a token restores available capacity",
			start,
			"M1.combat.tokens"
		)


## The single most important invariant in the game: a committed swing cannot follow a dodge.
##
## Enemies used to re-aim at ENEMY_TURN_SPEED through the entire wind-up and the whole active
## window, while also walking at the player, which made rolling — the defining verb of the
## genre — do nothing. A regression here is invisible in every other test and fatal to the feel,
## so it is asserted directly on the state machine rather than inferred from an outcome.
func _test_enemy_attack_commitment() -> void:
	var scene: PackedScene = EnemyCatalog.get_scene("castle_grunt")
	var start := Time.get_ticks_msec()
	if scene == null:
		ctx.timed_record(
			"enemy.attack_commitment",
			get_category(),
			false,
			"could not load castle_grunt scene",
			start,
			"M2.combat.commitment"
		)
		return
	var enemy: CharacterBody3D = scene.instantiate() as CharacterBody3D
	ctx.owner.add_child(enemy)
	await ctx.await_physics(2)

	# Active frames: no re-aim, and no pursuit unless the attack authors a lunge.
	enemy.set("_state", CastleEnemyBase.State.ATTACK)
	enemy.set("_current_attack_data", {})
	var attack_tracking: float = enemy.call("_tracking_speed_multiplier")
	enemy.call("_apply_attack_lunge")
	# Horizontal only: velocity.y carries whatever gravity accumulated over the frames above.
	var attack_velocity := Vector2(enemy.velocity.x, enemy.velocity.z)

	# Wind-up: re-aim is allowed early and locked once past the commit fraction.
	enemy.set("_state", CastleEnemyBase.State.WINDUP)
	enemy.set("_windup_duration", 1.0)
	enemy.set("_state_timer", 1.0)
	var early_tracking: float = enemy.call("_tracking_speed_multiplier")
	enemy.set("_state_timer", 0.05)
	var committed_tracking: float = enemy.call("_tracking_speed_multiplier")

	var ok: bool = (
		is_zero_approx(attack_tracking)
		and attack_velocity.length_squared() < 0.0001
		and early_tracking > 0.0
		and is_zero_approx(committed_tracking)
	)
	ctx.timed_record(
		"enemy.attack_commitment",
		get_category(),
		ok,
		"swing heading locks at the commit point and does not pursue during active frames",
		start,
		"M2.combat.commitment"
	)
	enemy.queue_free()
	await ctx.await_frame()


func _test_enemy_death_guards() -> void:
	var scene: PackedScene = EnemyCatalog.get_scene("castle_shield")
	if scene == null:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"enemy.shield_death_guard",
			get_category(),
			false,
			"could not load shield scene",
			start,
			"M2.combat.death"
		)
		return

	var enemy: CharacterBody3D = scene.instantiate() as CharacterBody3D
	ctx.owner.add_child(enemy)
	await ctx.await_physics(2)

	var health := enemy.get_node_or_null("Health") as Health
	var hitbox := enemy.find_child("Hitbox", true, false) as Hitbox
	if health == null:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"enemy.shield_death_guard",
			get_category(),
			false,
			"shield missing Health node",
			start,
			"M2.combat.death"
		)
		enemy.queue_free()
		return

	health.take_damage(health.max_health + 10.0)
	await ctx.await_physics()

	var start := Time.get_ticks_msec()
	var dead_after_kill: bool = enemy.is_dead() and health.is_dead()
	ctx.timed_record(
		"enemy.dies_at_zero_hp",
		get_category(),
		dead_after_kill,
		"shield dies when HP reaches 0",
		start,
		"M2.combat.death"
	)

	if dead_after_kill and enemy.has_method("apply_stagger"):
		enemy.call("apply_stagger", 1.0)
		await ctx.await_physics()
		start = Time.get_ticks_msec()
		var still_dead: bool = enemy.is_dead() and health.is_dead()
		ctx.timed_record(
			"enemy.no_stagger_revive",
			get_category(),
			still_dead,
			"stagger does not revive dead shield-bearer",
			start,
			"M2.combat.death"
		)
		if hitbox:
			start = Time.get_ticks_msec()
			ctx.timed_record(
				"enemy.hitbox_disabled_on_death",
				get_category(),
				not hitbox.is_active(),
				"enemy hitbox disabled after death",
				start,
				"M2.combat.death"
			)

	enemy.queue_free()


func _test_waves_run() -> void:
	var start := Time.get_ticks_msec()
	var captain_seed := -1
	for seed in 1_000:
		WavesRunService.restore_from_save(
			{
				"currentWave": 5,
				"prepActive": false,
				"lobbyReady": true,
				"killCount": 0,
				"seed": seed,
				"chestsOpened": {},
				"wavesInventory": {},
			}
		)
		var enemies: Array = WavesRunService.get_enemies_for_wave(5)
		if "miniboss_castle_captain" in enemies:
			captain_seed = seed
			break
	var captain_spawn_ok := captain_seed > 0
	ctx.timed_record(
		"wav.spawn.milestone_captain",
		get_category(),
		captain_spawn_ok,
		"milestone wave can roll miniboss_castle_captain into spawn list",
		start,
		"WAV-03"
	)

	start = Time.get_ticks_msec()
	WavesRunService.begin_new_run()
	WavesRunService.lobby_ready = true
	WavesRunService.start_waves()
	for _i in 4:
		WavesRunService.advance_wave()
	var prep_ok := (
		WavesRunService.current_wave == 5 and not WavesRunService.prep_active
	)
	ctx.timed_record(
		"wav.prep.flag_only_during_countdown",
		get_category(),
		prep_ok,
		"advancing into milestone combat does not set prep_active",
		start,
		"WAV-04"
	)

	start = Time.get_ticks_msec()
	WavesRunService.restore_from_save(
		{
			"currentWave": 0,
			"prepActive": false,
			"lobbyReady": false,
			"killCount": 0,
			"seed": captain_seed if captain_seed > 0 else 42,
			"chestsOpened": {},
			"wavesInventory": {},
		}
	)
	var wave_10: Array = WavesRunService.get_enemies_for_wave(10)
	var roster_count := mini(2 + (10 >> 1), 12) + 2
	var count_ok := wave_10.size() == roster_count + 1
	ctx.timed_record(
		"wav.content.formula",
		get_category(),
		count_ok,
		"wave 10 enemy count matches JSON-driven formula + milestone boss",
		start,
		"WAV-06"
	)

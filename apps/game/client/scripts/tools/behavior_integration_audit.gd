extends Node

## Cross-service acceptance checks that schema validation cannot express. Keep each assertion tied
## to a player-visible invariant so this is an integration gate, not a second content linter.

const ForgeServiceScript := preload("res://scripts/items/forge_service.gd")
const ConsumableServiceScript := preload("res://scripts/inventory/consumable_service.gd")
const HazardTrapScript := preload("res://scripts/dungeon/traps/hazard_trap.gd")
const CombatEventsScript := preload("res://scripts/combat/combat_events.gd")

var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_check_forge_instance_identity()
	await _check_weapon_art_behavior()
	await _check_consumable_commitment()
	await _check_pause_clock_behavior()
	_check_ranked_eligibility()
	_check_hitstop_budget()
	_check_footstep_effect_contract()
	await _check_content_behavior_archetypes()
	await _check_toad_leap_behavior()
	await _check_slime_space_behavior()
	await _check_leech_grab_behavior()
	print("BEHAVIOR INTEGRATION RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_forge_instance_identity() -> void:
	var inventory := GridInventory.new()
	_check(
		inventory.add_item("iron_sword", 1, {"instanceId": "audit-forge-a", "upgradeLevel": 2}),
		"forge fixture adds source weapon"
	)
	_check(
		inventory.add_item("iron_sword", 1, {"instanceId": "audit-forge-b", "upgradeLevel": 0}),
		"forge fixture adds adjacent same-item weapon"
	)
	var result := ForgeServiceScript.salvage_instance(inventory, "audit-forge-a")
	_check(bool(result.get("ok", false)), "salvaging selected instance succeeds")
	_check(
		inventory.find_instance_index("audit-forge-a") < 0,
		"forge removes exactly the selected instance"
	)
	_check(
		inventory.find_instance_index("audit-forge-b") >= 0,
		"forge preserves an adjacent same-item instance"
	)
	var restored := GridInventory.new()
	restored.from_save_dict(inventory.to_save_dict())
	_check(
		restored.find_instance_index("audit-forge-b") >= 0,
		"surviving forge target identity persists through inventory save/load"
	)


func _check_weapon_art_behavior() -> void:
	var body := CharacterBody3D.new()
	var stamina := Stamina.new()
	stamina.name = "Stamina"
	var weapon := WeaponController.new()
	weapon.name = "WeaponController"
	body.add_child(stamina)
	body.add_child(weapon)
	add_child(body)
	await get_tree().process_frame
	stamina.current = stamina.max_stamina
	weapon.set("_weapon_data", {
		"archetype": "axe",
		"art": {
			"behavior": "guard_break",
			"stamina_cost": 20.0,
			"damage": 18.0,
			"poise_damage": 20.0,
			"guard_break_mult": 2.0,
			"startup": 0.1,
			"active": 0.1,
			"recovery": 0.1,
		},
	})
	weapon.call("_try_weapon_art")
	var attack: Dictionary = weapon.get("_current_attack") as Dictionary
	_check(weapon.is_attacking, "weapon art enters the attack state")
	_check(
		float(attack.get("poise_damage", 0.0)) > 20.0,
		"guard-break art applies its distinct poise behavior"
	)
	_check(
		float(weapon.get("_art_cooldown_timer")) > 0.0,
		"successful weapon art starts its own cooldown"
	)
	body.queue_free()


func _check_consumable_commitment() -> void:
	var body := CharacterBody3D.new()
	var health := Health.new()
	var mana := Mana.new()
	var stamina := Stamina.new()
	var heal := PlayerHeal.new()
	var weapon := WeaponController.new()
	var dodge := Dodge.new()
	var guard := Guard.new()
	health.name = "Health"
	mana.name = "Mana"
	stamina.name = "Stamina"
	heal.name = "PlayerHeal"
	weapon.name = "WeaponController"
	dodge.name = "Dodge"
	guard.name = "Guard"
	for component in [health, mana, stamina, heal, weapon, dodge, guard]:
		body.add_child(component)
	add_child(body)
	await get_tree().process_frame

	var mana_tonic := {"consumableEffect": {"kind": "restoreMana", "amount": 30.0}}
	mana.current = mana.max_mana
	_check(
		not ConsumableServiceScript.apply(mana_tonic, body),
		"a full resource rejects a zero-effect consumable"
	)
	mana.current = 5.0
	_check(
		ConsumableServiceScript.apply(mana_tonic, body) and mana.current > 5.0,
		"a depleted resource consumes a meaningful restoration"
	)
	weapon.is_attacking = true
	_check(not ConsumableServiceScript.can_commit(body), "consumables cannot overlap an attack")
	weapon.is_attacking = false
	dodge.is_dodging = true
	_check(not ConsumableServiceScript.can_commit(body), "consumables cannot overlap a dodge")
	dodge.is_dodging = false
	heal.is_drinking = true
	_check(not ConsumableServiceScript.can_commit(body), "consumables cannot overlap flask recovery")
	heal.is_drinking = false
	_check(ConsumableServiceScript.can_commit(body), "consumables become available after recovery")
	body.queue_free()


func _check_pause_clock_behavior() -> void:
	var original_scale := Engine.time_scale
	VfxService.push_time_scale(&"behavior_audit_pause", 0.25, 25)
	_check(is_equal_approx(Engine.time_scale, 0.25), "hitstop request applies its scale")
	get_tree().paused = true
	var deadline := Time.get_ticks_msec() + 80
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(
		is_equal_approx(Engine.time_scale, 1.0),
		"wall-clock hitstop cleanup runs while the game is paused"
	)
	get_tree().paused = false
	Engine.time_scale = original_scale


func _check_ranked_eligibility() -> void:
	# The client may request ranked submission only for an opted-in, standard castle escape after
	# its boss.  The server remains authoritative, but this prevents obviously incomparable runs
	# from entering the submission/outbox path in the first place.
	var old_mode := RunFlow.run_mode
	var old_alternate := str(RunFlow.get("_active_alternate_mode"))
	var old_meta := LocalSave.get_meta_data().duplicate(true)
	RunFlow.run_mode = "castle"
	RunFlow.set("_active_alternate_mode", "")
	LocalSave.set_meta_data({"leaderboard": {"opt_in": true}})
	_check(
		bool(RunFlow.call("_should_submit_ranked", RunLifecycle.OUTCOME_ESCAPED, true)),
		"an opted-in standard boss escape is eligible for ranked submission"
	)
	_check(
		not bool(RunFlow.call("_should_submit_ranked", RunLifecycle.OUTCOME_DIED, true)),
		"a death is never eligible for ranked submission"
	)
	RunFlow.set("_active_alternate_mode", "ironman")
	_check(
		not bool(RunFlow.call("_should_submit_ranked", RunLifecycle.OUTCOME_ESCAPED, true)),
		"alternate-mode runs are excluded from the standard ranked board"
	)
	RunFlow.set("_active_alternate_mode", "")
	LocalSave.set_meta_data({"leaderboard": {"opt_in": false}})
	_check(
		not bool(RunFlow.call("_should_submit_ranked", RunLifecycle.OUTCOME_ESCAPED, true)),
		"ranked submission requires explicit player opt-in"
	)
	LocalSave.set_meta_data(old_meta)
	RunFlow.run_mode = old_mode
	RunFlow.set("_active_alternate_mode", old_alternate)


func _check_hitstop_budget() -> void:
	var original_intensity := AccessibilitySettings.hitstop_intensity
	var original_enabled := PixelDioramaSettings.hitstop_enabled
	var token := StringName("vfx_hitstop:behavior_audit_root_attack")
	AccessibilitySettings.set_hitstop_intensity(0.5)
	PixelDioramaSettings.hitstop_enabled = true
	VfxService.request_attack_hitstop("behavior_audit_root_attack", 80, 0.08)
	var requests: Dictionary = VfxService.get("_time_scale_requests") as Dictionary
	var request: Dictionary = requests.get(token, {}) as Dictionary
	_check(
		request.size() == 2
		and int(request.get("until_ms", 0)) > Time.get_ticks_msec()
		and is_equal_approx(float(request.get("scale", 1.0)), 0.54),
		"fractional hitstop accessibility scales both duration and slowdown strength"
	)
	VfxService.request_attack_hitstop("behavior_audit_root_attack", 80, 0.08)
	requests = VfxService.get("_time_scale_requests") as Dictionary
	_check(
		requests.has(token) and requests.keys().filter(func(id: Variant) -> bool: return id == token).size() == 1,
		"multiple victims from one root attack share one global hitstop budget"
	)
	VfxService.request_attack_hitstop("behavior_audit_rapid_combo", 2000, 0.08)
	requests = VfxService.get("_time_scale_requests") as Dictionary
	var combo_request: Dictionary = requests.get(StringName("vfx_hitstop:behavior_audit_rapid_combo"), {}) as Dictionary
	_check(
		int(combo_request.get("until_ms", 0)) <= Time.get_ticks_msec() + 180,
		"rapid follow-up attacks cannot extend aggregate global hitstop beyond its responsiveness budget"
	)
	VfxService.release_time_scale(token)
	VfxService.release_time_scale(&"vfx_hitstop:behavior_audit_rapid_combo")
	AccessibilitySettings.set_hitstop_intensity(original_intensity)
	PixelDioramaSettings.hitstop_enabled = original_enabled


func _check_footstep_effect_contract() -> void:
	var effects: Dictionary = VfxService.get("_effects") as Dictionary
	var stone: Dictionary = ((effects.get("footstep", {}) as Dictionary).get("layers", []) as Array)[0] as Dictionary
	var wood: Dictionary = ((effects.get("footstep_wood", {}) as Dictionary).get("layers", []) as Array)[0] as Dictionary
	var water: Dictionary = ((effects.get("footstep_water", {}) as Dictionary).get("layers", []) as Array)[0] as Dictionary
	var snow: Dictionary = ((effects.get("footstep_snow", {}) as Dictionary).get("layers", []) as Array)[0] as Dictionary
	_check(
		str(stone.get("chunk", "")) != str(wood.get("chunk", ""))
		and str(water.get("chunk", "")) != str(snow.get("chunk", ""))
		and int(stone.get("amount", 0)) > int(snow.get("amount", 0)),
		"footstep surfaces use distinct restrained dust, chips, splash, and snow profiles"
	)


func _check_content_behavior_archetypes() -> void:
	# Each trigger family is instantiated from its actual content definition. This exercises the
	# same setup path a generated room uses rather than merely checking the enum in JSON.
	var trigger_ids := {
		"proximity": "spike_trap",
		"plate": "bone_snare",
		"cycle": "gas_vent",
		"lure": "rot_censer",
	}
	for trigger in trigger_ids:
		var hazard := HazardTrapScript.new()
		hazard.trap_id = str(trigger_ids[trigger])
		add_child(hazard)
		await get_tree().process_frame
		_check(
			str(hazard.get("_trigger")) == str(trigger)
			and hazard.get("_area") is Area3D,
			"%s trap content configures a live hazard volume" % trigger
		)
		hazard.queue_free()
	var enemy := CastleEnemyBase.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	enemy.add_child(mesh)
	var body_collision := CollisionShape3D.new()
	body_collision.name = "CollisionShape3D"
	body_collision.shape = CapsuleShape3D.new()
	enemy.add_child(body_collision)
	enemy.set_catalog_id("castle_archer")
	add_child(enemy)
	await get_tree().process_frame
	var enemy_data: Dictionary = enemy.get("_data") as Dictionary
	var attacks: Array = enemy_data.get("attacks", []) as Array
	_check(
		not attacks.is_empty()
		and bool((attacks[0] as Dictionary).get("no_hitbox", false))
		and float(enemy.call("_derived_telegraph_radius", "line")) > 0.0,
		"authored enemy attacks load through the live enemy runtime with readable telegraph geometry"
	)
	enemy.queue_free()

	# Register every authored relic rule with the live event bus. A schema-valid event/effect that
	# the dispatcher cannot accept is therefore a failing executable contract, not dead content.
	var events: Node = CombatEventsScript.new()
	add_child(events)
	await get_tree().process_frame
	var registered_sources := 0
	for relic_id in RelicCatalog.get_all_ids():
		var definition := RelicCatalog.get_definition(relic_id)
		var rules: Array = definition.get("rules", []) as Array
		if rules.is_empty():
			continue
		events.register("audit:%s" % relic_id, rules)
		registered_sources += 1
	_check(
		(events.get("_sources") as Dictionary).size() == registered_sources,
		"every authored relic rule is accepted by the live combat-event dispatcher"
	)
	events.queue_free()

	# Resolve an authored room variant through the production catalog and ensure its authored props
	# and anchors survive the data boundary used by generation/dressing.
	RoomLayoutCatalog.clear_cache()
	var variant := RoomLayoutCatalog.variant_for_room(
		"forgotten_castle", 424242, "content-audit-room", "castle_courtyard"
	)
	var data := RoomLayoutCatalog.variant_data_for("forgotten_castle", "castle_courtyard", variant)
	_check(
		variant > 0
		and not data.is_empty()
		and not RoomLayoutCatalog.anchors_for("forgotten_castle", "castle_courtyard", "enemy", variant).is_empty(),
		"authored room variants resolve through the generation layout catalog"
	)
	var normal := Vector3(0.0, 0.7071068, 0.7071068)
	VfxService.play_footstep(Vector3.ZERO, Vector3.FORWARD, &"stone", normal)
	var pool: Array = VfxService.get("_burst_pool") as Array
	var active: CPUParticles3D = null
	for candidate in pool:
		if candidate is CPUParticles3D and (candidate as CPUParticles3D).emitting:
			active = candidate as CPUParticles3D
			break
	_check(
		active != null
		and active.direction.dot(normal) > 0.99
		and active.material_override is StandardMaterial3D
		and (active.material_override as StandardMaterial3D).billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED,
		"footstep flakes follow the sampled ground normal and face the camera"
	)
	VfxService.play_footstep(Vector3.ZERO, Vector3.FORWARD, &"water", normal)
	var decals: Array = VfxService.get("_decal_pool") as Array
	var ripple: Decal = null
	for candidate in decals:
		if candidate is Decal and (candidate as Decal).visible:
			ripple = candidate as Decal
			break
	_check(
		ripple != null
		and is_equal_approx(ripple.global_position.dot(normal), 0.02)
		and ripple.global_basis.y.dot(normal) > 0.99
		and ripple.modulate.is_equal_approx(Color("6b9ed1")),
		"water footsteps create a tinted, ground-aligned ripple"
	)


func _check_toad_leap_behavior() -> void:
	var player := Node3D.new()
	player.position = Vector3(0.0, 0.0, 5.5)
	add_child(player)
	var scene := load("res://scenes/enemies/swamp_toad.tscn") as PackedScene
	var toad := scene.instantiate() as CastleEnemyBase if scene != null else null
	_check(toad != null, "swamp toad production scene instantiates for leap behavior audit")
	if toad == null:
		player.queue_free()
		return
	toad.set_player(player)
	add_child(toad)
	await get_tree().process_frame
	var started := bool(toad.call("_try_leap_attack"))
	var attack: Dictionary = toad.get("_current_attack_data") as Dictionary
	_check(started, "swamp toad commits to a leap against a distant visible player")
	_check(
		str(toad.get("_state")) == "5"
		and is_equal_approx(float(attack.get("windup_duration", 0.0)), 1.1)
		and is_equal_approx(float(attack.get("lunge_distance", 0.0)), 4.5)
		and str(attack.get("telegraph_shape", "")) == "line"
		and str(attack.get("attackClass", "")) == "unblockable",
		"toad leap presents a committed, directional unblockable tell before contact"
	)
	toad.call("_start_attack")
	toad.call("_end_attack")
	_check(
		str(toad.get("_state")) == "7"
		and is_equal_approx(float(toad.get("_state_timer")), 1.35),
		"toad leap leaves a full 1.35-second landing punish window"
	)
	toad.queue_free()
	player.queue_free()


func _check_slime_space_behavior() -> void:
	var scene := load("res://scenes/enemies/crystal_slime.tscn") as PackedScene
	var slime := scene.instantiate() as CastleEnemyBase if scene != null else null
	_check(slime != null, "crystal slime production scene instantiates for space-shaping attack audit")
	if slime == null:
		return
	add_child(slime)
	await get_tree().process_frame
	var bloom: Dictionary = {}
	for candidate in (slime.get("_data") as Dictionary).get("attacks", []):
		if candidate is Dictionary and str(candidate.get("id", "")) == "shard_bloom":
			bloom = candidate
			break
	_check(not bloom.is_empty(), "crystal slime loads its authored shard-bloom move")
	_check(
		bool(bloom.get("no_hitbox", false))
		and str(bloom.get("attackBehavior", "")) == "hazard"
		and str(bloom.get("telegraph_shape", "")) == "line"
		and int((bloom.get("spawn_hazard", {}) as Dictionary).get("count", 0)) == 3,
		"shard bloom trades direct contact for three avoidable delayed space hazards"
	)
	var hazard_script := load("res://scripts/bosses/crystal_pillar_hazard.gd") as Script
	var existing := _count_children_with_script(hazard_script)
	slime.set("_current_attack_data", bloom)
	slime.call("_start_attack")
	await get_tree().process_frame
	var spawned: Array[Node] = []
	for child in get_children():
		if child.get_script() == hazard_script and child not in spawned:
			spawned.append(child)
	_check(spawned.size() - existing == 3, "shard bloom spawns three production crystal pillar hazards")
	for hazard in spawned:
		_check(
			str(hazard.get("_state")) == "0"
			and not bool((hazard.get_node("DamageArea") as Area3D).monitoring)
			and float(hazard.get("telegraph_time")) >= 1.0,
			"each shard-bloom pillar telegraphs before its damage area activates"
		)
	slime.queue_free()
	for hazard in spawned:
		if hazard != slime:
			hazard.queue_free()


func _count_children_with_script(script: Script) -> int:
	var count := 0
	for child in get_children():
		if child.get_script() == script:
			count += 1
	return count


func _check_leech_grab_behavior() -> void:
	var player := CharacterBody3D.new()
	var health := Health.new()
	health.name = "Health"
	var reactions := PlayerCombatReactions.new()
	reactions.name = "CombatReactions"
	var hurtbox := Hurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.team = "player"
	hurtbox.health_path = NodePath("../Health")
	player.add_child(health)
	player.add_child(hurtbox)
	player.add_child(reactions)
	add_child(player)
	var scene := load("res://scenes/enemies/swamp_leech.tscn") as PackedScene
	var leech := scene.instantiate() as CastleEnemyBase if scene != null else null
	_check(leech != null, "swamp leech production scene instantiates for siphon behavior audit")
	if leech == null:
		player.queue_free()
		return
	add_child(leech)
	await get_tree().process_frame
	var siphon: Dictionary = {}
	for candidate in (leech.get("_data") as Dictionary).get("attacks", []):
		if candidate is Dictionary and str(candidate.get("id", "")) == "siphon_grab":
			siphon = candidate
			break
	_check(not siphon.is_empty(), "leech loads its authored siphon-grab move")
	_check(
		str(siphon.get("attackClass", "")) == "grab"
		and str(siphon.get("telegraph_shape", "")) == "line"
		and float(siphon.get("windup_duration", 0.0)) >= 0.8
		and float(siphon.get("grab_duration", 0.0)) >= 1.5
		and float(siphon.get("grab_drain_per_second", 0.0)) > 0.0,
		"siphon is a readable, committed grab with authored duration and drain"
	)
	var info := DamageInfo.create(0.0, 0.0, leech, "poison", Vector3.ZERO, "", 0, "grab")
	info.grab_duration = float(siphon.get("grab_duration", 0.0))
	info.grab_drain_per_second = float(siphon.get("grab_drain_per_second", 0.0))
	hurtbox.receive_hit(info)
	_check(bool(reactions.is_grabbed), "player accepts the leech's production grab contract")
	var before_drain := health.current
	reactions._physics_process(0.4)
	_check(health.current < before_drain, "leech siphon drains health during attachment")
	leech.set("_state", CastleEnemyBase.State.STAGGER)
	reactions._physics_process(0.1)
	var after_interrupt := health.current
	_check(not reactions.is_grabbed, "staggering the leech interrupts its attachment")
	reactions._physics_process(0.4)
	_check(is_equal_approx(health.current, after_interrupt), "interrupted siphon cannot apply later drain ticks")
	player.queue_free()
	leech.queue_free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)

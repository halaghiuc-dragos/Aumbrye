extends Node3D

const ArenaDioramaScript := preload("res://scripts/debug/arena_diorama.gd")
const TrainingGruntScript := preload("res://scripts/enemies/training_grunt.gd")

const DUMMY_SPAWNS := [
	Vector3(7.0, 0.0, -4.5),
	Vector3(9.5, 0.0, 0.0),
	Vector3(7.0, 0.0, 4.5),
	Vector3(-7.0, 0.0, -4.5),
	Vector3(-9.5, 0.0, 0.0),
	Vector3(-7.0, 0.0, 4.5),
]
const PLAYER_SPAWN := Vector3(-0.02, 0.0, 9.50)
const PLAYER_SPAWN_LOOK_DIR := Vector3(0.0, -0.10, -1.0)

@export var player_path: NodePath
@export var enemy_path: NodePath
@export var overlay_path: NodePath
@export var hub_return_area_path: NodePath = NodePath("HubReturn/InteractArea")

var _overlay: Node
var _hub_return_area: Area3D
var _near_hub_return := false
var _player_death_reset_pending := false
var _practice_panel: Control
var _active_practice := ""


func _ready() -> void:
	add_to_group("training_arena")
	PixelDioramaBootstrap.prime()
	ArenaDioramaScript.apply(self)
	PixelDioramaBootstrap.attach_deferred(self)
	if overlay_path:
		_overlay = get_node(overlay_path)
	if hub_return_area_path:
		_hub_return_area = get_node_or_null(hub_return_area_path) as Area3D
		if _hub_return_area:
			_hub_return_area.body_entered.connect(_on_hub_return_enter)
			_hub_return_area.body_exited.connect(_on_hub_return_exit)
	# A deferred call is sufficient once the scene's children have entered the tree.  Keeping the
	# work as an async method made its continuation resume after short-lived debug arena instances
	# had already been freed by the scene sweep.
	call_deferred("orient_player_to_hub_return")
	call_deferred("_wire_training_death")
	call_deferred("_wire_dummy_death_reset")
	call_deferred("_build_practice_panel")
	PlayerControls.sync_player_loadout()


func _build_practice_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PracticeObjectives"
	layer.layer = 12
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 16.0
	panel.offset_top = -238.0
	panel.offset_right = 410.0
	panel.offset_bottom = -16.0
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "Content"
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var title := Label.new()
	title.text = tr("PRACTICE_TITLE")
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)
	var description := Label.new()
	description.name = "Description"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)
	var actions := GridContainer.new()
	actions.columns = 3
	column.add_child(actions)
	for exercise in ["parry", "dodge", "guard_break", "poise_break", "recovery"]:
		var button := Button.new()
		button.text = tr("PRACTICE_%s" % exercise.to_upper())
		button.pressed.connect(_start_practice.bind(exercise))
		actions.add_child(button)
	var retry := Button.new()
	retry.name = "Retry"
	retry.text = tr("PRACTICE_RETRY")
	retry.pressed.connect(_retry_practice)
	column.add_child(retry)
	_practice_panel = panel
	_set_practice_description("PRACTICE_CHOOSE")


func _start_practice(exercise: String) -> void:
	var player := get_node_or_null(player_path) as CharacterBody3D
	var target := get_node_or_null(enemy_path) as TrainingGruntScript
	if player == null or target == null:
		return
	_active_practice = exercise
	reset_training_session()
	var hurtbox := player.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox:
		hurtbox.team = "training"
		hurtbox.practice_invulnerable = true
	target.set_training_attack_class("unblockable" if exercise == "guard_break" else "blockable")
	var description := _practice_panel.get_node_or_null("Content/Description") as Label
	_disconnect_practice_signals(player, target)
	match exercise:
		"parry":
			description.text = "%s\n%s".format([
				tr("PRACTICE_PARRY_DESC"),
				tr("PRACTICE_ACTION_BLOCK").format([InputGlyphService.get_action_glyph("block")])
			])
			var guard := player.get_node_or_null("Guard") as Guard
			if guard and not guard.parry_success.is_connected(_on_practice_parry):
				guard.parry_success.connect(_on_practice_parry)
			if not target.attack_telegraph_started.is_connected(_prompt_training_attack):
				target.attack_telegraph_started.connect(_prompt_training_attack)
		"dodge":
			description.text = "%s\n%s".format([
				tr("PRACTICE_DODGE_DESC"),
				tr("PRACTICE_ACTION_DODGE").format([InputGlyphService.get_action_glyph("dodge")])
			])
			if not target.get_node("Hurtbox").hit_resolved.is_connected(_on_training_attack_resolved):
				target.get_node("Hurtbox").hit_resolved.connect(_on_training_attack_resolved)
			if not target.attack_telegraph_started.is_connected(_prompt_training_attack):
				target.attack_telegraph_started.connect(_prompt_training_attack)
		"poise_break":
			description.text = "%s\n%s".format([
				tr("PRACTICE_POISE_BREAK_DESC"),
				tr("PRACTICE_ACTION_ATTACK").format([InputGlyphService.get_action_glyph("light_attack")])
			])
			var poise := target.get_node_or_null("Poise") as Poise
			if poise and not poise.poise_broken.is_connected(_on_training_poise_broken):
				poise.poise_broken.connect(_on_training_poise_broken)
		"guard_break":
			description.text = "%s\n%s".format([
				tr("PRACTICE_GUARD_BREAK_DESC"),
				tr("PRACTICE_ACTION_BLOCK").format([InputGlyphService.get_action_glyph("block")])
			])
			var guard := player.get_node_or_null("Guard") as Guard
			if guard and not guard.guard_broken.is_connected(_on_player_guard_broken):
				guard.guard_broken.connect(_on_player_guard_broken)
			if not target.attack_telegraph_started.is_connected(_prompt_training_attack):
				target.attack_telegraph_started.connect(_prompt_training_attack)
		"recovery":
			description.text = tr("PRACTICE_RECOVERY_DESC")
			var stamina := player.get_node_or_null("Stamina") as Stamina
			if stamina and not stamina.recovered.is_connected(_on_training_stamina_recovered):
				stamina.recovered.connect(_on_training_stamina_recovered)
			if stamina:
				stamina.drain(stamina.current)
				description.text += "\n" + tr("PRACTICE_RECOVERY_WAIT")


func _retry_practice() -> void:
	if _active_practice != "":
		_start_practice(_active_practice)
		return
	var player := get_node_or_null(player_path) as CharacterBody3D
	var target := get_node_or_null(enemy_path) as TrainingGruntScript
	_disconnect_practice_signals(player, target)
	var hurtbox := player.get_node_or_null("Hurtbox") as Hurtbox if player else null
	if hurtbox:
		hurtbox.team = "player"
		hurtbox.practice_invulnerable = false
	reset_training_session()
	_set_practice_description("PRACTICE_CHOOSE")


func _disconnect_practice_signals(player: CharacterBody3D, target: TrainingGruntScript) -> void:
	if player:
		var guard := player.get_node_or_null("Guard") as Guard
		if guard and guard.parry_success.is_connected(_on_practice_parry):
			guard.parry_success.disconnect(_on_practice_parry)
		if guard and guard.guard_broken.is_connected(_on_player_guard_broken):
			guard.guard_broken.disconnect(_on_player_guard_broken)
		var stamina := player.get_node_or_null("Stamina") as Stamina
		if stamina and stamina.recovered.is_connected(_on_training_stamina_recovered):
			stamina.recovered.disconnect(_on_training_stamina_recovered)
	if target:
		var hurtbox := target.get_node_or_null("Hurtbox") as Hurtbox
		if hurtbox and hurtbox.hit_resolved.is_connected(_on_training_attack_resolved):
			hurtbox.hit_resolved.disconnect(_on_training_attack_resolved)
		var poise := target.get_node_or_null("Poise") as Poise
		if poise and poise.poise_broken.is_connected(_on_training_poise_broken):
			poise.poise_broken.disconnect(_on_training_poise_broken)
		if target.attack_telegraph_started.is_connected(_prompt_training_attack):
			target.attack_telegraph_started.disconnect(_prompt_training_attack)


func _prompt_training_attack() -> void:
	var player := get_node_or_null(player_path) as CharacterBody3D
	var guard := player.get_node_or_null("Guard") as Guard if player else null
	if guard and guard.has_signal("parry_success"):
		_set_practice_description("PRACTICE_TELEGRAPH_SHAPE")


func _on_practice_parry(_target: Node) -> void:
	_complete_practice("PRACTICE_PARRY_DONE")


func _on_training_attack_resolved(result: DamageResolution) -> void:
	if result.dodged:
		_complete_practice("PRACTICE_DODGE_DONE")


func _on_training_poise_broken() -> void:
	_complete_practice("PRACTICE_POISE_BREAK_DONE")


func _on_player_guard_broken() -> void:
	_complete_practice("PRACTICE_GUARD_BREAK_DONE")


func _on_training_stamina_recovered() -> void:
	_complete_practice("PRACTICE_RECOVERY_DONE")


func _complete_practice(key: String) -> void:
	_set_practice_description(key)


func _set_practice_description(key: String) -> void:
	if _practice_panel == null:
		return
	var description := _practice_panel.get_node_or_null("Content/Description") as Label
	if description:
		description.text = tr(key)


func _wire_training_death() -> void:
	var player := get_node_or_null(player_path) as CharacterBody3D
	if player == null:
		return
	var reactions := player.get_node_or_null("CombatReactions")
	if reactions == null or not reactions.has_signal("player_died"):
		return
	if not reactions.player_died.is_connected(_on_training_player_died):
		reactions.player_died.connect(_on_training_player_died)


func _on_training_player_died() -> void:
	if _player_death_reset_pending:
		return
	_player_death_reset_pending = true
	await get_tree().create_timer(0.55).timeout
	reset_training_player()
	_player_death_reset_pending = false


func reset_training_session() -> void:
	reset_training_player()
	reset_training_dummies()


func reset_training_player() -> void:
	var player := get_node_or_null(player_path) as CharacterBody3D
	if player == null:
		return
	var health := player.get_node_or_null("Health") as Health
	var stamina := player.get_node_or_null("Stamina") as Stamina
	var poise := player.get_node_or_null("Poise") as Poise
	if health:
		health.reset_health()
	if stamina:
		stamina.reset_stamina()
	if poise:
		poise.reset_poise()
	player.global_position = PLAYER_SPAWN
	player.velocity = Vector3.ZERO
	orient_player_to_hub_return()
	var reactions := player.get_node_or_null("CombatReactions") as PlayerCombatReactions
	if reactions != null:
		reactions.reset_combat_state()


func reset_training_dummies() -> void:
	for enemy in get_tree().get_nodes_in_group("training_dummy"):
		var grunt := enemy as TrainingGruntScript
		if grunt != null:
			grunt.reset_enemy()
		if enemy is CharacterBody3D:
			(enemy as CharacterBody3D).velocity = Vector3.ZERO


func _wire_dummy_death_reset() -> void:
	for enemy in get_tree().get_nodes_in_group("training_dummy"):
		var health := enemy.get_node_or_null("Health") as Health
		if health and not health.died.is_connected(_on_dummy_died):
			health.died.connect(_on_dummy_died.bind(enemy))


func _on_dummy_died(enemy: Node) -> void:
	if AchievementService:
		AchievementService.notify("arena_won")
	await get_tree().create_timer(0.8).timeout
	var grunt := enemy as TrainingGruntScript
	if grunt != null:
		grunt.reset_enemy()


func orient_player_to_hub_return() -> void:
	var player := get_node_or_null(player_path) as CharacterBody3D
	if player == null:
		return
	player.global_position = PLAYER_SPAWN
	var facing := player.get_node_or_null("Facing") as Node3D
	var flat_look := PLAYER_SPAWN_LOOK_DIR
	flat_look.y = 0.0
	if facing and flat_look.length_squared() > 0.0001:
		flat_look = flat_look.normalized()
		facing.rotation.y = LockOnMovement.world_direction_to_local_facing_y(player, flat_look)
	var spring_arm := player.get_node_or_null("CameraPivot/SpringArm3D")
	if spring_arm and spring_arm.has_method("snap_camera_forward"):
		spring_arm.call("snap_camera_forward", PLAYER_SPAWN_LOOK_DIR)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_duel") and _overlay and _overlay.has_method("reset_duel"):
		_overlay.call("reset_duel")
	if not event.is_action_pressed("interact") or not _near_hub_return:
		return
	var vp := get_viewport()
	if vp == null:
		return
	vp.set_input_as_handled()
	_near_hub_return = false
	RunFlow.return_to_hub("Returned from the training arena.")


func _on_hub_return_enter(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_hub_return = true


func _on_hub_return_exit(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_hub_return = false

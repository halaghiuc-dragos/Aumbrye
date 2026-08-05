extends Node3D

const ArenaDioramaScript := preload("res://scripts/debug/arena_diorama.gd")

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
	call_deferred("_orient_player_deferred")
	call_deferred("_wire_training_death")
	call_deferred("_wire_dummy_death_reset")
	PlayerControls.sync_player_loadout()


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
	var reactions := player.get_node_or_null("CombatReactions")
	if reactions and reactions.has_method("reset_combat_state"):
		reactions.call("reset_combat_state")


func reset_training_dummies() -> void:
	for enemy in get_tree().get_nodes_in_group("training_dummy"):
		if enemy.has_method("reset_enemy"):
			enemy.call("reset_enemy")
		if enemy is CharacterBody3D:
			(enemy as CharacterBody3D).velocity = Vector3.ZERO


func _wire_dummy_death_reset() -> void:
	for enemy in get_tree().get_nodes_in_group("training_dummy"):
		var health := enemy.get_node_or_null("Health") as Health
		if health and not health.died.is_connected(_on_dummy_died):
			health.died.connect(_on_dummy_died.bind(enemy))


func _on_dummy_died(enemy: Node) -> void:
	await get_tree().create_timer(0.8).timeout
	if enemy.has_method("reset_enemy"):
		enemy.call("reset_enemy")


func _orient_player_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	orient_player_to_hub_return()


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

extends CanvasLayer

@export var player_path: NodePath
@export var enemy_path: NodePath

var show_debug := true
var show_hitboxes := false

var _player: CharacterBody3D
var _enemy: CharacterBody3D
var _label: Label
var _dodge: Node
var _guard: Node
var _weapon: Node
var _hit_feedback: Node


func _ready() -> void:
	_label = $DebugLabel
	_apply_overlay_layout()
	if player_path:
		_player = get_node(player_path) as CharacterBody3D
		_dodge = _player.get_node_or_null("Dodge")
		_guard = _player.get_node_or_null("Guard")
		_weapon = _player.get_node_or_null("WeaponController")
		_hit_feedback = _player.get_node_or_null("HitFeedback")
	if enemy_path:
		_enemy = get_node(enemy_path) as CharacterBody3D


func _apply_overlay_layout() -> void:
	if _label == null:
		return
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.offset_left = -520.0
	_label.offset_top = 16.0
	_label.offset_right = -16.0
	_label.offset_bottom = 300.0
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_color_override("font_color", Color(0.94, 0.92, 0.86, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.82))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		show_debug = not show_debug
		_label.visible = show_debug
	if event.is_action_pressed("debug_hitboxes"):
		show_hitboxes = not show_hitboxes
		_toggle_hitbox_debug(show_hitboxes)
	if event.is_action_pressed("toggle_damage_numbers") and _hit_feedback:
		_hit_feedback.show_damage_numbers = not _hit_feedback.show_damage_numbers


func _process(_delta: float) -> void:
	if not show_debug:
		return
	var lines: PackedStringArray = []
	var fps := Engine.get_frames_per_second()
	(
		lines
		. append(
			(
				"F1: overlay | F2: hitboxes | F3: dmg nums | P: camera | R: reset | Q: tap block | FPS: %d"
				% fps
			)
		)
	)
	if _dodge:
		var dashing := "DASHING" if _dodge.get("is_dodging") else "off"
		lines.append("dash i-frames: %s" % ("ON" if _dodge.get("iframes_active") else dashing))
	if _guard:
		(
			lines
			. append(
				(
					"guard: %s | parry: %s | block: %s"
					% [
						"active" if _guard.get("is_guard_active") else "off",
						"OPEN" if _guard.get("parry_window_active") else "closed",
						"ON" if _guard.get("is_blocking") else "off",
					]
				)
			)
		)
	if _player:
		_append_player_location_lines(lines)
		_append_camera_facing_lines(lines)
		var spring_arm := _player.get_node_or_null("CameraPivot/SpringArm3D")
		if spring_arm and spring_arm.has_method("is_first_person"):
			lines.append("camera: %s" % ("1P" if spring_arm.call("is_first_person") else "3P"))
		if spring_arm and spring_arm.has_method("get_lock_tuning_debug"):
			var tuning: Dictionary = spring_arm.call("get_lock_tuning_debug")
			if tuning.get("lock_active", false):
				lines.append(
					(
						"lock cam: h=%.1f zoom=%.1f shift=[%.2f-%.2f] occ=%.2f"
						% [
							float(tuning.get("target_height", 0.0)),
							float(tuning.get("zoom_base", 0.0)),
							float(tuning.get("shift_min", 0.0)),
							float(tuning.get("shift_max", 0.0)),
							float(tuning.get("occlusion_blend", 0.0)),
						]
					)
				)
		var health := _player.get_node_or_null("Health") as Health
		var stamina := _player.get_node_or_null("Stamina") as Stamina
		if health:
			lines.append("HP: %.0f" % health.current)
		if stamina:
			lines.append("Stamina: %.0f" % stamina.current)
		if _player.has_method("get_current_speed_breakdown"):
			var breakdown: Dictionary = _player.call("get_current_speed_breakdown")
			lines.append(
				(
					"speed: %.2f (base %.2f x equip %.2f x status %.2f x weapon %.2f x dir %.2f)"
					% [
						float(breakdown.get("final", 0.0)),
						float(breakdown.get("base", 0.0)),
						float(breakdown.get("equipment", 1.0)),
						float(breakdown.get("status", 1.0)),
						float(breakdown.get("weapon", 1.0)),
						float(breakdown.get("direction", 1.0)),
					]
				)
			)
	if _enemy:
		var enemy_health := _enemy.get_node_or_null("Health") as Health
		if enemy_health:
			lines.append("Enemy HP: %.0f / %.0f" % [enemy_health.current, enemy_health.max_health])
	var dummy_count := get_tree().get_nodes_in_group("training_dummy").size()
	if dummy_count > 1:
		lines.append("training dummies: %d" % dummy_count)
	if show_hitboxes:
		var hit_nodes := get_tree().get_nodes_in_group("combat_hitbox")
		var hurt_nodes := get_tree().get_nodes_in_group("combat_hurtbox")
		var visible_meshes := _count_visible_debug_meshes()
		(
			lines
			. append(
				(
					"hitbox draw: ON (%d hit, %d hurt, %d meshes)"
					% [
						hit_nodes.size(),
						hurt_nodes.size(),
						visible_meshes,
					]
				)
			)
		)
	if _hit_feedback:
		lines.append("damage numbers: %s" % ("ON" if _hit_feedback.show_damage_numbers else "off"))
	if _weapon and _weapon.has_method("get_debug_state"):
		lines.append("attack: %s" % _weapon.call("get_debug_state"))
	if get_tree().root.has_meta("run_seed"):
		lines.append("base seed: %s" % str(get_tree().root.get_meta("run_seed")))
	if get_tree().root.has_meta("tier_generation_seed"):
		lines.append("tier gen seed: %s" % str(get_tree().root.get_meta("tier_generation_seed")))
	var reactions := _player.get_node_or_null("CombatReactions") if _player else null
	if reactions:
		if reactions.get("is_dead"):
			lines.append("player: DEAD (press R)")
		elif reactions.get("is_staggered"):
			lines.append("player: staggered")
	_label.text = "\n".join(lines)


func _append_player_location_lines(lines: PackedStringArray) -> void:
	var pos := _player.global_position
	lines.append("player pos: %.2f, %.2f, %.2f" % [pos.x, pos.y, pos.z])
	var room_label := _resolve_room_label(pos)
	if room_label != "":
		lines.append("room: %s" % room_label)
	var room := _find_current_room_template()
	if room:
		var local_pos := room.to_local(pos)
		lines.append("room local: %.2f, %.2f, %.2f" % [local_pos.x, local_pos.y, local_pos.z])


func _append_camera_facing_lines(lines: PackedStringArray) -> void:
	var camera := PixelDioramaViewport.get_gameplay_camera()
	if camera == null:
		return
	var forward := -camera.global_transform.basis.z.normalized()
	var yaw_deg := rad_to_deg(atan2(forward.x, forward.z))
	var pitch_deg := rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))
	lines.append(
		(
			"camera facing: yaw %.0f° pitch %.0f° | (%.2f, %.2f, %.2f)"
			% [yaw_deg, pitch_deg, forward.x, forward.y, forward.z]
		)
	)


func _resolve_room_label(_world_pos: Vector3) -> String:
	var castle := get_tree().get_first_node_in_group("castle_run")
	if castle:
		var room_id := str(castle.get("player_room_id"))
		if room_id != "":
			return room_id
		return "castle"
	var scene := get_tree().current_scene
	if scene:
		if scene.scene_file_path.ends_with("hub/hub.tscn"):
			return "Aumbrye Tower"
		return scene.name
	return ""


func _find_current_room_template() -> RoomTemplate:
	var castle := get_tree().get_first_node_in_group("castle_run")
	if castle == null:
		return null
	var room_id := str(castle.get("player_room_id"))
	if room_id == "":
		return null
	return _find_room_template(castle, room_id)


func _find_room_template(root: Node, room_id: String) -> RoomTemplate:
	for node in root.find_children("*", "RoomTemplate", true, false):
		var room := node as RoomTemplate
		if room and room.room_id == room_id:
			return room
	return null


func _toggle_hitbox_debug(enabled: bool) -> void:
	var hit_count := 0
	var hurt_count := 0
	for node in get_tree().get_nodes_in_group("combat_hitbox"):
		if node.has_method("set_debug_draw"):
			node.call("set_debug_draw", enabled)
			hit_count += 1
	for node in get_tree().get_nodes_in_group("combat_hurtbox"):
		if node.has_method("set_debug_draw"):
			node.call("set_debug_draw", enabled)
			hurt_count += 1
	if enabled and hit_count + hurt_count == 0:
		push_warning("DebugOverlay: no combat hit/hurt boxes found in scene tree")


func _count_visible_debug_meshes() -> int:
	var count := 0
	for group_name in ["combat_hitbox", "combat_hurtbox"]:
		for node in get_tree().get_nodes_in_group(group_name):
			var debug_mesh := node.get_node_or_null("DebugDraw")
			if debug_mesh and debug_mesh.visible:
				count += 1
	return count


func reset_duel() -> void:
	var arena := get_tree().current_scene
	if arena and arena.has_method("reset_training_session"):
		arena.call("reset_training_session")
		return
	if _player:
		var health := _player.get_node_or_null("Health") as Health
		var stamina := _player.get_node_or_null("Stamina") as Stamina
		var poise := _player.get_node_or_null("Poise") as Poise
		if health:
			health.reset_health()
		if stamina:
			stamina.reset_stamina()
		if poise:
			poise.reset_poise()
		_player.global_position = (
			CombatArenaScript.PLAYER_SPAWN
			if _has_combat_arena_constants()
			else Vector3(-0.02, 0.0, 9.5)
		)
		_player.velocity = Vector3.ZERO
		if arena and arena.has_method("orient_player_to_hub_return"):
			arena.call("orient_player_to_hub_return")
	var dummies := get_tree().get_nodes_in_group("training_dummy")
	if not dummies.is_empty():
		for enemy in dummies:
			if enemy.has_method("reset_enemy"):
				enemy.call("reset_enemy")
			enemy.velocity = Vector3.ZERO
	elif _enemy:
		if _enemy.has_method("reset_enemy"):
			_enemy.call("reset_enemy")
		_enemy.global_position = Vector3(6, 0, 0)
		_enemy.velocity = Vector3.ZERO
	if _player:
		var reactions := _player.get_node_or_null("CombatReactions")
		if reactions and reactions.has_method("reset_combat_state"):
			reactions.call("reset_combat_state")


const CombatArenaScript := preload("res://scripts/debug/combat_arena.gd")


func _has_combat_arena_constants() -> bool:
	return CombatArenaScript != null

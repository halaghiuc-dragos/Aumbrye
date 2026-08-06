class_name DioramaAnimController
extends Node

## Drives a voxel rig with a real AnimationPlayer and a strict priority stack.
##
## Add it as a child of the character body, then bind() the DioramaVisual built by
## DioramaCharacterSkin. Clips are compiled from DioramaAnimLibrary against that
## specific rig, so profiles with missing limbs simply get fewer tracks.
##
## Priority (highest wins): death > stagger > attack/parry > block > dash > locomotion.
## A lower-priority request is remembered and applied when the stack unwinds.

signal swing_frame
signal footstep_frame
signal heal_gulp_frame
signal heal_commit_frame

enum Priority {
	LOCOMOTION,
	DASH,
	BLOCK,
	ATTACK,
	STAGGER,
	DEATH,
}

const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
const AnimLibrary := preload("res://scripts/art/characters/diorama_anim_library.gd")

const LOCOMOTION_BLEND := 0.12
const ACTION_BLEND := 0.06
const LIBRARY_NAME := &""

## Locomotion clip speed is scaled by how fast the body is actually moving, so
## footfalls stay planted instead of skating.
const WALK_REFERENCE_SPEED := 4.5
const RUN_REFERENCE_SPEED := 7.0

var _visual: Node3D
var _player: AnimationPlayer
var _additive_player: AnimationPlayer
var _library: AnimationLibrary
var _additive_library: AnimationLibrary
var _rest_pose: Dictionary = {}
var _events_path := ""
var _profile := "player"
var _weapon_archetype := ""
var _weapon_id := ""
var _theme: int = 0
var _attack_clips: Array = []
var _combo_index := 0
var _priority: int = Priority.LOCOMOTION
var _desired_locomotion: StringName = &"idle"
var _blocking := false
var _dead := false
var _compiled_attacks: Dictionary = {}
var _mirrors: Array[DioramaAnimController] = []


## Registers a rig that should play whatever this controller plays. Used to keep
## the first-person viewmodel in lockstep with the third-person body from a
## single set of gameplay calls.
func add_mirror(other: DioramaAnimController) -> void:
	if other != null and other != self and not _mirrors.has(other):
		_mirrors.append(other)


func bind(visual: Node3D) -> void:
	_teardown()
	_visual = visual
	if visual == null:
		return
	if not visual.is_inside_tree():
		if not visual.tree_entered.is_connected(_on_bind_visual_tree_entered):
			visual.tree_entered.connect(_on_bind_visual_tree_entered, CONNECT_ONE_SHOT)
		return
	_finish_bind()


func _on_bind_visual_tree_entered() -> void:
	if _visual != null and is_instance_valid(_visual):
		_finish_bind()


func _finish_bind() -> void:
	var visual := _visual
	if visual == null or not is_instance_valid(visual):
		return
	_rest_pose = CharacterSkin.collect_rest_pose(visual)
	if _rest_pose.is_empty():
		return
	_events_path = _resolve_events_path(visual)
	var loaded := AnimLibrary.build_library(_rest_pose, _events_path, _profile)
	if AnimLibrary.can_use_authored_library(_rest_pose, _profile):
		_library = loaded.duplicate(true)
	else:
		_library = loaded
	_player = AnimationPlayer.new()
	_player.name = "DioramaAnimPlayer"
	visual.add_child(_player)
	# Tracks are authored relative to the visual root (parent of this player).
	_player.root_node = NodePath("..")
	_player.add_animation_library(LIBRARY_NAME, _library)
	_player.animation_finished.connect(_on_animation_finished)
	_player.playback_default_blend_time = LOCOMOTION_BLEND
	_setup_additive_player(visual)
	_dead = false
	_priority = Priority.LOCOMOTION
	_desired_locomotion = &"idle"
	# set_weapon may have arrived before the rig existed; apply it now.
	if _weapon_id != "":
		CharacterSkin.attach_weapon(visual, _weapon_id, _theme)
	_play(&"idle", LOCOMOTION_BLEND)


func is_bound() -> bool:
	return _player != null and is_instance_valid(_player)


func _resolve_events_path(visual: Node3D) -> String:
	if not is_inside_tree() or not visual.is_inside_tree():
		return ""
	var path := visual.get_path_to(self)
	if path.is_empty():
		return ""
	return String(path)


func has_footstep_markers() -> bool:
	if not is_bound() or _library == null:
		return false
	for clip_name in [&"walk", &"run"]:
		if not _library.has_animation(clip_name):
			continue
		var anim := _library.get_animation(clip_name)
		if anim == null:
			continue
		for track_idx in anim.get_track_count():
			if anim.track_get_type(track_idx) != Animation.TYPE_METHOD:
				continue
			for key_idx in anim.track_get_key_count(track_idx):
				var method_data: Dictionary = anim.track_get_key_value(track_idx, key_idx)
				if String(method_data.get("method", "")) == "anim_footstep":
					return true
	return false


func has_marker_tracks() -> bool:
	if not is_bound() or _library == null:
		return false
	for clip_name in [&"walk", &"run"]:
		if not _library.has_animation(clip_name):
			continue
		var anim := _library.get_animation(clip_name)
		if anim == null:
			continue
		var method_count := 0
		for track_idx in anim.get_track_count():
			if anim.track_get_type(track_idx) == Animation.TYPE_METHOD:
				method_count += anim.track_get_key_count(track_idx)
		if method_count >= 2:
			return true
	return false


func _setup_additive_player(visual: Node3D) -> void:
	if _additive_player and is_instance_valid(_additive_player):
		_additive_player.queue_free()
	_additive_library = AnimLibrary.build_additive_library(_rest_pose)
	if _additive_library == null or _additive_library.get_animation_list().is_empty():
		_additive_player = null
		return
	_additive_player = AnimationPlayer.new()
	_additive_player.name = "DioramaAdditivePlayer"
	visual.add_child(_additive_player)
	_additive_player.root_node = NodePath("..")
	_additive_player.add_animation_library(LIBRARY_NAME, _additive_library)
	if _additive_library.has_animation(&"breathe"):
		_additive_player.play(&"breathe")


func set_profile(profile: String) -> void:
	_profile = profile
	_refresh_attack_clips()


func set_theme(theme: int) -> void:
	_theme = theme


func set_weapon(weapon_id: String, archetype: String = "") -> void:
	for mirror in _mirrors:
		mirror.set_weapon(weapon_id, archetype)
	_weapon_id = weapon_id
	_weapon_archetype = archetype
	_refresh_attack_clips()
	if _visual:
		CharacterSkin.attach_weapon(_visual, weapon_id, _theme)


func has_clip(clip: StringName) -> bool:
	return _library != null and _library.has_animation(clip)


## state: idle | walk | run | air. speed_ratio scales playback for walk/run.
func request_locomotion(state: StringName, params: Dictionary = {}) -> void:
	for mirror in _mirrors:
		mirror.request_locomotion(state, params)
	if not is_bound():
		return
	_desired_locomotion = state
	if _priority > Priority.LOCOMOTION:
		return
	var speed := 1.0
	match state:
		&"walk", &"walk_l", &"walk_r", &"walk_b", &"block_walk":
			speed = clampf(
				float(params.get("speed", WALK_REFERENCE_SPEED)) / WALK_REFERENCE_SPEED, 0.45, 1.6
			)
		&"run", &"run_l", &"run_r", &"run_b":
			speed = clampf(
				float(params.get("speed", RUN_REFERENCE_SPEED)) / RUN_REFERENCE_SPEED, 0.6, 1.5
			)
	_player.speed_scale = speed
	if _player.current_animation != String(state):
		_play(state, LOCOMOTION_BLEND)


func play_dash(direction: StringName) -> void:
	var clip: StringName = direction
	if not has_clip(clip):
		clip = &"dash_f"
	_start_action(clip, Priority.DASH)


func set_blocking(holding: bool) -> void:
	for mirror in _mirrors:
		mirror.set_blocking(holding)
	if not is_bound() or _blocking == holding:
		return
	_blocking = holding
	if holding:
		if _priority <= Priority.BLOCK:
			_priority = Priority.BLOCK
			_play(&"block_start", ACTION_BLEND)
			_player.queue(&"block_hold")
	elif _priority == Priority.BLOCK:
		_priority = Priority.LOCOMOTION
		_resume_locomotion()


func play_block_impact() -> void:
	if not _blocking or not is_bound():
		return
	_priority = Priority.BLOCK
	_play(&"block_hit", 0.03)
	_player.queue(&"block_hold")


func play_parry() -> void:
	_blocking = false
	_start_action(&"parry_success", Priority.ATTACK)


func play_guard_break() -> void:
	_blocking = false
	_start_action(&"guard_break", Priority.STAGGER)


func play_flinch(direction: Vector3 = Vector3.ZERO) -> void:
	if _priority >= Priority.STAGGER:
		return
	var clip := _flinch_clip_for(direction)
	_start_action(clip, Priority.STAGGER)


func _flinch_clip_for(world_dir: Vector3) -> StringName:
	if world_dir.length_squared() < 0.01:
		return &"flinch_f" if has_clip(&"flinch_f") else &"flinch"
	var body := get_parent() as CharacterBody3D
	if body == null:
		return &"flinch_f" if has_clip(&"flinch_f") else &"flinch"
	var facing := body.get_node_or_null("Facing") as Node3D
	if facing == null:
		return &"flinch_f" if has_clip(&"flinch_f") else &"flinch"
	var forward := -facing.global_transform.basis.z
	var right := facing.global_transform.basis.x
	var flat := Vector3(world_dir.x, 0.0, world_dir.z).normalized()
	var fwd_dot := forward.dot(flat)
	var right_dot := right.dot(flat)
	var clip: StringName
	if absf(fwd_dot) >= absf(right_dot):
		clip = &"flinch_f" if fwd_dot >= 0.0 else &"flinch_b"
	else:
		clip = &"flinch_r" if right_dot >= 0.0 else &"flinch_l"
	if has_clip(clip):
		return clip
	return &"flinch"


func play_stagger(duration: float = 0.0, direction: Vector3 = Vector3.ZERO) -> void:
	_blocking = false
	var clip := _stagger_clip_for(direction)
	if not has_clip(clip):
		clip = &"stagger"
	_start_action(clip, Priority.STAGGER)
	if duration > 0.05 and is_bound():
		var clip_length := _player.current_animation_length
		if clip_length > 0.01:
			_player.speed_scale = clip_length / duration


func _stagger_clip_for(world_dir: Vector3) -> StringName:
	if world_dir.length_squared() < 0.01:
		return &"stagger"
	var body := get_parent() as CharacterBody3D
	if body == null:
		return &"stagger"
	var facing := body.get_node_or_null("Facing") as Node3D
	if facing == null:
		return &"stagger"
	var forward := -facing.global_transform.basis.z
	var right := facing.global_transform.basis.x
	var flat := Vector3(world_dir.x, 0.0, world_dir.z).normalized()
	var fwd_dot := forward.dot(flat)
	var right_dot := right.dot(flat)
	var clip: StringName
	if absf(fwd_dot) >= absf(right_dot):
		clip = &"stagger_f" if fwd_dot >= 0.0 else &"stagger_b"
	else:
		clip = &"stagger_r" if right_dot >= 0.0 else &"stagger_l"
	return clip if has_clip(clip) else &"stagger"


func play_heal(duration: float = 1.35) -> void:
	for mirror in _mirrors:
		if mirror.has_method("play_heal"):
			mirror.call("play_heal", duration)
	_blocking = false
	_start_action(&"heal", Priority.ATTACK)
	if duration > 0.05 and is_bound():
		var clip_length := _player.current_animation_length
		if clip_length > 0.01:
			_player.speed_scale = clampf(clip_length / duration, 0.4, 2.5)


func play_death() -> void:
	if _dead:
		return
	_dead = true
	_blocking = false
	_start_action(&"death", Priority.DEATH)


func revive() -> void:
	for mirror in _mirrors:
		mirror.revive()
	if not is_bound():
		_dead = false
		_priority = Priority.LOCOMOTION
		return
	_dead = false
	_blocking = false
	_priority = Priority.LOCOMOTION
	_desired_locomotion = &"idle"
	_player.speed_scale = 1.0
	if has_clip(&"RESET"):
		_play(&"RESET", 0.1)
	else:
		_apply_rest_pose()
		_play(&"idle", 0.0)


## Plays the next combo swing stretched onto the weapon's real phase timings, so
## the visual strike lands in the same frame the hitbox opens.
func play_attack(
	startup: float, active: float, recovery: float, clip_override: StringName = &""
) -> void:
	if not is_bound() or _dead:
		return
	var clip: StringName = clip_override
	if clip == &"" or not AnimLibrary.ATTACKS.has(clip):
		if _attack_clips.is_empty():
			_refresh_attack_clips()
		if _attack_clips.is_empty():
			return
		clip = _attack_clips[_combo_index % _attack_clips.size()]
		_combo_index += 1
	# Mirrors get the resolved clip so both rigs swing the same way.
	for mirror in _mirrors:
		mirror.play_attack(startup, active, recovery, clip)
	var runtime_name := _ensure_attack_clip(clip, startup, active, recovery)
	if runtime_name == &"":
		return
	_blocking = false
	_priority = Priority.ATTACK
	_player.speed_scale = 1.0
	_player.play(runtime_name, ACTION_BLEND)


func play_heavy_attack(startup: float, active: float, recovery: float) -> void:
	play_attack(startup, active, recovery, AnimLibrary.heavy_clip_for(_weapon_archetype))


func reset_combo() -> void:
	_combo_index = 0


func _refresh_attack_clips() -> void:
	_attack_clips = AnimLibrary.attack_clips_for(_profile, _weapon_archetype)
	_combo_index = 0


func _ensure_attack_clip(
	clip: StringName, startup: float, active: float, recovery: float
) -> StringName:
	# Cache per rounded timing set; weapon data only offers a handful of values.
	var key := (
		"%s_%d_%d_%d"
		% [clip, roundi(startup * 100.0), roundi(active * 100.0), roundi(recovery * 100.0)]
	)
	if _compiled_attacks.has(key):
		return _compiled_attacks[key]
	var anim := AnimLibrary.build_attack(clip, _rest_pose, _events_path, startup, active, recovery)
	if anim == null:
		return &""
	var runtime_name := StringName(key)
	_library.add_animation(runtime_name, anim)
	_compiled_attacks[key] = runtime_name
	return runtime_name


func _start_action(clip: StringName, priority: int) -> void:
	if not is_bound():
		return
	if priority < _priority:
		return
	if not has_clip(clip):
		return
	_priority = priority
	_player.speed_scale = 1.0
	_play(clip, ACTION_BLEND)


func _play(clip: StringName, blend: float) -> void:
	for mirror in _mirrors:
		mirror._priority = _priority
		mirror._desired_locomotion = _desired_locomotion
		mirror._play(clip, blend)
	if not has_clip(clip):
		return
	# Never restart a loop that is already running, or idle would stutter every
	# time a one-shot resolved back to it.
	if _player.current_animation == String(clip) and _player.is_playing():
		var running := _library.get_animation(clip)
		if running and running.loop_mode != Animation.LOOP_NONE:
			return
	_player.play(clip, blend)


func _resume_locomotion() -> void:
	if not is_bound() or _dead:
		return
	_player.speed_scale = 1.0
	if _blocking:
		_priority = Priority.BLOCK
		var block_clip := &"block_hold"
		if _desired_locomotion != &"idle" and has_clip(&"block_walk"):
			block_clip = &"block_walk"
		_play(block_clip, ACTION_BLEND)
		return
	_priority = Priority.LOCOMOTION
	_play(_desired_locomotion, LOCOMOTION_BLEND)


func _on_animation_finished(anim_name: StringName) -> void:
	if _dead:
		return
	var name_text := String(anim_name)
	if name_text == "block_start" or name_text == "block_hit":
		return
	if name_text.begins_with("block_hold") or name_text == "block_walk":
		return
	_resume_locomotion()


## Called from AnimationPlayer method tracks. See DioramaAnimLibrary markers.
func anim_swing_vfx() -> void:
	swing_frame.emit()


func anim_footstep() -> void:
	footstep_frame.emit()


func anim_hitbox_on() -> void:
	var body := get_parent() as CharacterBody3D
	if body == null:
		return
	var weapon := body.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("enable_hitbox_from_anim"):
		weapon.call("enable_hitbox_from_anim")


func anim_hitbox_off() -> void:
	var body := get_parent() as CharacterBody3D
	if body == null:
		return
	var weapon := body.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("disable_hitbox_from_anim"):
		weapon.call("disable_hitbox_from_anim")


func anim_heal_gulp() -> void:
	heal_gulp_frame.emit()


func anim_heal_commit() -> void:
	heal_commit_frame.emit()


func set_speed_scale(scale: float) -> void:
	if _player:
		_player.speed_scale = maxf(0.01, scale)
	for mirror in _mirrors:
		if mirror._player:
			mirror._player.speed_scale = maxf(0.01, scale)


func get_weapon_mount() -> Node3D:
	if _visual == null:
		return null
	return CharacterSkin.find_part(_visual, CharacterSkin.WEAPON_MOUNT)


func _apply_rest_pose() -> void:
	if _visual == null:
		return
	for key in _rest_pose:
		var data: Dictionary = _rest_pose[key]
		var part := _visual.get_node_or_null(NodePath(data["path"])) as Node3D
		if part:
			part.position = data["position"]
			part.rotation = data["rotation"]


func _teardown() -> void:
	if _additive_player and is_instance_valid(_additive_player):
		_additive_player.queue_free()
	_additive_player = null
	_additive_library = null
	if _player and is_instance_valid(_player):
		_player.queue_free()
	_player = null
	_library = null
	_compiled_attacks.clear()
	_rest_pose.clear()
	_blocking = false
	_dead = false

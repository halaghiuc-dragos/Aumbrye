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

enum Priority {
	LOCOMOTION,
	DASH,
	BLOCK,
	ATTACK,
	STAGGER,
	DEATH,
}

const CharacterSkin := preload("res://scripts/art/diorama_character_skin.gd")
const AnimLibrary := preload("res://scripts/art/diorama_anim_library.gd")

const LOCOMOTION_BLEND := 0.12
const ACTION_BLEND := 0.06
const LIBRARY_NAME := &""

## Locomotion clip speed is scaled by how fast the body is actually moving, so
## footfalls stay planted instead of skating.
const WALK_REFERENCE_SPEED := 4.5
const RUN_REFERENCE_SPEED := 7.0

var _visual: Node3D
var _player: AnimationPlayer
var _library: AnimationLibrary
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
	if visual == null or not visual.is_inside_tree():
		return
	_rest_pose = CharacterSkin.collect_rest_pose(visual)
	if _rest_pose.is_empty():
		return
	_events_path = String(visual.get_path_to(self))
	_library = AnimLibrary.build_library(_rest_pose, _events_path)
	_player = AnimationPlayer.new()
	_player.name = "DioramaAnimPlayer"
	visual.add_child(_player)
	_player.root_node = NodePath("..")
	_player.add_animation_library(LIBRARY_NAME, _library)
	_player.animation_finished.connect(_on_animation_finished)
	_player.playback_default_blend_time = LOCOMOTION_BLEND
	_dead = false
	_priority = Priority.LOCOMOTION
	_desired_locomotion = &"idle"
	# set_weapon may have arrived before the rig existed; apply it now.
	if _weapon_id != "":
		CharacterSkin.attach_weapon(visual, _weapon_id, _theme)
	_play(&"idle", LOCOMOTION_BLEND)


func is_bound() -> bool:
	return _player != null and is_instance_valid(_player)


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
		&"walk":
			speed = clampf(float(params.get("speed", WALK_REFERENCE_SPEED)) / WALK_REFERENCE_SPEED, 0.45, 1.6)
		&"run":
			speed = clampf(float(params.get("speed", RUN_REFERENCE_SPEED)) / RUN_REFERENCE_SPEED, 0.6, 1.5)
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


func play_flinch() -> void:
	if _priority >= Priority.STAGGER:
		return
	_start_action(&"flinch", Priority.STAGGER)


func play_stagger(duration: float = 0.0) -> void:
	_blocking = false
	_start_action(&"stagger", Priority.STAGGER)
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
	_apply_rest_pose()
	_play(&"idle", 0.0)


## Plays the next combo swing stretched onto the weapon's real phase timings, so
## the visual strike lands in the same frame the hitbox opens.
func play_attack(startup: float, active: float, recovery: float, clip_override: StringName = &"") -> void:
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
	clip: StringName,
	startup: float,
	active: float,
	recovery: float
) -> StringName:
	# Cache per rounded timing set; weapon data only offers a handful of values.
	var key := "%s_%d_%d_%d" % [clip, roundi(startup * 100.0), roundi(active * 100.0), roundi(recovery * 100.0)]
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
		_play(&"block_hold", ACTION_BLEND)
		return
	_priority = Priority.LOCOMOTION
	_play(_desired_locomotion, LOCOMOTION_BLEND)


func _on_animation_finished(anim_name: StringName) -> void:
	if _dead:
		return
	var name_text := String(anim_name)
	if name_text == "block_start" or name_text == "block_hit":
		return
	if name_text.begins_with("block_hold"):
		return
	_resume_locomotion()


## Called from AnimationPlayer method tracks. See DioramaAnimLibrary markers.
func anim_swing_vfx() -> void:
	swing_frame.emit()


func anim_footstep() -> void:
	footstep_frame.emit()


func anim_hitbox_on() -> void:
	pass


func anim_hitbox_off() -> void:
	pass


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
	if _player and is_instance_valid(_player):
		_player.queue_free()
	_player = null
	_library = null
	_compiled_attacks.clear()
	_rest_pose.clear()
	_blocking = false
	_dead = false

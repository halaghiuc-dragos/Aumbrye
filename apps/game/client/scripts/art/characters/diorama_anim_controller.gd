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
signal hitbox_open_frame
signal hitbox_close_frame

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
const RUNTIME_LIBRARY_NAME := &"runtime"
const ATTACK_CACHE_LIMIT := 24
const SPEED_SCALE_MIN := 0.5
const SPEED_SCALE_MAX := 2.2

var _visual: Node3D
var _player: AnimationPlayer
var _additive_player: AnimationPlayer
var _library: AnimationLibrary
var _runtime_library: AnimationLibrary
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
var _attack_cache_order: Array = []
var _missing_clips: Dictionary = {}
var _clamped_clips: Dictionary = {}
var _hitbox_signals_warned := false

## Whether this rig's owner is expected to act on hitbox frames.
##
## Attack clips emit open/close frames whether or not the owner can hurt anything, so a purely
## passive actor — the training dummies, which have no hitbox and never swing — tripped the
## "no listeners" warning once each on every arena load. Owners that cannot attack set this false
## so the warning keeps meaning "something that should be wired is not".
var expects_hitbox_listeners := true
var _mirrors: Array[DioramaAnimController] = []


## Registers a rig that should play whatever this controller plays. Used to keep
## the first-person viewmodel in lockstep with the third-person body from a
## single set of gameplay calls.
func add_mirror(other: DioramaAnimController) -> void:
	if other != null and other != self and not _mirrors.has(other):
		_mirrors.append(other)


func remove_mirror(other: DioramaAnimController) -> void:
	if other == null:
		return
	var idx := _mirrors.find(other)
	if idx >= 0:
		_mirrors.remove_at(idx)


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
		push_warning(
			"DioramaAnimController[%s]: no rest pose from visual %s; bind will retry"
			% [_profile, visual.name]
		)
		if not visual.tree_entered.is_connected(_on_bind_visual_tree_entered):
			visual.tree_entered.connect(_on_bind_visual_tree_entered, CONNECT_ONE_SHOT)
		return
	_events_path = _resolve_events_path(visual)
	var loaded := AnimLibrary.build_library(_rest_pose, _events_path, _profile)
	if AnimLibrary.can_use_authored_library(_rest_pose, _profile):
		_library = loaded.duplicate(true)
	else:
		_library = loaded
	_runtime_library = AnimationLibrary.new()
	_missing_clips.clear()
	_attack_cache_order.clear()
	_hitbox_signals_warned = false
	_player = AnimationPlayer.new()
	_player.name = "DioramaAnimPlayer"
	visual.add_child(_player)
	# Tracks are authored relative to the visual root (parent of this player).
	_player.root_node = NodePath("..")
	_player.add_animation_library(LIBRARY_NAME, _library)
	_player.add_animation_library(RUNTIME_LIBRARY_NAME, _runtime_library)
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
	call_deferred("_check_hitbox_signal_listeners")


func is_bound() -> bool:
	return _player != null and is_instance_valid(_player)


func drives_hitbox_events() -> bool:
	return not _events_path.is_empty()


func _resolve_events_path(visual: Node3D) -> String:
	if not is_inside_tree() or not visual.is_inside_tree():
		return ""
	var path := visual.get_path_to(self)
	if path.is_empty():
		return ""
	if visual.get_node_or_null(path) != self:
		push_warning(
			"DioramaAnimController: events path %s does not resolve back to self" % path
		)
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
	for mirror in _live_mirrors():
		mirror.set_weapon(weapon_id, archetype)
	_weapon_id = weapon_id
	_weapon_archetype = archetype
	_refresh_attack_clips()
	if _visual:
		CharacterSkin.attach_weapon(_visual, weapon_id, _theme)


func has_clip(clip: StringName) -> bool:
	if _library != null and _library.has_animation(clip):
		return true
	if clip.begins_with(RUNTIME_LIBRARY_NAME):
		var local_name := _clip_name_from_player_path(clip)
		return _runtime_library != null and _runtime_library.has_animation(local_name)
	return false


func select_locomotion_clip(speed: float) -> StringName:
	var clip := AnimLibrary.select_locomotion_clip(speed)
	# C-171: the `jog` special case is gone with the tier that produced it; the generic
	# missing-clip fallback below covers anything else the library lacks.
	if clip != &"idle" and not has_clip(clip) and has_clip(&"walk"):
		clip = &"walk"
	return clip


## state: idle | walk | run | air. speed_ratio scales playback for walk/run.
func request_locomotion(state: StringName, params: Dictionary = {}) -> void:
	for mirror in _live_mirrors():
		mirror.request_locomotion(state, params)
	if not is_bound():
		return
	_desired_locomotion = state
	if _priority > Priority.LOCOMOTION:
		return
	_player.speed_scale = _locomotion_speed_scale(state, params)
	if _player.current_animation != String(state):
		_play(state, LOCOMOTION_BLEND)


func _locomotion_speed_scale(state: StringName, params: Dictionary) -> float:
	var meta := AnimLibrary.clip_meta(state)
	var stride_m := float(meta.get("stride_m", 0.0))
	if stride_m <= 0.0:
		return 1.0
	var travel := float(params.get("speed", 0.0))
	var length := float(meta.get("length", 0.0))
	if travel <= 0.0 or length <= 0.0:
		return 1.0
	var raw := travel * length / stride_m
	if raw < SPEED_SCALE_MIN or raw > SPEED_SCALE_MAX:
		_report_clamp(state, raw)
	return clampf(raw, SPEED_SCALE_MIN, SPEED_SCALE_MAX)


func play_dash(direction: StringName) -> void:
	var clip: StringName = direction
	if not has_clip(clip):
		if clip != &"dash_f":
			_report_missing(clip, "dash")
		clip = &"dash_f"
	if not has_clip(clip):
		_report_missing(clip, "dash_fallback")
		return
	_start_action(clip, Priority.DASH)


func set_blocking(holding: bool) -> void:
	for mirror in _live_mirrors():
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
	if _priority > Priority.STAGGER:
		return
	if _priority == Priority.STAGGER and is_bound():
		var current := _player.current_animation
		if current != "flinch" and not current.begins_with("flinch_"):
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
	# C-41: forward is +basis.z for a Facing node (`CombatFacing.forward_of`); this had forked to
	# -basis.z, so flinch/stagger direction clips were mirrored front-to-back.
	var forward := CombatFacing.forward_of(facing)
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
	var scale := 1.0
	if duration > 0.05 and _library != null and _library.has_animation(clip):
		var clip_length := _library.get_animation(clip).length
		if clip_length > 0.01:
			scale = clampf(clip_length / duration, 0.4, 2.5)
	_begin_action(clip, Priority.STAGGER, scale)


## C-58: the single live implementation. Exposed publicly so `PlayerCombatReactions` can delegate
## rather than keep a second, divergent copy.
func stagger_clip_for_direction(world_dir: Vector3) -> StringName:
	return _stagger_clip_for(world_dir)


func _stagger_clip_for(world_dir: Vector3) -> StringName:
	if world_dir.length_squared() < 0.01:
		return &"stagger"
	var body := get_parent() as CharacterBody3D
	if body == null:
		return &"stagger"
	var facing := body.get_node_or_null("Facing") as Node3D
	if facing == null:
		return &"stagger"
	# C-41: forward is +basis.z for a Facing node (`CombatFacing.forward_of`); this had forked to
	# -basis.z, so flinch/stagger direction clips were mirrored front-to-back.
	var forward := CombatFacing.forward_of(facing)
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
	for mirror in _live_mirrors():
		if mirror.has_method("play_heal"):
			mirror.call("play_heal", duration)
	_blocking = false
	_start_action(&"heal", Priority.ATTACK)
	if duration > 0.05 and is_bound():
		var clip_length := _player.current_animation_length
		if clip_length > 0.01:
			_player.speed_scale = clampf(clip_length / duration, 0.4, 2.5)


## Drops the drink animation and hands the rig back to locomotion.
##
## Needed because the drink is now interruptible: without this the character keeps miming a
## flask it no longer has until the clip runs out, which reads as the heal still landing.
## A stagger arriving in the same frame outranks this and repossesses the rig immediately.
func cancel_heal() -> void:
	for mirror in _live_mirrors():
		if mirror.has_method("cancel_heal"):
			mirror.call("cancel_heal")
	if not is_bound() or _dead:
		return
	if _priority > Priority.ATTACK:
		return
	_priority = Priority.LOCOMOTION
	_resume_locomotion()


func play_death() -> void:
	if _dead:
		return
	_dead = true
	_blocking = false
	# C-164: `revive()` already forwards to every mirror; death did not, so the viewmodel kept
	# resuming locomotion over a dead player.
	for mirror in _live_mirrors():
		mirror.mirror_set_dead(true)
	_start_action(&"death", Priority.DEATH)


func revive() -> void:
	for mirror in _live_mirrors():
		mirror.revive()
	if not is_bound():
		_dead = false
		_priority = Priority.LOCOMOTION
		reset_combo()
		return
	_dead = false
	_blocking = false
	_priority = Priority.LOCOMOTION
	_desired_locomotion = &"idle"
	reset_combo()
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
			_report_missing(&"attack", "combo")
			return
		clip = _attack_clips[_combo_index % _attack_clips.size()]
		_combo_index += 1
	for mirror in _live_mirrors():
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
	var key := (
		"%s_%d_%d_%d"
		% [clip, roundi(startup * 100.0), roundi(active * 100.0), roundi(recovery * 100.0)]
	)
	if _compiled_attacks.has(key):
		var existing_idx := _attack_cache_order.find(key)
		if existing_idx >= 0:
			_attack_cache_order.remove_at(existing_idx)
		_attack_cache_order.append(key)
		return _compiled_attacks[key]
	while _attack_cache_order.size() >= ATTACK_CACHE_LIMIT:
		var evict_key: String = _attack_cache_order[0]
		_attack_cache_order.remove_at(0)
		var evict_path: StringName = _compiled_attacks.get(evict_key, &"")
		_compiled_attacks.erase(evict_key)
		var evict_name := _clip_name_from_player_path(evict_path)
		if evict_name != &"" and _runtime_library.has_animation(evict_name):
			_runtime_library.remove_animation(evict_name)
	var anim := AnimLibrary.build_attack(clip, _rest_pose, _events_path, startup, active, recovery)
	if anim == null:
		return &""
	var runtime_name := StringName(key)
	_runtime_library.add_animation(runtime_name, anim)
	var player_path := StringName("%s/%s" % [RUNTIME_LIBRARY_NAME, key])
	_compiled_attacks[key] = player_path
	_attack_cache_order.append(key)
	return player_path


func _start_action(clip: StringName, priority: int) -> void:
	_begin_action(clip, priority, 1.0)


func _begin_action(clip: StringName, priority: int, scale: float) -> void:
	if not is_bound():
		return
	if priority < _priority:
		return
	if not has_clip(clip):
		_report_missing(clip, "action")
		return
	_priority = priority
	for mirror in _live_mirrors():
		mirror.mirror_apply(priority, _desired_locomotion, clip, ACTION_BLEND, scale)
	_player.speed_scale = scale
	_play_local(clip, ACTION_BLEND)


func _play(clip: StringName, blend: float) -> void:
	var scale := _player.speed_scale if _player else 1.0
	for mirror in _live_mirrors():
		mirror.mirror_apply(_priority, _desired_locomotion, clip, blend, scale)
	_play_local(clip, blend)


func _play_local(clip: StringName, blend: float) -> void:
	if not has_clip(clip):
		_report_missing(clip, "play")
		return
	if _player == null:
		return
	var local_name := _clip_name_from_player_path(clip)
	var library := _library_for_clip(clip)
	if _player.current_animation == String(clip) and _player.is_playing():
		var running := library.get_animation(local_name)
		if running:
			if running.loop_mode != Animation.LOOP_NONE:
				return
			_player.seek(0.0, true)
	_player.play(clip, blend)


## A mirror follows the rig that drives it, but is not required to have the same clip library.
##
## The first-person viewmodel is arms only, so it has no locomotion clips at all — mirroring the
## body's "idle" through the normal path made it report a missing clip on every bind, for a clip it
## is not supposed to own. A mirror silently keeps its current pose for anything it lacks; a clip
## genuinely missing from the rig that drives it is still reported by that rig.
## C-164: the mirror received the death *clip* and its priority but never the `_dead` state, so on
## the first-person viewmodel `_on_animation_finished` saw `_dead == false`, fell through its early
## return and called `_resume_locomotion()` — the arms went back to idling over a dead player. The
## driving controller's own `_dead` guard is what stops that, and it was the one field that did not
## propagate.
func mirror_apply(
	priority: int, locomotion: StringName, clip: StringName, blend: float, scale: float
) -> void:
	_priority = priority
	_desired_locomotion = locomotion
	if _player:
		_player.speed_scale = scale
	if not has_clip(clip):
		return
	_play_local(clip, blend)


## C-164: death and revival are states, not clips, and have to cross to the mirror as states.
func mirror_set_dead(dead: bool) -> void:
	_dead = dead


func _live_mirrors() -> Array[DioramaAnimController]:
	var out: Array[DioramaAnimController] = []
	for mirror in _mirrors:
		if mirror != null and is_instance_valid(mirror):
			out.append(mirror)
	if out.size() != _mirrors.size():
		_mirrors = out
	return out


func _library_for_clip(clip: StringName) -> AnimationLibrary:
	if clip.begins_with(RUNTIME_LIBRARY_NAME):
		return _runtime_library
	return _library


func _clip_name_from_player_path(clip: StringName) -> StringName:
	var text := String(clip)
	if "/" in text:
		return StringName(text.split("/")[-1])
	return clip


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
	if "/" in name_text:
		name_text = name_text.split("/")[-1]
	if name_text == "block_start" or name_text == "block_hit":
		return
	if name_text.begins_with("block_"):
		return
	_resume_locomotion()


func _report_missing(clip: StringName, context: String) -> void:
	if _missing_clips.has(clip):
		return
	_missing_clips[clip] = true
	push_warning(
		"DioramaAnimController[%s]: clip '%s' missing (%s)" % [_profile, clip, context]
	)


## Throttled per clip, matching `_report_missing_clip` directly above. This fired from
## `_locomotion_speed_scale`, which runs every physics frame — a training grunt whose stride metadata
## puts it permanently out of range produced a warning *per frame*. The validation run logged 3,198
## of these before dying; the flood is not the underlying tuning problem, but it buries every other
## diagnostic and makes the log unreadable.
func _report_clamp(clip: StringName, raw_scale: float) -> void:
	if _clamped_clips.has(clip):
		return
	_clamped_clips[clip] = true
	push_warning(
		(
			"DioramaAnimController[%s]: locomotion '%s' speed_scale %.2f clamped to [%.1f, %.1f]"
			+ " (further clamps for this clip suppressed)"
		)
		% [_profile, clip, raw_scale, SPEED_SCALE_MIN, SPEED_SCALE_MAX]
	)


func _check_hitbox_signal_listeners() -> void:
	if _hitbox_signals_warned:
		return
	_hitbox_signals_warned = true
	if not expects_hitbox_listeners:
		return
	if _events_path.is_empty():
		return
	if hitbox_open_frame.get_connections().is_empty() and hitbox_close_frame.get_connections().is_empty():
		push_warning("DioramaAnimController[%s]: hitbox signals have no listeners" % _profile)


## Called from AnimationPlayer method tracks. See DioramaAnimLibrary markers.
func anim_swing_vfx() -> void:
	swing_frame.emit()


func anim_footstep() -> void:
	footstep_frame.emit()


func anim_hitbox_on() -> void:
	hitbox_open_frame.emit()


func anim_hitbox_off() -> void:
	hitbox_close_frame.emit()


func anim_heal_gulp() -> void:
	heal_gulp_frame.emit()


func anim_heal_commit() -> void:
	heal_commit_frame.emit()


func set_speed_scale(scale: float) -> void:
	var clamped := maxf(0.01, scale)
	if _player:
		_player.speed_scale = clamped
	for mirror in _live_mirrors():
		if mirror._player:
			mirror._player.speed_scale = clamped


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
	_mirrors = _live_mirrors()
	if _additive_player and is_instance_valid(_additive_player):
		_additive_player.queue_free()
	_additive_player = null
	_additive_library = null
	if _player and is_instance_valid(_player):
		_player.queue_free()
	_player = null
	_library = null
	_runtime_library = null
	_compiled_attacks.clear()
	_attack_cache_order.clear()
	_missing_clips.clear()
	AnimLibrary.clear_attack_cache()
	_rest_pose.clear()
	_blocking = false
	_dead = false

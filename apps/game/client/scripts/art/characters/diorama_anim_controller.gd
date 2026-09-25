class_name DioramaAnimController
extends Node


signal swing_frame
signal footstep_frame
signal heal_gulp_frame
signal heal_commit_frame
signal hitbox_open_frame(generation: int)
signal hitbox_close_frame(generation: int)

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
const SPEED_SCALE_MIN := 0.35
const SPEED_SCALE_MAX := 2.2
const CLAMP_REPORT_MARGIN := 0.35

const CLAMP_REPORT_FRAMES := 30

const STRIDE_SCALE_BY_PROFILE := {
	"hound": 0.55,
	"brute": 1.25,
}

var _visual: Node3D
var _player: AnimationPlayer
var _library: AnimationLibrary
var _runtime_library: AnimationLibrary
var _head_look_offset: Node3D
var _breath_offset: Node3D
var _arm_recoil_offset: Node3D
var _torso_recoil_offset: Node3D
var _breath_time := 0.0
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
var _desired_locomotion_params: Dictionary = {}
var _blocking := false
var _dead := false
var _compiled_attacks: Dictionary = {}
var _missing_clips: Dictionary = {}
var _clamped_clips: Dictionary = {}
var _clamp_streak: Dictionary = {}
var _hitbox_signals_warned := false
var _base_speed_scale := 1.0
var _transient_speed_scale := 1.0
var _action_generation := 0

var expects_hitbox_listeners := true
var _attack_generation := 0
var _mirrors: Array[DioramaAnimController] = []


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
	_hitbox_signals_warned = false
	_player = AnimationPlayer.new()
	_player.name = "DioramaAnimPlayer"
	visual.add_child(_player)
	_player.root_node = NodePath("..")
	_player.add_animation_library(LIBRARY_NAME, _library)
	_player.add_animation_library(RUNTIME_LIBRARY_NAME, _runtime_library)
	_player.animation_finished.connect(_on_animation_finished)
	_player.playback_default_blend_time = LOCOMOTION_BLEND
	_setup_visual_offsets(visual)
	_dead = false
	_priority = Priority.LOCOMOTION
	_desired_locomotion = &"idle"
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
	for clip_name in AnimLibrary.FOOTSTEP_CLIPS:
		if not _library.has_animation(clip_name):
			return false
		var anim := _library.get_animation(clip_name)
		if anim == null:
			return false
		var markers := 0
		for track_idx in anim.get_track_count():
			if anim.track_get_type(track_idx) != Animation.TYPE_METHOD:
				continue
			if anim.track_get_path(track_idx) != NodePath(_events_path):
				continue
			for key_idx in anim.track_get_key_count(track_idx):
				var method_data: Dictionary = anim.track_get_key_value(track_idx, key_idx)
				if String(method_data.get("method", "")) == "anim_footstep":
					markers += 1
		if markers < 2:
			return false
	return true


func has_hitbox_markers(clip: StringName) -> bool:
	if not is_bound() or _library == null or _events_path.is_empty():
		return false
	if not _library.has_animation(clip):
		return false
	var animation := _library.get_animation(clip)
	if animation == null:
		return false
	var opened := false
	var closed := false
	for track_idx in animation.get_track_count():
		if animation.track_get_type(track_idx) != Animation.TYPE_METHOD:
			continue
		if animation.track_get_path(track_idx) != NodePath(_events_path):
			continue
		for key_idx in animation.track_get_key_count(track_idx):
			var method_data: Dictionary = animation.track_get_key_value(track_idx, key_idx)
			var method := String(method_data.get("method", ""))
			opened = opened or method == "anim_hitbox_on"
			closed = closed or method == "anim_hitbox_off"
	return opened and closed


func set_attack_generation(generation: int) -> void:
	_attack_generation = generation


func _setup_visual_offsets(_visual_root: Node3D) -> void:
	_head_look_offset = _insert_visual_offset(_resolve_part("Head"), "HeadLookOffset")
	_breath_offset = _insert_visual_offset(_resolve_part("Torso"), "BreathOffset")
	_arm_recoil_offset = _insert_visual_offset(_resolve_part("ArmR"), "ImpactRecoilOffset")
	_torso_recoil_offset = _insert_visual_offset(
		_resolve_part("Torso"), "ImpactRecoilOffset", ["BreathOffset"]
	)


func _insert_visual_offset(
	part: Node3D, offset_name: String, wrapped_offsets: Array[String] = []
) -> Node3D:
	if part == null:
		return null
	var offset := Node3D.new()
	offset.name = offset_name
	part.add_child(offset)
	for child in part.get_children().duplicate():
		if child == offset or child is Node3D and (child.name in ["Head", "ArmL", "ArmR"]):
			continue
		if child is VisualInstance3D or child.name in wrapped_offsets:
			part.remove_child(child)
			offset.add_child(child)
	return offset


func set_head_look_offset(rotation_offset: Vector3) -> void:
	if _head_look_offset != null and is_instance_valid(_head_look_offset):
		_head_look_offset.rotation = rotation_offset


func _process(delta: float) -> void:
	_breath_time += delta
	if _breath_offset != null and is_instance_valid(_breath_offset):
		_breath_offset.rotation.x = sin(_breath_time * TAU / 3.4) * 0.015
		_breath_offset.position.y = sin(_breath_time * TAU / 3.4) * 0.008


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
	if clip != &"idle" and not has_clip(clip) and has_clip(&"walk"):
		clip = &"walk"
	return clip


func request_locomotion(state: StringName, params: Dictionary = {}) -> void:
	for mirror in _live_mirrors():
		mirror.request_locomotion(state, params)
	if not is_bound():
		return
	_desired_locomotion = state
	_desired_locomotion_params = params.duplicate()
	if _blocking and _priority == Priority.BLOCK:
		var guarded_clip := _guarded_locomotion_clip()
		if _player.current_animation != String(guarded_clip):
			_play(guarded_clip, LOCOMOTION_BLEND)
		return
	if _priority > Priority.LOCOMOTION:
		return
	var clip := _locomotion_fallback(state)
	_player.speed_scale = _locomotion_speed_scale(clip, params)
	if _player.current_animation != String(clip):
		_play(clip, LOCOMOTION_BLEND)


func _guarded_locomotion_clip() -> StringName:
	var speed := float(_desired_locomotion_params.get("speed", 0.0))
	if _desired_locomotion != &"idle" and speed > 0.05 and has_clip(&"block_walk"):
		return &"block_walk"
	return &"block_hold"


func _locomotion_fallback(state: StringName) -> StringName:
	if has_clip(state):
		return state
	var clip_name := String(state)
	var cut := clip_name.rfind("_")
	if cut > 0:
		var base := StringName(clip_name.substr(0, cut))
		if has_clip(base):
			return base
	return state


func _locomotion_speed_scale(state: StringName, params: Dictionary) -> float:
	var meta := AnimLibrary.clip_meta(state)
	var stride_m := (
		float(meta.get("stride_m", 0.0)) * float(STRIDE_SCALE_BY_PROFILE.get(_profile, 1.0))
	)
	if stride_m <= 0.0:
		return 1.0
	var travel := float(params.get("speed", 0.0))
	var length := float(meta.get("length", 0.0))
	if travel <= 0.0 or length <= 0.0:
		return 1.0
	var raw := travel * length / stride_m
	var far_out := (
		raw < SPEED_SCALE_MIN * (1.0 - CLAMP_REPORT_MARGIN)
		or raw > SPEED_SCALE_MAX * (1.0 + CLAMP_REPORT_MARGIN)
	)
	if far_out:
		var streak := int(_clamp_streak.get(state, 0)) + 1
		_clamp_streak[state] = streak
		if streak >= CLAMP_REPORT_FRAMES:
			_report_clamp(state, raw)
	else:
		_clamp_streak[state] = 0
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


const IMPACT_RECOIL_DURATION := 0.09
const IMPACT_RECOIL_ARM_OFFSET := Vector3(0.32, 0.0, 0.5)
const IMPACT_RECOIL_TORSO_OFFSET := Vector3(-0.08, 0.0, 0.0)

var _recoil_tween: Tween


## `AN-03`: connecting used to do nothing to the *attacker's* pose -- the weapon passed through the
## target and the swing just resumed once hit-stop released. `strength` comes straight from
## `HitFeedback`'s `ImpactClass` (glancing 0.3, solid 0.7, critical 1.0), which `AnimationPlayer`
## has no built-in way to scale a single played clip by -- there is no per-call blend-amount
## parameter without an `AnimationTree`. This nudges `ArmR`/`Torso` directly instead and tweens
## them back, timed to land inside the hit-stop window: the main clip is itself nearly frozen there
## (`speed_scale` 0.05, see `HitFeedback._freeze_attacker()`), so the nudge reads as the swing
## hitching against the target rather than fighting the main pose for the property.
func play_impact_recoil(strength: float) -> void:
	if _visual == null or not is_bound() or _dead or _priority >= Priority.STAGGER:
		return
	if _arm_recoil_offset == null and _torso_recoil_offset == null:
		return
	if _recoil_tween and _recoil_tween.is_valid():
		_recoil_tween.kill()
	_recoil_tween = _visual.create_tween()
	_recoil_tween.set_parallel(true)
	var amount := clampf(strength, 0.0, 1.0)
	if _arm_recoil_offset != null:
		_arm_recoil_offset.rotation = IMPACT_RECOIL_ARM_OFFSET * amount
		_recoil_tween.tween_property(_arm_recoil_offset, "rotation", Vector3.ZERO, IMPACT_RECOIL_DURATION)
	if _torso_recoil_offset != null:
		_torso_recoil_offset.rotation = IMPACT_RECOIL_TORSO_OFFSET * amount
		_recoil_tween.tween_property(_torso_recoil_offset, "rotation", Vector3.ZERO, IMPACT_RECOIL_DURATION)


func _resolve_part(part_name: String) -> Node3D:
	if _visual == null or not _rest_pose.has(part_name):
		return null
	var data: Dictionary = _rest_pose[part_name]
	return _visual.get_node_or_null(NodePath(data.get("path", part_name))) as Node3D


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
	_blocking = false
	var scale := 1.0
	if duration > 0.05 and has_clip(&"heal"):
		var anim := _library.get_animation(&"heal")
		if anim != null and anim.length > 0.01:
			scale = clampf(anim.length / duration, 0.4, 2.5)
	_begin_action(&"heal", Priority.ATTACK, scale)


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
	_player.stop()
	_apply_rest_pose()
	if has_clip(&"RESET"):
		_play(&"RESET", 0.0)
	else:
		_play(&"idle", 0.0)


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
	_action_generation += 1
	_player.speed_scale = 1.0
	_player.play(runtime_name, ACTION_BLEND)


func play_heavy_attack(startup: float, active: float, recovery: float) -> void:
	play_attack(startup, active, recovery, AnimLibrary.heavy_clip_for(_weapon_archetype))


## `AN-04`: the bow already had a draw state (`AttackPhase.DRAWING`) with no held pose -- the
## character just stood in an idle while charge accumulated. `normalized_time` is a 0..1 fraction
## of the *played* clip's own (phase-scaled) length; freezing at the `AN-02` wound pose (roughly
## `startup / (startup+active+recovery)`) is deliberate -- that pose is already the frame a charge
## should hold on. Plays the clip exactly like `play_attack()`, then stops advancing once playback
## would reach `normalized_time`, via a one-shot timer rather than a per-frame poll (this
## controller has no existing `_process`, and one hold check a charge does not need one).
func hold_at(
	clip: StringName,
	normalized_time: float,
	startup: float = 0.0,
	active: float = 0.0,
	recovery: float = 0.0
) -> void:
	if not is_bound() or _dead:
		return
	for mirror in _live_mirrors():
		mirror.hold_at(clip, normalized_time, startup, active, recovery)
	var runtime_name := _ensure_attack_clip(clip, startup, active, recovery)
	if runtime_name == &"":
		return
	_blocking = false
	_priority = Priority.ATTACK
	_action_generation += 1
	var action_generation := _action_generation
	_player.speed_scale = 1.0
	_player.play(runtime_name, ACTION_BLEND)
	_charge_shake_active = false
	var anim := _player.get_animation(runtime_name)
	if anim == null:
		return
	var hold_time := clampf(normalized_time, 0.0, 1.0) * anim.length
	if hold_time <= 0.0:
		_player.speed_scale = 0.0
		return
	var tree := get_tree()
	if tree == null:
		return
	var timer := tree.create_timer(hold_time, false, false, false)
	timer.timeout.connect(_on_hold_reached.bind(runtime_name, action_generation))


func _on_hold_reached(runtime_name: StringName, action_generation: int) -> void:
	if not is_bound() or action_generation != _action_generation:
		return
	if _player.current_animation == runtime_name:
		_player.speed_scale = 0.0


## `AN-04`: a 1-pixel tremor at full charge, growing linearly with `amount` (0..1). Call every
## frame while charging; call with 0 (or stop calling) to settle back to the held pose. Like
## `play_impact_recoil()`, this bypasses the additive `AnimationPlayer` -- there is no per-call
## amplitude to scale a played clip by -- and is safe to write directly here because the main clip
## is frozen (`speed_scale` 0) for the entire duration a charge holds, so nothing is fighting this
## for the property.
const CHARGE_SHAKE_MAX_ANGLE := 0.073

var _charge_shake_base := Vector3.ZERO
var _charge_shake_active := false


func set_charge_shake(amount: float) -> void:
	for mirror in _live_mirrors():
		mirror.set_charge_shake(amount)
	var arm := _resolve_part("ArmR")
	if arm == null:
		return
	var clamped := clampf(amount, 0.0, 1.0)
	if clamped <= 0.0:
		if _charge_shake_active:
			arm.rotation = _charge_shake_base
			_charge_shake_active = false
		return
	if not _charge_shake_active:
		_charge_shake_base = arm.rotation
		_charge_shake_active = true
	var max_angle := CHARGE_SHAKE_MAX_ANGLE * clamped
	arm.rotation = _charge_shake_base + Vector3(
		randf_range(-max_angle, max_angle),
		randf_range(-max_angle, max_angle),
		randf_range(-max_angle, max_angle)
	)


func reset_combo() -> void:
	_combo_index = 0


func _refresh_attack_clips() -> void:
	_attack_clips = AnimLibrary.attack_clips_for(_profile, _weapon_archetype)
	_combo_index = 0


func _ensure_attack_clip(
	clip: StringName, startup: float, active: float, recovery: float
) -> StringName:
	var key := (
		"%s_%d_%d_%d_%d"
		% [
			clip,
			roundi(startup * 1000.0),
			roundi(active * 1000.0),
			roundi(recovery * 1000.0),
			roundi(PixelDioramaSettings.animation_steps_per_second * 100.0),
		]
	)
	if _compiled_attacks.has(key):
		return _compiled_attacks[key]
	# Oldest-first eviction, off the Dictionary's own insertion order — the expensive part
	# (`AnimLibrary.build_attack`) is memoised globally, so this bound only caps how many clips one
	# rig's runtime library holds. A rig cycles through a handful of attacks and never reaches the
	# limit in practice, which is why true LRU ordering was not worth a scan on every cache hit.
	while _compiled_attacks.size() >= ATTACK_CACHE_LIMIT:
		var evict_key: String = _compiled_attacks.keys()[0]
		var evict_path: StringName = _compiled_attacks[evict_key]
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
	if priority >= Priority.STAGGER:
		_clear_impact_recoil()
	_priority = priority
	_action_generation += 1
	_base_speed_scale = scale
	_transient_speed_scale = 1.0
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


func mirror_apply(
	priority: int, locomotion: StringName, clip: StringName, blend: float, scale: float
) -> void:
	if priority >= Priority.STAGGER:
		_clear_impact_recoil()
	_priority = priority
	_desired_locomotion = locomotion
	if _player:
		_player.speed_scale = scale
	if not has_clip(clip):
		return
	_play_local(clip, blend)


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
		_play(_guarded_locomotion_clip(), ACTION_BLEND)
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
	# Hitbox callbacks are connected lazily when an attack with authored markers starts. Checking
	# during setup reports a false warning for the player before their first attack.
	pass


func anim_swing_vfx() -> void:
	swing_frame.emit()


func anim_footstep() -> void:
	footstep_frame.emit()


func anim_hitbox_on() -> void:
	_warn_if_hitbox_signals_unhandled()
	hitbox_open_frame.emit(_attack_generation)


func anim_hitbox_off() -> void:
	_warn_if_hitbox_signals_unhandled()
	hitbox_close_frame.emit(_attack_generation)


func _warn_if_hitbox_signals_unhandled() -> void:
	if _hitbox_signals_warned or not expects_hitbox_listeners:
		return
	if not hitbox_open_frame.get_connections().is_empty() or not hitbox_close_frame.get_connections().is_empty():
		return
	_hitbox_signals_warned = true
	push_warning("DioramaAnimController[%s]: emitted hitbox signal without a listener" % _profile)


func anim_heal_gulp() -> void:
	heal_gulp_frame.emit()


func anim_heal_commit() -> void:
	heal_commit_frame.emit()


func set_speed_scale(scale: float) -> void:
	_base_speed_scale = maxf(0.01, scale)
	_apply_composed_speed()


func begin_hitstop(factor: float) -> int:
	_transient_speed_scale = clampf(factor, 0.01, 1.0)
	_apply_composed_speed()
	return _action_generation


func end_hitstop(generation: int) -> void:
	if generation != _action_generation:
		return
	_transient_speed_scale = 1.0
	_apply_composed_speed()


func _apply_composed_speed() -> void:
	var clamped := maxf(0.01, _base_speed_scale * _transient_speed_scale)
	if _player:
		_player.speed_scale = clamped
	for mirror in _live_mirrors():
		if mirror._player:
			mirror._player.speed_scale = clamped


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
	if _recoil_tween and _recoil_tween.is_valid():
		_recoil_tween.kill()
	_recoil_tween = null
	_mirrors = _live_mirrors()
	_head_look_offset = null
	_breath_offset = null
	_arm_recoil_offset = null
	_torso_recoil_offset = null
	if _player and is_instance_valid(_player):
		_player.queue_free()
	_player = null
	_library = null
	_runtime_library = null
	_compiled_attacks.clear()
	_missing_clips.clear()
	_rest_pose.clear()
	_blocking = false
	_dead = false
	_base_speed_scale = 1.0
	_transient_speed_scale = 1.0
	_action_generation += 1


func _clear_impact_recoil() -> void:
	if _recoil_tween and _recoil_tween.is_valid():
		_recoil_tween.kill()
	_recoil_tween = null
	if _arm_recoil_offset != null and is_instance_valid(_arm_recoil_offset):
		_arm_recoil_offset.rotation = Vector3.ZERO
	if _torso_recoil_offset != null and is_instance_valid(_torso_recoil_offset):
		_torso_recoil_offset.rotation = Vector3.ZERO

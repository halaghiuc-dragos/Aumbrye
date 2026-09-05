extends CharacterBody3D
class_name CastleEnemyBase


enum State {
	PATROL, CHASE, INVESTIGATE, RETREAT, CIRCLE, WINDUP, ATTACK, RECOVERY, STAGGER, DEAD,
	GUARD, SIDESTEP, PUNISH,
}

signal enemy_died
signal attack_telegraph_started(attack_class: String)
signal attack_active
signal boss_phase_entered(index: int, phase: Dictionary)

signal phase_changed(phase: int)

const DATA_PATH := ""

const ENEMY_TURN_SPEED := 22.0

## How far into a wind-up the enemy may still turn to track the player. Past this it is locked to
## the heading it committed to, which is what makes a wind-up dodgeable rather than homing.
const WINDUP_TRACKING_FRACTION := 0.55
const WINDUP_TRACKING_SPEED_MULT := 0.45
const ATTACK_TRACKING_SPEED_MULT := 0.0
const RECOVERY_TRACKING_SPEED_MULT := 0.25
const WINDUP_APPROACH_SPEED_MULT := 0.45
const RECOVERY_APPROACH_SPEED_MULT := 0.3
const PATROL_SPEED_MULT := 0.45
const SIDESTEP_DURATION := 0.35
const SIDESTEP_IFRAME_FRACTION := 0.6
const SIDESTEP_SPEED := 6.0
const GUARD_FALLBACK_DURATION := 0.6
const PUNISH_WINDOW_DEFAULT := 0.0
## `EN-12`: an elite is a visibly, mechanically harder fight, not `is_elite` metadata nobody reads.
const ELITE_POISE_MULT := 1.4
const ELITE_SCALE_MULT := 1.15
const ELITE_RIM_TINT := Color(0.95, 0.78, 0.25, 1.0)
const HP_BAR_SCRIPT := preload("res://scripts/ui/enemy_health_bar.gd")
const MaterialDissolveScript := preload("res://scripts/art/characters/material_dissolve.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")
const GlobalDropServiceScript := preload("res://scripts/loot/global_drop_service.gd")
const CharacterFloorSnapScript := preload("res://scripts/art/characters/character_floor_snap.gd")
const PixelStyleScript := preload("res://scripts/art/style/pixel_diorama_style.gd")
const LightEmbersScript := preload("res://scripts/art/vfx/light_embers.gd")
const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
const CharacterRigCatalogScript := preload("res://scripts/art/characters/character_rig_catalog.gd")
const AnimControllerScript := preload("res://scripts/art/characters/diorama_anim_controller.gd")
const ShieldHurtboxScript := preload("res://scripts/combat/shield_hurtbox.gd")
const CombatLayersScript := preload("res://scripts/combat/combat_layers.gd")

@export var player_path: NodePath

@export var enemy_id: String = ""

@export_flags_3d_physics var los_mask: int = CombatLayersScript.WORLD_OCCLUDERS

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _body_collision: CollisionShape3D = $CollisionShape3D

var _enemy_rng := RandomNumberGenerator.new()
var _data: Dictionary = {}
var _hp_bar: EnemyHealthBar
var _state := State.PATROL
var _player: Node3D
var _health: Health
var _poise: Poise
var _knockback: Knockback
var _hitbox: Hitbox
var _hurtbox: Hurtbox
## `BS-01` "vulnerability" phases: a procedurally-spawned weak-point Hurtbox, freed once the phase
## that authored it ends.
var _weak_point_hurtbox: Hurtbox
var _state_timer := 0.0
var _cooldown := 0.0
var _stagger_timer := 0.0
var _spawn_origin := Vector3.ZERO
var _patrol_target := Vector3.ZERO
var _patrol_wait := 0.0
var _aggro_locked := false
var _diorama_visual: Node3D
## `BS-03`: the current phase's persistent scale multiplier. `_end_attack()` restores the diorama's
## rest scale to this instead of `Vector3.ONE`, so a windup's transient grow-and-release doesn't
## erase a phase's lasting size change.
var _phase_scale_mult := 1.0
var _animator: DioramaAnimController
var _anim_profile := "melee"
var _last_known_player_pos := Vector3.ZERO
var _attack_token_group := ""
var _attack_token_held := false
var _current_attack_data: Dictionary = {}
var _combo_step := 0
var _combat_registered := false
var _deaggro_los_timer := 0.0
var _weapon_charge: Node3D
var _windup_duration := 0.0
var _in_windup_hold := false
var _windup_hold_timer := 0.0
var _windup_will_feint := false
var _short_recovery_cooldown := false

## RM-08: "idle" (default) is today's always-perceiving behaviour. "ambush" spawns hidden, frozen
## and unhittable until `wake_ambush()` is called (by `DungeonBuilder.wake_ambushers()` when the
## player enters the room). "delayed" does the same but wakes itself on a timer instead of waiting
## for a call -- simpler than deferring instantiation entirely, and invisible-and-frozen already
## reads as "not here yet" to the player.
var _spawn_trigger := "idle"
var _spawn_trigger_delay := 0.0
var _ambush_hidden := false
var _saved_collision_layer := 0
var _saved_collision_mask := 0
const FEINT_COOLDOWN := 0.3
## `PH-02`: matches `PlayerCombatReactions.STAGGER_POISE_HIGH` so a poise break carries the same
## knockback weight on both sides of a fight, rather than each side inventing its own scale.
const STAGGER_POISE_HIGH_REFERENCE := 45.0

## `EN-07`: defensive verbs. `is_guarding` is public (no underscore) so `ShieldHurtbox` can read it
## by name across the module boundary the same way it already reads `block_mitigation` -- mitigation
## used to apply to every frontal hit unconditionally, which is passive, not a decision.
var is_guarding := false
var _sidestep_timer := 0.0
var _sidestep_iframe_timer := 0.0
var _guard_timer := 0.0
var _punish_watching := false
var _punish_watch_timer := 0.0
var _defensive_token_held := false
var _last_hit_direction := Vector3.ZERO
var _last_hit_poise_damage := 0.0
var _catalog_id_override := ""
var _damage_multiplier := 1.0
var _base_damage_multiplier := 1.0
var _phase_damage_multiplier := 1.0
var _sync_hitbox_from_anim := false
const DEAGGRO_LOS_TIMEOUT := 3.0

var _move_speed := 3.5
var _attack_range := 2.2
var _aggro_range := 10.0
var _deaggro_range := 16.0
var _patrol_radius := 4.0
var _attack_cooldown_data := 1.5
var _retreat_threshold := 0.0
var _stagger_duration_data := 1.0
var _preferred_range := 10.0
var _retreat_range := 6.0

var _attacks: Array = []
## `BS-01` "pattern" phases: walk `_attacks` in authored order instead of the weighted roll.
var _attacks_ordered := false
var _ordered_attack_index := 0
var _base_attacks: Array = []
var _max_attack_range := 2.2
var _engage_range := 2.2
var _is_boss := false
var _phase_controller: Node
var _phase_lock_timer := 0.0
var _phase_invuln_timer := 0.0

const AWARENESS_INVESTIGATE := 0.45
const ALLY_ALERT_AWARENESS := 0.7
var _awareness := 0.0
var _alert_broadcast := false
var _vision_cone_cos := -0.34
var _hearing_range := 7.0
var _awareness_rate := 2.4
var _awareness_decay := 0.7
var _alert_radius := 12.0
var _perception_frame := -1

var _circle_direction := 1.0
var _desired_flank_angle_deg := 0.0
var _circle_radius_mult := 1.4
var _room_id := 0
var _room_registered := false
var _role: int = EnemyBlackboard.Role.ENGAGER
const FLANKER_RADIUS_MULT := 1.15
const WAITER_RADIUS_MULT := 1.7
var _nav_agent: NavigationAgent3D
var _nav_probe_timer := 0.0
var _nav_repath_timer := 0.0
const NAV_PROBE_INTERVAL := 1.5
const NAV_REPATH_INTERVAL := 0.3
const NAV_MAX_STEP_DISTANCE_SQ := 36.0

var _castle_run: Node
var _los_cache_frame := -1
var _los_cache_result := false
var _dist_to_player_sq_cache_frame := -1
var _dist_to_player_sq_cache := INF

const ADD_SPAWN_HEIGHT := 0.15
const AI_LOD_NEAR_RANGE_SQ := 400.0
const AI_LOD_MID_RANGE_SQ := 1600.0
const AI_LOD_MID_STRIDE := 4
const AI_LOD_FAR_STRIDE := 16
var _ai_tick_phase := 0

## `EN-10`: the five optional, data-driven behaviour mixins. Each is guarded by `_data.has("<key>")`
## so an enemy that does not author the key pays nothing beyond a dictionary lookup per relevant
## tick. See `_try_leap_attack()`, `_process_burrow_mixin()`, `_apply_splits_on_death()`,
## `_process_summons_mixin()` and `_process_aura_mixin()`.
var _leap_cooldown := 0.0
const BURROW_HIDE_DURATION := 0.35
const BURROW_REVEAL_TELEGRAPH := 0.5
var _burrow_cooldown := 0.0
var _burrow_phase := ""
var _burrow_timer := 0.0
var _summon_cooldown := 0.0
var _summoned_adds: Array = []
var _aura_timer := 0.0


func set_damage_multiplier(mult: float) -> void:
	_base_damage_multiplier = maxf(0.1, mult)
	_damage_multiplier = maxf(0.1, _base_damage_multiplier * _phase_damage_multiplier)


## `BS-08`: the biome's final-floor arena modifier, applied once when the boss spawns -- see
## `dungeon_builder.gd:_apply_final_floor_arena_flavor()`. `damageMult` folds into
## `_base_damage_multiplier`, the same persistent hook `set_damage_multiplier()` uses, so it survives
## every later phase transition; `moveSpeedMult`/`attackCooldownMult` are a one-time nudge on top of
## whatever the boss's own `_data` baseline currently is and get overwritten the next time a
## health-threshold phase transition calls `apply_phase_modifiers()` from that baseline again -- fine
## for a single arena-wide flavor multiplier, not meant to out-fight a boss's own phase tuning.
func apply_arena_modifier(mods: Dictionary) -> void:
	if mods.has("damageMult"):
		set_damage_multiplier(_base_damage_multiplier * float(mods["damageMult"]))
	if mods.has("moveSpeedMult"):
		_move_speed = maxf(0.01, _move_speed * float(mods["moveSpeedMult"]))
	if mods.has("attackCooldownMult"):
		_attack_cooldown_data = maxf(0.0, _attack_cooldown_data * float(mods["attackCooldownMult"]))
	if mods.has("poiseMult") and _poise:
		_poise.configure(_poise.max_poise * float(mods["poiseMult"]), _stagger_duration_data)


func get_health_ratio() -> float:
	if _health == null or _health.max_health <= 0.0:
		return 1.0
	return clampf(_health.current / _health.max_health, 0.0, 1.0)


func apply_phase_modifiers(mods: Dictionary) -> void:
	_move_speed = maxf(
		0.01, float(_data.get("move_speed", 3.5)) * float(mods.get("moveSpeedMult", 1.0))
	)
	_attack_cooldown_data = maxf(
		0.0, float(_data.get("attack_cooldown", 1.5)) * float(mods.get("attackCooldownMult", 1.0))
	)
	_phase_damage_multiplier = maxf(0.1, float(mods.get("damageMult", 1.0)))
	_damage_multiplier = maxf(0.1, _base_damage_multiplier * _phase_damage_multiplier)
	if _poise and mods.has("poiseMult"):
		_poise.configure(
			float(_data.get("poise", 40.0)) * maxf(0.1, float(mods["poiseMult"])),
			_stagger_duration_data
		)
	_apply_vulnerability(mods.get("vulnerability", {}) as Dictionary)


## `BS-01` "vulnerability" phases: while `spec` is non-empty, the boss's own body `Hurtbox` takes
## reduced damage and a procedurally-spawned weak-point `Hurtbox` (a second `Area3D` region, per
## `hurtbox.gd`'s existing `region`/`region_damage_mult` support) is the only thing that still takes
## full damage. Called on every phase entry -- including a phase with no `vulnerability` entry,
## which is what clears it back to normal.
func _apply_vulnerability(spec: Dictionary) -> void:
	if _hurtbox == null:
		return
	if spec.is_empty():
		_hurtbox.region_damage_mult = 1.0
		if _weak_point_hurtbox and is_instance_valid(_weak_point_hurtbox):
			_weak_point_hurtbox.queue_free()
		_weak_point_hurtbox = null
		return
	_hurtbox.region_damage_mult = clampf(float(spec.get("bodyDamageMult", 0.35)), 0.0, 1.0)
	if _weak_point_hurtbox == null or not is_instance_valid(_weak_point_hurtbox):
		_weak_point_hurtbox = Hurtbox.new()
		_weak_point_hurtbox.name = "VulnerabilityWeakPoint"
		_weak_point_hurtbox.collision_layer = _hurtbox.collision_layer
		_weak_point_hurtbox.collision_mask = _hurtbox.collision_mask
		_weak_point_hurtbox.team = _hurtbox.team
		_weak_point_hurtbox.health_path = NodePath("../Health")
		_weak_point_hurtbox.poise_path = NodePath("../Poise")
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		shape.shape = SphereShape3D.new()
		_weak_point_hurtbox.add_child(shape)
		add_child(_weak_point_hurtbox)
		_weak_point_hurtbox.damaged.connect(_on_hurt)
	_weak_point_hurtbox.region = String(spec.get("region", "weakpoint"))
	_weak_point_hurtbox.region_damage_mult = maxf(0.0, float(spec.get("regionDamageMult", 1.5)))
	var sphere := (_weak_point_hurtbox.get_node("CollisionShape3D") as CollisionShape3D).shape as SphereShape3D
	sphere.radius = maxf(0.1, float(spec.get("radius", 0.4)))
	var offset := Vector3(0.0, 1.6, 0.0)
	var raw_offset: Variant = spec.get("offset", null)
	if raw_offset is Array and (raw_offset as Array).size() >= 3:
		var parts: Array = raw_offset
		offset = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	_weak_point_hurtbox.position = offset


func get_lock_threat() -> float:
	if _state in [State.WINDUP, State.ATTACK]:
		return 0.6
	if _aggro_locked:
		return 0.3
	return 0.0


func get_lock_priority() -> float:
	var priority := 0.0
	if _is_boss_enemy():
		priority += 3.0
	else:
		priority += clampf(float(_data.get("threat_cost", 20)) / 100.0, 0.0, 1.5)
	if _state in [State.WINDUP, State.ATTACK]:
		priority += 0.75
	elif _aggro_locked:
		priority += 0.25
	return priority


func get_lock_orbit_radius() -> float:
	var collision_radius := _get_collision_radius()
	if _is_boss_enemy():
		return maxf(LockOnMovement.ORBIT_RADIUS_BOSS_MIN, collision_radius + LockOnMovement.ORBIT_RADIUS_BOSS_PAD)
	if collision_radius <= 0.38:
		return LockOnMovement.ORBIT_RADIUS_SMALL
	if _anim_profile == "brute" or collision_radius >= 0.55:
		return LockOnMovement.ORBIT_RADIUS_LARGE
	return LockOnMovement.ORBIT_RADIUS_STANDARD


func _get_collision_radius() -> float:
	if _body_collision and _body_collision.shape is CapsuleShape3D:
		return (_body_collision.shape as CapsuleShape3D).radius
	return 0.45


func _is_boss_enemy() -> bool:
	if not _data.is_empty():
		return _is_boss
	var catalog_id := get_enemy_id()
	return catalog_id.contains("boss") or catalog_id.contains("miniboss")


func _ready() -> void:
	add_to_group("lockable")
	add_to_group("enemy")
	_spawn_origin = global_position
	_enemy_rng.seed = (
		FloorSeedMix.mix(RunFlow.current_seed, RunFlow.current_floor) ^ hash(str(get_path()))
	)
	var catalog_id := get_enemy_id()
	if catalog_id.is_empty():
		_data = ContentLoader.load_json(get_data_path())
	else:
		_data = EnemyCatalog.get_definition(catalog_id)
	_health = get_node_or_null("Health") as Health
	_poise = get_node_or_null("Poise") as Poise
	_knockback = get_node_or_null("Knockback") as Knockback
	_hitbox = get_node_or_null("AttackPivot/Hitbox") as Hitbox
	_hurtbox = get_node_or_null("Hurtbox") as Hurtbox
	if player_path and not player_path.is_empty():
		_player = get_node_or_null(player_path) as Node3D
	if _health:
		_health.configure(_data.get("health", 80.0))
		_health.died.connect(_on_died)
	if _poise:
		var poise_max: float = _data.get("poise", 40.0)
		if _is_elite():
			poise_max *= ELITE_POISE_MULT
		_poise.configure(poise_max, float(_data.get("stagger_duration", 1.0)))
		_poise.poise_broken.connect(_on_poise_broken)
	if _hurtbox:
		_hurtbox.damaged.connect(_on_hurt)
		_apply_hurtbox_data()
	_unpack_tuning()
	_castle_run = get_tree().get_first_node_in_group("castle_run")
	_ai_tick_phase = int(get_instance_id() % AI_LOD_FAR_STRIDE)
	_circle_direction = 1.0 if _enemy_rng.randf() < 0.5 else -1.0
	_setup_diorama_visual()
	if _health:
		_attach_health_bar()
	if _is_elite():
		_apply_elite_status()
	_setup_phase_controller()
	if not boss_phase_entered.is_connected(_relay_phase_changed):
		boss_phase_entered.connect(_relay_phase_changed)
	if _is_boss_enemy() and AudioDirector:
		AudioDirector.play_boss_music()
	_pick_patrol_target()
	_join_room_board()
	match _spawn_trigger:
		"ambush":
			_enter_ambush_hidden()
		"delayed":
			_enter_ambush_hidden()
			get_tree().create_timer(maxf(0.05, _spawn_trigger_delay)).timeout.connect(wake_ambush)


## Called by `DungeonBuilder` before this node enters the tree, so `_ready()` can read it.
func set_spawn_trigger(trigger: String, delay: float = 0.0) -> void:
	_spawn_trigger = trigger
	_spawn_trigger_delay = delay


func _enter_ambush_hidden() -> void:
	_ambush_hidden = true
	visible = false
	set_physics_process(false)
	set_process(false)
	if _hurtbox:
		_hurtbox.monitoring = false
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	collision_layer = 0
	collision_mask = 0


## `DungeonBuilder.wake_ambushers(room_id)` calls this on room entry; a "delayed" enemy calls it on
## its own timer instead. Safe to call more than once -- only the first call does anything.
func wake_ambush() -> void:
	if not _ambush_hidden:
		return
	_ambush_hidden = false
	if VfxService:
		VfxService.play_telegraph(global_position, 1.4, 0.35)
	visible = true
	set_physics_process(true)
	set_process(true)
	if _hurtbox:
		_hurtbox.monitoring = true
	collision_layer = _saved_collision_layer
	collision_mask = _saved_collision_mask
	_latch_aggro()


func get_arena_half_extent() -> float:
	return maxf(1.0, float(_data.get("arenaHalfExtent", 12.0)))


func clamp_to_arena(center: Vector3) -> void:
	var half := get_arena_half_extent()
	var offset := global_position - center
	offset.x = clampf(offset.x, -half, half)
	offset.z = clampf(offset.z, -half, half)
	global_position = center + offset


func _relay_phase_changed(index: int, _phase: Dictionary) -> void:
	phase_changed.emit(index + 1)


func _join_room_board() -> void:
	if _is_boss or _room_registered:
		return
	_room_id = EnemyBlackboard.room_key(self)
	EnemyBlackboard.register(_room_id, self)
	_room_registered = true


func _exit_tree() -> void:
	_release_attack_token()
	if not _room_registered:
		return
	EnemyBlackboard.unregister(_room_id, self)
	_room_registered = false


func set_ai_role(role: int) -> void:
	_role = role


func _unpack_tuning() -> void:
	_move_speed = maxf(0.01, float(_data.get("move_speed", 3.5)))
	_attack_range = float(_data.get("attack_range", 2.2))
	_aggro_range = float(_data.get("aggro_range", 10.0))
	_deaggro_range = float(_data.get("deaggro_range", _aggro_range * 1.6))
	_patrol_radius = float(_data.get("patrol_radius", 4.0))
	_attack_cooldown_data = float(_data.get("attack_cooldown", 1.5))
	_retreat_threshold = float(_data.get("retreat_threshold", 0.0))
	_stagger_duration_data = float(_data.get("stagger_duration", 1.0))
	_preferred_range = float(_data.get("preferred_range", 10.0))
	_retreat_range = float(_data.get("retreat_range", 6.0))
	_is_boss = bool(_data.get("isBoss", false))
	_base_attacks = _data.get("attacks", []) as Array
	set_active_attacks(_base_attacks)
	var cone_deg := clampf(float(_data.get("vision_cone_deg", 140.0)), 10.0, 360.0)
	_vision_cone_cos = cos(deg_to_rad(cone_deg * 0.5))
	_hearing_range = float(_data.get("hearing_range", _aggro_range * 0.7))
	_awareness_rate = maxf(0.05, float(_data.get("awareness_rate", 2.4)))
	_awareness_decay = maxf(0.0, float(_data.get("awareness_decay", 0.7)))
	_alert_radius = maxf(0.0, float(_data.get("alert_radius", 12.0)))
	_circle_radius_mult = maxf(1.0, float(_data.get("circle_radius_mult", 1.4)))


func set_active_attacks(list: Array, ordered: bool = false) -> void:
	_attacks = list
	_attacks_ordered = ordered
	_ordered_attack_index = 0
	_max_attack_range = 0.0
	_engage_range = INF
	for entry in _attacks:
		if not (entry is Dictionary):
			continue
		var reach := float((entry as Dictionary).get("max_range", _attack_range))
		_max_attack_range = maxf(_max_attack_range, reach)
		_engage_range = minf(_engage_range, reach)
	if _max_attack_range <= 0.0 or is_inf(_engage_range):
		_max_attack_range = _attack_range
		_engage_range = _attack_range


func get_base_attacks() -> Array:
	return _base_attacks


func _setup_phase_controller() -> void:
	if _phase_controller != null:
		return
	var phases: Array = _data.get("phases", []) as Array
	if phases.is_empty():
		return
	var controller_script := load("res://scripts/bosses/boss_phase_controller.gd") as GDScript
	if controller_script == null:
		return
	_phase_controller = controller_script.new() as Node
	_phase_controller.name = "PhaseController"
	add_child(_phase_controller)
	_phase_controller.call("setup", self, phases)


func spawn_adds(spec: Dictionary) -> Array[Node]:
	var spawned: Array[Node] = []
	var catalog_id := String(spec.get("enemyId", ""))
	if catalog_id.is_empty() or not EnemyCatalog.has_enemy(catalog_id):
		return spawned
	var scene: PackedScene = EnemyCatalog.get_scene(catalog_id)
	var parent := get_parent()
	if scene == null or parent == null:
		return spawned
	var count := maxi(1, int(spec.get("count", 1)))
	var radius := maxf(1.0, float(spec.get("radius", 5.0)))
	for i in count:
		var add := scene.instantiate() as Node3D
		if add == null:
			continue
		var angle := TAU * (float(i) / float(count)) + _enemy_rng.randf_range(-0.35, 0.35)
		var offset := Vector3(cos(angle) * radius, ADD_SPAWN_HEIGHT, sin(angle) * radius)
		add.position = _local_spawn_point(parent, global_position + offset)
		var add_enemy := add as CastleEnemyBase
		if add_enemy != null:
			add_enemy.set_catalog_id(catalog_id)
			if _player:
				add_enemy.set_player(_player)
		parent.add_child(add)
		spawned.append(add)
	return spawned


func spawn_hazard_ring(spec: Dictionary) -> Array[Node]:
	var spawned: Array[Node] = []
	var scene_path := String(spec.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return spawned
	var scene: PackedScene = load(scene_path)
	var parent := get_parent()
	if scene == null or parent == null:
		return spawned
	var count := maxi(1, int(spec.get("count", 1)))
	var radius := maxf(1.0, float(spec.get("radius", 6.0)))
	var min_reach := clampf(float(spec.get("minRadiusFraction", 0.55)), 0.0, 1.0)
	var lifetime := maxf(0.0, float(spec.get("lifetime", 0.0)))
	for i in count:
		var hazard := scene.instantiate() as Node3D
		if hazard == null:
			continue
		var angle := TAU * (float(i) / float(count)) + _enemy_rng.randf_range(-0.4, 0.4)
		var reach := radius * _enemy_rng.randf_range(min_reach, 1.0)
		var target := global_position + Vector3(cos(angle) * reach, 0.05, sin(angle) * reach)
		hazard.position = _local_spawn_point(parent, target)
		parent.add_child(hazard)
		if lifetime > 0.0:
			get_tree().create_timer(lifetime).timeout.connect(hazard.queue_free)
		spawned.append(hazard)
	return spawned


func _local_spawn_point(parent: Node, world_point: Vector3) -> Vector3:
	if parent is Node3D:
		return (parent as Node3D).to_local(world_point)
	return world_point


func restart_phases() -> void:
	_phase_lock_timer = 0.0
	_phase_invuln_timer = 0.0
	_phase_damage_multiplier = 1.0
	_damage_multiplier = _base_damage_multiplier
	_unpack_tuning()
	_phase_scale_mult = 1.0
	if _diorama_visual and is_instance_valid(_diorama_visual):
		_diorama_visual.scale = Vector3.ONE
		_apply_mesh_tint(Color.WHITE)
		MaterialFlashScript.clear_persistent_glow(_diorama_visual)
	_apply_vulnerability({})
	if _phase_controller and _phase_controller.has_method("reset_phases"):
		_phase_controller.call("reset_phases")


func get_phase_index() -> int:
	if _phase_controller and _phase_controller.has_method("get_phase_index"):
		return int(_phase_controller.call("get_phase_index"))
	return 0


func begin_phase_transition(lock_duration: float, invulnerable_for: float) -> void:
	_phase_lock_timer = maxf(0.0, lock_duration)
	_phase_invuln_timer = maxf(0.0, invulnerable_for)
	if _state in [State.WINDUP, State.ATTACK]:
		_end_attack()
	if _hitbox:
		_hitbox.disable()
		_hitbox.reset_swing()
	hide_attack_windup_bar()
	_combo_step = 0
	_release_attack_token()
	is_guarding = false
	_sidestep_iframe_timer = 0.0
	_punish_watching = false
	if _animator and _animator.is_bound():
		_animator.set_blocking(false)
	_release_defensive_token()
	_state = State.CHASE
	_cooldown = maxf(_cooldown, _phase_lock_timer)


func is_immune() -> bool:
	return _phase_invuln_timer > 0.0 or _sidestep_iframe_timer > 0.0


func notify_phase_entered(index: int, phase: Dictionary) -> void:
	boss_phase_entered.emit(index, phase)


## `BS-02`: called by the boss-intro sequence while the camera holds. Phase 1 already entered (its
## `spawnAdds`/`hazards` already ran) the instant `BossPhaseController` started ticking at spawn, so
## this only replays the telegraph flash/vfx in sync with the framing shot rather than redoing them.
func play_intro_telegraph() -> void:
	if _phase_controller and _phase_controller.has_method("replay_intro_telegraph"):
		_phase_controller.call("replay_intro_telegraph")


func set_player(player: Node3D) -> void:
	_player = player


func get_player() -> Node3D:
	return _player


## `EN-08`: a flanker's target bearing (degrees, signed relative to the player's own facing), set
## by `EnemyBlackboard._assign_flank_bearings()`. `_process_circle()` steers toward it instead of
## just orbiting at a radius multiplier.
func set_desired_flank_angle_deg(angle_deg: float) -> void:
	_desired_flank_angle_deg = angle_deg


func set_catalog_id(id: String) -> void:
	_catalog_id_override = id
	if not _data.is_empty() or id.is_empty():
		return
	_data = EnemyCatalog.get_definition(id)
	if _data.is_empty():
		return
	_unpack_tuning()
	if _health:
		_health.configure(_data.get("health", 80.0))
	if _poise:
		_poise.configure(
			float(_data.get("poise", 40.0)), float(_data.get("stagger_duration", 1.0))
		)


func get_enemy_id() -> String:
	if not _catalog_id_override.is_empty():
		return _catalog_id_override
	return _resolve_enemy_id()


## AD-06: the death recap wants to name the exact attack that landed the killing blow, not just
## the attack class -- `_current_attack_data` already carries it, this just exposes it publicly.
func get_current_attack_name() -> String:
	return str(_current_attack_data.get("name", _current_attack_data.get("id", "")))


func _resolve_enemy_id() -> String:
	return enemy_id


func get_data_path() -> String:
	var catalog_id := get_enemy_id()
	if catalog_id.is_empty():
		return DATA_PATH
	return EnemyCatalog.get_content_path(catalog_id)


func _setup_diorama_visual() -> void:
	var catalog_id := get_enemy_id()
	if catalog_id.is_empty():
		catalog_id = str(_data.get("id", ""))
	_anim_profile = CharacterSkin.profile_for_enemy_data(_data)
	var theme := CharacterSkin.theme_for_enemy_id(catalog_id)
	_diorama_visual = CharacterSkin.build_enemy_body(self, _anim_profile, theme, catalog_id, _data)
	if _mesh:
		_mesh.visible = false
	CharacterFloorSnapScript.snap_character(self, _diorama_visual)
	_animator = AnimControllerScript.new()
	_animator.name = "AnimController"
	add_child(_animator)
	_animator.set_profile(_anim_profile)
	_animator.set_theme(theme)
	_animator.set_weapon(String(_data.get("weapon_kit", _default_weapon_for_profile())))
	_animator.bind(_diorama_visual)
	_animator.swing_frame.connect(_on_anim_swing_frame)
	_animator.hitbox_open_frame.connect(_on_anim_hitbox_open)
	_animator.hitbox_close_frame.connect(_on_anim_hitbox_close)


## Tolerant by design: `windup_variance` can land the animation's open frame a tick or two before
## `_start_attack()` transitions, and returning early there drops the swing entirely. Promote the
## phase instead. `WeaponController.enable_hitbox_from_anim` handles the same race the same way.
func _on_anim_hitbox_open() -> void:
	if _hitbox == null:
		return
	if _state == State.WINDUP:
		_start_attack()
	if _state != State.ATTACK:
		return
	if bool(_current_attack_data.get("no_hitbox", false)):
		return
	_hitbox.enable()


func _on_anim_hitbox_close() -> void:
	if _hitbox:
		_hitbox.disable()
		_hitbox.reset_swing()


func _default_weapon_for_profile() -> String:
	match _anim_profile:
		"ranged":
			return "bow"
		"brute":
			return "greatsword"
		"caster", "beast", "hound":
			return ""
	return "sword"


func _on_anim_swing_frame() -> void:
	var anchor: Array = VfxService.resolve_combat_anchor(self)
	VfxService.play_weapon_trail(anchor[0], anchor[1], Color(0.95, 0.62, 0.42))


func get_diorama_visual() -> Node3D:
	return _diorama_visual


func get_hp_bar_height() -> float:
	return _estimate_body_top_y() + 0.22


func get_lock_aim_point() -> Vector3:
	var chest_y := maxf(1.0, _estimate_body_top_y() * 0.55)
	return global_position + Vector3(0.0, chest_y, 0.0)


func _estimate_body_top_y() -> float:
	if _diorama_visual:
		return _node_max_y(_diorama_visual)
	if _body_collision and _body_collision.shape is CapsuleShape3D:
		var cap := _body_collision.shape as CapsuleShape3D
		return _body_collision.position.y + cap.height * 0.5
	return 1.55


func _node_max_y(node: Node3D) -> float:
	var max_y := 0.0
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh is BoxMesh:
				var box := mesh_instance.mesh as BoxMesh
				max_y = maxf(max_y, mesh_instance.position.y + box.size.y * 0.5)
		elif child is Node3D:
			max_y = maxf(max_y, child.position.y + _node_max_y(child as Node3D))
	return max_y


func _attach_health_bar() -> void:
	_hp_bar = HP_BAR_SCRIPT.new() as EnemyHealthBar
	_hp_bar.name = "HealthBar"
	add_child(_hp_bar)
	_hp_bar.setup(_health, get_hp_bar_height(), _poise)


func _is_elite() -> bool:
	return bool(get_meta("is_elite", false))


## `EN-12`: the poise multiplier lands earlier, alongside `_poise.configure()` in `_ready()` --
## this covers the rest: +15% scale on the whole body (not `_mesh`, which the windup wind-up and
## other transient effects scale on top of, so the two must compose rather than fight), a
## persistent gold rim distinct from any class-tinted VFX, and the name plate on the health bar.
func _apply_elite_status() -> void:
	scale *= ELITE_SCALE_MULT
	var rim_anchor := Vector3(0.0, get_hp_bar_height() * 0.5, 0.0)
	var embers := LightEmbersScript.attach(self, rim_anchor, ELITE_RIM_TINT, 0.6, 0.9)
	if embers:
		embers.name = "EliteRim"
	if _hp_bar:
		var display_name := str(_data.get("title", _data.get("name", "")))
		_hp_bar.mark_elite(display_name)


## `EN-09`: the HUD's off-screen danger chevron walks this group on its own slow tick rather than
## being pushed to per-frame -- see `CombatHud._update_danger_chevrons()`. Membership, not a
## per-enemy screen check, is what keeps that cheap.
const TELEGRAPHING_GROUP := "telegraphing"


func telegraphed_attack_class() -> String:
	return _current_attack_class()


func begin_attack_windup_bar(duration: float, attack_class: String = "blockable") -> void:
	_windup_duration = maxf(0.05, duration)
	add_to_group(TELEGRAPHING_GROUP)
	if _hp_bar:
		_hp_bar.begin_attack_telegraph(_windup_duration, attack_class)
	# AD-07: every enemy telegraph funnels through here, so this is the one place that can catch
	# "first amber/blue/red telegraph ever seen" without a bespoke hook per enemy.
	var hint := HubTutorialService.notify_telegraph_seen(attack_class)
	if hint != "" and RunFlow:
		RunFlow.emit_run_warning(hint)


func hide_attack_windup_bar() -> void:
	_windup_duration = 0.0
	remove_from_group(TELEGRAPHING_GROUP)
	_end_weapon_charge()
	if _hp_bar:
		_hp_bar.hide_attack_telegraph()


func _current_damage_type() -> String:
	return String(
		_current_attack_data.get("damage_type", _data.get("damage_type", DamageInfo.TYPE_PHYSICAL))
	)


func _telegraph_radius_scale() -> float:
	return 1.0


## Local telegraph size for a ranged attack when nothing is authored: draw/nock cue at the
## archer's own feet, not a wedge toward the target. `max_range` on these attacks is the arrow's
## travel distance -- feeding it into the melee formula below drew a telegraph as long as the shot
## itself (a "quick_shot" with `max_range: 14` telegraphed a 29m line for a single arrow).
const RANGED_TELEGRAPH_RADIUS := 1.4


## `EN-03`: the invariant is that the telegraph must never be smaller than the attack. When
## `telegraph_radius` is not authored, derive it from the attack's own `max_range` -- the reach
## that will actually open the hitbox -- rather than trust a number authored independently of it.
## A cone's tip overshoots by 5% so the player can see the edge of the wedge before they are in it.
## Exempts `no_hitbox` (ranged/projectile) attacks from that formula: they have no melee reach to
## honour, and `max_range` there is shot distance, not telegraph size.
func _derived_telegraph_radius(shape: String) -> float:
	if bool(_current_attack_data.get("no_hitbox", false)):
		return RANGED_TELEGRAPH_RADIUS
	var max_range := float(_current_attack_data.get("max_range", _data.get("max_range", 1.6)))
	if shape == "cone" or shape == "line":
		return max_range * 1.05
	return max_range


func _show_attack_telegraph(duration: float) -> void:
	var shape := String(
		_current_attack_data.get("telegraph_shape", _data.get("telegraph_shape", "circle"))
	)
	var radius: float
	if _current_attack_data.has("telegraph_radius"):
		radius = float(_current_attack_data.get("telegraph_radius"))
	elif _data.has("telegraph_radius"):
		radius = float(_data.get("telegraph_radius"))
	else:
		radius = _derived_telegraph_radius(shape)
	radius *= _telegraph_radius_scale()
	var arc_deg := float(
		_current_attack_data.get("telegraph_arc_deg", _data.get("telegraph_arc_deg", 90.0))
	)
	var attack_class := _current_attack_class()
	var tint := VfxService.telegraph_class_tint(attack_class)
	if _data.has("telegraph_tint"):
		tint = Color(_data["telegraph_tint"])
	var pattern := AccessibilitySettings.get_telegraph_class_pattern(attack_class)
	var forward := CombatFacing.forward_of(self)
	VfxService.play_telegraph(
		global_position, radius, duration, tint, shape, forward, self, arc_deg, pattern
	)
	_begin_weapon_charge(tint, duration)


func _begin_weapon_charge(class_tint: Color, duration: float) -> void:
	_end_weapon_charge()
	if _diorama_visual == null:
		return
	var mount := CharacterSkin.find_part(_diorama_visual, CharacterSkin.WEAPON_MOUNT)
	if mount == null:
		mount = CharacterSkin.find_part(_diorama_visual, "Torso")
	if mount == null:
		return
	var charge := Node3D.new()
	charge.name = "AttackCharge"
	mount.add_child(charge)
	_weapon_charge = charge
	var core := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.26, 0.26, 0.26)
	core.mesh = box
	core.material_override = PixelStyleScript.make_glow_material(
		Color(class_tint.r, class_tint.g, class_tint.b, 0.9),
		Color(class_tint.r, class_tint.g, class_tint.b, 0.6),
		2.4
	)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	charge.add_child(core)
	charge.scale = Vector3(0.05, 0.05, 0.05)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(charge, "scale", Vector3.ONE, maxf(duration, 0.05))
	var embers := LightEmbersScript.attach(
		charge, Vector3.ZERO, MaterialFlashScript.tint_for_damage_type(_current_damage_type()),
		1.2, 0.9
	)
	if embers:
		embers.name = "ChargeEmbers"


func _end_weapon_charge() -> void:
	if _weapon_charge != null and is_instance_valid(_weapon_charge):
		_weapon_charge.queue_free()
	_weapon_charge = null


func _apply_hurtbox_data() -> void:
	if _hurtbox == null:
		return
	if (
		not _data.has("block_mitigation")
		and not _data.has("block_angle_deg")
		and not _data.has("block_reduction")
	):
		return
	if _hurtbox.get_script() != ShieldHurtboxScript:
		_hurtbox.set_script(ShieldHurtboxScript)
	if _data.has("block_mitigation"):
		_hurtbox.set("block_mitigation", float(_data.get("block_mitigation")))
	if _data.has("block_angle_deg"):
		_hurtbox.set("block_angle_deg", float(_data.get("block_angle_deg")))
	if _data.has("block_reduction"):
		_hurtbox.call("set_block_reduction", _data.get("block_reduction"))


## `BS-03`: applies a phase's `onEnter` visual keys -- `bodyTint`, `emissive`, `scaleMult` --
## permanently to the diorama, so escalating phases stay visibly different after their transient
## telegraph/VFX/SFX have faded. Called by `BossPhaseController._play_entry()`.
func apply_phase_visuals(on_enter: Dictionary) -> void:
	if on_enter.has("bodyTint"):
		var tint := _color_from_variant(on_enter.get("bodyTint"), Color.WHITE)
		_apply_mesh_tint(tint)
	if on_enter.has("emissive") and _diorama_visual and is_instance_valid(_diorama_visual):
		var spec: Variant = on_enter.get("emissive")
		var glow_color := Color.WHITE
		var glow_energy := 2.2
		if spec is Array and (spec as Array).size() >= 3:
			var parts: Array = spec
			glow_color = Color(float(parts[0]), float(parts[1]), float(parts[2]))
			if parts.size() >= 4:
				glow_energy = float(parts[3])
		elif spec is String:
			glow_color = Color(spec as String)
		MaterialFlashScript.set_persistent_glow(_diorama_visual, glow_color, glow_energy)
	if on_enter.has("scaleMult"):
		_phase_scale_mult = maxf(0.1, float(on_enter.get("scaleMult")))
		if _diorama_visual:
			_diorama_visual.scale = Vector3.ONE * _phase_scale_mult
		elif _mesh:
			_mesh.scale = Vector3.ONE * _phase_scale_mult


func _color_from_variant(value: Variant, fallback: Color) -> Color:
	if value is Array and (value as Array).size() >= 3:
		var parts: Array = value
		return Color(float(parts[0]), float(parts[1]), float(parts[2]))
	if value is String:
		return Color(value as String)
	return fallback


func _apply_mesh_tint(color: Color) -> void:
	if _diorama_visual and is_instance_valid(_diorama_visual):
		CharacterSkin.apply_body_tint(_diorama_visual, color)
	if _mesh == null:
		return
	var mat: Material = _mesh.get_surface_override_material(0)
	if mat is ShaderMaterial:
		var shader_mat := (mat as ShaderMaterial).duplicate() as ShaderMaterial
		shader_mat.set_shader_parameter("color_base", color)
		shader_mat.set_shader_parameter("color_shadow", color.darkened(0.3))
		_mesh.set_surface_override_material(0, shader_mat)
		return
	var standard := (
		(mat.duplicate() as StandardMaterial3D)
		if mat is StandardMaterial3D
		else StandardMaterial3D.new()
	)
	standard.albedo_color = color
	_mesh.set_surface_override_material(0, standard)


func respawn_at_rest() -> void:
	if not is_dead():
		return
	_state = State.PATROL
	_stagger_timer = 0.0
	_cooldown = 0.0
	_aggro_locked = false
	_awareness = 0.0
	_alert_broadcast = false
	_combo_step = 0
	restart_phases()
	_leave_room_engagement()
	_unregister_combat_engagement()
	global_position = _spawn_origin
	velocity = Vector3.ZERO
	if _health:
		_health.configure(_data.get("health", 80.0))
	if _poise:
		_poise.configure(_data.get("poise", 40.0), float(_data.get("stagger_duration", 1.0)))
	if _hitbox:
		_hitbox.disable()
		_hitbox.reset_swing()
	hide_attack_windup_bar()
	if _hurtbox:
		_hurtbox.monitorable = true
		_hurtbox.monitoring = true
	if _body_collision:
		_body_collision.disabled = false
	if _hp_bar:
		_hp_bar.visible = true
	if _animator and _animator.is_bound():
		_animator.revive()
	if _diorama_visual:
		MaterialDissolveScript.reset_death_visual(_diorama_visual)
		MaterialFlashScript.restore_all(_diorama_visual)
		_apply_mesh_tint(Color.WHITE)
		_phase_scale_mult = 1.0
		_diorama_visual.scale = Vector3.ONE
	_pick_patrol_target()


func is_dead() -> bool:
	return _state == State.DEAD


func capture_state() -> Dictionary:
	var defeated := is_dead() or (_health != null and _health.is_dead())
	var state := {"alive": not defeated}
	if _health and not defeated:
		state["health"] = _health.current
	return state


func apply_state(state: Dictionary) -> void:
	if not state.get("alive", true):
		_finalize_death(true)
		return
	if is_dead():
		respawn_at_rest()
	if _health and state.has("health"):
		var hp := float(state.get("health", _health.max_health))
		if hp <= 0.0:
			_finalize_death(true)
			return
		_health.restore_current(hp)


func _finalize_death(silent: bool) -> void:
	if is_dead():
		return
	_clear_combat_debug_draw()
	_state = State.DEAD
	velocity = Vector3.ZERO
	_stagger_timer = 0.0
	_cooldown = 0.0
	_aggro_locked = false
	_leave_room_engagement()
	_unregister_combat_engagement()
	_release_attack_token()
	is_guarding = false
	_sidestep_iframe_timer = 0.0
	_punish_watching = false
	_release_defensive_token()
	if _phase_controller and _phase_controller.has_method("clear_death_spawns"):
		_phase_controller.call("clear_death_spawns")
	if _is_boss_enemy() and AudioDirector:
		AudioDirector.end_boss_music()
	if _health:
		_health.force_dead()
	if not silent:
		RunFlow.register_kill(get_enemy_id())
		_award_kill_coins()
		_try_roll_global_drop()
		_apply_splits_on_death()
		if CombatEvents:
			CombatEvents.dispatch(CombatEvents.ON_KILL, {"actor": _player, "target": self})
		enemy_died.emit()
	if _hitbox:
		_hitbox.disable()
		_hitbox.reset_swing()
	hide_attack_windup_bar()
	if _hp_bar:
		_hp_bar.visible = false
	if _animator and _animator.is_bound():
		_animator.play_death()
	if _hurtbox:
		_hurtbox.monitorable = false
		_hurtbox.monitoring = false
	if _weak_point_hurtbox and is_instance_valid(_weak_point_hurtbox):
		_weak_point_hurtbox.monitorable = false
		_weak_point_hurtbox.monitoring = false
	if _body_collision:
		_body_collision.disabled = true
	_play_death_visual()


func _play_death_visual() -> void:
	AudioDirector.play_sfx("death", global_position)
	var visual := _diorama_visual if _diorama_visual else _mesh as Node3D
	if visual == null:
		return
	var archetype := CharacterRigCatalogScript.archetype_for_enemy(get_enemy_id(), _data)
	var opts := MaterialDissolveScript.death_opts_for_enemy(
		_anim_profile, _is_boss_enemy(), _data, archetype
	)
	opts["vfx_position"] = global_position
	opts["vfx_tint"] = Color(0.55, 0.22, 0.18)
	opts["has_animator"] = _animator != null and _animator.is_bound()
	if _last_hit_direction.length_squared() > 0.01:
		opts["sweep_dir"] = _last_hit_direction
	MaterialDissolveScript.play_death_visual(visual, opts)


const COIN_REWARD_PER_THREAT := 0.35
const COIN_REWARD_MIN := 3


func _award_kill_coins() -> void:
	var reward := int(_data.get("coinReward", _data.get("goldReward", -1)))
	if reward < 0:
		var threat := float(_data.get("threat_cost", 20))
		reward = maxi(COIN_REWARD_MIN, int(round(threat * COIN_REWARD_PER_THREAT)))
	if reward > 0 and CharacterService:
		CharacterService.add_gold(reward)


func _try_roll_global_drop() -> void:
	if not RunFlow.is_run_active():
		return
	if RunFlow.get_run_mode() == "waves":
		return
	var floor_index := RunFlow.get_current_floor()
	var tier := RunFlow.get_difficulty_tier() if RunFlow.get_run_mode() == "castle" else 1
	var dungeon_id := RunFlow.current_dungeon_id if RunFlow.get_run_mode() == "castle" else ""
	var drop_ordinal := RunFlow.next_loot_drop_ordinal() if RunFlow else 0
	var drop_id := GlobalDropServiceScript.roll_enemy_drop(
		drop_ordinal, floor_index, tier, dungeon_id
	)
	if drop_id != "":
		InventoryService.add_loot(drop_id)


func apply_stagger(duration: float) -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	if _state in [State.WINDUP, State.ATTACK]:
		_combo_step = 0
		_release_attack_token()
	if _state in [State.GUARD, State.SIDESTEP, State.PUNISH]:
		is_guarding = false
		_sidestep_iframe_timer = 0.0
		if _animator and _animator.is_bound():
			_animator.set_blocking(false)
		_release_defensive_token()
	_punish_watching = false
	_state = State.STAGGER
	_stagger_timer = duration
	_yield_room_turn()
	if _hitbox:
		_hitbox.disable()
	hide_attack_windup_bar()
	if _animator and _animator.is_bound():
		_animator.play_stagger(duration, _last_hit_direction)
	elif _mesh:
		_mesh.scale = Vector3.ONE
	if _knockback and _last_hit_direction.length_squared() > 0.0001:
		# `PH-02`: same normalisation the player's stagger impulse uses, so a poise break reads
		# with the same weight on both sides of a fight.
		_knockback.apply(_last_hit_direction, 0.8 * _last_hit_poise_damage / STAGGER_POISE_HIGH_REFERENCE)


func cancel_attack() -> void:
	if _state in [State.WINDUP, State.ATTACK]:
		_end_attack()


func _physics_process(delta: float) -> void:
	if _health and _health.is_dead() and not is_dead():
		_finalize_death(true)
	var staggered := false
	if _cooldown > 0.0:
		_cooldown -= delta
	if _leap_cooldown > 0.0:
		_leap_cooldown -= delta
	if _burrow_cooldown > 0.0:
		_burrow_cooldown -= delta
	if _summon_cooldown > 0.0:
		_summon_cooldown -= delta
	if _phase_lock_timer > 0.0:
		_phase_lock_timer -= delta
	if _phase_invuln_timer > 0.0:
		_phase_invuln_timer -= delta
	if not is_dead() and _stagger_timer > 0.0:
		_stagger_timer -= delta
		staggered = true
		if _stagger_timer <= 0.0:
			staggered = false
			if _health and _health.is_dead():
				_finalize_death(true)
			else:
				_state = State.PATROL
	var ai_enabled := not is_dead() and not staggered
	if ai_enabled:
		var stride := _ai_lod_stride()
		if _should_run_ai_tick(stride):
			var ai_delta := delta * stride
			_update_ai(ai_delta)
			var track_mult := _tracking_speed_multiplier()
			if track_mult > 0.0 and _should_track_player():
				_track_player_facing(ai_delta, track_mult)
		elif stride > 1:
			var damping := clampf(LOD_VELOCITY_DAMPING * delta, 0.0, 1.0)
			velocity.x = lerpf(velocity.x, 0.0, damping)
			velocity.z = lerpf(velocity.z, 0.0, damping)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if str(_data.get("enemy_type", "")) == "flyer":
		_apply_flyer_height_hold(delta)
	elif not is_on_floor():
		velocity += get_gravity() * delta
	if _knockback:
		var impulse := _knockback.consume(delta)
		velocity.x += impulse.x
		velocity.z += impulse.z
	move_and_slide()
	_update_diorama_animation(delta)


func _update_diorama_animation(_delta: float) -> void:
	if _animator == null or not _animator.is_bound() or is_dead():
		return
	var speed := velocity.length()
	var shield_up := _anim_profile == "shield" and _state == State.CHASE and speed < 0.2
	_animator.set_blocking(shield_up)
	if speed > 0.35:
		var move_speed: float = _move_speed
		var clip := &"run" if speed > move_speed * 0.85 and _animator.has_clip(&"run") else &"walk"
		_animator.request_locomotion(clip, {"speed": speed})
	else:
		_animator.request_locomotion(&"idle")


func _update_ai(delta: float) -> void:
	_update_perception(delta)
	if _room_registered:
		EnemyBlackboard.maybe_reassign(_room_id)
	_process_aura_mixin(delta)
	if _data.has("summons"):
		_process_summons_mixin(delta)
	if _process_burrow_mixin(delta):
		return
	if _phase_lock_timer > 0.0 and _state not in [State.WINDUP, State.ATTACK, State.RECOVERY]:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	match _state:
		State.PATROL:
			_process_patrol(delta)
		State.CHASE:
			_process_chase(delta)
		State.INVESTIGATE:
			_process_investigate(delta)
		State.RETREAT:
			_process_retreat(delta)
		State.CIRCLE:
			_process_circle(delta)
		State.WINDUP:
			if _in_windup_hold:
				_process_windup_hold(delta)
			else:
				var commit := _windup_commit_ratio()
				_apply_chase_velocity(delta, WINDUP_APPROACH_SPEED_MULT * (1.0 - commit))
				_on_windup_tick(commit >= 1.0)
				_state_timer -= delta
				if _windup_duration > 0.0:
					var elapsed := _windup_duration - _state_timer
					if _hp_bar:
						_hp_bar.set_attack_telegraph_progress(
							clampf(elapsed / _windup_duration, 0.0, 1.0)
						)
				if _state_timer <= 0.0:
					if _windup_hold_timer > 0.0:
						_enter_windup_hold()
					else:
						_start_attack()
		State.ATTACK:
			_apply_attack_lunge()
			_state_timer -= delta
			if _state_timer <= 0.0:
				_end_attack()
		State.RECOVERY:
			_apply_chase_velocity(delta, RECOVERY_APPROACH_SPEED_MULT)
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = State.CHASE if _has_aggro() else State.PATROL
				if _short_recovery_cooldown:
					_cooldown = FEINT_COOLDOWN
					_short_recovery_cooldown = false
				else:
					_cooldown = _attack_cooldown_data
		State.GUARD:
			_process_guard_state(delta)
		State.SIDESTEP:
			_process_sidestep_state(delta)
		State.PUNISH:
			_process_punish(delta)
	if _punish_watching and _state in [State.CHASE, State.CIRCLE]:
		_process_punish_watch(delta)


func _process_patrol(delta: float) -> void:
	if _has_aggro():
		_state = State.CHASE
		return
	if _awareness >= AWARENESS_INVESTIGATE:
		_state = State.INVESTIGATE
		_state_timer = 3.5
		return
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		velocity = Vector3.ZERO
		return
	var to_target := _patrol_target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.5:
		_patrol_wait = _enemy_rng.randf_range(1.0, 2.5)
		_pick_patrol_target()
		return
	var dir := _direction_toward(_patrol_target, delta, false)
	if dir.length_squared() < 0.01:
		_patrol_wait = _enemy_rng.randf_range(0.5, 1.2)
		_pick_patrol_target()
		return
	velocity = dir * _move_speed * PATROL_SPEED_MULT
	_face_direction(dir, delta)


func _process_chase(delta: float) -> void:
	if not _has_aggro():
		_state = State.INVESTIGATE
		_state_timer = 2.5
		return
	_last_known_player_pos = _player.global_position
	if _should_retreat():
		_state = State.RETREAT
		_state_timer = 1.8
		return
	if _try_defensive_reaction():
		return
	if _try_leap_attack():
		return
	if _can_attack():
		_start_windup()
		return
	if str(_data.get("enemy_type", "")) == "caster":
		_process_caster_kite(delta)
		return
	var holding_back := _cooldown > 0.0 or _role != EnemyBlackboard.Role.ENGAGER
	if holding_back and _distance_to_player_sq() <= _circle_entry_range_sq():
		_enter_circle()
		return
	_apply_chase_velocity(delta)


## `EN-10` "the zoner": a `caster`-type enemy never closes to melee range on its own -- it holds at
## `preferred_range`, backs off if the player crowds inside `retreat_range`, and only ever answers
## with its own (long-range, telegraphed) attacks. Mirrors `CastleArcher._process_chase()`'s kiting
## without a subclass, since every caster should get it for free.
func _process_caster_kite(delta: float) -> void:
	if _player == null:
		velocity = Vector3.ZERO
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var move_dir := Vector3.ZERO
	if dist < _retreat_range:
		move_dir = -to_player.normalized()
	elif dist > _preferred_range:
		move_dir = _direction_toward(_player.global_position, delta, true)
	velocity = move_dir * _move_speed
	if to_player.length_squared() > 0.01:
		_face_direction(to_player, delta)


func _circle_entry_range_sq() -> float:
	var reach: float = _engage_range * 1.35 * _role_spacing_mult()
	return reach * reach


func _role_spacing_mult() -> float:
	if _role == EnemyBlackboard.Role.FLANKER:
		return FLANKER_RADIUS_MULT
	if _role == EnemyBlackboard.Role.WAITER:
		return WAITER_RADIUS_MULT
	return 1.0


func _enter_circle() -> void:
	_state = State.CIRCLE
	_state_timer = _enemy_rng.randf_range(0.7, 1.6)
	if _enemy_rng.randf() < 0.2:
		_circle_direction = -_circle_direction


func _process_circle(delta: float) -> void:
	if not _has_aggro() or _player == null:
		_state = State.INVESTIGATE
		_state_timer = 2.5
		return
	_last_known_player_pos = _player.global_position
	_state_timer -= delta
	if _try_defensive_reaction():
		return
	if _try_leap_attack():
		return
	if _can_attack():
		_start_windup()
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist < 0.05:
		velocity = Vector3.ZERO
		return
	var dir := to_player / dist
	var desired: float = _engage_range * _circle_radius_mult * _role_spacing_mult()
	var radial := clampf((dist - desired) / maxf(0.5, desired), -1.0, 1.0)
	var tangent_dir := _circle_direction
	var tangent_speed_mult := 1.0
	if _role == EnemyBlackboard.Role.FLANKER:
		var bearing_error := _flank_bearing_error_deg()
		if not is_nan(bearing_error):
			tangent_dir = 1.0 if bearing_error > 0.0 else -1.0
			tangent_speed_mult = clampf(absf(bearing_error) / 30.0, 0.15, 1.0)
	var tangent := Vector3(-dir.z, 0.0, dir.x) * tangent_dir * tangent_speed_mult
	var move := tangent + dir * radial
	if move.length_squared() < 0.01:
		velocity = Vector3.ZERO
	else:
		velocity = move.normalized() * _move_speed * 0.8
	if _state_timer <= 0.0:
		_state = State.CHASE


## `EN-08`: how far (in degrees) this flanker still has to travel around the player to reach its
## assigned bearing, signed so `_process_circle()` can pick a tangent direction from it directly.
## `NAN` means there is no player facing to steer against, so the caller should fall back to the
## plain orbit every other role already uses.
func _flank_bearing_error_deg() -> float:
	if _player == null:
		return NAN
	var facing := CombatFacing.aim_forward_of(_player)
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return NAN
	facing = facing.normalized()
	var to_self := global_position - _player.global_position
	to_self.y = 0.0
	if to_self.length_squared() < 0.0001:
		return NAN
	var current := rad_to_deg(facing.signed_angle_to(to_self.normalized(), Vector3.UP))
	return wrapf(_desired_flank_angle_deg - current, -180.0, 180.0)


func _process_investigate(delta: float) -> void:
	if _has_aggro():
		_state = State.CHASE
		return
	_state_timer -= delta
	var to_last := _last_known_player_pos - global_position
	to_last.y = 0.0
	if to_last.length() > 0.75:
		var dir := _direction_toward(_last_known_player_pos, delta, false)
		velocity = dir * _move_speed * 0.75
		_face_direction(dir, delta)
	else:
		velocity = Vector3.ZERO
		_awareness = maxf(0.0, _awareness - _awareness_decay * delta)
	if _state_timer <= 0.0:
		_state = State.PATROL
		_pick_patrol_target()


func _process_retreat(delta: float) -> void:
	_state_timer -= delta
	if _player == null:
		_state = State.PATROL
		return
	var away := global_position - _player.global_position
	away.y = 0.0
	if away.length_squared() > 0.01:
		velocity = away.normalized() * _move_speed
		_face_direction(-away, delta)
	if _state_timer <= 0.0:
		_state = State.CHASE if _has_aggro() else State.PATROL


func _should_retreat() -> bool:
	if _health == null:
		return false
	var threshold: float = _retreat_threshold
	if threshold <= 0.0:
		return false
	return _health.current / _health.max_health <= threshold


func _apply_chase_velocity(delta: float, speed_mult: float = 1.0) -> void:
	if _player == null:
		velocity = Vector3.ZERO
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var stop_range: float = _engage_range * 0.85
	if dist > stop_range:
		var dir := _direction_toward(_player.global_position, delta, true)
		velocity = dir * _move_speed * speed_mult
	else:
		velocity = Vector3.ZERO
	velocity += _crowd_separation()


## `PH-05`: `NavigationAgent3D` avoidance is enabled but its result is never read -- the state
## machine writes `velocity` directly in seven places and an avoidance callback would fight all of
## them. A separation term added at this one choke point is smaller, deterministic and easier to
## reason about than wiring the callback through every writer. Capped at 30% of `_move_speed` so it
## nudges a crowd into an arc rather than steering it outright.
const CROWD_SEPARATION_RADIUS := 1.2
const CROWD_SEPARATION_CAP_FRACTION := 0.3


func _crowd_separation() -> Vector3:
	var push := Vector3.ZERO
	for other in EnemyBlackboard.nearby(global_position, CROWD_SEPARATION_RADIUS):
		if other == self or not (other is Node3D):
			continue
		var away := global_position - (other as Node3D).global_position
		away.y = 0.0
		var dist := away.length()
		if dist < 0.01 or dist >= CROWD_SEPARATION_RADIUS:
			continue
		push += away / (dist * dist)
	if push.length_squared() < 0.0001:
		return Vector3.ZERO
	var cap := _move_speed * CROWD_SEPARATION_CAP_FRACTION
	if push.length() > cap:
		push = push.normalized() * cap
	return push


func _direction_toward(target: Vector3, delta: float, sidestep_when_blocked: bool) -> Vector3:
	if _nav_agent == null:
		_nav_probe_timer -= delta
		if _nav_probe_timer <= 0.0:
			_nav_probe_timer = NAV_PROBE_INTERVAL
			_ensure_nav_agent()
	if _nav_agent != null:
		_nav_repath_timer -= delta
		if (
			_nav_repath_timer <= 0.0
			or _nav_agent.target_position.distance_squared_to(target) > 1.0
		):
			_nav_repath_timer = NAV_REPATH_INTERVAL
			_nav_agent.target_position = target
		if not _nav_agent.is_navigation_finished():
			var step := _nav_agent.get_next_path_position() - global_position
			step.y = 0.0
			var step_len_sq := step.length_squared()
			if step_len_sq > 0.0025 and step_len_sq < NAV_MAX_STEP_DISTANCE_SQ:
				return step.normalized()
	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0025:
		return Vector3.ZERO
	var dir := to_target.normalized()
	if sidestep_when_blocked and not _has_line_of_sight_to_player():
		dir = (dir + Vector3(-dir.z, 0.0, dir.x) * _circle_direction * 0.7).normalized()
	return dir


func _ensure_nav_agent() -> void:
	if _nav_agent != null or not is_inside_tree():
		return
	var world := get_world_3d()
	if world == null:
		return
	var map: RID = world.navigation_map
	if not map.is_valid() or NavigationServer3D.map_get_regions(map).is_empty():
		return
	_nav_agent = NavigationAgent3D.new()
	_nav_agent.name = "NavAgent"
	_nav_agent.path_desired_distance = 0.6
	_nav_agent.target_desired_distance = 0.6
	_nav_agent.path_max_distance = 4.0
	_nav_agent.avoidance_enabled = true
	_nav_agent.radius = 0.55
	_nav_agent.neighbor_distance = 4.0
	_nav_agent.max_neighbors = 6
	_nav_agent.avoidance_priority = 0.5
	add_child(_nav_agent)


func _has_aggro() -> bool:
	return _player != null and _aggro_locked


func _update_perception(delta: float) -> void:
	if _player == null:
		return
	var frame := Engine.get_physics_frames()
	if frame == _perception_frame:
		return
	_perception_frame = frame
	var dist_sq := _distance_to_player_sq()
	if _aggro_locked:
		_awareness = 1.0
		if dist_sq > _deaggro_range * _deaggro_range:
			_drop_aggro()
			return
		if _has_line_of_sight_to_player():
			_deaggro_los_timer = 0.0
		else:
			_deaggro_los_timer += delta
			if _deaggro_los_timer >= DEAGGRO_LOS_TIMEOUT:
				_drop_aggro()
		return
	var gain := 0.0
	if dist_sq <= _aggro_range * _aggro_range and _has_line_of_sight_to_player():
		var dist := sqrt(dist_sq)
		var closeness := 1.0 - clampf(dist / maxf(0.01, _aggro_range), 0.0, 1.0)
		gain = _awareness_rate * (0.3 + 0.7 * closeness)
		if not _player_inside_vision_cone():
			gain *= 0.25
	if _hearing_range > 0.0 and dist_sq <= _hearing_range * _hearing_range:
		var noise := _player_noise_level()
		if noise > 0.0:
			var hear_close := 1.0 - clampf(sqrt(dist_sq) / maxf(0.01, _hearing_range), 0.0, 1.0)
			gain = maxf(gain, _awareness_rate * noise * (0.3 + 0.7 * hear_close))
	if gain > 0.0:
		_awareness = clampf(_awareness + gain * delta, 0.0, 1.0)
		if _awareness >= AWARENESS_INVESTIGATE:
			_last_known_player_pos = _player.global_position
		if _awareness >= 1.0:
			_latch_aggro()
	else:
		_awareness = maxf(0.0, _awareness - _awareness_decay * delta)


func _player_inside_vision_cone() -> bool:
	if _player == null:
		return false
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.01:
		return true
	var facing := CombatFacing.forward_of(self)
	facing.y = 0.0
	if facing.length_squared() < 0.01:
		return true
	return facing.normalized().dot(to_player.normalized()) >= _vision_cone_cos


func _player_noise_level() -> float:
	if _player == null:
		return 0.0
	if _player.has_method("get_noise_level"):
		return clampf(float(_player.call("get_noise_level")), 0.0, 1.0)
	if not (_player is CharacterBody3D):
		return 0.0
	var flat := (_player as CharacterBody3D).velocity
	flat.y = 0.0
	return clampf((flat.length() - 2.0) / 4.5, 0.0, 1.0)


func _latch_aggro() -> void:
	if _aggro_locked:
		return
	_awareness = 1.0
	_aggro_locked = true
	_deaggro_los_timer = 0.0
	if _player:
		_last_known_player_pos = _player.global_position
	_register_combat_engagement()
	if _room_registered:
		EnemyBlackboard.report_player_position(_room_id, _last_known_player_pos)
		EnemyBlackboard.report_engaged(_room_id, self, true)
	_broadcast_alert()


func _broadcast_alert() -> void:
	if _alert_broadcast or _alert_radius <= 0.0:
		return
	_alert_broadcast = true
	var radius_sq := _alert_radius * _alert_radius
	for node in _alert_candidates():
		if node == self or not (node is CastleEnemyBase):
			continue
		var ally := node as CastleEnemyBase
		if ally.global_position.distance_squared_to(global_position) > radius_sq:
			continue
		ally.notice_ally_alert(_last_known_player_pos)


func _alert_candidates() -> Array:
	if _room_registered:
		var roster := EnemyBlackboard.members(_room_id)
		if not roster.is_empty():
			return roster

	var neighbours := EnemyBlackboard.nearby(global_position, _alert_radius)
	if not neighbours.is_empty():
		return neighbours

	if OS.is_debug_build():
		return get_tree().get_nodes_in_group("enemy")
	return []


func notice_ally_alert(source_position: Vector3) -> void:
	if is_dead() or _aggro_locked or _player == null:
		return
	_awareness = maxf(_awareness, ALLY_ALERT_AWARENESS)
	_last_known_player_pos = source_position
	if _state == State.PATROL:
		_state = State.INVESTIGATE
		_state_timer = 4.0


func _drop_aggro() -> void:
	_aggro_locked = false
	_deaggro_los_timer = 0.0
	_awareness = AWARENESS_INVESTIGATE
	_alert_broadcast = false
	_leave_room_engagement()
	_unregister_combat_engagement()


func _leave_room_engagement() -> void:
	if not _room_registered:
		return
	EnemyBlackboard.report_engaged(_room_id, self, false)
	_role = EnemyBlackboard.Role.ENGAGER


## `EN-07`: the enemy reads the player's own public `WeaponController` state -- never the other way
## round, or the player side picks up AI coupling it should never need. Gated behind the attack
## token exactly like an attack: the *one* enemy holding a token is the one that reacts, so a room
## of six does not sidestep in unison.
func _try_defensive_reaction() -> bool:
	if _role != EnemyBlackboard.Role.ENGAGER or _player == null or _phase_lock_timer > 0.0:
		return false
	var guard_chance := float(_data.get("guard_chance", 0.0))
	var sidestep_chance := float(_data.get("sidestep_chance", 0.0))
	if guard_chance <= 0.0 and sidestep_chance <= 0.0:
		return false
	var weapon := _player.get_node_or_null("WeaponController") as WeaponController
	if weapon == null or not weapon.is_attacking:
		return false
	if weapon.current_phase != WeaponController.AttackPhase.STARTUP:
		return false
	var in_engage_range := _distance_to_player_sq() <= _engage_range * _engage_range
	if in_engage_range and guard_chance > 0.0 and _enemy_rng.randf() < guard_chance:
		if not _request_defensive_token():
			return false
		_enter_guard_state(weapon)
		return true
	if not in_engage_range and sidestep_chance > 0.0 and _enemy_rng.randf() < sidestep_chance:
		if not _request_defensive_token():
			return false
		_enter_sidestep_state()
		return true
	return false


func _request_defensive_token() -> bool:
	if _defensive_token_held:
		return true
	_attack_token_group = str(_data.get("attack_token_group", "room_default"))
	if AttackTokenService and not AttackTokenService.request_token(_attack_token_group):
		return false
	_defensive_token_held = true
	return true


func _release_defensive_token() -> void:
	if _defensive_token_held and AttackTokenService:
		AttackTokenService.release_token(_attack_token_group)
	_defensive_token_held = false


## Held for roughly the player's remaining startup + active window so the shield is actually up
## while the swing that provoked it lands, rather than a canned duration guessing at the timing.
func _enter_guard_state(_weapon: WeaponController) -> void:
	_state = State.GUARD
	_guard_timer = GUARD_FALLBACK_DURATION
	is_guarding = true
	velocity.x = 0.0
	velocity.z = 0.0
	if _animator and _animator.is_bound():
		_animator.set_blocking(true)


func _process_guard_state(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _player:
		_face_direction((_player.global_position - global_position), delta)
	_guard_timer -= delta
	if _guard_timer <= 0.0:
		_end_guard_state()


func _end_guard_state() -> void:
	is_guarding = false
	if _animator and _animator.is_bound():
		_animator.set_blocking(false)
	_release_defensive_token()
	_start_punish_watch()
	_state = State.CHASE if _has_aggro() else State.PATROL


## A 0.35 s lateral dash with i-frames over its first 60% -- the sidestep is the read-and-answer to
## a ranged or lunging attack the enemy cannot block its way out of.
func _enter_sidestep_state() -> void:
	_state = State.SIDESTEP
	_sidestep_timer = SIDESTEP_DURATION
	_sidestep_iframe_timer = SIDESTEP_DURATION * SIDESTEP_IFRAME_FRACTION


func _process_sidestep_state(delta: float) -> void:
	var tangent := Vector3(-1.0, 0.0, 0.0)
	if _player:
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.01:
			var dir := to_player.normalized()
			tangent = Vector3(-dir.z, 0.0, dir.x) * _circle_direction
	velocity = tangent * SIDESTEP_SPEED
	_sidestep_timer -= delta
	if _sidestep_iframe_timer > 0.0:
		_sidestep_iframe_timer -= delta
	if _sidestep_timer <= 0.0:
		_end_sidestep_state()


func _end_sidestep_state() -> void:
	_sidestep_iframe_timer = 0.0
	_release_defensive_token()
	_start_punish_watch()
	_state = State.CHASE if _has_aggro() else State.PATROL


## `PUNISH` is the payoff for reading the player correctly: if their attack whiffs and lands in
## `RECOVERY` within `punish_window` of the guard or sidestep, the enemy skips its own cooldown and
## swings immediately with the fastest attack in its kit.
func _start_punish_watch() -> void:
	var window := float(_data.get("punish_window", PUNISH_WINDOW_DEFAULT))
	if window <= 0.0:
		return
	_punish_watching = true
	_punish_watch_timer = window


func _process_punish_watch(delta: float) -> void:
	_punish_watch_timer -= delta
	if _punish_watch_timer <= 0.0:
		_punish_watching = false
		return
	if _player == null:
		return
	var weapon := _player.get_node_or_null("WeaponController") as WeaponController
	if weapon == null:
		return
	if weapon.current_phase == WeaponController.AttackPhase.RECOVERY:
		_punish_watching = false
		_state = State.PUNISH


func _process_punish(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not _request_defensive_token():
		_state = State.CHASE if _has_aggro() else State.PATROL
		return
	_current_attack_data = _fastest_attack()
	_enter_windup(_current_attack_data)


func _fastest_attack() -> Dictionary:
	var fastest: Dictionary = {}
	var best_windup := INF
	for entry in _attacks:
		if not (entry is Dictionary):
			continue
		var atk: Dictionary = entry
		var windup := float(atk.get("windup_duration", _data.get("windup_duration", 0.7)))
		if windup < best_windup:
			best_windup = windup
			fastest = atk
	if fastest.is_empty():
		return _first_attack_entry()
	return fastest


func _can_attack() -> bool:
	if _cooldown > 0.0 or _player == null or _phase_lock_timer > 0.0:
		return false
	if _role != EnemyBlackboard.Role.ENGAGER:
		return false
	if _is_cross_boss_boundary_with_player():
		return false
	if _distance_to_player_sq() > _max_attack_range * _max_attack_range:
		return false
	return _has_line_of_sight_to_player()


func _has_line_of_sight_to_player() -> bool:
	if _player == null:
		return false
	var frame := Engine.get_physics_frames()
	if frame == _los_cache_frame:
		return _los_cache_result
	_los_cache_frame = frame
	var space := get_world_3d().direct_space_state
	if space == null:
		_los_cache_result = true
		return true
	var from := global_position + Vector3(0, 1.2, 0)
	var to := _player.global_position + Vector3(0, 1.0, 0)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = los_mask
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.exclude = [get_rid()]
	if _player is CollisionObject3D:
		params.exclude.append((_player as CollisionObject3D).get_rid())
	_los_cache_result = space.intersect_ray(params).is_empty()
	return _los_cache_result


func _distance_to_player_sq() -> float:
	if _player == null:
		return INF
	var frame := Engine.get_physics_frames()
	if frame == _dist_to_player_sq_cache_frame:
		return _dist_to_player_sq_cache
	_dist_to_player_sq_cache_frame = frame
	_dist_to_player_sq_cache = global_position.distance_squared_to(_player.global_position)
	return _dist_to_player_sq_cache


func _is_cross_boss_boundary_with_player() -> bool:
	if _player == null:
		return false
	if _castle_run == null or not is_instance_valid(_castle_run):
		_castle_run = get_tree().get_first_node_in_group("castle_run")
	if _castle_run and _castle_run.has_method("is_cross_boss_boundary"):
		return _castle_run.call("is_cross_boss_boundary", self, _player)
	return false


const LOD_VELOCITY_DAMPING := 6.0


func _ai_lod_stride() -> int:
	if is_visible_in_tree():
		var dist_sq := _distance_to_player_sq()
		if dist_sq <= AI_LOD_NEAR_RANGE_SQ:
			return 1
		if dist_sq <= AI_LOD_MID_RANGE_SQ:
			return AI_LOD_MID_STRIDE
		return AI_LOD_FAR_STRIDE
	return AI_LOD_FAR_STRIDE


func _should_run_ai_tick(stride: int) -> bool:
	if stride <= 1:
		return true
	var frame := Engine.get_physics_frames()
	return (frame + _ai_tick_phase) % stride == 0


func _start_windup() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	## `EN-10` "the many": a `swarm` enemy is meant to dogpile the player all at once rather than
	## politely queue for a shared attack token -- that is the whole point of the archetype, and
	## `AttackTokenService` gating it would make a swarm behave like a single-file line of melee.
	if str(_data.get("enemy_type", "")) == "swarm":
		_attack_token_held = false
		_select_attack_data()
		_enter_windup(_current_attack_data)
		return
	_attack_token_group = str(_data.get("attack_token_group", "room_default"))
	if AttackTokenService and not AttackTokenService.request_token(_attack_token_group):
		_cooldown = _enemy_rng.randf_range(0.25, 0.6)
		if _has_aggro():
			_enter_circle()
		return
	_attack_token_held = true
	_select_attack_data()
	_enter_windup(_current_attack_data)


## `EN-05`: `hold_fraction` reserves the tail of the windup as a frozen hold rather than letting the
## telegraph fill creep at a constant rate -- a player who dodges on the ring instead of the enemy
## has nothing to read. The hold is timed separately from `_state_timer`/`_windup_duration` (see
## `_windup_hold_timer`) precisely so the commit-facing math in `_windup_commit_ratio()` still
## resolves against the pre-hold run alone: committing facing only through the hold's start, not
## through the hold itself, is what keeps a feint escapable.
func _enter_windup(attack_data: Dictionary) -> void:
	_current_attack_data = attack_data
	_state = State.WINDUP
	_in_windup_hold = false
	_windup_hold_timer = 0.0
	_windup_will_feint = false
	var windup: float = float(
		attack_data.get("windup_duration", _data.get("windup_duration", 0.7))
	)
	var windup_variance: float = float(
		attack_data.get("windup_variance", _data.get("windup_variance", 0.0))
	)
	if windup_variance > 0.0:
		windup += _enemy_rng.randf_range(-windup_variance, windup_variance)
	windup = maxf(0.05, windup)
	var hold_fraction := clampf(
		float(attack_data.get("hold_fraction", _data.get("hold_fraction", 0.0))), 0.0, 0.6
	)
	if hold_fraction > 0.0:
		var feint_chance := clampf(
			float(attack_data.get("feint_chance", _data.get("feint_chance", 0.0))), 0.0, 0.4
		)
		_windup_will_feint = _enemy_rng.randf() < feint_chance
		_windup_hold_timer = windup * hold_fraction
		windup *= (1.0 - hold_fraction)
	_state_timer = windup
	_sync_hitbox_from_anim = (
		_animator != null and _animator.is_bound() and _animator.drives_hitbox_events()
	)
	if _animator and _animator.is_bound():
		_animator.play_attack(
			_state_timer,
			float(attack_data.get("active_duration", _data.get("active_duration", 0.15))),
			float(attack_data.get("recovery_duration", _data.get("recovery_duration", 0.9)))
		)
	elif _mesh:
		_mesh.scale = Vector3(1.08, 1.08, 1.08)
	_show_attack_telegraph(_state_timer)
	begin_attack_windup_bar(_state_timer, _current_attack_class())
	AudioDirector.play_sfx(_windup_cue(), global_position + Vector3(0.0, 1.0, 0.0))
	attack_telegraph_started.emit(_current_attack_class())


## `AU-04`: audio carries the same read as the colour and the shape -- a rising tone for
## `parryable`, a low growl for `unblockable`, a short grunt for `blockable`, a shout for `grab`.
## `"voice"` is an optional per-enemy prefix (e.g. a biome's own windup bank) that only wins if the
## bank actually defines it; an enemy with no authored voice cue falls back to the plain
## `windup_<class>` cue every enemy already gets for free.
func _windup_cue() -> String:
	var attack_class := _current_attack_class()
	var class_cue := "windup_%s" % attack_class
	var voice := str(_data.get("voice", ""))
	if voice != "":
		var voiced_cue := "windup_%s_%s" % [voice, attack_class]
		if AudioDirector.has_sfx_entry(voiced_cue):
			return voiced_cue
	return class_cue


## `EN-01`: every attack in `content/enemies/*.json` and `content/bosses/*.json` now authors
## `attackClass` directly, so this is a safety net for content that has not been re-authored (or a
## future addition that forgets it), not the primary path. The poise-derived guess it replaces only
## ever produced `blockable`/`unblockable`, so `parryable` and `grab` never appeared in the game.
static var _warned_missing_class: Dictionary = {}


func _current_attack_class() -> String:
	var authored := str(_current_attack_data.get("attackClass", ""))
	if authored != "":
		return authored
	var root_authored := str(_data.get("attackClass", ""))
	if root_authored != "":
		return root_authored
	var catalog_id := get_enemy_id()
	if not _warned_missing_class.has(catalog_id):
		_warned_missing_class[catalog_id] = true
		push_warning(
			"CastleEnemyBase: enemy '%s' has an attack with no attackClass -- defaulting to blockable"
			% catalog_id
		)
	return "blockable"


func _start_attack() -> void:
	if is_dead() or (_health and _health.is_dead()):
		_release_attack_token()
		return
	_state = State.ATTACK
	_state_timer = float(
		_current_attack_data.get("active_duration", _data.get("active_duration", 0.15))
	)
	hide_attack_windup_bar()
	_end_weapon_charge()
	if _hitbox:
		_hitbox.set_attack_values(
			float(_current_attack_data.get("attack_damage", _data.get("attack_damage", 14.0)))
			* _damage_multiplier,
			float(
				_current_attack_data.get(
					"attack_poise_damage", _data.get("attack_poise_damage", 12.0)
				)
			)
			* _damage_multiplier,
			_current_attack_data.get(
				"damage_type", _data.get("damage_type", DamageInfo.TYPE_PHYSICAL)
			),
			_current_attack_data.get("status_on_hit", _data.get("status_on_hit", "")),
			int(
				_current_attack_data.get(
					"status_stacks_on_hit", _data.get("status_stacks_on_hit", 1)
				)
			),
			0.0,
			1.5,
			_current_attack_class()
		)
		if not _sync_hitbox_from_anim and not bool(_current_attack_data.get("no_hitbox", false)):
			_hitbox.enable()
	var hazard_spec: Dictionary = _current_attack_data.get("spawn_hazard", {}) as Dictionary
	if not hazard_spec.is_empty():
		spawn_hazard_ring(hazard_spec)
	attack_active.emit()


func _end_attack() -> void:
	if _hitbox:
		_hitbox.disable()
		_hitbox.reset_swing()
	if _diorama_visual:
		_diorama_visual.scale = Vector3.ONE * _phase_scale_mult
	elif _mesh:
		_mesh.scale = Vector3.ONE * _phase_scale_mult
	var combo: Array = _current_attack_data.get("combo_followups", [])
	if combo.size() > 0 and _combo_step < combo.size() and _has_aggro() and _phase_lock_timer <= 0.0:
		_combo_step += 1
		_enter_windup(combo[_combo_step - 1])
		return
	_combo_step = 0
	_release_attack_token()
	_yield_room_turn()
	_state = State.RECOVERY
	_state_timer = float(
		_current_attack_data.get("recovery_duration", _data.get("recovery_duration", 0.9))
	)


func _select_attack_data() -> void:
	if _attacks.is_empty():
		_current_attack_data = _data
		_combo_step = 0
		return
	if _combo_step > 0:
		return
	_combo_step = 0
	if _attacks_ordered:
		_select_ordered_attack_data()
		return
	var dist := sqrt(_distance_to_player_sq()) if _player != null else 0.0
	var candidates: Array[Dictionary] = []
	var weights: Array[float] = []
	var total := 0.0
	for entry in _attacks:
		if not (entry is Dictionary):
			continue
		var atk: Dictionary = entry
		if dist < float(atk.get("min_range", 0.0)):
			continue
		if dist > float(atk.get("max_range", _attack_range)):
			continue
		var weight := maxf(0.01, float(atk.get("weight", 1.0)))
		candidates.append(atk)
		weights.append(weight)
		total += weight
	if candidates.is_empty():
		_current_attack_data = _first_attack_entry()
		return
	var roll := _enemy_rng.randf() * total
	for i in candidates.size():
		roll -= weights[i]
		if roll <= 0.0:
			_current_attack_data = candidates[i]
			return
	_current_attack_data = candidates[candidates.size() - 1]


## `BS-01` "pattern" phases: a fixed, learnable sequence instead of a weighted roll. Walks
## `_attacks` starting where the last selection left off, skipping any entry out of range this
## frame but still advancing past it, so the sequence keeps its order rather than stalling on a
## move the player is currently too far (or too close) to be hit by.
func _select_ordered_attack_data() -> void:
	var dist := sqrt(_distance_to_player_sq()) if _player != null else 0.0
	var attempts := 0
	while attempts < _attacks.size():
		var entry: Variant = _attacks[_ordered_attack_index % _attacks.size()]
		_ordered_attack_index = (_ordered_attack_index + 1) % _attacks.size()
		attempts += 1
		if not (entry is Dictionary):
			continue
		var atk: Dictionary = entry
		if dist < float(atk.get("min_range", 0.0)):
			continue
		if dist > float(atk.get("max_range", _attack_range)):
			continue
		_current_attack_data = atk
		return
	_current_attack_data = _first_attack_entry()


func _first_attack_entry() -> Dictionary:
	for entry in _attacks:
		if entry is Dictionary:
			return entry as Dictionary
	return _data


func _yield_room_turn() -> void:
	if _room_registered:
		EnemyBlackboard.yield_engager(_room_id, self)


func _release_attack_token() -> void:
	if _attack_token_held and AttackTokenService:
		AttackTokenService.release_token(_attack_token_group)
	_attack_token_held = false


func _register_combat_engagement() -> void:
	if _combat_registered or AudioDirector == null:
		return
	_combat_registered = true
	AudioDirector.register_combat_engagement()


func _unregister_combat_engagement() -> void:
	if not _combat_registered or AudioDirector == null:
		return
	_combat_registered = false
	AudioDirector.unregister_combat_engagement()


func _face_direction(dir: Vector3, delta: float, speed_mult: float = 1.0) -> void:
	if dir.length_squared() < 0.01 or speed_mult <= 0.0:
		return
	var angle := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, angle, minf(1.0, ENEMY_TURN_SPEED * speed_mult * delta))


func _should_track_player() -> bool:
	return _player != null and (_aggro_locked or _state != State.PATROL)


func _tracking_speed_multiplier() -> float:
	match _state:
		State.WINDUP:
			if _windup_commit_ratio() >= 1.0:
				return 0.0
			return WINDUP_TRACKING_SPEED_MULT
		State.ATTACK:
			return ATTACK_TRACKING_SPEED_MULT
		State.RECOVERY:
			return RECOVERY_TRACKING_SPEED_MULT
	return 1.0


func _windup_commit_ratio() -> float:
	if _windup_duration <= 0.0:
		return 1.0
	var fraction := clampf(
		float(
			_current_attack_data.get(
				"tracking_fraction", _data.get("tracking_fraction", WINDUP_TRACKING_FRACTION)
			)
		),
		0.0,
		1.0
	)
	if fraction <= 0.0:
		return 1.0
	var elapsed := clampf(
		(_windup_duration - _state_timer) / _windup_duration, 0.0, 1.0
	)
	return clampf(elapsed / fraction, 0.0, 1.0)


func _on_windup_tick(_committed: bool) -> void:
	pass


## The pre-hold run already committed facing (see `_enter_windup()`'s doc comment), so the hold
## itself only has to freeze the body and the telegraph -- rolling early during a held tell should
## still work, since nothing here re-locks the player's position.
func _enter_windup_hold() -> void:
	_in_windup_hold = true
	velocity.x = 0.0
	velocity.z = 0.0
	if _animator and _animator.is_bound():
		_animator.set_speed_scale(0.0)
	if _windup_will_feint:
		_cancel_windup_as_feint()


func _process_windup_hold(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_windup_hold_timer -= delta
	if _windup_hold_timer <= 0.0:
		_release_windup_hold()


func _release_windup_hold() -> void:
	_in_windup_hold = false
	_windup_hold_timer = 0.0
	if _animator and _animator.is_bound():
		_animator.set_speed_scale(1.0)
	_start_attack()


## A feint is not a whiffed attack -- it never opens a hitbox and never spends the normal recovery,
## so the follow-up (the real attack) can arrive again quickly. `FEINT_COOLDOWN` is short on
## purpose: the whole point is to punish a player who rolled the instant the hold began.
func _cancel_windup_as_feint() -> void:
	_in_windup_hold = false
	_windup_hold_timer = 0.0
	_windup_will_feint = false
	if _animator and _animator.is_bound():
		_animator.set_speed_scale(1.0)
	hide_attack_windup_bar()
	if _hitbox:
		_hitbox.disable()
	_combo_step = 0
	_release_attack_token()
	_yield_room_turn()
	_state = State.RECOVERY
	_state_timer = 0.25
	_short_recovery_cooldown = true


func _apply_attack_lunge() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	var distance := float(_current_attack_data.get("lunge_distance", 0.0))
	if distance <= 0.0:
		return
	var forward := CombatFacing.forward_of(self)
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		return
	var duration := maxf(
		0.01,
		float(_current_attack_data.get("active_duration", _data.get("active_duration", 0.15)))
	)
	var step := forward.normalized() * (distance / duration)
	velocity.x = step.x
	velocity.z = step.z


## `EN-10` "the fast one": a committed gap-closer with its own telegraph. `leaps` data is
## `{range, windup, distance, cooldown}` -- reuses `_enter_windup()` (for the telegraph and the
## commit-to-heading read) and `_apply_attack_lunge()` (via the synthetic `lunge_distance` key) so
## a leap is dodgeable and readable exactly like every other windup, just faster and further.
func _try_leap_attack() -> bool:
	if not _data.has("leaps"):
		return false
	if _leap_cooldown > 0.0 or _player == null:
		return false
	var spec: Dictionary = _data.get("leaps", {})
	var leap_range := maxf(0.1, float(spec.get("range", 6.0)))
	var dist_sq := _distance_to_player_sq()
	if dist_sq > leap_range * leap_range:
		return false
	if dist_sq <= _engage_range * _engage_range:
		return false
	if not _has_line_of_sight_to_player():
		return false
	_attack_token_group = str(_data.get("attack_token_group", "room_default"))
	if AttackTokenService and not AttackTokenService.request_token(_attack_token_group):
		return false
	_attack_token_held = true
	var windup := maxf(0.05, float(spec.get("windup", 0.5)))
	var distance := maxf(0.0, float(spec.get("distance", 5.0)))
	_leap_cooldown = maxf(0.1, float(spec.get("cooldown", 5.0)))
	var leap_data := {
		"windup_duration": windup,
		"active_duration": 0.22,
		"recovery_duration": float(_data.get("recovery_duration", 0.9)),
		"attack_damage": float(_data.get("attack_damage", 20.0)),
		"attack_poise_damage": float(_data.get("attack_poise_damage", 10.0)),
		"attackClass": str(spec.get("attackClass", "unblockable")),
		"max_range": leap_range,
		"lunge_distance": distance,
		"telegraph_shape": "line",
	}
	_combo_step = 0
	_enter_windup(leap_data)
	return true


## `EN-10` "the ambusher": vanish, reposition, re-emerge with a telegraph. `burrows` data is
## `{cooldown, reappear_behind}`. Reuses `MaterialDissolveScript.dissolve()`/`.restore()` -- the
## same fade the death visual uses -- run in reverse instead of a bespoke shader hookup, and
## `_show_attack_telegraph()` for the re-emergence warning. Returns true while the sequence owns
## the frame (the caller should skip the normal state machine for that tick).
func _process_burrow_mixin(delta: float) -> bool:
	if not _data.has("burrows"):
		return false
	if is_dead():
		return false
	if _burrow_phase != "":
		velocity.x = 0.0
		velocity.z = 0.0
		_burrow_timer -= delta
		if _burrow_timer > 0.0:
			return true
		if _burrow_phase == "hiding":
			_teleport_behind_player()
			_burrow_phase = "revealing"
			_burrow_timer = BURROW_REVEAL_TELEGRAPH
			if _diorama_visual:
				MaterialDissolveScript.restore(_diorama_visual)
			if _hurtbox:
				_hurtbox.monitorable = true
				_hurtbox.monitoring = true
			if _body_collision:
				_body_collision.disabled = false
			_current_attack_data = {}
			_show_attack_telegraph(_burrow_timer)
		else:
			_burrow_phase = ""
			var spec: Dictionary = _data.get("burrows", {})
			_burrow_cooldown = maxf(0.1, float(spec.get("cooldown", 8.0)))
		return true
	if _burrow_cooldown > 0.0 or not _has_aggro() or _player == null:
		return false
	if _state != State.CHASE:
		return false
	_burrow_phase = "hiding"
	_burrow_timer = BURROW_HIDE_DURATION
	if _diorama_visual:
		MaterialDissolveScript.dissolve(_diorama_visual, {"duration": BURROW_HIDE_DURATION, "sweep": "down"})
	if _hurtbox:
		_hurtbox.monitorable = false
		_hurtbox.monitoring = false
	if _body_collision:
		_body_collision.disabled = true
	velocity.x = 0.0
	velocity.z = 0.0
	return true


func _teleport_behind_player() -> void:
	if _player == null:
		return
	var spec: Dictionary = _data.get("burrows", {})
	var behind_dist := maxf(0.5, float(spec.get("reappear_behind", 2.0)))
	var forward := CombatFacing.forward_of(_player)
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	global_position = _player.global_position - forward * behind_dist
	global_position.y = _spawn_origin.y


## `EN-10` "the many": on death, spawn `count` smaller copies of `enemyId` each with
## `health_fraction` of this enemy's max health. `splits` data is
## `{enemyId, count, health_fraction}`. Reuses `spawn_adds()`, which already parents new enemies to
## `get_parent()` -- load-bearing for room culling and `EnemyBlackboard.room_key()`. `max_alive`
## caps the *total room population of the child id*, not just this splitter's own spawns, so a room
## of splitting slimes cannot become unbounded.
func _apply_splits_on_death() -> void:
	if not _data.has("splits"):
		return
	var spec: Dictionary = _data.get("splits", {})
	var child_id := str(spec.get("enemyId", ""))
	if child_id.is_empty():
		return
	var max_alive := maxi(1, int(spec.get("max_alive", 6)))
	var parent := get_parent()
	var alive_of_type := 0
	if parent:
		for sib in parent.get_children():
			var enemy := sib as CastleEnemyBase
			if (
				enemy != null
				and is_instance_valid(enemy)
				and enemy != self
				and not enemy.is_dead()
				and enemy.get_enemy_id() == child_id
			):
				alive_of_type += 1
	var count := clampi(int(spec.get("count", 2)), 0, maxi(0, max_alive - alive_of_type))
	if count <= 0:
		return
	var frac := clampf(float(spec.get("health_fraction", 0.5)), 0.05, 1.0)
	var base_max := _health.max_health if _health else 40.0
	var spawned := spawn_adds({"enemyId": child_id, "count": count, "radius": 1.6})
	for node in spawned:
		var health_node := node.get_node_or_null("Health") as Health
		if health_node:
			health_node.configure(maxf(1.0, base_max * frac))


## `EN-10` "the support": periodically calls `spawn_adds()`, capped at `max_alive` living summons
## from this summoner. `summons` data is `{enemyId, count, cooldown, max_alive}`.
func _process_summons_mixin(delta: float) -> void:
	if is_dead():
		return
	var spec: Dictionary = _data.get("summons", {})
	var child_id := str(spec.get("enemyId", ""))
	if child_id.is_empty():
		return
	_summon_cooldown -= delta
	if _summon_cooldown > 0.0:
		return
	if not _has_aggro():
		_summon_cooldown = 0.5
		return
	var pruned: Array = []
	for node in _summoned_adds:
		var enemy := node as CastleEnemyBase
		if enemy != null and is_instance_valid(enemy) and not enemy.is_dead():
			pruned.append(node)
	_summoned_adds = pruned
	var max_alive := maxi(1, int(spec.get("max_alive", 2)))
	if _summoned_adds.size() >= max_alive:
		_summon_cooldown = 1.0
		return
	var count := clampi(int(spec.get("count", 1)), 0, max_alive - _summoned_adds.size())
	if count <= 0:
		_summon_cooldown = 1.0
		return
	var spawned := spawn_adds({"enemyId": child_id, "count": count, "radius": 4.0})
	_summoned_adds.append_array(spawned)
	_summon_cooldown = maxf(0.5, float(spec.get("cooldown", 8.0)))


## `EN-10` "the big one": every `interval` seconds, apply `build_up` of `statusId` to the player if
## within `radius`. `aura` data is `{statusId, radius, interval, build_up}`. Reuses
## `StatusController.add_build_up()` -- the same meter a status-on-hit uses, so the aura and a
## weapon both feeding the same status stack toward the same threshold rather than fighting.
func _process_aura_mixin(delta: float) -> void:
	if not _data.has("aura"):
		return
	if is_dead():
		return
	var spec: Dictionary = _data.get("aura", {})
	var interval := maxf(0.1, float(spec.get("interval", 2.0)))
	_aura_timer -= delta
	if _aura_timer > 0.0:
		return
	_aura_timer = interval
	if _player == null:
		return
	var radius := maxf(0.1, float(spec.get("radius", 4.0)))
	if _distance_to_player_sq() > radius * radius:
		return
	var status_ctrl := _player.get_node_or_null("StatusController") as StatusController
	if status_ctrl == null:
		return
	status_ctrl.add_build_up(str(spec.get("statusId", "torpor")), float(spec.get("build_up", 10.0)))


## `EN-10` "the flyer": a simple height-holding steering term instead of `NavigationAgent3D` -- a
## `flyer` ignores ground nav entirely and just servos `velocity.y` toward `hover_height` above its
## spawn point, letting the existing chase/circle/attack state machine handle the rest (strafing is
## already what `State.CIRCLE` does; diving is just closing distance from the air).
func _apply_flyer_height_hold(delta: float) -> void:
	var hover_height := float(_data.get("hover_height", 2.2))
	var target_y := _spawn_origin.y + hover_height
	var diff := target_y - global_position.y
	var desired_vy := clampf(diff * 4.0, -6.0, 6.0)
	velocity.y = lerpf(velocity.y, desired_vy, clampf(delta * 6.0, 0.0, 1.0))


func _track_player_facing(delta: float, speed_mult: float = 1.0) -> void:
	if _player == null:
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	_face_direction(to_player, delta, speed_mult)


func _pick_patrol_target() -> void:
	var radius: float = _patrol_radius
	var offset := Vector3(
		_enemy_rng.randf_range(-radius, radius), 0.0, _enemy_rng.randf_range(-radius, radius)
	)
	_patrol_target = _spawn_origin + offset


func _on_died() -> void:
	_finalize_death(false)


func _on_poise_broken() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	apply_stagger(_stagger_duration_data)


func _on_hurt(info: DamageInfo) -> void:
	if info.direction.length_squared() > 0.01:
		_last_hit_direction = info.direction
	_last_hit_poise_damage = info.poise_damage
	if is_dead():
		return
	if _state in [State.WINDUP, State.ATTACK]:
		return
	if _animator and _animator.is_bound():
		_animator.play_flinch(_last_hit_direction)
		return
	if not _mesh:
		return
	var tween := create_tween()
	_mesh.scale = Vector3(1.12, 1.12, 1.12)
	tween.tween_property(_mesh, "scale", Vector3.ONE, 0.1)


func _clear_combat_debug_draw() -> void:
	if _hitbox and _hitbox.has_method("set_debug_draw"):
		_hitbox.call("set_debug_draw", false)
	if _hurtbox and _hurtbox.has_method("set_debug_draw"):
		_hurtbox.call("set_debug_draw", false)

extends CharacterBody3D
class_name CastleEnemyBase

## Shared patrol/chase/deaggro AI for castle enemies (ENEMY-2.1 base).

enum State { PATROL, CHASE, INVESTIGATE, RETREAT, CIRCLE, WINDUP, ATTACK, RECOVERY, STAGGER, DEAD }

signal enemy_died
signal attack_telegraph_started
signal attack_active
signal boss_phase_entered(index: int, phase: Dictionary)

const DATA_PATH := ""

const ENEMY_TURN_SPEED := 22.0

## Attack commitment. An enemy may re-aim freely while it is deciding, but once a swing is
## committed the player's spacing decision has to stick — otherwise the roll, the single verb
## the whole genre is built on, does nothing.
##
## `tracking_fraction` is how far into the wind-up re-aiming is still allowed (0.55 = the first
## 55%, i.e. the readable half of the telegraph). Past that the enemy is locked to the heading it
## chose. During the active frames it does not turn at all, and it does not walk: the swing arc
## does the work. Both are overridable per attack (`tracking_fraction`) and per enemy, so a
## homing-by-design boss move stays expressible in data.
const WINDUP_TRACKING_FRACTION := 0.55
const WINDUP_TRACKING_SPEED_MULT := 0.45
const ATTACK_TRACKING_SPEED_MULT := 0.0
const RECOVERY_TRACKING_SPEED_MULT := 0.25
const WINDUP_APPROACH_SPEED_MULT := 0.45
const RECOVERY_APPROACH_SPEED_MULT := 0.3
const PATROL_SPEED_MULT := 0.45
const HP_BAR_SCRIPT := preload("res://scripts/ui/enemy_health_bar.gd")
const MaterialDissolveScript := preload("res://scripts/art/characters/material_dissolve.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")
const GlobalDropServiceScript := preload("res://scripts/loot/global_drop_service.gd")
const CharacterFloorSnapScript := preload("res://scripts/art/characters/character_floor_snap.gd")
const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
const CharacterRigCatalogScript := preload("res://scripts/art/characters/character_rig_catalog.gd")
const AnimControllerScript := preload("res://scripts/art/characters/diorama_anim_controller.gd")
const CombatLayersScript := preload("res://scripts/combat/combat_layers.gd")

@export var player_path: NodePath

## Content id of the definition this scene instances. Set per scene so a variant needs no
## script of its own; a subclass with real behaviour may still override _resolve_enemy_id().
@export var enemy_id: String = ""

## Physics layers that block this enemy's sight line. Defaults to the project-wide occluder set;
## override per scene only for enemies that are meant to see through something others cannot.
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
var _hitbox: Hitbox
var _hurtbox: Hurtbox
var _state_timer := 0.0
var _cooldown := 0.0
var _stagger_timer := 0.0
var _spawn_origin := Vector3.ZERO
var _patrol_target := Vector3.ZERO
var _patrol_wait := 0.0
var _aggro_locked := false
var _diorama_visual: Node3D
var _animator: DioramaAnimController
var _anim_profile := "melee"
var _last_known_player_pos := Vector3.ZERO
var _attack_token_group := ""
var _attack_token_held := false
var _current_attack_data: Dictionary = {}
var _combo_step := 0
var _combat_registered := false
var _deaggro_los_timer := 0.0
var _windup_duration := 0.0
var _last_hit_direction := Vector3.ZERO
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


func set_damage_multiplier(mult: float) -> void:
	_base_damage_multiplier = maxf(0.1, mult)
	_damage_multiplier = maxf(0.1, _base_damage_multiplier * _phase_damage_multiplier)


func get_player() -> Node3D:
	return _player


func get_enemy_rng() -> RandomNumberGenerator:
	return _enemy_rng


func get_health_ratio() -> float:
	if _health == null or _health.max_health <= 0.0:
		return 1.0
	return clampf(_health.current / _health.max_health, 0.0, 1.0)


func get_health_node() -> Health:
	return _health


## Applied by the phase controller on every phase entry; every value is a multiplier
## over the boss's own base tuning so phases never drift from the source data.
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


func get_lock_threat() -> float:
	if _state in [State.WINDUP, State.ATTACK]:
		return 0.6
	if _aggro_locked:
		return 0.3
	return 0.0


## Feeds LockOn._get_lockable_targets(): bosses outrank elites outrank trash, and an enemy mid-swing
## outranks an idle one, so auto-lock prefers the threat actually worth watching.
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
	var enemy_id := get_enemy_id()
	return enemy_id.contains("boss") or enemy_id.contains("miniboss")


func _ready() -> void:
	add_to_group("lockable")
	add_to_group("enemy")
	_spawn_origin = global_position
	_enemy_rng.seed = (
		FloorSeedMix.mix(RunFlow.current_seed, RunFlow.current_floor) ^ hash(str(get_path()))
	)
	var enemy_id := get_enemy_id()
	if enemy_id.is_empty():
		_data = ContentLoader.load_json(get_data_path())
	else:
		_data = EnemyCatalog.get_definition(enemy_id)
	_health = get_node_or_null("Health") as Health
	_poise = get_node_or_null("Poise") as Poise
	_hitbox = get_node_or_null("AttackPivot/Hitbox") as Hitbox
	_hurtbox = get_node_or_null("Hurtbox") as Hurtbox
	if player_path and not player_path.is_empty():
		_player = get_node_or_null(player_path) as Node3D
	if _health:
		_health.configure(_data.get("health", 80.0))
		_health.died.connect(_on_died)
	if _poise:
		_poise.configure(_data.get("poise", 40.0), float(_data.get("stagger_duration", 1.0)))
		_poise.poise_broken.connect(_on_poise_broken)
	if _hurtbox:
		# Only `damaged` drives the hit reaction. Hurtbox.receive_hit emits both `damaged` and
		# `hit_resolved` for the same hit, so listening to both played the flinch twice per hit
		# and clobbered _last_hit_direction with a zero vector, breaking directional death sweeps.
		_hurtbox.damaged.connect(_on_hurt)
		_apply_hurtbox_data()
	_unpack_tuning()
	_castle_run = get_tree().get_first_node_in_group("castle_run")
	_ai_tick_phase = int(get_instance_id() % AI_LOD_FAR_STRIDE)
	_circle_direction = 1.0 if _enemy_rng.randf() < 0.5 else -1.0
	_setup_diorama_visual()
	if _health:
		_attach_health_bar()
	_setup_phase_controller()
	_pick_patrol_target()
	_join_room_board()


func _join_room_board() -> void:
	if _is_boss or _room_registered:
		return
	_room_id = EnemyBlackboard.room_key(self)
	EnemyBlackboard.register(_room_id, self)
	_room_registered = true


func _exit_tree() -> void:
	# Freeing mid-swing is the third way a token used to leak, alongside stagger and death.
	_release_attack_token()
	if not _room_registered:
		return
	EnemyBlackboard.unregister(_room_id, self)
	_room_registered = false


func set_ai_role(role: int) -> void:
	_role = role


func get_ai_role() -> int:
	return _role


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


## Swaps the pool `_select_attack_data()` draws from. Boss phases call this to
## hand the fight a new move set without touching the shared enemy tuning.
func set_active_attacks(list: Array) -> void:
	_attacks = list
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


func get_active_attacks() -> Array:
	return _attacks


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


func get_phase_controller() -> Node:
	return _phase_controller


## Places `count` instances of `enemyId` in a ring around this enemy. Positions are set
## before the child enters the tree so each add records the right patrol origin.
func spawn_adds(spec: Dictionary) -> Array[Node]:
	var spawned: Array[Node] = []
	var enemy_id := String(spec.get("enemyId", ""))
	if enemy_id.is_empty() or not EnemyCatalog.has_enemy(enemy_id):
		return spawned
	var scene: PackedScene = EnemyCatalog.get_scene(enemy_id)
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
			add_enemy.set_catalog_id(enemy_id)
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
	if _phase_controller and _phase_controller.has_method("reset_phases"):
		_phase_controller.call("reset_phases")


func get_phase_index() -> int:
	if _phase_controller and _phase_controller.has_method("get_phase_index"):
		return int(_phase_controller.call("get_phase_index"))
	return 0


## Called by the phase controller when a threshold is crossed; the boss holds its
## ground for the length of the tell so the swap is readable rather than instant.
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
	_state = State.CHASE
	_cooldown = maxf(_cooldown, _phase_lock_timer)


func is_phase_transitioning() -> bool:
	return _phase_lock_timer > 0.0


func is_immune() -> bool:
	return _phase_invuln_timer > 0.0


func notify_phase_entered(index: int, phase: Dictionary) -> void:
	boss_phase_entered.emit(index, phase)


func set_player(player: Node3D) -> void:
	_player = player


func set_catalog_id(id: String) -> void:
	_catalog_id_override = id
	if not _data.is_empty() or id.is_empty():
		return
	_data = EnemyCatalog.get_definition(id)
	if _data.is_empty():
		return
	# Unpack first so health and poise configure from the same tuning fields every other spawn
	# path uses. Configuring poise with only its first argument here made boss adds fall back to
	# the default stagger duration instead of the catalog's.
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


func _resolve_enemy_id() -> String:
	return enemy_id


func get_data_path() -> String:
	var enemy_id := get_enemy_id()
	if enemy_id.is_empty():
		return DATA_PATH
	return EnemyCatalog.get_content_path(enemy_id)


func _setup_diorama_visual() -> void:
	var enemy_id := get_enemy_id()
	if enemy_id.is_empty():
		enemy_id = str(_data.get("id", ""))
	_anim_profile = CharacterSkin.profile_for_enemy_data(_data)
	var theme := CharacterSkin.theme_for_enemy_id(enemy_id)
	_diorama_visual = CharacterSkin.build_enemy_body(self, _anim_profile, theme, enemy_id, _data)
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


func _on_anim_hitbox_open() -> void:
	if _state != State.ATTACK or _hitbox == null:
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
	_hp_bar.setup(_health, get_hp_bar_height())


func begin_attack_windup_bar(duration: float) -> void:
	_windup_duration = maxf(0.05, duration)
	if _hp_bar:
		_hp_bar.begin_attack_telegraph(_windup_duration)


func hide_attack_windup_bar() -> void:
	_windup_duration = 0.0
	if _hp_bar:
		_hp_bar.hide_attack_telegraph()


func _show_attack_telegraph(duration: float) -> void:
	var radius := float(
		_current_attack_data.get("telegraph_radius", _data.get("telegraph_radius", 1.6))
	)
	var shape := String(
		_current_attack_data.get("telegraph_shape", _data.get("telegraph_shape", "circle"))
	)
	var tint := Color(0.95, 0.34, 0.28)
	if _data.has("telegraph_tint"):
		tint = Color(_data["telegraph_tint"])
	var forward := -global_transform.basis.z
	VfxService.play_telegraph(global_position, radius, duration, tint, shape, forward)


func _apply_hurtbox_data() -> void:
	if _hurtbox == null:
		return
	if _data.has("block_mitigation"):
		_hurtbox.set("block_mitigation", _data.get("block_mitigation"))
	if _data.has("block_angle_deg"):
		_hurtbox.set("block_angle_deg", _data.get("block_angle_deg"))


func _apply_mesh_tint(color: Color) -> void:
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
		# _finalize_death disabled this; without restoring it a bonfire-respawned enemy is a ghost
		# the player and its own navigation walk straight through.
		_body_collision.disabled = false
	if _hp_bar:
		_hp_bar.visible = true
	if _animator and _animator.is_bound():
		_animator.revive()
	if _diorama_visual:
		MaterialDissolveScript.reset_death_visual(_diorama_visual)
		MaterialFlashScript.restore_all(_diorama_visual)
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
	# Dying mid-swing must hand the attack token back too.
	_release_attack_token()
	if _health:
		_health.force_dead()
	if not silent:
		RunFlow.register_kill(get_enemy_id())
		_award_kill_coins()
		_try_roll_global_drop()
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


func _award_kill_coins() -> void:
	var reward := int(_data.get("coinReward", _data.get("goldReward", 5)))
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
	var drop_id := GlobalDropServiceScript.roll_enemy_drop(
		get_instance_id(), floor_index, tier, dungeon_id
	)
	if drop_id != "":
		InventoryService.add_loot(drop_id)


func _force_dead_silent() -> void:
	_finalize_death(true)


func apply_stagger(duration: float) -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	# A stagger jumps straight to STATE.STAGGER without routing through _end_attack, so an enemy
	# interrupted mid-windup used to keep its attack token forever. Tokens gate how many enemies
	# may swing at once, so leaked ones drain the pool until nothing can attack at all.
	if _state in [State.WINDUP, State.ATTACK]:
		_combo_step = 0
		_release_attack_token()
	_state = State.STAGGER
	_stagger_timer = duration
	_yield_room_turn()
	if _hitbox:
		_hitbox.disable()
	hide_attack_windup_bar()
	if _animator and _animator.is_bound():
		_animator.play_stagger(duration)
	elif _mesh:
		_mesh.scale = Vector3.ONE


func cancel_attack() -> void:
	if _state in [State.WINDUP, State.ATTACK]:
		_end_attack()


func _physics_process(delta: float) -> void:
	if _health and _health.is_dead() and not is_dead():
		_finalize_death(true)
	var staggered := false
	if _cooldown > 0.0:
		_cooldown -= delta
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
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	_update_diorama_animation(delta)


## Only locomotion is pushed per frame. Attacks, staggers and death are one-shot
## clips owned by the controller's priority stack, so they are started from the
## state transitions instead of being re-asserted every tick.
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
			# Closing slows to a stop as the swing commits, so the distance the player reads at
			# the start of the telegraph is the distance the swing actually lands at.
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
				_start_attack()
		State.ATTACK:
			# No pursuit during the active frames. An attack that walks after the player during
			# its own hitbox window cannot be dodged by spacing, only by i-frames — and it beats
			# those too by re-overlapping the moment they end. Authored lunges still move.
			_apply_attack_lunge()
			_state_timer -= delta
			if _state_timer <= 0.0:
				_end_attack()
		State.RECOVERY:
			_apply_chase_velocity(delta, RECOVERY_APPROACH_SPEED_MULT)
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = State.CHASE if _has_aggro() else State.PATROL
				_cooldown = _attack_cooldown_data


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
	# Patrolling at full chase speed made "hasn't noticed you" and "hunting you" look identical,
	# which wastes the vision-cone/hearing/awareness system feeding this state.
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
	if _can_attack():
		_start_windup()
		return
	var holding_back := _cooldown > 0.0 or _role != EnemyBlackboard.Role.ENGAGER
	if holding_back and _distance_to_player_sq() <= _circle_entry_range_sq():
		_enter_circle()
		return
	_apply_chase_velocity(delta)


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


## Enemies held back by cooldown or the attack-token budget orbit at spacing instead
## of standing on the player, so a group surrounds rather than queues.
func _process_circle(delta: float) -> void:
	if not _has_aggro() or _player == null:
		_state = State.INVESTIGATE
		_state_timer = 2.5
		return
	_last_known_player_pos = _player.global_position
	_state_timer -= delta
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
	var tangent := Vector3(-dir.z, 0.0, dir.x) * _circle_direction
	var move := tangent + dir * radial
	if move.length_squared() < 0.01:
		velocity = Vector3.ZERO
	else:
		velocity = move.normalized() * _move_speed * 0.8
	if _state_timer <= 0.0:
		_state = State.CHASE


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


## Uses a navigation path when the world has one baked, and otherwise steers directly
## with a seeded sidestep whenever the target is behind cover, so an enemy separated
## by a pillar slides around it instead of pressing into it.
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
	_nav_agent.avoidance_enabled = false
	add_child(_nav_agent)


## Pure query. All latching and decay happens once per AI tick in `_update_perception`,
## so the states below can ask this as often as they like for free.
func _has_aggro() -> bool:
	return _player != null and _aggro_locked


func get_awareness() -> float:
	return _awareness


func is_unaware() -> bool:
	return not _aggro_locked and _awareness < AWARENESS_INVESTIGATE


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
	var facing := -global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.01:
		return true
	return facing.normalized().dot(to_player.normalized()) >= _vision_cone_cos


## Sprinting is loud, walking is quiet, standing still is silent. Read off the
## player's own velocity so nothing has to be pushed in from the locomotion side.
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


## Fired once per aggro latch, never per frame: one walk over the room roster when it
## wakes up, instead of every enemy alive on the floor.
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

	# Allies in adjacent rooms still count, and the board can answer that without touching every
	# enemy on the floor.
	var neighbours := EnemyBlackboard.nearby(global_position, _alert_radius)
	if not neighbours.is_empty():
		return neighbours

	# Whole-floor group scan: correct but O(N) inside a single frame. Kept only as a debug-build
	# safety net for enemies that never registered with the board.
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
	_attack_token_group = str(_data.get("attack_token_group", "room_default"))
	if AttackTokenService and not AttackTokenService.request_token(_attack_token_group):
		# Refused: orbit instead of re-requesting a token every physics frame.
		_cooldown = _enemy_rng.randf_range(0.25, 0.6)
		if _has_aggro():
			_enter_circle()
		return
	_attack_token_held = true
	_select_attack_data()
	_enter_windup(_current_attack_data)


func _enter_windup(attack_data: Dictionary) -> void:
	_current_attack_data = attack_data
	_state = State.WINDUP
	var windup: float = float(
		attack_data.get("windup_duration", _data.get("windup_duration", 0.7))
	)
	var windup_variance: float = float(
		attack_data.get("windup_variance", _data.get("windup_variance", 0.0))
	)
	if windup_variance > 0.0:
		windup += _enemy_rng.randf_range(-windup_variance, windup_variance)
	_state_timer = maxf(0.05, windup)
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
	begin_attack_windup_bar(_state_timer)
	AudioDirector.play_sfx("windup", global_position + Vector3(0.0, 1.0, 0.0))
	attack_telegraph_started.emit()


func _start_attack() -> void:
	if is_dead() or (_health and _health.is_dead()):
		_release_attack_token()
		return
	_state = State.ATTACK
	_state_timer = float(
		_current_attack_data.get("active_duration", _data.get("active_duration", 0.15))
	)
	hide_attack_windup_bar()
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
			)
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
		_diorama_visual.scale = Vector3.ONE
	elif _mesh:
		_mesh.scale = Vector3.ONE
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


## Picks from the active move set, keeping only the entries whose `min_range`/`max_range`
## band contains the current spacing, then rolling on `weight`.
func _select_attack_data() -> void:
	if _attacks.is_empty():
		_current_attack_data = _data
		_combo_step = 0
		return
	if _combo_step > 0:
		return
	_combo_step = 0
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


## How fast this enemy may re-aim at the player right now, as a multiple of ENEMY_TURN_SPEED.
## Zero means the heading is locked: the swing is committed and cannot follow a dodge.
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


## 0 while the wind-up is still readable and re-aimable, ramping to 1 at the commit point.
## The commit point is `tracking_fraction` of the way through the wind-up, overridable per
## attack and per enemy so a deliberately relentless boss move can still be authored.
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


## Per-frame hook for the wind-up, with whether the swing has passed its commit point.
##
## Exists so subclasses that resolve a trajectory up front (the archer's locked shot, any aimed
## projectile) can keep re-aiming exactly as long as the body is still allowed to turn, and
## freeze on the same frame it does. Without a shared commit point the fired direction and the
## visible heading disagree, which reads as the projectile curving.
func _on_windup_tick(_committed: bool) -> void:
	pass


## Drives the authored forward step of an attack during its active frames. Enemies stand still
## by default; `lunge_distance` on an attack entry buys a committed dash along the heading the
## swing was locked to, which is dodgeable precisely because it cannot be re-aimed.
func _apply_attack_lunge() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	var distance := float(_current_attack_data.get("lunge_distance", 0.0))
	if distance <= 0.0:
		return
	var forward := -global_transform.basis.z
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
	if is_dead():
		return
	# A flinch during a committed swing is a lie: the hitbox stays open and the state machine
	# keeps running, but the player reads the animation as a stagger and steps in. Only poise
	# breaks (which route through apply_stagger) may interrupt a swing.
	if _state in [State.WINDUP, State.ATTACK]:
		return
	if _animator and _animator.is_bound():
		_animator.play_flinch()
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

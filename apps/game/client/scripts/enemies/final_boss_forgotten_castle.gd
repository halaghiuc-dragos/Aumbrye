extends CastleEnemyBase

## Floor 10 final boss — Forgotten Castle (FLOOR-7.5).
## Phase 1: combat to ~25% HP
## Phase 2: dodge simultaneous floor spikes
## Phase 3: collect crystals → cannon → break shield (immune until then)

signal boss_defeated
signal phase_changed(phase: int)

const SPIKE_SCENE := preload("res://scenes/traps/spike_trap.tscn")
const CRYSTAL_SCENE := preload("res://scenes/bosses/final_boss_crystal.tscn")

enum Phase { COMBAT = 1, SPIKES = 2, PUZZLE = 3 }

var _phase := Phase.COMBAT
var _phase2_done := false
var _shield_active := false
var _crystals_collected := 0
var _crystals_required := 3
var _spike_timer := 0.0
var _immune := false


func get_enemy_id() -> String:
	return "final_boss_forgotten_castle"


func get_hp_bar_height() -> float:
	return 3.2


func _ready() -> void:
	super._ready()
	if _health:
		_health.health_changed.connect(_on_health_changed)
	AudioDirector.play_boss_music()


func is_immune() -> bool:
	return _immune or (_phase == Phase.PUZZLE and _shield_active)


func _on_hurt(_info: DamageInfo) -> void:
	if is_immune():
		return
	super._on_hurt(_info)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _state == State.DEAD:
		return
	match _phase:
		Phase.SPIKES:
			_process_spike_phase(delta)
		Phase.PUZZLE:
			_process_puzzle_phase(delta)


func _on_health_changed(current: float, max_value: float) -> void:
	if _phase != Phase.COMBAT or max_value <= 0.0:
		return
	if current / max_value <= 0.25 and not _phase2_done:
		_enter_phase(Phase.SPIKES)


func _enter_phase(new_phase: Phase) -> void:
	_phase = new_phase
	phase_changed.emit(int(_phase))
	match _phase:
		Phase.SPIKES:
			_immune = true
			_spike_timer = 0.0
		Phase.PUZZLE:
			_immune = true
			_shield_active = true
			_spawn_puzzle_crystals()
		_:
			_immune = false


func _process_spike_phase(delta: float) -> void:
	_spike_timer -= delta
	if _spike_timer > 0.0:
		return
	_spike_timer = 0.45
	_spawn_spike_burst()
	if _spike_timer <= 0.0:
		# After several bursts transition to puzzle.
		if randi() % 5 == 0:
			_phase2_done = true
			_enter_phase(Phase.PUZZLE)


func _spawn_spike_burst() -> void:
	for _i in range(6):
		var trap: Node3D = SPIKE_SCENE.instantiate() as Node3D
		trap.position = Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-8.0, 8.0))
		get_parent().add_child(trap)


func _spawn_puzzle_crystals() -> void:
	for i in range(_crystals_required):
		var crystal: Node3D = CRYSTAL_SCENE.instantiate() as Node3D
		crystal.position = Vector3(-6.0 + i * 6.0, 0.5, 6.0)
		if crystal.has_signal("collected"):
			crystal.collected.connect(_on_crystal_collected)
		get_parent().add_child(crystal)


func _on_crystal_collected() -> void:
	_crystals_collected += 1
	if _crystals_collected >= _crystals_required:
		_break_shield()


func _break_shield() -> void:
	_shield_active = false
	_immune = false


func _process_puzzle_phase(_delta: float) -> void:
	pass


func _on_died() -> void:
	super._on_died()
	boss_defeated.emit()


func register_cannon_hit() -> void:
	if _shield_active:
		_break_shield()


func capture_state() -> Dictionary:
	return {
		"alive": not is_dead(),
		"phase": int(_phase),
		"shieldActive": _shield_active,
		"crystalsCollected": _crystals_collected,
	}


func apply_state(state: Dictionary) -> void:
	if not state.get("alive", true):
		super.apply_state(state)
		return
	_phase = int(state.get("phase", Phase.COMBAT)) as Phase
	_shield_active = bool(state.get("shieldActive", false))
	_crystals_collected = int(state.get("crystalsCollected", 0))
	_immune = _phase != Phase.COMBAT or _shield_active

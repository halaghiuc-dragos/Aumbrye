extends Node
class_name BossPhaseController


signal phase_entered(index: int, phase: Dictionary)

const DEFAULT_TELL_DURATION := 1.1

var _boss: CastleEnemyBase
var _phases: Array = []
var _index := -1
var _spawned: Array[Node] = []

var _despawn_on_death: Array[Node] = []


func setup(boss: CastleEnemyBase, phases: Array) -> void:
	_boss = boss
	_phases = phases


func get_phase_index() -> int:
	return maxi(_index, 0)


func reset_phases() -> void:
	_index = -1
	_clear_spawned()


func _physics_process(_delta: float) -> void:
	if _boss == null or not is_instance_valid(_boss) or _phases.is_empty():
		return
	if _boss.is_dead():
		return
	var target := _resolve_phase_for_ratio(_boss.get_health_ratio())
	if target <= _index:
		return
	var silent := _index < 0 and target > 0
	_index = target
	_enter_phase(target, silent)


func _resolve_phase_for_ratio(ratio: float) -> int:
	var resolved := 0
	for i in _phases.size():
		var entry: Variant = _phases[i]
		if not (entry is Dictionary):
			continue
		var phase: Dictionary = entry
		if ratio <= float(phase.get("hpBelow", 1.0)):
			resolved = maxi(resolved, i)
	return resolved


func _enter_phase(index: int, silent: bool) -> void:
	var entry: Variant = _phases[index]
	if not (entry is Dictionary):
		return
	var phase: Dictionary = entry
	var attacks: Array = phase.get("attacks", []) as Array
	if attacks.is_empty():
		attacks = _boss.get_base_attacks()
	_boss.set_active_attacks(attacks)
	_boss.apply_phase_modifiers(phase)
	var on_enter: Dictionary = phase.get("onEnter", {}) as Dictionary
	if not silent and not on_enter.is_empty():
		_play_entry(on_enter)
	_boss.notify_phase_entered(index, phase)
	phase_entered.emit(index, phase)


func _play_entry(on_enter: Dictionary) -> void:
	var tell := maxf(0.0, float(on_enter.get("tellDuration", DEFAULT_TELL_DURATION)))
	var invuln := maxf(0.0, float(on_enter.get("invulnerableFor", 0.0)))
	_boss.begin_phase_transition(tell, invuln)
	var origin: Vector3 = _boss.global_position
	var telegraph_radius := float(on_enter.get("telegraphRadius", 0.0))
	if telegraph_radius > 0.0 and VfxService:
		VfxService.play_telegraph(
			origin,
			telegraph_radius,
			maxf(0.2, tell),
			_color_from(on_enter.get("telegraphTint", null), Color(0.95, 0.6, 0.35)),
			String(on_enter.get("telegraphShape", "circle")),
			CombatFacing.forward_of(_boss)
		)
	var vfx := String(on_enter.get("vfx", ""))
	if vfx != "" and VfxService:
		VfxService.play(vfx, origin + Vector3(0.0, 1.0, 0.0))
	var sfx := String(on_enter.get("sfx", ""))
	if sfx != "" and AudioDirector:
		AudioDirector.play_sfx(sfx, origin + Vector3(0.0, 1.0, 0.0))
	if AudioDirector:
		AudioDirector.set_boss_phase(get_phase_index(), String(on_enter.get("music", "")))
	var shake := float(on_enter.get("shake", 0.0))
	if shake > 0.0 and VfxService:
		VfxService.request_shake(shake, int(maxf(0.2, tell) * 1000.0))
	for spec in on_enter.get("spawnAdds", []):
		if spec is Dictionary:
			var adds: Array = _boss.spawn_adds(spec as Dictionary)
			_spawned.append_array(adds)
			if bool((spec as Dictionary).get("despawnOnDeath", false)):
				_despawn_on_death.append_array(adds)
	for spec in on_enter.get("hazards", []):
		if spec is Dictionary:
			var hazards: Array = _boss.spawn_hazard_ring(spec as Dictionary)
			_spawned.append_array(hazards)
			_despawn_on_death.append_array(hazards)


func clear_death_spawns() -> void:
	for node in _despawn_on_death:
		if is_instance_valid(node):
			node.queue_free()
		_spawned.erase(node)
	_despawn_on_death.clear()


func _clear_spawned() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.queue_free()
	_spawned.clear()
	_despawn_on_death.clear()


func _color_from(value: Variant, fallback: Color) -> Color:
	if value is Array and (value as Array).size() >= 3:
		var parts: Array = value
		return Color(float(parts[0]), float(parts[1]), float(parts[2]))
	if value is String:
		return Color(value as String)
	return fallback

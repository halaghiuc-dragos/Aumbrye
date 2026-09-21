extends Node
class_name StatusController


signal statuses_changed
signal build_up_changed

@export var health_path: NodePath
@export var team: String = "enemy"

var _health: Health
var _active: Dictionary = {}
var _meters: Dictionary = {}
var _resistance: Dictionary = {}
var _slow_multiplier := 1.0
var _stunned := false
var _damage_taken_multiplier := 1.0
var _stat_totals: Dictionary = {}


func _ready() -> void:
	if health_path:
		_health = get_node_or_null(health_path) as Health


func set_health(health: Health) -> void:
	_health = health


func _physics_process(delta: float) -> void:
	if not _meters.is_empty():
		_tick_meters(delta)
	if _active.is_empty():
		return
	var expired: Array[String] = []
	var modifiers_dirty := false
	var lifecycle_dirty := false
	for status_id in _active.keys():
		if not _active.has(status_id):
			continue
		var entry: Dictionary = _active[status_id]
		var def := StatusCatalog.get_definition(status_id)
		entry["remaining"] = float(entry.get("remaining", 0.0)) - delta
		entry["elapsed"] = float(entry.get("elapsed", 0.0)) + delta
		entry["tick_timer"] = float(entry.get("tick_timer", 0.0)) - delta
		var interval := maxf(0.001, float(def.get("tickInterval", 1.0)))
		var catch_up := 0
		while entry["tick_timer"] <= 0.0 and catch_up < 16:
			# A tick belongs to the status only while its simulated lifetime remains positive.
			if float(entry.get("remaining", 0.0)) + delta + float(entry["tick_timer"]) > 0.0:
				_apply_tick(entry, def)
			entry["tick_timer"] = float(entry["tick_timer"]) + interval
			catch_up += 1
		if float(entry.get("remaining", 0.0)) > 0.0:
			continue
		if bool(def.get("stackDecay", false)) and int(entry.get("stacks", 1)) > 1:
			entry["stacks"] = int(entry.get("stacks", 1)) - 1
			entry["remaining"] = float(entry.get("duration", 0.0))
			modifiers_dirty = true
			lifecycle_dirty = true
			continue
		expired.append(status_id)
	for status_id in expired:
		_remove_status(status_id)
		lifecycle_dirty = true
	if modifiers_dirty or not expired.is_empty():
		_recalc_modifiers(false)
	if lifecycle_dirty:
		statuses_changed.emit()
	for expired_id in expired:
		var expired_def := StatusCatalog.get_definition(expired_id)
		var follow_up := str(expired_def.get("expireStatusId", ""))
		if follow_up != "":
			apply_status(follow_up, int(expired_def.get("expireStatusStacks", 1)))


func apply_status(
	status_id: String,
	stacks: int = 1,
	duration_override: float = -1.0,
	instigator: Node = null,
	application_origin: String = "direct",
	weapon_item_id: String = ""
) -> void:
	if status_id == "":
		return
	var def := StatusCatalog.get_definition(status_id)
	if def.is_empty():
		return
	var max_stacks: int = int(def.get("maxStacks", 1))
	var duration := (
		duration_override if duration_override > 0.0 else float(def.get("duration", 4.0))
	)
	if _active.has(status_id):
		var entry: Dictionary = _active[status_id]
		var refresh_policy := str(def.get("refreshPolicy", "extend"))
		match refresh_policy:
			"reset":
				entry["remaining"] = duration
				entry["duration"] = duration
				entry["elapsed"] = 0.0
				entry["tick_timer"] = float(def.get("tickInterval", 1.0))
			"replace":
				entry["stacks"] = mini(stacks, max_stacks)
				entry["remaining"] = duration
				entry["duration"] = duration
				entry["elapsed"] = 0.0
				entry["tick_timer"] = float(def.get("tickInterval", 1.0))
			_:
				entry["remaining"] = maxf(float(entry.get("remaining", 0.0)), duration)
				entry["duration"] = maxf(float(entry.get("duration", duration)), duration)
		if refresh_policy != "replace":
			entry["stacks"] = mini(int(entry.get("stacks", 1)) + stacks, max_stacks)
	else:
		_active[status_id] = {
			"stacks": mini(stacks, max_stacks),
			"remaining": duration,
			"duration": duration,
			"tick_timer": float(def.get("tickInterval", 1.0)),
			"elapsed": 0.0,
		}
	var active_entry: Dictionary = _active[status_id]
	active_entry["instigator"] = weakref(instigator) if instigator != null else null
	active_entry["weapon_item_id"] = weapon_item_id
	active_entry["application_origin"] = application_origin
	_recalc_modifiers(false)
	statuses_changed.emit()
	if CombatEvents:
		var actor := instigator if instigator != null and is_instance_valid(instigator) else get_parent()
		CombatEvents.dispatch(
			CombatEvents.ON_STATUS_APPLIED,
			{
				"actor": actor,
				"instigator": instigator,
				"target": get_parent(),
				"statusId": status_id,
				"applicationOrigin": application_origin,
			},
		)


func add_build_up(
	status_id: String, amount: float = -1.0, instigator: Node = null, weapon_item_id: String = ""
) -> bool:
	if status_id == "":
		return false
	var def := StatusCatalog.get_definition(status_id)
	if def.is_empty():
		return false
	var threshold := float(def.get("buildUpThreshold", 0.0))
	if threshold <= 0.0:
		apply_status(status_id, 1, -1.0, instigator, "build_up", weapon_item_id)
		return true
	var gain := amount if amount > 0.0 else float(def.get("buildUpPerHit", threshold * 0.25))
	var meter: Dictionary = _meters.get(status_id, {"value": 0.0, "grace": 0.0})
	meter["value"] = float(meter.get("value", 0.0)) + gain
	meter["grace"] = float(def.get("buildUpGrace", 1.0))
	_meters[status_id] = meter
	if float(meter["value"]) < _required_build_up(status_id, def):
		build_up_changed.emit()
		return false
	_meters.erase(status_id)
	var cap := float(def.get("buildUpResistCap", threshold * 1.5))
	var gained := float(def.get("buildUpResistGain", threshold * 0.25))
	_resistance[status_id] = minf(cap, float(_resistance.get(status_id, 0.0)) + gained)
	apply_status(status_id, int(def.get("buildUpStacks", 1)), -1.0, instigator, "build_up", weapon_item_id)
	_burst(def, instigator)
	build_up_changed.emit()
	return true


func debug_apply(status_id: String) -> void:
	apply_status(status_id, 1)


func get_active_statuses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for status_id in _active:
		var entry: Dictionary = _active[status_id]
		(
			out
			. append(
				{
					"id": status_id,
					"stacks": int(entry.get("stacks", 1)),
					"remaining": float(entry.get("remaining", 0.0)),
					"duration": float(entry.get("duration", 0.0)),
				}
			)
		)
	return out


func get_build_up_meters() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for status_id in _meters:
		var def := StatusCatalog.get_definition(status_id)
		var required := _required_build_up(status_id, def)
		if required <= 0.0:
			continue
		var value := float(_meters[status_id].get("value", 0.0))
		(
			out
			. append(
				{
					"id": status_id,
					"value": value,
					"threshold": required,
					"ratio": clampf(value / required, 0.0, 1.0),
				}
			)
		)
	return out


func get_slow_multiplier() -> float:
	return _slow_multiplier


func get_damage_taken_multiplier() -> float:
	return _damage_taken_multiplier


func get_stat_totals() -> Dictionary:
	return _stat_totals.duplicate()


func is_stunned() -> bool:
	return _stunned


func clear_all() -> void:
	_active.clear()
	_meters.clear()
	_resistance.clear()
	_slow_multiplier = 1.0
	_stunned = false
	_damage_taken_multiplier = 1.0
	_stat_totals.clear()
	statuses_changed.emit()
	build_up_changed.emit()


## Removes harmful effects and their partial buildup without stripping buffs or resetting the
## acquired resistance earned from earlier applications.
func cleanse_debuffs() -> bool:
	var removed_active := false
	var removed_meter := false
	for status_id in _active.keys():
		if str(StatusCatalog.get_definition(status_id).get("polarity", "debuff")) == "debuff":
			_active.erase(status_id)
			removed_active = true
	for status_id in _meters.keys():
		if str(StatusCatalog.get_definition(status_id).get("polarity", "debuff")) == "debuff":
			_meters.erase(status_id)
			removed_meter = true
	if removed_active:
		_recalc_modifiers(false)
		statuses_changed.emit()
	if removed_meter:
		build_up_changed.emit()
	return removed_active or removed_meter


func _required_build_up(status_id: String, def: Dictionary) -> float:
	return float(def.get("buildUpThreshold", 0.0)) + float(_resistance.get(status_id, 0.0))


func _tick_meters(delta: float) -> void:
	var drained: Array[String] = []
	var changed := false
	for status_id in _meters.keys():
		if not _meters.has(status_id):
			continue
		var meter: Dictionary = _meters[status_id]
		var grace := float(meter.get("grace", 0.0))
		if grace > 0.0:
			meter["grace"] = grace - delta
			continue
		var def := StatusCatalog.get_definition(status_id)
		var threshold := float(def.get("buildUpThreshold", 0.0))
		var decay := float(def.get("buildUpDecay", threshold * 0.1))
		if decay <= 0.0:
			continue
		var value := float(meter.get("value", 0.0)) - decay * delta
		changed = true
		if value <= 0.0:
			drained.append(status_id)
		else:
			meter["value"] = value
	for status_id in drained:
		_meters.erase(status_id)
	if changed:
		build_up_changed.emit()


func _apply_tick(entry: Dictionary, def: Dictionary) -> void:
	var stacks := float(int(entry.get("stacks", 1)))
	var heal := float(def.get("tickHeal", 0.0)) * stacks
	if heal > 0.0 and _health != null and not _health.is_dead():
		_health.heal(heal)
	var growth := float(def.get("tickGrowth", 0.0))
	var ramp_age := float(entry.get("elapsed", 0.0))
	var ramp_cap := float(def.get("tickGrowthMaxSeconds", -1.0))
	if ramp_cap >= 0.0:
		ramp_age = minf(ramp_age, ramp_cap)
	var ramp := 1.0 + growth * ramp_age
	var tick_dmg: float = float(def.get("tickDamage", 0.0)) * stacks * ramp
	_deal_damage(
		tick_dmg,
		str(def.get("damageType", DamageInfo.TYPE_PHYSICAL)),
		_resolve_instigator(entry),
		str(entry.get("weapon_item_id", ""))
	)


func _burst(def: Dictionary, instigator: Node = null) -> void:
	_deal_damage(
		float(def.get("procDamage", 0.0)),
		str(def.get("damageType", DamageInfo.TYPE_PHYSICAL)),
		instigator
	)


func _resolve_instigator(entry: Dictionary) -> Node:
	var reference: Variant = entry.get("instigator")
	if reference is WeakRef:
		var node := (reference as WeakRef).get_ref() as Node
		return node if node != null and is_instance_valid(node) else null
	return null


func _deal_damage(
	amount: float, dmg_type: String, instigator: Node = null, weapon_item_id: String = ""
) -> void:
	if amount <= 0.0 or _health == null or _health.is_dead():
		return
	var body := get_parent()
	if body:
		var hurtbox := body.get_node_or_null("Hurtbox") as Hurtbox
		if hurtbox:
			hurtbox.receive_periodic_damage(amount, dmg_type, instigator, weapon_item_id)
			return
	_health.take_damage(DamageInfo.apply_resistance(amount, dmg_type, _get_resistances()))


func _get_resistances() -> Dictionary:
	var body := get_parent()
	if body and body.has_method("get_enemy_id"):
		var enemy_id: String = body.call("get_enemy_id")
		if enemy_id != "":
			return EnemyCatalog.get_definition(enemy_id).get("resistances", {})
	return {}


func remove_status(status_id: String) -> bool:
	return cleanse_status(status_id)


## Removes an active effect and its partial buildup independently while preserving acquired
## resistance. This is the targeted cleanse contract; lifecycle reset remains `clear_all()`.
func cleanse_status(status_id: String) -> bool:
	var removed_active := _active.erase(status_id)
	var removed_meter := _meters.erase(status_id)
	if removed_active:
		_recalc_modifiers(false)
		statuses_changed.emit()
	if removed_meter:
		build_up_changed.emit()
	return removed_active or removed_meter


func _remove_status(status_id: String) -> void:
	_active.erase(status_id)


func _recalc_modifiers(emit_change: bool = true) -> void:
	var prev_slow := _slow_multiplier
	var prev_stun := _stunned
	var prev_taken := _damage_taken_multiplier
	var prev_stats: Dictionary = _stat_totals.duplicate()
	var slow := 1.0
	var haste := 1.0
	_stunned = false
	_damage_taken_multiplier = 1.0
	_stat_totals.clear()
	for status_id in _active:
		var entry: Dictionary = _active[status_id]
		var def := StatusCatalog.get_definition(status_id)
		var stacks := float(int(entry.get("stacks", 1)))
		var elapsed := float(entry.get("elapsed", 0.0))
		slow = minf(slow, float(def.get("slowMultiplier", 1.0)))
		haste *= float(def.get("speedMultiplier", 1.0))
		var stun_dur := float(def.get("stunDuration", 0.0))
		if stun_dur > 0.0:
			if bool(def.get("stunPulse", false)):
				if fmod(elapsed, maxf(0.1, float(def.get("tickInterval", 1.0)))) < stun_dur * stacks:
					_stunned = true
			elif elapsed < stun_dur:
				_stunned = true
		_damage_taken_multiplier *= pow(float(def.get("damageTakenMultiplier", 1.0)), stacks)
		var stats: Dictionary = def.get("stats", {})
		for stat in stats:
			_stat_totals[stat] = float(_stat_totals.get(stat, 0.0)) + float(stats[stat]) * stacks
	_slow_multiplier = slow * haste
	if emit_change and (
		not is_equal_approx(prev_slow, _slow_multiplier)
		or prev_stun != _stunned
		or not is_equal_approx(prev_taken, _damage_taken_multiplier)
		or not _stat_totals_equal(prev_stats, _stat_totals)
	):
		statuses_changed.emit()


static func _stat_totals_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key):
			return false
		if not is_equal_approx(float(a[key]), float(b[key])):
			return false
	return true

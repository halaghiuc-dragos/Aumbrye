extends Node


signal rule_triggered(source_id: String, effect: String)

const ON_HIT := &"onHit"
const ON_KILL := &"onKill"
const ON_PARRY := &"onParry"
const ON_BLOCK := &"onBlock"
const ON_DODGE := &"onDodge"
const ON_CRIT := &"onCrit"
const ON_BACKSTAB := &"onBackstab"
const ON_RIPOSTE := &"onRiposte"
const ON_HIT_TAKEN := &"onHitTaken"
const ON_LOW_HEALTH := &"onLowHealth"
const ON_ROOM_CLEAR := &"onRoomClear"
const ON_FLOOR_ENTER := &"onFloorEnter"
const ON_STATUS_APPLIED := &"onStatusApplied"
const ON_RUN_START := &"onRunStart"

const ALL_EVENTS: Array[StringName] = [
	ON_HIT,
	ON_KILL,
	ON_PARRY,
	ON_BLOCK,
	ON_DODGE,
	ON_CRIT,
	ON_BACKSTAB,
	ON_RIPOSTE,
	ON_HIT_TAKEN,
	ON_LOW_HEALTH,
	ON_ROOM_CLEAR,
	ON_FLOOR_ENTER,
	ON_STATUS_APPLIED,
	ON_RUN_START,
]

const AMOUNT_EVENTS: Array[StringName] = [
	ON_HIT,
	ON_CRIT,
	ON_BACKSTAB,
	ON_RIPOSTE,
	ON_BLOCK,
	ON_HIT_TAKEN,
]

const EFFECTS: Array[String] = [
	"restore_stamina",
	"restore_health",
	"restore_mana",
	"lifesteal",
	"apply_status",
	"spread_status",
	"add_stack",
	"bonus_gold",
	"refund_flask",
	"clear_status",
]

const LOW_HEALTH_RATIO := 0.3

var _rules_by_event: Dictionary = {}
var _sources: Dictionary = {}
var _stacks: Dictionary = {}
var _cooldowns: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _rng_seeded := false
var _low_health_latched := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for event in ALL_EVENTS:
		_rules_by_event[event] = [] as Array[Dictionary]
	_rng_seeded = false


func _ensure_rng_seeded() -> void:
	if _rng_seeded:
		return
	_rng_seeded = true
	_rng.seed = FloorSeedMix.mix(RunFlow.current_seed if RunFlow else 0, hash("combat_events"))


func register(source_id: String, rules: Array) -> void:
	if source_id == "" or rules.is_empty():
		return
	unregister(source_id)
	var accepted: Array[Dictionary] = []
	for entry in rules:
		if not entry is Dictionary:
			continue
		var rule: Dictionary = (entry as Dictionary).duplicate(true)
		var event := StringName(str(rule.get("event", "")))
		if not _rules_by_event.has(event):
			push_warning(
				"CombatEvents: '%s' declares unknown event '%s' — rule dropped" % [source_id, event]
			)
			continue
		var effect := str(rule.get("effect", ""))
		if not EFFECTS.has(effect):
			push_warning(
				"CombatEvents: '%s' declares unknown effect '%s' — rule dropped"
				% [source_id, effect]
			)
			continue
		if effect == "lifesteal" and not AMOUNT_EVENTS.has(event):
			if not rule.has("amount"):
				push_warning(
					(
						"CombatEvents: '%s' pairs lifesteal with '%s', which carries no damage"
						+ " amount, and sets no flat `amount` fallback — rule dropped"
					)
					% [source_id, event]
				)
				continue
		rule["sourceId"] = source_id
		rule["event"] = event
		accepted.append(rule)
		(_rules_by_event[event] as Array).append(rule)
	if accepted.is_empty():
		return
	_sources[source_id] = accepted


func unregister(source_id: String) -> void:
	if not _sources.has(source_id):
		return
	for event in _rules_by_event:
		var bucket: Array = _rules_by_event[event]
		for i in range(bucket.size() - 1, -1, -1):
			if str((bucket[i] as Dictionary).get("sourceId", "")) == source_id:
				bucket.remove_at(i)
	_sources.erase(source_id)
	for key in _stacks.keys():
		if str(key).begins_with(source_id + "/"):
			_stacks.erase(key)
	for key in _cooldowns.keys():
		if str(key).begins_with(source_id + "/"):
			_cooldowns.erase(key)


func is_registered(source_id: String) -> bool:
	return _sources.has(source_id)


func clear_all() -> void:
	for event in _rules_by_event:
		(_rules_by_event[event] as Array).clear()
	_sources.clear()
	_stacks.clear()
	_cooldowns.clear()
	_low_health_latched = false
	_rng_seeded = false


func dispatch(event: StringName, ctx: Dictionary = {}) -> void:
	_ensure_rng_seeded()
	var bucket: Array = _rules_by_event.get(event, [])
	if bucket.is_empty():
		_reset_stacks_for(event)
		return
	for rule in bucket:
		_try_rule(rule as Dictionary, ctx)
	_reset_stacks_for(event)


func get_stat_bonus(stat: String) -> float:
	if _stacks.is_empty():
		return 0.0
	var total := 0.0
	for source_id in _sources:
		for rule in _sources[source_id] as Array[Dictionary]:
			if str(rule.get("effect", "")) != "add_stack":
				continue
			if str(rule.get("stat", "")) != stat:
				continue
			var key := _stack_key(rule)
			total += float(rule.get("perStack", 0.0)) * float(_stacks.get(key, 0))
	return total


func notify_health_ratio(ratio: float, actor: Node) -> void:
	if ratio <= LOW_HEALTH_RATIO:
		if not _low_health_latched:
			_low_health_latched = true
			dispatch(ON_LOW_HEALTH, {"actor": actor})
	elif ratio > LOW_HEALTH_RATIO + 0.05:
		_low_health_latched = false


func _try_rule(rule: Dictionary, ctx: Dictionary) -> void:
	var cooldown := float(rule.get("cooldown", 0.0))
	var key := "%s/%s/%s/%s" % [
		str(rule.get("sourceId", "")),
		str(rule.get("event", "")),
		str(rule.get("effect", "")),
		str(rule.get("stackId", "")),
	]
	if cooldown > 0.0:
		var now := Time.get_ticks_msec() / 1000.0
		if now < float(_cooldowns.get(key, 0.0)):
			return
		_cooldowns[key] = now + cooldown
	var chance := float(rule.get("chance", 1.0))
	if chance < 1.0 and _rng.randf() > chance:
		return
	if not _passes_conditions(rule, ctx):
		return
	_apply_effect(rule, ctx)
	rule_triggered.emit(str(rule.get("sourceId", "")), str(rule.get("effect", "")))


func _passes_conditions(rule: Dictionary, ctx: Dictionary) -> bool:
	var required_status := str(rule.get("ifTargetHasStatus", ""))
	if required_status != "":
		var target := ctx.get("target") as Node
		if target == null or not is_instance_valid(target):
			return false
		var controller := target.get_node_or_null("StatusController") as StatusController
		if controller == null:
			return false
		var found := false
		for entry in controller.get_active_statuses():
			if str(entry.get("id", "")) == required_status:
				found = true
				break
		if not found:
			return false
	var required_type := str(rule.get("ifDamageType", ""))
	if required_type != "" and str(ctx.get("damageType", "")) != required_type:
		return false
	return true


func _apply_effect(rule: Dictionary, ctx: Dictionary) -> void:
	var effect := str(rule.get("effect", ""))
	var amount := float(rule.get("amount", 0.0))
	match effect:
		"restore_stamina":
			var stamina := _node_child(ctx.get("actor"), "Stamina") as Stamina
			if stamina:
				stamina.restore(amount)
		"restore_health":
			var health := _node_child(ctx.get("actor"), "Health") as Health
			if health:
				health.heal(amount)
		"restore_mana":
			var mana := _node_child(ctx.get("actor"), "Mana")
			if mana and mana.has_method("restore"):
				mana.call("restore", amount)
		"lifesteal":
			var self_health := _node_child(ctx.get("actor"), "Health") as Health
			if self_health:
				var base := float(ctx.get("amount", 0.0))
				if base <= 0.0:
					base = float(rule.get("amount", 0.0))
				var pct := float(rule.get("pct", 0.0))
				self_health.heal(base * (pct if pct > 0.0 else 1.0))
		"apply_status":
			_apply_status_to(ctx.get("target"), rule)
		"spread_status":
			_spread_status(ctx, rule)
		"add_stack":
			var stack_key := _stack_key(rule)
			var maximum := int(rule.get("maxStacks", 1))
			_stacks[stack_key] = mini(maximum, int(_stacks.get(stack_key, 0)) + 1)
		"bonus_gold":
			if CharacterService:
				CharacterService.add_gold(int(amount))
		"refund_flask":
			var heal_node := _node_child(ctx.get("actor"), "PlayerHeal") as PlayerHeal
			if heal_node:
				heal_node.grant_charge(int(maxf(1.0, amount)))
		"clear_status":
			var controller := _node_child(ctx.get("actor"), "StatusController") as StatusController
			if controller:
				controller.clear_all()


func _apply_status_to(target: Variant, rule: Dictionary) -> void:
	var node := target as Node
	if node == null or not is_instance_valid(node):
		return
	var controller := node.get_node_or_null("StatusController") as StatusController
	if controller == null:
		return
	controller.apply_status(str(rule.get("statusId", "")), int(rule.get("stacks", 1)))


func _spread_status(ctx: Dictionary, rule: Dictionary) -> void:
	var origin_node := ctx.get("target") as Node3D
	if origin_node == null or not is_instance_valid(origin_node):
		return
	var radius := float(rule.get("radius", 4.0))
	var radius_sq := radius * radius
	var origin := origin_node.global_position
	for node in CombatGroups.hostiles(get_tree()):
		var enemy := node as Node3D
		if enemy == null or enemy == origin_node or not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_squared_to(origin) > radius_sq:
			continue
		_apply_status_to(enemy, rule)


func _reset_stacks_for(event: StringName) -> void:
	if _stacks.is_empty():
		return
	for source_id in _sources:
		for rule in _sources[source_id] as Array[Dictionary]:
			if str(rule.get("effect", "")) != "add_stack":
				continue
			var reset_on: Array = rule.get("resetOn", [])
			for entry in reset_on:
				if StringName(str(entry)) == event:
					_stacks.erase(_stack_key(rule))
					break


func _stack_key(rule: Dictionary) -> String:
	return "%s/%s" % [str(rule.get("sourceId", "")), str(rule.get("stackId", "default"))]


func _node_child(source_owner: Variant, child_name: String) -> Node:
	var node := source_owner as Node
	if node == null or not is_instance_valid(node):
		return null
	return node.get_node_or_null(child_name)

extends Node3D
class_name DamageNumberSpawner

const SCENE := preload("res://scenes/combat/damage_number.tscn")

const LIFETIME := 0.65
const RISE_SPEED := 1.2
const BASE_FONT_SIZE := 48
## A crit reading the same size as any other hit is a stat the player has to check a log for. This
## is the one place its whole point -- "that landed harder" -- can be read at a glance instead.
const CRIT_FONT_SIZE := 72
const CRIT_OUTLINE_SIZE := 10
const MAX_VISIBLE := 24
const STACK_SPREAD := 0.24
const AGGREGATE_WINDOW_MS := 180

static var _spawn_counts: Dictionary = {}
static var _aggregate_numbers: Dictionary = {}
static var _pool: Array[DamageNumberSpawner] = []

@onready var _label: Label3D = $Label3D

var _amount := 0.0
var _float_tween: Tween


func _ready() -> void:
	add_to_group("damage_number")


static func spawn(
	world_position: Vector3,
	amount: float,
	parent: Node,
	damage_type: String = "physical",
	is_crit: bool = false
) -> void:
	if AccessibilitySettings.restrained_damage_numbers and not is_crit:
		var restrained_key := _aggregate_key(parent, world_position, damage_type)
		var restrained_existing := _aggregate_numbers.get(restrained_key) as DamageNumberSpawner
		if restrained_existing and is_instance_valid(restrained_existing):
			restrained_existing.add_amount(amount)
			return
	_trim_visible(parent)
	if _aggregate_numbers.size() > 256:
		_aggregate_numbers.clear()
	var aggregate_key := _aggregate_key(parent, world_position, damage_type)
	var existing := _aggregate_numbers.get(aggregate_key) as DamageNumberSpawner
	if not is_crit and existing and is_instance_valid(existing):
		if Time.get_ticks_msec() <= int(existing.get_meta("aggregate_until", 0)):
			existing.add_amount(amount)
			return
	var node := _acquire(parent)
	node.global_position = world_position + _next_offset(parent, world_position)
	if node.has_method("show_amount"):
		node.call("show_amount", amount, damage_type, is_crit)
	if not is_crit:
		_aggregate_numbers[aggregate_key] = node


static func spawn_text(
	world_position: Vector3, text: String, parent: Node, color: Color = Color.WHITE
) -> void:
	_trim_visible(parent)
	var node := _acquire(parent)
	node.global_position = world_position + Vector3(0.0, 2.0, 0.0)
	if node.has_method("show_text"):
		node.call("show_text", text, color)


static func _acquire(parent: Node) -> DamageNumberSpawner:
	while not _pool.is_empty():
		var node: DamageNumberSpawner = _pool.pop_back()
		if is_instance_valid(node):
			parent.add_child(node)
			node.show()
			return node
	var created := SCENE.instantiate() as DamageNumberSpawner
	parent.add_child(created)
	return created


static func recycle(node: DamageNumberSpawner) -> void:
	if node == null or not is_instance_valid(node):
		return
	for key in _aggregate_numbers:
		if _aggregate_numbers[key] == node:
			_aggregate_numbers.erase(key)
	if _pool.size() >= MAX_VISIBLE:
		node.queue_free()
		return
	if node.get_parent():
		node.get_parent().remove_child(node)
	node.hide()
	_pool.append(node)


static func _trim_visible(parent: Node) -> void:
	var visible_numbers := parent.get_tree().get_nodes_in_group("damage_number")
	while visible_numbers.size() >= MAX_VISIBLE:
		var oldest := visible_numbers.pop_front() as Node
		if oldest != null and is_instance_valid(oldest):
			oldest.queue_free()


static func _next_offset(parent: Node, world_position: Vector3) -> Vector3:
	if _spawn_counts.size() > 256:
		_spawn_counts.clear()
	var key := "%d:%d:%d:%d" % [
		parent.get_instance_id(),
		roundi(world_position.x * 4.0),
		roundi(world_position.y * 4.0),
		roundi(world_position.z * 4.0)
	]
	var count := int(_spawn_counts.get(key, 0))
	_spawn_counts[key] = (count + 1) % 4
	var column := float(count % 2) - 0.5
	var row := float(count) / 2.0
	return Vector3(column * STACK_SPREAD, row * STACK_SPREAD, 0.0)


static func _aggregate_key(parent: Node, world_position: Vector3, damage_type: String) -> String:
	return "%d:%d:%d:%d:%s" % [
		parent.get_instance_id(),
		roundi(world_position.x * 2.0),
		roundi(world_position.y * 2.0),
		roundi(world_position.z * 2.0),
		damage_type,
	]


func show_amount(amount: float, damage_type: String = "physical", is_crit: bool = false) -> void:
	_reset_visual()
	_amount = amount
	set_meta("aggregate_until", Time.get_ticks_msec() + AGGREGATE_WINDOW_MS)
	if _label:
		_update_amount_label()
		_label.modulate = AccessibilitySettings.get_damage_color(damage_type)
		_label.font_size = CRIT_FONT_SIZE if is_crit else BASE_FONT_SIZE
		_label.outline_size = CRIT_OUTLINE_SIZE if is_crit else 8
	_animate_float(is_crit)


func add_amount(amount: float) -> void:
	_amount += amount
	set_meta("aggregate_until", Time.get_ticks_msec() + AGGREGATE_WINDOW_MS)
	if _label:
		_update_amount_label()


func _update_amount_label() -> void:
	var displayed := int(round(_amount))
	if _amount > 0.0:
		displayed = maxi(1, displayed)
	_label.text = str(displayed)


func show_text(text: String, color: Color) -> void:
	_reset_visual()
	if _label:
		_label.text = text
		_label.modulate = color
	_animate_float()


func _animate_float(is_crit: bool = false) -> void:
	if _float_tween and _float_tween.is_valid():
		_float_tween.kill()
	var tween := create_tween()
	_float_tween = tween
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y + RISE_SPEED * LIFETIME, LIFETIME)
	tween.tween_property(_label, "modulate:a", 0.0, LIFETIME)
	tween.chain().tween_callback(_finish)
	if is_crit:
		# A quick overshoot-and-settle so a crit visibly *lands* instead of just appearing at its
		# final (larger) size -- the same punch language the hitstop/camera-punch system already
		# uses for a critical impact, just on the number instead of the camera. Its own tween, since
		# it needs to finish in a couple of frames while the float/fade above runs the full lifetime.
		_label.scale = Vector3(0.55, 0.55, 0.55)
		var punch := create_tween()
		punch.tween_property(_label, "scale", Vector3(1.15, 1.15, 1.15), 0.09).set_trans(
			Tween.TRANS_BACK
		).set_ease(Tween.EASE_OUT)
		punch.tween_property(_label, "scale", Vector3.ONE, 0.1).set_trans(Tween.TRANS_SINE)


func _reset_visual() -> void:
	if _float_tween and _float_tween.is_valid():
		_float_tween.kill()
	position = Vector3.ZERO
	scale = Vector3.ONE
	_amount = 0.0
	if _label:
		_label.modulate.a = 1.0
		_label.scale = Vector3.ONE
		_label.font_size = BASE_FONT_SIZE
		_label.outline_size = 8


func _finish() -> void:
	DamageNumberSpawner.recycle(self)

extends Area3D

## Recoverable XP left at a death spot — grants stored XP on interact.

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

var _xp_amount := 0
var _visual: Node3D
var _player: Node3D
var _label: Label3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.2
	shape.shape = sphere
	add_child(shape)
	_visual = DioramaSkin.build_loot_pickup(self, DioramaSkin.resolve_biome(self))
	_label = Label3D.new()
	_label.name = "Label3D"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 32
	_label.modulate = Color(0.7, 0.9, 1.0, 1.0)
	_label.visible = false
	add_child(_label)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func configure(world_pos: Vector3, xp_amount: int) -> void:
	global_position = world_pos
	_xp_amount = maxi(0, xp_amount)
	_label.text = "Echo shard (+%d XP)" % _xp_amount


func _process(_delta: float) -> void:
	if _visual:
		_visual.position.y = float(_visual.get_meta("bob_base_y", 0.0)) + sin(Time.get_ticks_msec() * 0.004) * 0.1
	if _player == null:
		return
	if Input.is_action_just_pressed("interact"):
		_collect()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body
		_label.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null
		_label.visible = false


func _collect() -> void:
	if _xp_amount <= 0:
		queue_free()
		return
	ProgressionService.grant_xp(_xp_amount, "xp_shard")
	RunFlow.clear_recoverable_xp_shard()
	queue_free()

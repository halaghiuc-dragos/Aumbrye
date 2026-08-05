extends Node3D

## Waves lobby chest — opens into WavesRunService inventory only.

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

var _index := 0
var _visual: Node3D
var _opened := false
var _player: Node3D
var _label: Label3D


func configure(index: int) -> void:
	_index = index
	_visual = DioramaSkin.build_waves_chest(self, index)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = true
	var shape := CollisionShape3D.new()
	var col := BoxShape3D.new()
	col.size = Vector3(2, 2, 2)
	shape.shape = col
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 1.5, 0)
	_label.visible = false
	add_child(_label)


func apply_opened_state(open: bool) -> void:
	_opened = open


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not _opened:
		_player = body
		_label.visible = true
		_label.text = "Press E — %s" % WavesRunService.get_chest_label(_index)


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null
		_label.visible = false


func _process(_delta: float) -> void:
	if _opened or _player == null:
		return
	if Input.is_action_just_pressed("interact"):
		var run := get_tree().get_first_node_in_group("waves_run")
		if run and run.has_method("open_waves_chest"):
			run.call("open_waves_chest", _index)
			_opened = WavesRunService.chests_opened.get(str(_index), false)
			if _opened:
				_label.visible = false

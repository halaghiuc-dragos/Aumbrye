extends Node3D

## Crystal cannon for final boss puzzle — load collected crystals, then fire to break shield.

signal fired

@export var boss_path: NodePath

var _boss: Node
var _loaded := 0
var _required := 3
var _fired := false
var _near_player := false
var _label: Label3D
var _interact_area: Area3D


func _ready() -> void:
	_boss = get_node_or_null(boss_path)
	if get_node_or_null("InteractArea") == null:
		_build_interact_area()
	_interact_area = get_node_or_null("InteractArea") as Area3D
	_label = get_node_or_null("Label3D") as Label3D
	if _label == null:
		_label = Label3D.new()
		_label.name = "Label3D"
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 24
		_label.position = Vector3(0.0, 2.5, 0.0)
		add_child(_label)
	if _interact_area:
		_interact_area.body_entered.connect(_on_body_entered)
		_interact_area.body_exited.connect(_on_body_exited)
	_update_label()


func _build_interact_area() -> void:
	var interact := Area3D.new()
	interact.name = "InteractArea"
	interact.collision_layer = 0
	interact.collision_mask = 2
	interact.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 3.0)
	shape.shape = box
	interact.add_child(shape)
	add_child(interact)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.5, 1.0, 2.0)
	mesh.mesh = box_mesh
	add_child(mesh)


func configure(boss: Node, required: int = 3) -> void:
	_boss = boss
	_required = maxi(1, required)
	_update_label()


func deposit_crystal() -> void:
	if _fired:
		return
	_loaded = mini(_loaded + 1, _required)
	_update_label()


func get_loaded_count() -> int:
	return _loaded


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _near_player or _fired:
		return
	if _loaded < _required:
		return
	_fire()
	get_viewport().set_input_as_handled()


func _fire() -> void:
	if _fired:
		return
	_fired = true
	if _boss and _boss.has_method("register_cannon_hit"):
		_boss.call("register_cannon_hit")
	if _boss and _boss.has_method("on_cannon_fired"):
		_boss.call("on_cannon_fired")
	fired.emit()
	_update_label()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = true
		_update_label()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false
		_update_label()


func _update_label() -> void:
	if _label == null:
		return
	if not _near_player:
		_label.visible = false
		return
	_label.visible = true
	if _fired:
		_label.text = "Cannon fired!"
	elif _loaded < _required:
		_label.text = "Load crystals (%d/%d)" % [_loaded, _required]
	else:
		_label.text = "%s Fire cannon!" % InputGlyphService.format_interact_label()

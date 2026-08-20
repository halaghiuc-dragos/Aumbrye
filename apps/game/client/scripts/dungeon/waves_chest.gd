extends Node3D

## Waves lobby chest — opens into WavesRunService inventory only.

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")

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


## C-228: this only set the flag. `configure()` had already built the closed visual, so after
## continuing a Waves run every looted chest still looked shut — and walking up gave no prompt,
## because both `_on_body_entered` and `_process` bail on `_opened`. The lobby lied about its state.
##
## Opened chests are flattened and dimmed in place rather than hidden, so the player can still see
## where they were and that they are spent.
func apply_opened_state(open: bool) -> void:
	_opened = open
	if _label:
		_label.visible = false
	if _visual == null or not is_instance_valid(_visual):
		return
	_visual.scale = Vector3(1.0, 0.4, 1.0) if open else Vector3.ONE
	for child in _visual.get_children():
		if child is GeometryInstance3D:
			var mesh_child := child as GeometryInstance3D
			mesh_child.transparency = 0.45 if open else 0.0


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not _opened:
		_player = body
		_label.visible = true
		_label.text = "%s — %s" % [
			InputGlyphServiceScript.get_action_prompt(&"interact"),
			WavesRunService.get_chest_label(_index),
		]


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null
		_label.visible = false


## C-226: this polled the `Input` singleton from `_process`, so a press already consumed by the
## inventory panel, the pause menu or a dialogue box still opened the chest. `_unhandled_input`
## only ever sees what no focused Control claimed, and marking the event handled stops it
## travelling further. Same pattern as `room_merchant_content` and `room_lore_content`.
func _unhandled_input(event: InputEvent) -> void:
	if _opened or _player == null:
		return
	if not PlayerInput.interact_just_pressed(event):
		return
	get_viewport().set_input_as_handled()
	var run := get_tree().get_first_node_in_group("waves_run")
	if run and run.has_method("open_waves_chest"):
		run.call("open_waves_chest", _index)
		_opened = WavesRunService.chests_opened.get(str(_index), false)
		if _opened:
			apply_opened_state(true)

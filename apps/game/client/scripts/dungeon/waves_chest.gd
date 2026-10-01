extends Node3D


const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")
const INTERACT_RANGE := 2.4

var _index := 0
var _visual: Node3D
var _opened := false
var _label: Label3D


func configure(index: int) -> void:
	_index = index
	_visual = DioramaSkin.build_waves_chest(self, index)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.outline_size = 11
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_label.position = Vector3(0, 1.5, 0)
	_label.visible = false
	add_child(_label)
	DungeonInteractionService.register_candidate(
		self,
		_visual,
		INTERACT_RANGE,
		2,
		Callable(self, "_interact"),
		Callable(self, "_can_open"),
		Callable(self, "_set_selected_prompt")
	)


func apply_opened_state(open: bool) -> void:
	_opened = open
	if _label:
		_label.visible = false
	if _visual == null or not is_instance_valid(_visual):
		return
	var lid := DioramaSkin.find_chest_lid(_visual)
	if lid:
		if open and not is_zero_approx(lid.rotation.x - DioramaSkin.LID_OPEN_ANGLE):
			var tween := create_tween()
			tween.set_trans(Tween.TRANS_BACK)
			tween.set_ease(Tween.EASE_OUT)
			tween.tween_property(lid, "rotation:x", DioramaSkin.LID_OPEN_ANGLE, 0.42)
		elif not open:
			lid.rotation.x = 0.0
	for child in _visual.get_children():
		if child is GeometryInstance3D:
			var mesh_child := child as GeometryInstance3D
			mesh_child.transparency = 0.35 if open else 0.0


func _can_open() -> bool:
	return not _opened


func _set_selected_prompt(active: bool) -> void:
	if _label == null:
		return
	_label.visible = active and not _opened
	if _label.visible:
		_label.text = "%s — %s" % [
			InputGlyphServiceScript.get_action_prompt(&"interact"),
			WavesRunService.get_chest_label(_index),
		]


func _interact() -> void:
	if _opened:
		return
	var run := get_tree().get_first_node_in_group("waves_run")
	if run and run.has_method("open_waves_chest"):
		run.call("open_waves_chest", _index)
		_opened = WavesRunService.chests_opened.get(str(_index), false)
		if _opened:
			apply_opened_state(true)

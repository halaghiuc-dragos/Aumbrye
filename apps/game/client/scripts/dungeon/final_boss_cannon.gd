extends Node3D


const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const INTERACT_RANGE := 2.6

signal fired

@export var boss_path: NodePath

var _boss: Node
var _loaded := 0
var _required := 3
var _fired := false
var _selected := false
var _label: Label3D


func _ready() -> void:
	_boss = get_node_or_null(boss_path)
	DioramaSkin.build_cannon(self, BiomeRegistry.BIOME_CASTLE)
	_label = get_node_or_null("Label3D") as Label3D
	if _label == null:
		_label = Label3D.new()
		_label.name = "Label3D"
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 24
		_label.outline_size = 11
		_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		_label.position = Vector3(0.0, 2.5, 0.0)
		add_child(_label)
	DungeonInteractionService.register_candidate(
		self,
		self,
		INTERACT_RANGE,
		3,
		Callable(self, "_interact"),
		Callable(),
		Callable(self, "_set_selected_prompt")
	)
	_update_label()


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


func _interact() -> void:
	if _fired or _loaded < _required:
		return
	_fire()


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


func _set_selected_prompt(active: bool) -> void:
	_selected = active
	_update_label()


func _update_label() -> void:
	if _label == null:
		return
	if not _selected:
		_label.visible = false
		return
	_label.visible = true
	if _fired:
		_label.text = tr("BOSS_CANNON_FIRED")
	elif _loaded < _required:
		_label.text = tr("BOSS_CANNON_LOAD").format({"loaded": _loaded, "required": _required})
	else:
		_label.text = InputGlyphService.format_interact_name(tr("BOSS_CANNON_FIRE"))

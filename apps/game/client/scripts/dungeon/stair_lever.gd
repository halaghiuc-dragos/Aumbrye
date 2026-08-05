extends Node3D

## FLOOR-7.2 — stair lever interactable for ascending/descending floors.

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

signal lever_used(direction: String)

var _interact_area: Area3D
var _label: Label3D
var _near_player := false
var _unlocked := false
var _can_ascend := true
var _can_descend := false
var _can_retreat := false


func _ready() -> void:
	if get_node_or_null(DioramaSkin.VISUAL_NAME) == null:
		DioramaSkin.build_lever(self, DioramaSkin.resolve_biome(self))
	_interact_area = get_node_or_null("InteractArea") as Area3D
	_label = get_node_or_null("Label3D") as Label3D
	if _interact_area:
		_interact_area.body_entered.connect(_on_body_entered)
		_interact_area.body_exited.connect(_on_body_exited)
	_update_label()


func configure(can_ascend: bool, can_descend: bool, can_retreat: bool = false) -> void:
	_can_ascend = can_ascend
	_can_descend = can_descend
	_can_retreat = can_retreat
	_update_label()


func unlock() -> void:
	_unlocked = true
	_update_label()


func is_unlocked() -> bool:
	return _unlocked


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _near_player or not _unlocked:
		return
	var menu := get_tree().get_first_node_in_group("stair_menu")
	if menu and menu.has_method("open_for_lever"):
		menu.call("open_for_lever", self)
		get_viewport().set_input_as_handled()
		return
	if _can_retreat and Input.is_key_pressed(KEY_CTRL) and RunFlow.can_retreat_to_hub():
		RunFlow.retreat_to_hub()
		get_viewport().set_input_as_handled()
		return
	if _can_ascend and Input.is_key_pressed(KEY_SHIFT):
		_use_lever("descend")
		get_viewport().set_input_as_handled()
		return
	if _can_ascend:
		_use_lever("ascend")
		get_viewport().set_input_as_handled()
	elif _can_descend:
		_use_lever("descend")
		get_viewport().set_input_as_handled()


func _use_lever(direction: String) -> void:
	lever_used.emit(direction)
	if direction == "ascend":
		RunFlow.ascend_floor()
	elif direction == "descend":
		RunFlow.descend_floor()


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
	if not _unlocked or not _near_player:
		_label.visible = false
		return
	var parts: PackedStringArray = []
	if _can_ascend or _can_descend or _can_retreat:
		parts.append("%s Floor options" % InputGlyphService.format_interact_label())
	_label.text = "\n".join(parts)
	_label.visible = not parts.is_empty()

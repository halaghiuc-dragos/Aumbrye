extends Node3D

## Static loot chest with fixed contents (LOOT-2.1).

signal opened

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")

var _mesh: Node3D
@onready var _interact_area: Area3D = $InteractArea
@onready var _label: Label3D = $Label3D

var _items: Array = []
var _opened := false
var _player: Node3D


func _ready() -> void:
	_mesh = DioramaSkin.build_chest(self, DioramaSkin.resolve_biome(self))
	if _opened:
		apply_opened_state(true)
	_interact_area.body_entered.connect(_on_body_entered)
	_interact_area.body_exited.connect(_on_body_exited)
	_label.visible = false
	set_process_unhandled_input(false)


func configure(placement: Dictionary) -> void:
	_items = placement.get("items", []).duplicate(true)


func is_opened() -> bool:
	return _opened


func apply_opened_state(was_opened: bool) -> void:
	_opened = was_opened
	if _opened and _mesh:
		_mesh.scale = Vector3(0.8, 0.5, 0.8)
	_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _opened or _player == null:
		return
	if PlayerInput.interact_just_pressed(event):
		_open()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body
		if not _opened:
			_label.visible = true
			_label.text = InputGlyphServiceScript.get_action_prompt(&"interact")
			set_process_unhandled_input(true)


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null
		_label.visible = false
		set_process_unhandled_input(false)


## C-160: `_opened` was claimed *before* the grant loop and the chest is never re-openable — both
## `apply_opened_state` and the `_unhandled_input` guard key off it, and the state persists into the
## run snapshot. A failed `add_loot()`, which is exactly what a full grid produces, silently dropped
## the item: the reward was destroyed and the chest was spent.
##
## Items that cannot be granted stay in the chest, and the chest stays shut. The player is told why,
## through the same `inventory_rejected` channel the HUD already listens on (C-221's
## "Inventory full" banner), so a refused chest reads as a refusal rather than as nothing happening.
func _open() -> void:
	if _opened:
		return
	var remaining: Array = []
	var granted_any := false
	for entry in _items:
		var item_id: String = entry.get("itemId", "")
		var qty: int = entry.get("quantity", 1)
		if item_id == "":
			continue
		var opts := {"quantity": qty, "roll": bool(entry.get("roll", false))}
		if entry.has("rollSeed"):
			opts["rollSeed"] = int(entry.get("rollSeed", -1))
		if InventoryService.add_loot(item_id, opts):
			granted_any = true
			RunFlow.register_loot(item_id, str(entry.get("instanceId", "")))
		else:
			remaining.append(entry)
	_items = remaining
	if not remaining.is_empty():
		# Partially emptied chests stay open-able for the rest they still hold.
		if InventoryService and InventoryService.has_signal("inventory_rejected"):
			InventoryService.inventory_rejected.emit("full")
		return
	_opened = true
	_label.visible = false
	opened.emit()
	if _mesh:
		var tween := create_tween()
		tween.tween_property(_mesh, "scale", Vector3(0.8, 0.5, 0.8), 0.2)

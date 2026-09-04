extends Node3D


signal opened

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const ToastScene: PackedScene = preload("res://scenes/ui/achievement_toast.tscn")

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
	if _opened:
		var lid := DioramaSkin.find_chest_lid(_mesh)
		if lid:
			lid.rotation.x = DioramaSkin.LID_OPEN_ANGLE
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


func _present_rarity_juice(item_id: String) -> void:
	var def := ItemCatalog.get_definition(item_id)
	var rarity := RarityRegistryScript.normalize(str(def.get("rarity", "common")))
	if AudioDirector:
		var sfx := RarityRegistryScript.drop_sfx_id(rarity)
		if AudioDirector.has_sfx(sfx):
			AudioDirector.play_sfx(sfx, global_position)
		else:
			AudioDirector.play_sfx("ui_interact_near", global_position)
	if RarityRegistryScript.wants_drop_toast(rarity):
		var toast := ToastScene.instantiate()
		if toast.has_method("show_loot"):
			get_tree().root.add_child(toast)
			toast.show_loot(str(def.get("name", item_id)), RarityRegistryScript.display_color(rarity))
	if RarityRegistryScript.wants_camera_nudge(rarity) and VfxService:
		VfxService.request_shake(0.12, 320)
		# AU-03: the same top-tier gate that earns a camera nudge earns the "you should look at
		# this" stinger -- a legendary should be impossible to miss even with your eyes elsewhere.
		AudioDirector.play_stinger("rare_drop")


func _open() -> void:
	if _opened:
		return
	var remaining: Array = []
	for entry in _items:
		var item_id: String = entry.get("itemId", "")
		var qty: int = entry.get("quantity", 1)
		if item_id == "":
			continue
		var opts := {"quantity": qty, "roll": bool(entry.get("roll", false))}
		if entry.has("rollSeed"):
			opts["rollSeed"] = int(entry.get("rollSeed", -1))
		if InventoryService.add_loot(item_id, opts):
			RunFlow.register_loot(item_id, str(entry.get("instanceId", "")))
			_present_rarity_juice(item_id)
		else:
			remaining.append(entry)
	_items = remaining
	if not remaining.is_empty():
		if InventoryService and InventoryService.has_signal("inventory_rejected"):
			InventoryService.inventory_rejected.emit("full")
		return
	_opened = true
	_label.visible = false
	opened.emit()
	var lid := DioramaSkin.find_chest_lid(_mesh)
	if lid:
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(lid, "rotation:x", DioramaSkin.LID_OPEN_ANGLE, 0.42)

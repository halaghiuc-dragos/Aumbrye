extends "res://scripts/dungeon/room_content/room_content_base.gd"

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const MERCHANT_SCENE := preload("res://scenes/ui/merchant_ui.tscn")

var _near_player := false
var _merchant_ui: Control


func configure(_entry: Dictionary, _definition: Dictionary) -> void:
	var stall := Node3D.new()
	stall.name = "MerchantStall"
	var interact := Area3D.new()
	interact.name = "InteractArea"
	interact.collision_layer = 0
	interact.collision_mask = 2
	interact.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.5, 3.0)
	shape.shape = box
	interact.add_child(shape)
	stall.add_child(interact)
	interact.body_entered.connect(_on_body_entered)
	interact.body_exited.connect(_on_body_exited)
	stall.position = Vector3(-1.5, 0.0, 0.0)
	DioramaSkin.build_portal(stall, DioramaSkin.resolve_biome(self))
	_content_root().add_child(stall)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _near_player:
		return
	_open_merchant()
	get_viewport().set_input_as_handled()


func _open_merchant() -> void:
	if _merchant_ui == null:
		_merchant_ui = MERCHANT_SCENE.instantiate() as Control
		get_tree().root.add_child(_merchant_ui)
	if _merchant_ui.has_method("open_for_merchant"):
		_merchant_ui.call("open_for_merchant", "dungeon_merchant")

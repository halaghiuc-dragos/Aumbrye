extends "res://scripts/dungeon/room_content/room_content_base.gd"

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const MERCHANT_SCENE := preload("res://scenes/ui/merchant_ui.tscn")
const InteractPromptScript := preload("res://scripts/ui/interact_prompt.gd")

var _near_player := false
var _merchant_ui: Control
var _prompt: InteractPrompt


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
	stall.position = _anchor(0).position
	DioramaSkin.build_merchant_stall(stall, DioramaSkin.resolve_biome(self))
	_content_root().add_child(stall)
	_prompt = InteractPromptScript.build(stall, Vector3(0.0, 2.6, 0.0))


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = true
		if _prompt:
			_prompt.show_action("Trade")


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false
		if _prompt:
			_prompt.hide_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if not PlayerInput.interact_just_pressed(event) or not _near_player:
		return
	_open_merchant()
	get_viewport().set_input_as_handled()


const MERCHANT_UI_GROUP := &"dungeon_merchant_ui"


func _open_merchant() -> void:
	var existing := get_tree().get_first_node_in_group(MERCHANT_UI_GROUP) as Control
	if existing == null or not is_instance_valid(existing):
		existing = MERCHANT_SCENE.instantiate() as Control
		existing.add_to_group(MERCHANT_UI_GROUP)
		var host: Node = get_tree().current_scene
		if host == null:
			host = get_tree().root
		host.add_child(existing)
	_merchant_ui = existing
	if _merchant_ui.has_method("open_for_merchant"):
		_merchant_ui.call("open_for_merchant", "dungeon_merchant")

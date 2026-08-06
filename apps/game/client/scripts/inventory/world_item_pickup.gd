extends Area3D

## World item pickup — adds to grid inventory on interact (INV-2.1).

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

@export var item_id := "iron_scrap"
@export var quantity := 1

var _visual: Node3D
var _label: Label3D
var _player: Node3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.2
	shape.shape = sphere
	add_child(shape)
	_visual = DioramaSkin.build_loot_pickup(self, DioramaSkin.resolve_biome(self))
	_label = Label3D.new()
	_label.name = "Label3D"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 32
	_label.modulate = Color(0.7, 0.9, 1.0, 1.0)
	_label.visible = false
	add_child(_label)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func configure(id: String, qty: int = 1) -> void:
	item_id = id
	quantity = maxi(1, qty)
	var def := ItemCatalog.get_definition(item_id)
	_label.text = def.get("name", item_id)


func _process(_delta: float) -> void:
	if _visual:
		_visual.position.y = (
			float(_visual.get_meta("bob_base_y", 0.0)) + sin(Time.get_ticks_msec() * 0.003) * 0.08
		)
	if _player == null:
		return
	if Input.is_action_just_pressed("interact"):
		_pickup()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body
		_label.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null
		_label.visible = false


func _pickup() -> void:
	if InventoryService.add_loot(item_id, {"quantity": quantity}):
		if RunFlow:
			RunFlow.register_loot(item_id)
		queue_free()

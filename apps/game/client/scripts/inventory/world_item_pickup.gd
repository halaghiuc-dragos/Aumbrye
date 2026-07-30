extends Area3D

## World item pickup — adds to grid inventory on interact (INV-2.1).

@export var item_id := "iron_scrap"
@export var quantity := 1

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _label: Label3D = $Label3D

var _player: Node3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_label.visible = false


func configure(id: String, qty: int = 1) -> void:
	item_id = id
	quantity = qty


func _process(_delta: float) -> void:
	if _player == null:
		return
	if Input.is_action_just_pressed("interact"):
		_pickup()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body
		_label.visible = true
		_label.text = "Press E"


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null
		_label.visible = false


func _pickup() -> void:
	if InventoryService.add_item(item_id, quantity):
		RunFlow.register_loot(item_id)
		queue_free()

extends Area3D

## Swamp environmental poison hazard (THEME-5.3 / DMG-5.2).

const DioramaSkin := preload("res://scripts/art/diorama_interactable_skin.gd")

@export var poison_status := "poison"
@export var tick_interval := 1.5

var _timer := 0.0


func _ready() -> void:
	var old_mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if old_mesh:
		old_mesh.visible = false
	DioramaSkin.build_poison_pool(self, DioramaSkin.resolve_biome(self))
	monitoring = true
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = tick_interval
	for body in get_overlapping_bodies():
		_apply_poison(body)


func _on_body_entered(body: Node3D) -> void:
	_apply_poison(body)


func _apply_poison(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var status_ctrl := body.get_node_or_null("StatusController") as StatusController
	if status_ctrl:
		status_ctrl.apply_status(poison_status, 1, 4.0)

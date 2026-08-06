extends Area3D

## Swamp environmental poison hazard (THEME-5.3 / DMG-5.2).

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

@export var poison_status := "poison"
@export var tick_interval := 1.5
@export var status_stacks := 1
@export var status_duration := 4.0

var _timer := 0.0


func _ready() -> void:
	var old_mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if old_mesh:
		old_mesh.visible = false
	DioramaSkin.build_poison_pool(self, DioramaSkin.resolve_biome(self))
	monitoring = true
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = tick_interval
	for area in get_overlapping_areas():
		_apply_poison(area)
	for body in get_overlapping_bodies():
		_apply_poison_to_body(body)


func _on_body_entered(body: Node3D) -> void:
	_apply_poison_to_body(body)


func _on_area_entered(area: Area3D) -> void:
	_apply_poison(area)


func _apply_poison_to_body(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var hurtbox := body.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox:
		hurtbox.try_apply_status(poison_status, status_stacks, status_duration)


func _apply_poison(area: Area3D) -> void:
	if not area.has_method("try_apply_status"):
		return
	if area.get("team") != "player":
		return
	area.call("try_apply_status", poison_status, status_stacks, status_duration)

extends Area3D


const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

signal collected

var _taken := false
var _visual: Node3D
var _animation_time := 0.0


func _ready() -> void:
	var old_mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if old_mesh:
		old_mesh.visible = false
	_visual = DioramaSkin.build_crystal_pillar(self, BiomeRegistry.BIOME_CRYSTAL)
	_visual.scale = Vector3(0.55, 0.55, 0.55)
	body_entered.connect(_on_body_entered)
	monitoring = true


func _process(delta: float) -> void:
	if _visual and not _taken:
		_animation_time += delta
		_visual.rotation.y += delta * 1.2
		_visual.position.y = sin(_animation_time * 4.0) * 0.12


func _on_body_entered(body: Node3D) -> void:
	if _taken:
		return
	if body.is_in_group("player"):
		_taken = true
		collected.emit()
		queue_free()

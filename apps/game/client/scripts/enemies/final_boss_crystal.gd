extends Area3D

## Collectible crystal for final boss puzzle phase.

const DioramaSkin := preload("res://scripts/art/diorama_interactable_skin.gd")

signal collected

var _taken := false
var _visual: Node3D


func _ready() -> void:
	var old_mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if old_mesh:
		old_mesh.visible = false
	_visual = DioramaSkin.build_crystal_pillar(self, BiomeRegistry.BIOME_CRYSTAL)
	_visual.scale = Vector3(0.55, 0.55, 0.55)
	body_entered.connect(_on_body_entered)
	monitoring = true


func _process(_delta: float) -> void:
	if _visual and not _taken:
		_visual.rotation.y += 0.02
		_visual.position.y = sin(Time.get_ticks_msec() * 0.004) * 0.12


func _on_body_entered(body: Node3D) -> void:
	if _taken:
		return
	if body.is_in_group("player"):
		_taken = true
		collected.emit()
		queue_free()

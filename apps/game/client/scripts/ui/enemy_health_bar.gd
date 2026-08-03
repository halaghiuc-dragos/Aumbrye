extends Node3D
class_name EnemyHealthBar

## Billboard HP bar shown above enemies during combat.

const BAR_WIDTH := 1.1
const BAR_HEIGHT := 0.12
const BAR_DEPTH := 0.04
const FILL_INSET := 0.015
const FILL_DEPTH := 0.02
const DEFAULT_HEIGHT := 2.2

var _bg_mesh: MeshInstance3D
var _fill_mesh: MeshInstance3D
var _health: Health


func setup(health: Health, height_offset: float = DEFAULT_HEIGHT) -> void:
	_health = health
	position.y = height_offset
	_build_meshes()
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	_on_health_changed(health.current, health.max_health)


func _build_meshes() -> void:
	_bg_mesh = MeshInstance3D.new()
	_bg_mesh.name = "Background"
	var bg_mesh := BoxMesh.new()
	bg_mesh.size = Vector3(BAR_WIDTH, BAR_HEIGHT, BAR_DEPTH)
	_bg_mesh.mesh = bg_mesh
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.04, 0.04, 0.04, 1.0)
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bg_mesh.material_override = bg_mat
	add_child(_bg_mesh)

	_fill_mesh = MeshInstance3D.new()
	_fill_mesh.name = "Fill"
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(BAR_WIDTH - FILL_INSET * 2.0, BAR_HEIGHT - FILL_INSET * 2.0, FILL_DEPTH)
	_fill_mesh.mesh = fill_mesh
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.9, 0.15, 0.1, 1.0)
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fill_mesh.material_override = fill_mat
	# look_at() points -Z toward the camera; offset fill toward camera (negative local Z).
	_fill_mesh.position.z = -(BAR_DEPTH * 0.5 + FILL_DEPTH * 0.5 + 0.01)
	add_child(_fill_mesh)


func _process(_delta: float) -> void:
	var camera := PixelDioramaViewport.get_gameplay_camera()
	if camera == null:
		return
	var to_camera := camera.global_position - global_position
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.001:
		return
	look_at(global_position + to_camera.normalized(), Vector3.UP)


func _on_health_changed(current: float, max_value: float) -> void:
	if _fill_mesh == null:
		return
	var ratio: float = 0.0 if max_value <= 0.0 else clampf(current / max_value, 0.0, 1.0)
	_update_fill(ratio)
	visible = ratio > 0.0


func _update_fill(ratio: float) -> void:
	var fill_mesh := _fill_mesh.mesh as BoxMesh
	if fill_mesh == null:
		return

	var inner_width := BAR_WIDTH - FILL_INSET * 2.0
	var inner_height := BAR_HEIGHT - FILL_INSET * 2.0
	var fill_width := inner_width * ratio
	if fill_width <= 0.001:
		_fill_mesh.visible = false
		return

	_fill_mesh.visible = true
	fill_mesh.size = Vector3(fill_width, inner_height, FILL_DEPTH)
	# Anchor fill to the right; depletes right → left.
	_fill_mesh.position.x = inner_width * 0.5 - fill_width * 0.5


func _on_died() -> void:
	visible = false
